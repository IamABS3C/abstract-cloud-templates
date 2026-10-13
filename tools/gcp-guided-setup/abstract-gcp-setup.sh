#!/usr/bin/env bash
# =============================================================================
#  Abstract Security — Google Cloud guided setup
#
#  Walks you through every piece, in order, and checks each one:
#
#    1  Sign-in and organization        who you are, which org, which scope
#    2  What you can change             the roles each later step needs, checked live
#    3  Logging project                 create or pick it, billing, APIs
#    4  Log pipeline                    topic, subscription, sink, publisher grant
#    5  Abstract's access               service account, subscriber grant, key
#    6  Data Access logs     (optional) generate them AND route them — both switches
#    7  Google Workspace     (optional) identity logs: service account + delegation
#    8  Health alerts        (optional) tell you when the pipeline stops
#    9  Test and verify                 a fresh event, from the sink to the topic
#   10  Connect Abstract                the exact values to enter
#
#  Usage
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh              guided: every step, asks before each change
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6     one step
#    ... --step 7 --new-key      make another Workspace key even though the one made for Abstract still exists
#                                 (a lost or rotated key); step 7 never offers one unasked while it does
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --check      verify everything, change nothing
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --reset      forget the saved answers and start over
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --remove     list what clean-up would delete; --remove --confirm deletes it
#    ... --remove --project <id>                                 no saved answers: list what carries the setup's names
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --teardown   FULL RESET, to start from scratch: list everything the
#                                 setup and the templates make across the organization; deletes only with
#                                 --teardown --confirm (asks you to type the organization ID; with no terminal it
#                                 also needs --yes-i-mean-it). Never deletes a project or Terraform state: prints
#                                 their commands, and bucket notifications by hand. Options: --org <id>,
#                                 --project <id> (repeatable), --include-audit-settings (take off only the log
#                                 types step 6 recorded adding, a copy saved first; with no record, nothing),
#                                 --include-grants (remove the bindings --grant recorded)
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant <email>
#                                 the roles the setup needs, for that person (user:, group: or serviceAccount:
#                                 before the email; a bare email is a user): what each is for, required or
#                                 optional; asks before each, adds one binding per role, records it. Run by
#                                 someone who can set IAM policy at the scope; otherwise it prints the commands
#    ... --grant <email> --check  which of those roles they hold directly; changes nothing
#
#  Nothing changes without a "y". Every command is printed before it runs. Answers are
#  kept in ~/.abstract-gcp-setup.env so you can stop and resume. No secret is printed;
#  the only secret made (a service-account key) is written to a 0600 file you upload
#  to Abstract and then delete.
# =============================================================================
set -uo pipefail

STATE="${ABSTRACT_GCP_STATE:-$HOME/.abstract-gcp-setup.env}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"   # the repository root: this script lives in tools/gcp-guided-setup

# The step 6 answers offered first, and offered again when allServices + DATA_READ is declined.
# iam and sts record service-account token minting and Workload Identity Federation token exchange.
DA_DEFAULT_SERVICES="bigquery.googleapis.com,storage.googleapis.com,cloudkms.googleapis.com,iam.googleapis.com,sts.googleapis.com"
DA_DEFAULT_TYPES="ADMIN_READ,DATA_WRITE"
# Defaults; anything in the state file wins. A function, so "start over" can put every answer back.
defaults() {
  TOPIC="abstract-audit-logs"; SUB="abstract-audit-logs-sub"; SINK="abstract-org-audit-sink"  # the Terraform and deploy-script default
  SA="abstract-pubsub-reader"; WS_SA="abstract-workspace-reader"; RETENTION_DAYS=7
  DA_SERVICES="$DA_DEFAULT_SERVICES"; DA_TYPES="$DA_DEFAULT_TYPES"
  # 1 once a person said yes to DATA_READ on allServices (step 6). Until then step 4 routes no Data Access
  # clause for it, so a saved answer alone can never send every service's reads to Abstract.
  DA_ALL_READ_ACK=0
  DATA_ACCESS=no; WORKSPACE=no; ALERTS=no
  ORG_ID=""; SCOPE=""; SCOPE_ID=""; LOG_PROJECT=""; BILLING=""; WS_ADMIN=""; ALERT_EMAIL=""
  ALERT_POLICIES=""; ALERT_CHANNELS=""   # the alerts step 8 made, recorded by name
  # Step 6: 1 once Google confirmed the audit-settings change, 0 when this script decided not to change them,
  # empty when unknown (an answers file written before this was recorded). DA_BACKUP is the copy taken first.
  DA_CHANGED=""; DA_BACKUP=""; DA_ADDED=""
  # The private_key_id of the key each step made for Abstract, so step 10 never offers to delete it.
  KEY_ID=""; WS_KEY_ID=""
  SINK_CREATED_AT=0
  # Set to 1 only when THIS script creates the piece, so --remove never deletes something it found.
  TOPIC_CREATED=0; SUB_CREATED=0; SA_CREATED=0; WS_SA_CREATED=0
  # The role bindings --grant added, as kind:id:role:member joined by ";", so --teardown --include-grants removes
  # exactly those and never a grant that existed before.
  GRANTS=""
}
defaults; FIND_PROJECT=""
# Keys go outside any checkout, in a folder only you can read, so they cannot be committed by accident.
KEY_DIR="${ABSTRACT_KEY_DIR:-$HOME/abstract-keys}"
KEY_FILE="$KEY_DIR/abstract-pubsub-key.json"; WS_KEY_FILE="$KEY_DIR/abstract-workspace-key.json"
# The answers this script saves, in this order. Nothing else may appear in an answers file.
ANSWER_KEYS="ORG_ID SCOPE SCOPE_ID LOG_PROJECT BILLING TOPIC SUB SINK SA RETENTION_DAYS DATA_ACCESS DA_SERVICES DA_TYPES
  WORKSPACE WS_SA WS_ADMIN ALERTS ALERT_EMAIL SINK_CREATED_AT TOPIC_CREATED SUB_CREATED SA_CREATED WS_SA_CREATED
  ALERT_POLICIES ALERT_CHANNELS DA_CHANGED DA_BACKUP DA_ADDED DA_ALL_READ_ACK KEY_ID WS_KEY_ID GRANTS"

# Load an answers file only if every line is one this script could have written: a comment, a blank line, or
# KEY=value for a key above, with the value as printf %q writes it (plain characters, or one character escaped
# with a backslash, or ''). Such a line only assigns text. Anything else - a command, $(...), backticks, an
# unknown key - and the file is refused, never run: the docs tell people to upload an answers file and pass
# --state, so the file may not be the one this script wrote (PR #55 review).
load_answers() {
  local f="$1" line n=0 key val
  local value_re="^(''|([A-Za-z0-9_.:@/+=%,-]|\\\\.)*)$"
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue
    key="${line%%=*}"; val="${line#*=}"
    if [[ "$line" != *=* || " $(echo $ANSWER_KEYS) " != *" $key "* || ! "$val" =~ $value_re ]]; then
      printf 'The answers file %s has a line this script did not write (line %d), so it was not loaded and nothing in it was run.\n' "$f" "$n" >&2
      printf 'Look at that line, or start over without it:  %s --reset\n' "$0" >&2
      exit 2
    fi
  done <"$f"
  # shellcheck disable=SC1090  # every line was checked above: only KEY=escaped-text assignments remain
  source "$f"
}
[[ -f "$STATE" ]] && load_answers "$STATE"

B=$'\033[1m'; P=$'\033[38;5;198m'; G=$'\033[0;32m'; Y=$'\033[0;33m'; R=$'\033[0;31m'; D=$'\033[2m'; O=$'\033[0m'
title() { printf '\n%s━━ %s %s━━%s\n' "$P" "$1" "$2" "$O"; }
say()   { printf '%s\n' "$*"; }
why()   { printf '%s   %s%s\n' "$D" "$*" "$O"; }
pass()  { printf '  %s✓%s %s\n' "$G" "$O" "$*"; PASSES=$((PASSES+1)); }
warn()  { printf '  %s!%s %s\n' "$Y" "$O" "$*"; WARNS=$((WARNS+1)); }
# A failure also leaves a line in FAIL_LOG when one is set (--teardown sets it), so a bad() inside $(...) - whose
# FAILS+1 dies with the subshell - is still counted: td_count_fails reads the file back.
bad()   { printf '  %s✗%s %s\n' "$R" "$O" "$*"; FAILS=$((FAILS+1)); if [[ -n "${FAIL_LOG:-}" ]]; then echo x >>"$FAIL_LOG"; fi; }
PASSES=0; WARNS=0; FAILS=0
CHECK_ONLY=false; ONLY_STEP=""; REMOVE=false; CONFIRM=false; NEW_KEY=false

save() {
  $CHECK_ONLY && return 0
  umask 077
  # %q escapes every value, so an answer containing shell syntax is stored as text, never run.
  { echo "# Abstract GCP guided setup — your answers. Safe to delete; nothing secret is kept here."
    local v; for v in $ANSWER_KEYS; do printf '%s=%q\n' "$v" "${!v}"; done; } > "$STATE"
  # A temporary Cloud Shell session deletes this file with it, and clean-up needs it. A copy downloaded at step 1
  # holds none of what later steps create, so it is offered again whenever a save records something clean-up
  # reads: what was created, the logging project, a key id, a change to the audit settings.
  local rec; rec="$LOG_PROJECT|$SINK_CREATED_AT|$TOPIC_CREATED|$SUB_CREATED|$SA_CREATED|$WS_SA_CREATED|$KEY_ID|$WS_KEY_ID|$DA_CHANGED|$DA_BACKUP|$ALERT_POLICIES|$ALERT_CHANNELS|$GRANTS"
  if [[ "${CLOUD_SHELL:-}" == true && "$rec" != "$ANSWERS_OFFERED" ]]; then
    ANSWERS_OFFERED="$rec"; offer_download "$STATE" "your answers file (again: it now records more)"
  fi
}
ANSWERS_OFFERED=""

# gcloud must never stop to ask something itself: its questions go to stderr, which the lookups below hide,
# so a hidden "enable this API and retry? (y/N)" would freeze the script (measured 2026-10-08 in the estate
# audit). The sign-in command turns questions back on for itself.
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# ── Questions ───────────────────────────────────────────────────────────────────
# Every question is written to and read from the terminal itself (/dev/tty), never stdout or stderr: answers are
# captured with $(...), and stderr is often hidden. Until 2026-10-11 the prompt went to stderr and was thrown
# away with 2>/dev/null, so every question was invisible and the script looked frozen; Enter then took the
# default, which looked like a skipped step. Answers are checked and asked again when they do not fit.
# Without a terminal (CI, a pipe) nothing is asked: the default is taken and a yes/no is "no", never a hang.
# Written for bash 3.2 (macOS): no ${x,,}, and empty arrays are expanded with ${a[@]+"${a[@]}"}.
HAVE_TTY=false; { : </dev/tty >/dev/tty; } 2>/dev/null && HAVE_TTY=true
interactive() { ! $CHECK_ONLY && $HAVE_TTY; }
to_tty() { printf "$@" >/dev/tty; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }
csv()   { tr -d '[:space:]' <<<"$1"; }   # "a, b" -> "a,b": a list answer is used exactly as Google needs it

# ask "question" [default] [check]   check: a function that prints why an answer does not fit and returns 1.
# A check starting with "?" (e.g. "?valid_email") also accepts an empty answer.
ask() {
  local q="$1" def="${2:-}" check="${3:-}" a why_not optional=false
  [[ "$check" == \?* ]] && { optional=true; check="${check#\?}"; }
  interactive || { printf '%s' "$def"; return; }
  while true; do
    to_tty '  %s%s%s%s: ' "$B" "$q" "$O" "${def:+ [$def]}"
    IFS= read -r a </dev/tty || { to_tty '\n'; printf '%s' "$def"; return; }
    a=$(trim "${a:-$def}")
    if [[ -z "$a" ]]; then $optional && return; to_tty '  %sAn answer is needed here.%s\n' "$Y" "$O"; continue; fi
    if [[ -n "$check" ]] && ! why_not=$("$check" "$a"); then to_tty '  %s%s%s\n' "$Y" "$why_not" "$O"; continue; fi
    printf '%s' "$a"; return
  done
}

# yes_no "question" [y|n]   the second argument is what Enter means (default n). Only y, yes, n or no count.
yes_no() {
  local def="${2:-n}" a; interactive || return 1
  while true; do
    to_tty '  %s %s ' "$1" "$([[ $def == y ]] && echo '[Y/n]' || echo '[y/N]')"
    IFS= read -r a </dev/tty || { to_tty '\n'; return 1; }
    a=$(lower "$(trim "$a")"); [[ -z "$a" ]] && a="$def"
    case "$a" in y|yes) return 0 ;; n|no) return 1 ;; esac
    to_tty '  %sType y or n.%s\n' "$Y" "$O"
  done
}

# choose "title" "id<TAB>description lines" [new-option label] [default id] [id pattern]
# (choose_existing below re-asks until the chosen id is one Google can describe.)
# Prints the chosen id, or "+new" when the extra option is picked. Accepts the number shown, an id from the
# list, or an id matching the pattern (for ones the list cannot show); any other text narrows the list.
choose() {
  local title="$1" list="$2" new="${3:-}" def="${4:-}" pat="${5:-}" id desc a i n filter="" max=25
  local -a ids=() descs=() shown=()
  while IFS=$'\t' read -r id desc; do [[ -n "$id" ]] && { ids+=("$id"); descs+=("$desc"); }; done <<<"$list"
  interactive || { printf '%s' "$def"; return; }
  while true; do
    shown=()
    for ((i = 0; i < ${#ids[@]}; i++)); do
      [[ -z "$filter" ]] || grep -qiF -- "$filter" <<<"${ids[$i]} ${descs[$i]}" && shown+=("$i")
    done
    to_tty '\n  %s%s%s\n' "$B" "$title" "$O"
    n=0
    for i in ${shown[@]+"${shown[@]}"}; do
      (( n >= max )) && break; n=$((n + 1))
      to_tty '    %s%2d)%s %s%s%s\n' "$P" "$n" "$O" "${ids[$i]}" "${descs[$i]:+  $D${descs[$i]}}" "$O"
    done
    (( ${#shown[@]} > max )) && to_tty '    %s... %d more - type part of a name to narrow the list%s\n' "$D" $(( ${#shown[@]} - max )) "$O"
    (( ${#shown[@]} == 0 )) && to_tty '    %snothing matches "%s" - type other text, or press Enter for the full list%s\n' "$Y" "$filter" "$O"
    [[ -n "$new" ]] && to_tty '    %s n)%s %s\n' "$P" "$O" "$new"
    if (( ${#ids[@]} <= 9 )) && [[ -z "$filter" ]]; then to_tty '  Choose 1-%d%s' "$n" "${new:+ or n}"
    else to_tty '  Choose a number%s, an ID, or type part of a name to search' "${new:+, n for new}"; fi
    to_tty '%s: ' "${def:+ [$def]}"
    IFS= read -r a </dev/tty || { to_tty '\n'; printf '%s' "$def"; return; }
    a=$(trim "$a")
    if [[ -z "$a" ]]; then
      [[ -n "$filter" ]] && { filter=""; continue; }
      [[ -n "$def" ]] && { printf '%s' "$def"; return; }
      to_tty '  %sChoose one to continue.%s\n' "$Y" "$O"; continue
    fi
    if [[ -n "$new" && $(lower "$a") == n ]]; then printf '+new'; return; fi
    if [[ "$a" =~ ^[0-9]+$ ]] && (( a >= 1 && a <= n )); then printf '%s' "${ids[${shown[$((a - 1))]}]}"; return; fi
    for ((i = 0; i < ${#ids[@]}; i++)); do [[ "${ids[$i]}" == "$a" ]] && { printf '%s' "$a"; return; }; done
    # Text that matches entries narrows the list; only an id that matches none is taken as typed (the caller
    # then checks it exists).
    if [[ -n "$pat" && "$a" =~ $pat ]] && ! grep -qiF -- "$a" <<<"$list"; then printf '%s' "$a"; return; fi
    filter="$a"
  done
}

# choose_existing "what" "describe command with {} for the id" choose-args...   re-asks until the id exists.
choose_existing() {
  local what="$1" describe="$2" pick; shift 2
  while true; do
    pick=$(choose "$@")
    [[ -z "$pick" || "$pick" == +new ]] && { printf '%s' "$pick"; return; }
    # shellcheck disable=SC2086  # the describe command is split into words on purpose
    ${describe//\{\}/$pick} >/dev/null 2>&1 && { printf '%s' "$pick"; return; }
    interactive || { printf '%s' "$pick"; return; }
    to_tty '  %s%s %s was not found, or you cannot see it. Choose again.%s\n' "$Y" "$what" "$pick" "$O"
  done
}

# Checks for ask(): print why an answer does not fit, and return 1.
valid_project_id() { [[ "$1" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] && return
  echo "A project ID is 6 to 30 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."; return 1; }
valid_email() { [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] && return; echo "That is not an email address."; return 1; }
valid_services() { local s; for s in ${1//,/ }; do [[ "$s" == allServices || "$s" =~ ^[a-z0-9-]+\.googleapis\.com$ ]] \
    || { echo "\"$s\" is not a service name: use names like storage.googleapis.com, separated by commas."; return 1; }; done; }
valid_log_types() { local t; for t in ${1//,/ }; do case "$t" in ADMIN_READ|DATA_WRITE|DATA_READ) ;; \
    *) echo "\"$t\" is not a log type: use ADMIN_READ, DATA_WRITE and/or DATA_READ, separated by commas."; return 1 ;; esac; done; }

# Show the command, ask, run it. Returns the command's status; "no" is not a failure.
run() { printf '%s   $' "$D"; printf ' %q' "$@"; printf '%s\n' "$O"; if $CHECK_ONLY; then return 3; fi
  if yes_no "Run it?"; then "$@"; return $?; fi; say "  skipped"; return 3; }

need() { command -v "$1" >/dev/null || { bad "$1 is not installed. Cloud Shell has everything this needs."; exit 1; }; }
token() { gcloud auth print-access-token 2>/dev/null; }

# Which of these permissions does the signed-in principal hold on a resource?
# (the resource's own answer, from testIamPermissions — no guessing from role names)
held() {  # held <resource-url> perm...
  local url="$1"; shift
  local body; body=$(python3 -c 'import json,sys;print(json.dumps({"permissions":sys.argv[1:]}))' "$@")
  # Only the "permissions" list is an answer ({} = none held). An error reply, an empty or non-JSON body says
  # nothing about what is held: print why and return 1, so callers say "could not check", never "you cannot".
  curl -s -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" -d "$body" "$url:testIamPermissions" \
    | python3 -c 'import json,sys
raw = sys.stdin.read().strip()
try: d = json.loads(raw)
except ValueError: sys.exit(print("no readable answer from Google" if not raw else "the answer was not JSON") or 1)
if not isinstance(d, dict): sys.exit(print("the answer was not a permissions list") or 1)
if "error" in d:
    e = d["error"]; sys.exit(print((e.get("message") if isinstance(e, dict) else "") or "Google returned an error") or 1)
print(" ".join(d.get("permissions", [])))'
}
scope_url() { case "$SCOPE" in
  organization) echo "https://cloudresourcemanager.googleapis.com/v3/organizations/$SCOPE_ID" ;;
  folder)       echo "https://cloudresourcemanager.googleapis.com/v3/folders/$SCOPE_ID" ;;
  project)      echo "https://cloudresourcemanager.googleapis.com/v3/projects/$SCOPE_ID" ;; esac; }
scope_flag() { case "$SCOPE" in organization) echo "--organization=$SCOPE_ID" ;; folder) echo "--folder=$SCOPE_ID" ;; project) echo "--project=$SCOPE_ID" ;; esac; }
has() { [[ " $1 " == *" $2 "* ]]; }

# The command that runs this script again on the same answers: --state is named whenever it is not the default,
# so a hint copied into another session reads the same file.
again() { if [[ "$STATE" == "$HOME/.abstract-gcp-setup.env" ]]; then printf '%s %s' "$0" "$*"; else printf '%s --state %q %s' "$0" "$STATE" "$*"; fi; }

# ── Launch: who you are, what is saved, and a way to change either ──────────────────
MIRROR_URL="https://github.com/IamABS3C/abstract-cloud-templates"

# A listed account is not a working sign-in: gcloud keeps showing an account as active after its sign-in
# has expired (measured 2026-10-09). Only a token proves it, and only Google (tokeninfo) says whose it is.
# gcloud-identity.sh decides that alike for all three scripts, impersonation and token files included.
# shellcheck source=gcloud-identity.sh
source "$HERE/gcloud-identity.sh"
token_email() { gid_token_email "$(gcloud auth print-access-token 2>/dev/null)"; }
# Signed in = the configured account can mint a token AND the token acts as that account, or as the service
# account gcloud is set to impersonate (when Google says). GID_LINE then says who acts, for the person.
signed_in() {
  local acct; acct=$(gcloud config get-value account 2>/dev/null)
  [[ -n "$acct" ]] && gcloud auth print-access-token >/dev/null 2>&1 || return 1
  gid_check "$acct" "$(token_email)"
}
# Why signed_in failed, for the person: a wrong account is told apart from no sign-in at all.
signed_in_problem() {
  local acct; acct=$(gcloud config get-value account 2>/dev/null)
  if [[ -z "$acct" ]]; then echo "not signed in to gcloud. Sign in: gcloud auth login --update-adc"
  elif ! gcloud auth print-access-token >/dev/null 2>&1; then echo "$acct must sign in again: gcloud auth login $acct --update-adc"
  else gid_check "$acct" "$(token_email)"; echo "$GID_LINE"; fi
}

sign_in() {
  say "  Signing in. A browser opens, or gcloud prints a link to open; finish there and come back."
  why "--update-adc also refreshes the credentials Terraform uses, for the template path."
  # The one command allowed to ask questions: it may need a code pasted back.
  CLOUDSDK_CORE_DISABLE_PROMPTS=0 gcloud auth login --update-adc </dev/tty >/dev/tty 2>&1 \
    && signed_in && pass "$GID_LINE" || bad "sign-in did not finish"
}

switch_account() {
  local accts pick
  accts=$(gcloud auth list --format='value(account)' 2>/dev/null | sed 's/$/\t/')
  pick=$(choose "Which account?" "$accts" "sign in with another account" "$(gcloud config get-value account 2>/dev/null)")
  if [[ "$pick" == +new ]]; then sign_in
  elif [[ -n "$pick" ]]; then gcloud config set account "$pick" >/dev/null 2>&1
    signed_in && pass "using $pick" || { warn "$pick needs to sign in again"; sign_in; }
  fi
  # Answers saved under another account describe what that account could see.
  if [[ -n "$ORG_ID" ]] && ! gcloud organizations describe "$ORG_ID" >/dev/null 2>&1; then
    warn "this account cannot see the saved organization $ORG_ID"
    yes_no "Forget the saved answers and start over?" y && start_over
  fi
}

start_over() {
  local old; old="$STATE.old-$(date +%Y%m%d%H%M%S)"
  # Moved, never deleted: it records what this script created, which --remove --state with its path still cleans up.
  [[ -f "$STATE" ]] && mv "$STATE" "$old" && say "  saved answers moved to $old (clean-up of what they created: --remove --state $old)"
  defaults
}

update_and_restart() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    run git -C "$ROOT" pull --ff-only || { warn "not updated"; return; }
    say "  restarting with the updated scripts"
    exec bash "$0" ${ARGS[@]+"${ARGS[@]}"}
  fi
  warn "this folder is not a git copy of the repository, so it cannot update itself"
  say "  Get a fresh copy:  git clone $MIRROR_URL && cd abstract-cloud-templates && ./tools/gcp-guided-setup/abstract-gcp-setup.sh"
}

# Google opens a repository that is not its own in a TEMPORARY Cloud Shell: "without access to the user's
# credentials", with a home folder "deleted when the session ends" (Cloud Shell docs, open-in-cloud-shell).
# That deletes the saved answers and the key file too. CLOUD_SHELL is only a hint that this is Cloud Shell.
explain_cloud_shell() {
  [[ "${CLOUD_SHELL:-}" == true ]] || return 0
  say ""
  say "  ${B}Cloud Shell:${O} a repository opened from a link that is not Google's runs in a temporary session,"
  say "  without your credentials, and its home folder (saved answers, the key file step 5 makes, the copy of"
  say "  the audit settings step 6 saves) is deleted when the session ends. Either:"
  say "    - sign in here, download the key as soon as step 5 makes it, and download each file this script"
  say "      offers before you close Cloud Shell, or"
  say "    - open Cloud Shell from the Google Cloud console (the >_ button, top right) and run:"
  say "        git clone $MIRROR_URL && cd abstract-cloud-templates && ./tools/gcp-guided-setup/abstract-gcp-setup.sh"
}

# In Cloud Shell, a file that must outlive the session is downloaded as soon as it exists.
offer_download() {  # offer_download <file> <what it is>
  [[ "${CLOUD_SHELL:-}" == true && -f "$1" ]] || return 0
  say "  ${B}Download $2 now${O} (this Cloud Shell session may be temporary):  cloudshell download $1"
}

launch() {
  local acct st=() ok=false a
  acct=$(gcloud config get-value account 2>/dev/null)
  signed_in && ok=true
  if $ok; then st+=("ok|$GID_LINE")
  else st+=("bad|$(signed_in_problem)"); fi
  [[ -n "$ORG_ID$SCOPE$LOG_PROJECT" ]] && st+=("info|saved: organization ${ORG_ID:-?}, scope ${SCOPE:-?} ${SCOPE_ID}, logging project ${LOG_PROJECT:-not chosen}")
  python3 "$HERE/brand.py" header "Google Cloud setup" "$($CHECK_ONLY && echo 'check only - nothing will change' || echo 'guided setup')" ${st[@]+"${st[@]}"}
  # Shown whenever this is Cloud Shell, signed in or not: the session may be the temporary kind either way.
  explain_cloud_shell
  interactive || return 0
  while true; do
    if ! signed_in; then
      say ""; say "  ${B}Sign in to continue:${O}  1) sign in now   2) switch to another account gcloud knows   q) quit"
      a=$(ask "Choose" 1)
      case "$a" in 1) sign_in ;; 2) switch_account ;; q|Q) exit 0 ;; *) warn "choose 1, 2 or q" ;; esac
      continue
    fi
    say ""
    say "  ${B}Enter${O} continue as $(gcloud config get-value account 2>/dev/null)   ${B}s${O} switch account   ${B}l${O} sign in again"
    say "  ${B}r${O} start over (forget saved answers)   ${B}u${O} update this repository and restart   ${B}q${O} quit"
    a=$(lower "$(ask "Choose" continue)")
    case "$a" in
      continue|c) return 0 ;;
      s) switch_account ;; l) sign_in ;; r) start_over; pass "starting over" ;; u) update_and_restart ;; q) exit 0 ;;
      *) warn "press Enter, or type s, l, r, u or q" ;;
    esac
  done
}

# ─────────────────────────────────────────────────────────────────────────────
step1() {
  title 1 "Sign-in and organization"
  why "Everything below is checked for the account you are signed in as."
  local acct; acct=$(gcloud config get-value account 2>/dev/null)
  signed_in && pass "$GID_LINE" || { bad "$(signed_in_problem) (or start the script again and choose to sign in)"; return; }

  local orgs; orgs=$(listing gcloud organizations list --format='value(ID,displayName)')
  if [[ -z "$orgs" ]]; then bad "no organization visible to $acct. An organization is needed for org or folder scope; a project pilot still works."
  else
    if [[ -z "$ORG_ID" ]]; then
      if [[ $(grep -c . <<<"$orgs") -eq 1 ]]; then ORG_ID=$(cut -f1 <<<"$orgs")
      else ORG_ID=$(choose_existing organization "gcloud organizations describe {}" "Which organization?" "$orgs" "" "" '^[0-9]{6,}$'); fi
    fi
    gcloud organizations describe "$ORG_ID" >/dev/null 2>&1 && pass "organization $ORG_ID ($(gcloud organizations describe "$ORG_ID" --format='value(displayName)'))" || bad "cannot read organization ${ORG_ID:-(none chosen)}"
  fi

  if [[ -z "$SCOPE" ]] && interactive; then
    SCOPE=$(choose "Which part of Google Cloud should send logs?" "$(printf '%s\t%s\n' \
      organization "the whole organization - every project, including ones created later (recommended)" \
      folder "one folder - every project in it; anything outside is missed" \
      project "one project - a pilot; does not cover other or future projects")" "" organization)
  fi
  case "$SCOPE" in
    organization) SCOPE_ID="$ORG_ID" ;;
    folder) if [[ -z "$SCOPE_ID" || "$SCOPE_ID" == "$ORG_ID" ]]; then
              SCOPE_ID=$(choose_existing folder "gcloud resource-manager folders describe {}" "Which folder? (top-level folders are listed; type the ID of a nested one)" \
                "$(listing gcloud resource-manager folders list --organization="$ORG_ID" --format='value(ID,displayName)')" "" "" '^[0-9]{6,}$')
            fi ;;
    project) if [[ -z "$SCOPE_ID" || "$SCOPE_ID" == "$ORG_ID" ]]; then
               SCOPE_ID=$(choose_existing project "gcloud projects describe {}" "Which project is the pilot?" "$(project_list)" "" "$(gcloud config get-value project 2>/dev/null)" '^[a-z][a-z0-9-]{4,28}[a-z0-9]$')
             fi ;;
  esac
  [[ -n "$SCOPE" && -n "$SCOPE_ID" ]] && pass "scope: $SCOPE $SCOPE_ID" || bad "no scope chosen yet"
  save
}

# A lookup that fails says so on the screen, instead of looking like an empty list. Callers capture stdout,
# so the message goes to the terminal (stderr without one), never into the list being built.
listing() {
  local out err rc=0; err=$(mktemp)
  if out=$("$@" 2>"$err"); then printf '%s' "$out"
  else rc=1
    if $HAVE_TTY; then to_tty '  %s!%s could not list: %s\n' "$Y" "$O" "$(grep -v '^[[:space:]]*$' "$err" | head -n1)"
    else printf '  ! could not list: %s\n' "$(grep -v '^[[:space:]]*$' "$err" | head -n1)" >&2; fi
  fi
  rm -f "$err"; return $rc
}
project_list() { listing gcloud projects list --format='value(projectId,name)' --sort-by=projectId; }

# Who can change the audit settings at the scope. A function: bash 3.2 cannot parse a case inside $(...).
audit_admins() {
  case "$SCOPE" in
    organization) echo "Organization Admin or Security Admin" ;;
    folder) echo "Folder Admin or Security Admin on the folder" ;;
    *) echo "Owner, Project IAM Admin or Security Admin on the project" ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
step2() {
  title 2 "What you can change"
  why "Each later step needs a specific permission. This asks Google directly which ones you hold."
  [[ -n "$SCOPE" && -n "$SCOPE_ID" ]] || { bad "choose a scope first (step 1)"; return; }
  local h
  if ! h=$(held "$(scope_url)" logging.sinks.create "resourcemanager.$( [[ $SCOPE == organization ]] && echo organizations || echo "${SCOPE}s" ).setIamPolicy"); then
    warn "could not check your rights at the $SCOPE: $h. Steps 4 and 6 report a missing permission when they reach it."
  else
  has "$h" logging.sinks.create && pass "create the log sink at the $SCOPE (step 4)" \
    || { local me; me=$(gcloud config get-value account 2>/dev/null)
         # The grant goes on the scope itself, never wider than the sink needs.
         case "$SCOPE" in
           organization) bad "you cannot create a sink at the organization. You need roles/logging.configWriter there — not included in Organization Admin."
                         why "An Organization Admin can grant it:  gcloud organizations add-iam-policy-binding $SCOPE_ID --member=user:$me --role=roles/logging.configWriter" ;;
           folder) bad "you cannot create a sink at the folder. You need roles/logging.configWriter on folder $SCOPE_ID."
                   why "A Folder Admin (or anyone who can set the folder's IAM policy) can grant it:  gcloud resource-manager folders add-iam-policy-binding $SCOPE_ID --member=user:$me --role=roles/logging.configWriter" ;;
           project) bad "you cannot create a sink in the project. You need roles/logging.configWriter on project $SCOPE_ID."
                    why "A project Owner or Project IAM Admin can grant it:  gcloud projects add-iam-policy-binding $SCOPE_ID --member=user:$me --role=roles/logging.configWriter" ;;
         esac; }
  has "$h" "resourcemanager.$( [[ $SCOPE == organization ]] && echo organizations || echo "${SCOPE}s" ).setIamPolicy" \
    && pass "turn on Data Access logs at the $SCOPE (step 6, optional)" \
    || warn "you cannot turn on Data Access logs at the $SCOPE (needs $(audit_admins)). Skip step 6 or ask them."
  fi
  if [[ -n "$ORG_ID" ]]; then
    local o
    if ! o=$(held "https://cloudresourcemanager.googleapis.com/v3/organizations/$ORG_ID" resourcemanager.projects.create); then
      warn "could not check whether you can create projects in the organization: $o"
    else
      has "$o" resourcemanager.projects.create && pass "create a new logging project (step 3)" || warn "you cannot create projects in the organization; pick an existing logging project in step 3"
    fi
  fi
  if [[ -n "$LOG_PROJECT" ]]; then project_checks
  else
    warn "not checked yet: your rights in the logging project, and whether an org policy blocks the key step 5 makes. Step 3 checks both as soon as the project is chosen, before step 4 builds anything."
  fi
  local me; me=$(gcloud config get-value account 2>/dev/null)
  why "Who needs what: every role these steps need, what each is for and where it goes, is listed (and checked,"
  why "changing nothing) by:  $(again --grant "${me:-you@example.com}" --check)"
  why "Someone who can set IAM policy at the $SCOPE grants them one at a time with:  $(again --grant "${me:-you@example.com}")"
}

# What steps 4 and 5 need in the logging project. Step 2 runs it when the project is already known,
# and step 3 runs it again, so a blocked key shows up before step 4 creates the sink, not after.
# Called directly, never through $(...): a subshell would lose the pass and fail counts.
project_checks() {
  local p
  if ! p=$(held "https://cloudresourcemanager.googleapis.com/v3/projects/$LOG_PROJECT" pubsub.topics.create pubsub.subscriptions.create iam.serviceAccounts.create iam.serviceAccountKeys.create serviceusage.services.enable pubsub.topics.setIamPolicy); then
    warn "could not check your rights in $LOG_PROJECT: $p. Steps 4 and 5 report a missing permission when they reach it."
  else
    local miss=""; for x in pubsub.topics.create pubsub.subscriptions.create pubsub.topics.setIamPolicy iam.serviceAccounts.create iam.serviceAccountKeys.create serviceusage.services.enable; do
      has "$p" "$x" || miss+=" $x"; done
    [[ -z "$miss" ]] && pass "build the pipeline in $LOG_PROJECT (steps 3-5)" \
      || bad "missing in $LOG_PROJECT:$miss — Owner, or Pub/Sub Admin + Service Account Admin + Service Account Key Admin + Service Usage Admin"
  fi
  # The org policies that block the key in step 5: the legacy boolean constraint and its managed successor
  # (iam.managed.*, read through the Org Policy v2 API). A lookup that fails is not an answer: it is reported
  # as unknown, never as "allowed". Keys are allowed only when BOTH were read and neither is enforced.
  local kp km legacy=unknown managed=unknown
  if kp=$(gcloud resource-manager org-policies describe iam.disableServiceAccountKeyCreation --project="$LOG_PROJECT" --effective --format='value(booleanPolicy.enforced)' 2>/dev/null); then
    [[ "$kp" == True ]] && legacy=on || legacy=off
  fi
  if km=$(gcloud org-policies describe iam.managed.disableServiceAccountKeyCreation --project="$LOG_PROJECT" --effective --format=json 2>/dev/null); then
    managed=$(python3 -c 'import json, sys
d = json.loads(sys.stdin.read())
print("on" if any(r.get("enforce") is True for r in (d.get("spec") or {}).get("rules", [])) else "off")' <<<"$km" 2>/dev/null) || managed=unknown
  fi
  local c
  for c in legacy managed; do
    local name=iam.disableServiceAccountKeyCreation; [[ $c == managed ]] && name=iam.managed.disableServiceAccountKeyCreation
    case "${!c}" in
      on) bad "org policy $name is enforced on $LOG_PROJECT: step 5 cannot create a key. Ask for an exception on this project before step 4." ;;
      unknown) warn "could not read the org policy $name on $LOG_PROJECT (it needs Organization Policy Viewer). If it is enforced, step 5 cannot create a key; ask your organization admin before step 4." ;;
    esac
  done
  [[ $legacy == off && $managed == off ]] && \
    pass "service-account keys are allowed on $LOG_PROJECT (org policies iam.disableServiceAccountKeyCreation and iam.managed.disableServiceAccountKeyCreation are not enforced)"
}

# ─────────────────────────────────────────────────────────────────────────────
step3() {
  title 3 "Logging project"
  why "One dedicated project holds the topic, subscription and Abstract's service account."
  why "Not a workload project: whoever owns that project could read or break the pipeline."
  while [[ -z "$LOG_PROJECT" ]] && interactive; do
    # Suggest the project an existing Abstract sink already sends to, as the estate audit does.
    local sent=""; [[ -n "$SCOPE" && -n "$SCOPE_ID" ]] && sent=$(gcloud logging sinks list "$(scope_flag)" --format='value(destination)' 2>/dev/null \
      | sed -n "s|^pubsub.googleapis.com/projects/\([^/]*\)/topics/$TOPIC\$|\1|p" | head -n1)
    [[ -n "$sent" ]] && say "  The existing sink already sends to $sent: choosing it keeps one pipeline."
    local pick; pick=$(choose_existing project "gcloud projects describe {}" "Which project holds the pipeline?" "$(project_list)" "create a new project for Abstract (recommended when none exists)" "$sent" '^[a-z][a-z0-9-]{4,28}[a-z0-9]$')
    if [[ "$pick" == +new ]]; then
      # Where a new project goes comes from step 1. Without it, choosing an existing project still works.
      [[ -n "$SCOPE" && -n "$SCOPE_ID" ]] || { warn "creating a project needs step 1 first (or --state ANSWERS_FILE, the path of an answers file step 1 saved), to know where it goes; or choose an existing project"; continue; }
      local new; new=$(ask "New project ID (globally unique, e.g. COMPANY-security-logging)" "" valid_project_id)
      local -a parent=()
      if [[ "$SCOPE" == folder ]]; then parent=("--folder=$SCOPE_ID")
      elif [[ -n "$ORG_ID" ]]; then parent=("--organization=$ORG_ID"); fi
      # Saved only once it exists: an ID Google refused (taken, quota, no right) must not be kept.
      if run gcloud projects create "$new" ${parent[@]+"${parent[@]}"} --name="Abstract security logging"; then LOG_PROJECT="$new"
      else warn "project $new was not created; choose again"; fi
    else LOG_PROJECT="$pick"; fi
  done
  save
  [[ -n "$LOG_PROJECT" ]] || { bad "no logging project chosen"; return; }
  local st; st=$(gcloud projects describe "$LOG_PROJECT" --format='value(lifecycleState)' 2>/dev/null)
  [[ "$st" == ACTIVE ]] && pass "project $LOG_PROJECT is active" || { bad "project $LOG_PROJECT not found or not active"; return; }

  local be; be=$(gcloud billing projects describe "$LOG_PROJECT" --format='value(billingEnabled)' 2>/dev/null)
  if [[ "$be" == True ]]; then pass "billing is linked"
  else
    warn "no billing linked. That is fine for this path: Pub/Sub and Logging free tiers cover an audit feed."
    why "Link billing only if you will use Infrastructure Manager, high-volume logs, or a Terraform state bucket in this project."
    if ! $CHECK_ONLY && yes_no "Link a billing account now?"; then
      local accounts; accounts=$(listing gcloud billing accounts list --filter=open=true --format='value(name.basename(),displayName)')
      if [[ -z "$accounts" ]]; then warn "no open billing account is visible to you; ask your billing admin to link one to $LOG_PROJECT"
      else BILLING=$(choose "Which billing account?" "$accounts" "" "" '^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$'); save
        run gcloud billing projects link "$LOG_PROJECT" --billing-account="$BILLING"; fi
    fi
  fi

  local apis="pubsub.googleapis.com logging.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com"
  [[ "$WORKSPACE" == yes ]] && apis+=" admin.googleapis.com"
  [[ "$ALERTS" == yes ]] && apis+=" monitoring.googleapis.com"
  local on; on=$(gcloud services list --enabled --project="$LOG_PROJECT" --format='value(config.name)' 2>/dev/null)
  local missing=""; for a in $apis; do grep -qx "$a" <<<"$on" || missing+=" $a"; done
  if [[ -z "$missing" ]]; then pass "APIs enabled: ${apis// /, }"
  else
    warn "APIs not enabled:$missing"
    # shellcheck disable=SC2086
    run gcloud services enable $missing --project="$LOG_PROJECT" && pass "APIs enabled"
  fi
  # Step 2 cannot check the project before it is chosen. Check now, once the APIs these lookups
  # use are on, and before step 4 creates the sink outside this project.
  why "What steps 4 and 5 need in $LOG_PROJECT:"
  project_checks
}

# ─────────────────────────────────────────────────────────────────────────────
# Google turns token-minting logs on ONLY through the IAM API (iam.googleapis.com), but the events carry
# serviceName iamcredentials.googleapis.com. So the audit settings and the sink filter need different
# names: https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds
audit_services() {   # the names Google accepts in the audit settings
  tr ',' '\n' <<<"$1" | sed 's/^iamcredentials\.googleapis\.com$/iam.googleapis.com/' | awk 'NF && !seen[$0]++' | paste -sd, -
}
routed_services() {  # the serviceName values the events carry, for the sink filter. Only the token
  # events are routed for iam: its other ADMIN_READ entries (listing roles, reading policies) stay in Cloud Logging.
  tr ',' '\n' <<<"$1" | sed 's/^iam\.googleapis\.com$/iamcredentials.googleapis.com/' | awk 'NF && !seen[$0]++' | paste -sd, -
}

# DATA_READ on allServices: every read of every service. One predicate for step 4, step 6 and the question.
all_services_read() { [[ ",$DA_SERVICES," == *,allServices,* && ",$DA_TYPES," == *,DATA_READ,* ]]; }
# ...and not yet confirmed by a person, so nothing may route it (step 4) or turn it on (step 6).
all_services_read_unconfirmed() { all_services_read && [[ "${DA_ALL_READ_ACK:-0}" != 1 ]]; }

filter() {
  local f='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy"'
  # Unconfirmed allServices + DATA_READ gets no Data Access clause at all: the unrestricted one would carry
  # every service's reads, BigQuery's default-on logs among them, even with switch 1 unchanged. Step 4 says so.
  if [[ "$DATA_ACCESS" == yes ]] && ! all_services_read_unconfirmed; then
    # allServices is the audit-config wildcard: no entry carries it as a serviceName, so it is routed by a
    # Data Access clause that names no service at all.
    if [[ ",$DA_SERVICES," == *,allServices,* ]]; then f+=' OR logName:"cloudaudit.googleapis.com%2Fdata_access"'
    else
      local c=""; IFS=',' read -ra S <<<"$(routed_services "$DA_SERVICES")"; for s in "${S[@]}"; do c+="${c:+ OR }\"$s\""; done
      f+=" OR (logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND protoPayload.serviceName=($c))"
    fi
  fi
  printf '%s' "$f"
}

# Sinks already at this scope that export audit logs somewhere else. The estate audit lists only
# organization sinks, so a folder or project export is seen here, before a second sink is added.
# A listing that fails is said to have failed, never read as "none".
existing_audit_sinks() {  # existing_audit_sinks <scope flag> <our destination>
  local out
  if ! out=$(gcloud logging sinks list "$1" --format='value(name,destination,filter)' 2>&1); then
    warn "could not list the sinks already at the $SCOPE (${out%%$'\n'*}). Check them before you add one: gcloud logging sinks list $1"
    return
  fi
  local name dest filter found=0
  while IFS=$'\t' read -r name dest filter; do
    [[ -z "$name" || "$dest" == "$2" ]] && continue
    # An empty filter routes every log, audit logs included. _Required and _Default are Google's own.
    [[ "$name" == _Required || "$name" == _Default ]] && continue
    if [[ -z "$filter" || "$filter" == *cloudaudit* ]]; then
      warn "sink $name at the $SCOPE already exports audit logs, to $dest"; found=1
    fi
  done <<<"$out"
  (( found )) && why "A new sink adds a second copy for Abstract; it changes nothing for those. If one of them is meant to feed Abstract, stop and ask its owner first."
  (( found )) || pass "no other sink at the $SCOPE exports audit logs"
}

# Is the sink at the scope Terraform's? "yes" when its description carries the module's marker, "maybe" when its
# filter has the module's "\n  OR " join or it has the template's default name and this setup did not create it.
sink_tf() {  # sink_tf <description> <filter>
  if [[ "$1" == *"managed-by: abstract-cloud-templates (terraform)"* ]]; then echo yes
  elif [[ "$2" == *$'\n  OR '* || ( "$SINK" == abstract-org-audit-sink && "${SINK_CREATED_AT:-0}" == 0 ) ]]; then echo maybe
  else echo no; fi
}

# The sink of this name already sends somewhere else (measured 2026-10-12: a new logging project was chosen while
# the organization's Terraform sink sent to another, and step 4 said only "sends to A, not B"). Name both ways on;
# move the sink only when nothing else owns it. Returns 0 once it sends to $2, 1 when it does not: step 4 then
# stops, because nothing in it may change a sink that feeds another pipeline.
sink_elsewhere() {  # sink_elsewhere <current destination> <wanted destination> <scope flag>
  local d="$1" dest="$2" sf="$3" proj="" top="" desc f tf
  bad "sink $SINK sends to $d, not $dest"
  if [[ "$d" =~ ^pubsub\.googleapis\.com/projects/([^/]+)/topics/([^/]+)$ ]]; then proj="${BASH_REMATCH[1]}"; top="${BASH_REMATCH[2]}"
  else
    say "   That is not a Pub/Sub topic, so it is not a pipeline Abstract reads, and moving the sink would cut off"
    say "   whatever it feeds. Give Abstract a sink of its own: put a new name in your answers file, $STATE,"
    say "   as SINK=abstract-audit-sink (any name not used at the $SCOPE), then run:  $(again --step 4)"
    return 1
  fi
  say "   Two ways on:"
  say "   1) Keep the existing pipeline: use $proj as the logging project. Start over and choose $proj at script step 3:"
  say "        $(again --reset)"
  [[ "$top" != "$TOPIC" ]] && say "      Its topic is $top, not $TOPIC: once step 1 has saved new answers, set TOPIC=$top in $STATE before step 4."
  say "      Your answers so far are kept aside, so what this run made in $LOG_PROJECT can still be cleaned up: start over prints where it keeps them, and --remove --state takes that path."
  say "   2) Move the sink to this project: it then sends to $TOPIC in $LOG_PROJECT. The topic in $proj gets nothing"
  say "      new, so whatever reads it (an Abstract integration on $proj) stops receiving events: point that at $LOG_PROJECT."
  desc=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(description)' 2>/dev/null)
  f=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(filter)' 2>/dev/null)
  tf=$(sink_tf "$desc" "$f")
  if [[ "$tf" != no ]]; then
    # A gcloud update here would be put back by the next terraform apply, so it is never offered.
    local dir="$ROOT/templates/gcp/gcp-source-audit-logs-$SCOPE" here
    here=$(printf '%q' "$dir")
    if [[ "$tf" == yes ]]; then say "   This sink is managed by Terraform (its description says so). Move it there, not here:"
    else say "   This sink may be managed by Terraform (the template's filter layout or default name, and this setup did not"
         say "   create it). If it is, move it there, not here:"; fi
    say "   a gcloud update would be reverted by the next terraform apply, so this step does not make one."
    say "     In $dir/terraform.tfvars set:  log_project = \"$LOG_PROJECT\""
    [[ "$SCOPE" == project ]] && say "     and keep the sink where it is:  sink_project = \"$SCOPE_ID\""
    say "     The module's topic and subscription carry prevent_destroy, so terraform plan refuses to replace them. Take them,"
    say "     and Abstract's service account, out of the state first. They stay in $proj, with any events not yet read, and"
    say "     the integration reading them keeps working until you delete them:"
    say "       cd $here"
    say "       terraform state rm 'module.log_export.google_pubsub_topic.abstract' 'module.log_export.google_pubsub_subscription.abstract' 'module.log_export.google_service_account.abstract'"
    local email="$SA@$LOG_PROJECT.iam.gserviceaccount.com" imports=()
    gcloud pubsub topics describe "$TOPIC" --project="$LOG_PROJECT" >/dev/null 2>&1 \
      && imports+=("terraform import 'module.log_export.google_pubsub_topic.abstract' projects/$LOG_PROJECT/topics/$TOPIC")
    gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" >/dev/null 2>&1 \
      && imports+=("terraform import 'module.log_export.google_pubsub_subscription.abstract' projects/$LOG_PROJECT/subscriptions/$SUB")
    gcloud iam service-accounts describe "$email" --project="$LOG_PROJECT" >/dev/null 2>&1 \
      && imports+=("terraform import 'module.log_export.google_service_account.abstract' projects/$LOG_PROJECT/serviceAccounts/$email")
    if (( ${#imports[@]} )); then
      say "     This setup already made these in $LOG_PROJECT; import them, or terraform apply stops at \"already exists\":"
      local i; for i in "${imports[@]}"; do say "       $i"; done
    fi
    say "     Then preview, read the plan (it moves the sink and the grants to $LOG_PROJECT), and apply it:"
    say "       terraform plan -out=abstract.tfplan"
    say "       terraform apply abstract.tfplan"
    return 1
  fi
  if ! gcloud pubsub topics describe "$TOPIC" --project="$LOG_PROJECT" >/dev/null 2>&1; then
    say "   The topic $TOPIC does not exist in $LOG_PROJECT yet, so the sink cannot be moved there; this step creates it first."
    bad "topic $TOPIC does not exist in $LOG_PROJECT: run $(again --step 4) and say yes to the topic, then to the move"
    return 1
  fi
  why "The update changes only where the sink sends; its filter and exclusions stay as they are."
  run gcloud logging sinks update "$SINK" "$dest" "$sf" || return 1
  local now; now=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(destination)' 2>/dev/null)
  if [[ "$now" == "$dest" ]]; then
    pass "sink $SINK now sends to $TOPIC in $LOG_PROJECT (read back from the sink)"
    warn "the topic in $proj gets nothing new from now on: whatever reads it there stops receiving events"
    return 0
  fi
  bad "the update ran, but sink $SINK still reads as sending to ${now:-an unreadable destination}"; return 1
}

step4() {
  title 4 "Log pipeline"
  why "A sink at the ${SCOPE:-chosen scope} copies matching audit logs, as they are written, to a Pub/Sub topic."
  why "Abstract reads them from a subscription on that topic. There is no backfill: what the"
  why "filter misses while it is not in place is gone."
  [[ -n "$LOG_PROJECT" && -n "$SCOPE" ]] || { bad "finish steps 1 and 3 first"; return; }

  if gcloud pubsub topics describe "$TOPIC" --project="$LOG_PROJECT" >/dev/null 2>&1; then pass "topic $TOPIC"
  else warn "topic $TOPIC does not exist"; run gcloud pubsub topics create "$TOPIC" --project="$LOG_PROJECT" && { pass "topic created"; TOPIC_CREATED=1; save; }; fi

  if gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" >/dev/null 2>&1; then
    local ttl on; ttl=$(gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" --format='value(expirationPolicy.ttl)')
    on=$(gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" --format='value(topic)')
    [[ "$on" == "projects/$LOG_PROJECT/topics/$TOPIC" ]] && pass "subscription $SUB reads $TOPIC" \
      || bad "subscription $SUB reads $on, not $TOPIC: Abstract would read the wrong feed. Choose another subscription name (SUB) and re-run."
    [[ -z "$ttl" ]] && pass "subscription $SUB, never expires" || bad "subscription $SUB expires after $ttl idle — a quiet week deletes it. Fix: gcloud pubsub subscriptions update $SUB --project=$LOG_PROJECT --expiration-period=never"
  else
    warn "subscription $SUB does not exist"
    why "--expiration-period=never matters: by default an idle subscription is deleted after 31 days."
    why "The retry delays match the Terraform template, so a refused message is redelivered the same way on both paths."
    run gcloud pubsub subscriptions create "$SUB" --topic="$TOPIC" --project="$LOG_PROJECT" \
      --ack-deadline=60 --message-retention-duration="${RETENTION_DAYS}d" --expiration-period=never \
      --min-retry-delay=10s --max-retry-delay=600s && { pass "subscription created"; SUB_CREATED=1; save; }
  fi

  local sf; sf=$(scope_flag); local want; want=$(filter)
  [[ "$DATA_ACCESS" == yes ]] && all_services_read_unconfirmed && \
    warn "these answers ask for DATA_READ on allServices, which was never confirmed, so this filter routes no Data Access logs for it. Step 6 asks: $(again --step 6)"
  local dest="pubsub.googleapis.com/projects/$LOG_PROJECT/topics/$TOPIC"
  # A sink already sending to this topic under another name is adopted, never duplicated:
  # two sinks to one topic deliver every event twice.
  if ! gcloud logging sinks describe "$SINK" "$sf" >/dev/null 2>&1; then
    local other; other=$(gcloud logging sinks list "$sf" --format='value(name,destination)' 2>/dev/null | awk -v d="$dest" '$2==d{print $1; exit}')
    [[ -n "$other" ]] && { say "  found sink $other already sending to $TOPIC; using it"; SINK="$other"; SINK_CREATED_AT=0; save; }
  fi
  if gcloud logging sinks describe "$SINK" "$sf" >/dev/null 2>&1; then
    local d f ic desc ex; d=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(destination)')
    ic=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(includeChildren)')
    if [[ "$d" == "$dest" ]]; then pass "sink $SINK sends to $TOPIC"
    else
      # Until it is moved, the sink feeds another pipeline: nothing below may change its filter or grant it here.
      sink_elsewhere "$d" "$dest" "$sf" || return
    fi
    if [[ "$SCOPE" != project ]]; then
      [[ "$ic" == True ]] && pass "sink covers every project under the $SCOPE (includeChildren)" \
        || bad "sink $SINK does not include child projects: logs from projects under the $SCOPE never reach Abstract. Recreate it with --include-children (or set include_children in Terraform)."
    fi
    # An exclusion drops matching entries even when the filter routes them.
    if ex=$(gcloud logging sinks describe "$SINK" "$sf" --format='json(exclusions)' 2>/dev/null); then
      ex=$(python3 -c 'import json,sys
d=json.loads(sys.stdin.read() or "null") or {}   # no exclusions: Google prints null
print(" ".join(e.get("name","?") for e in d.get("exclusions",[]) if not e.get("disabled")))' <<<"$ex" 2>/dev/null) \
        || ex="(unreadable)"
      [[ -n "$ex" ]] && warn "sink $SINK has exclusions that drop entries before they reach Abstract: $ex. Check none of them matches audit logs: gcloud logging sinks describe $SINK $sf"
    else warn "could not read the exclusions on sink $SINK; check them: gcloud logging sinks describe $SINK $sf"; fi
    # A filter that could not be read is not an empty filter: empty would mean "routes everything".
    local ferr; ferr=$(mktemp)
    if ! f=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(filter)' 2>"$ferr"); then
      bad "could not read the filter of sink $SINK ($(grep -v '^[[:space:]]*$' "$ferr" | head -n1)); nothing was compared or changed"
    elif [[ -z "$f" ]]; then
      # Everything these answers need is routed, but so is every other log at the scope: a warning, not a pass.
      warn "sink $SINK has no filter: it routes every log entry at the $SCOPE, application and network logs too, not only the audit logs these answers need. Abstract's managed GCP parser keeps only Cloud Audit Log records, so the rest is pulled and discarded."
      why "Narrow it by replacing its filter with this step's, not by adding to it. This step never removes what a"
      why "sink routes, so it does not make that change; if Terraform manages this sink, set its log_categories instead."
      say "   replace its filter with: $want"
    else
      # Only ever ADD what is missing, clause by clause (sink_routes.py). An existing sink may route more
      # (firewall, DNS…); that is kept, and named: Abstract's managed parser discards what is not an audit log.
      local other_logs; other_logs=$(python3 "$HERE/sink_routes.py" --non-audit "$f" 2>/dev/null)
      [[ -n "$other_logs" ]] && warn "sink $SINK also routes logs that are not Cloud Audit Logs: $other_logs. Abstract's managed GCP parser keeps only Cloud Audit Log records, so these are pulled and discarded. This step never removes a clause: take them out of the sink (its tfvars, if Terraform manages it) and collect them with templates/gcp/gcp-source-network-threat-logs."
      local missing_clauses; missing_clauses=$(python3 "$HERE/sink_routes.py" --missing "$f" "$want") || missing_clauses="?"
      desc=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(description)' 2>/dev/null)
      # A sink Terraform built before the managed-by marker existed has no marker, but its filter carries the
      # module's "\n  OR " join, or it has the template's default name and this setup did not create it.
      local maybe_tf=false
      [[ "$f" == *$'\n  OR '* ]] && maybe_tf=true
      [[ "$SINK" == abstract-org-audit-sink && "${SINK_CREATED_AT:-0}" == 0 ]] && maybe_tf=true
      if [[ "$missing_clauses" == "?" ]]; then bad "could not compare the filter of sink $SINK with what these answers need"
      elif [[ -z "$missing_clauses" ]]; then pass "sink filter routes everything these answers need"
      elif [[ "$desc" == *"managed-by: abstract-cloud-templates (terraform)"* ]]; then
        # The next terraform apply would undo a change made here, silently.
        warn "the sink does not yet route: $missing_clauses"
        say "   This sink is managed by Terraform (its description says so): change its tfvars and apply, not the sink:"
        python3 "$HERE/sink_routes.py" --tfvars "$f" "$want" | sed 's/^/     /'
      else
        warn "the sink does not yet route: $missing_clauses"
        if $maybe_tf; then
          say "   This sink may be managed by Terraform (the template's filter layout or default name, and this setup did not"
          say "   create it). If it is, change its tfvars and apply instead, and answer no below: the next apply would undo"
          say "   an update made here. One apply also adds the managed-by marker to its description, so this is not asked again:"
          python3 "$HERE/sink_routes.py" --tfvars "$f" "$want" | sed 's/^/     /'
        fi
        why "Its existing filter is kept; only the missing part is added. If Terraform manages this sink, add it there and answer no."
        run gcloud logging sinks update "$SINK" "$sf" --log-filter="($f) OR $missing_clauses" && pass "sink filter extended"
      fi
    fi
    rm -f "$ferr"
  else
    warn "sink $SINK does not exist at the $SCOPE"
    existing_audit_sinks "$sf" "$dest"
    say "   filter: $want"
    local ic=""; [[ "$SCOPE" != project ]] && ic="--include-children"
    # shellcheck disable=SC2086
    run gcloud logging sinks create "$SINK" "$dest" "$sf" $ic --log-filter="$want" && { pass "sink created"; SINK_CREATED_AT=$(date +%s); save; }
  fi

  local w; w=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(writerIdentity)' 2>/dev/null)
  if [[ -n "$w" ]]; then
    if gcloud pubsub topics get-iam-policy "$TOPIC" --project="$LOG_PROJECT" --format=json 2>/dev/null | grep -q "\"$w\""; then
      pass "the sink's own identity can publish to $TOPIC"
    else
      bad "the sink's identity cannot publish yet — the #1 missed step. The sink looks healthy and sends nothing."
      if run gcloud pubsub topics add-iam-policy-binding "$TOPIC" --project="$LOG_PROJECT" --member="$w" --role=roles/pubsub.publisher --format=none; then
        # Read back, not assumed: the grant is what makes the sink deliver.
        if gcloud pubsub topics get-iam-policy "$TOPIC" --project="$LOG_PROJECT" --format=json 2>/dev/null | grep -q "\"$w\""; then
          pass "publisher granted to the sink identity (read back from the topic's policy)"
        else bad "the grant ran, but the topic's policy does not list $w yet. Check again in a minute: $(again --step 4 --check)"; fi
      fi
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
step5() {
  title 5 "Abstract's access"
  why "Abstract signs in as its own service account and may only read the one subscription."
  why "Subscriber, never publisher, never project-wide."
  [[ -n "$LOG_PROJECT" ]] || { bad "finish step 3 first"; return; }
  local email="$SA@$LOG_PROJECT.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$email" --project="$LOG_PROJECT" >/dev/null 2>&1; then pass "service account $email"
  else warn "service account $email does not exist"
       run gcloud iam service-accounts create "$SA" --project="$LOG_PROJECT" --display-name="Abstract Security log reader" && { pass "service account created"; SA_CREATED=1; save; }; fi

  # Least privilege: roles/pubsub.subscriber on the one subscription, and nothing else it can be checked for.
  local pol roles
  if ! pol=$(gcloud pubsub subscriptions get-iam-policy "$SUB" --project="$LOG_PROJECT" --format=json 2>&1) \
     || ! roles=$(member_roles "serviceAccount:$email" <<<"$pol"); then
    warn "could not read the access policy of $SUB ($(first_line "$pol")); whether $email can read it was not checked"
  elif [[ "$roles" == roles/pubsub.subscriber ]]; then
    pass "it can read $SUB (roles/pubsub.subscriber on the subscription, and no other role there)"
  else
    if [[ " $roles " == *" roles/pubsub.subscriber "* ]]; then pass "it can read $SUB (roles/pubsub.subscriber on the subscription)"
    else
      bad "it cannot read $SUB yet"
      run gcloud pubsub subscriptions add-iam-policy-binding "$SUB" --project="$LOG_PROJECT" --member="serviceAccount:$email" --role=roles/pubsub.subscriber >/dev/null && pass "subscriber granted"
    fi
    local extra; extra=$(tr ' ' '\n' <<<"$roles" | grep -vx 'roles/pubsub.subscriber' | grep . | paste -sd' ' -)
    [[ -n "$extra" ]] && warn "$email also holds $extra on $SUB. It needs only roles/pubsub.subscriber; remove the others."
  fi
  # A grant on the topic (publisher above all) would let the Abstract credential write events into the feed.
  if ! pol=$(gcloud pubsub topics get-iam-policy "$TOPIC" --project="$LOG_PROJECT" --format=json 2>&1) \
     || ! roles=$(member_roles "serviceAccount:$email" <<<"$pol"); then
    warn "could not read the access policy of the topic $TOPIC ($(first_line "$pol")); grants there were not checked"
  elif [[ -n "$roles" ]]; then
    warn "$email holds ${roles// /, } on the topic $TOPIC. It needs none there; remove it."
  fi
  # Anything broader than that one subscription is a finding, not a convenience.
  local proj
  if ! proj=$(gcloud projects get-iam-policy "$LOG_PROJECT" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$email" --format='value(bindings.role)' 2>&1); then
    warn "could not read the IAM policy of project $LOG_PROJECT (${proj%%$'\n'*}); project-wide roles were not checked"
  elif grep -q . <<<"$proj"; then
    warn "$email also holds project-wide roles on $LOG_PROJECT ($(paste -sd' ' - <<<"$proj")). It needs none; remove them."
  else pass "no roles granted directly on project $LOG_PROJECT (roles inherited from a folder or the organization are not checked here)"; fi

  # The key. A file for another account (an earlier logging project, a start-over) would sign Abstract in as
  # an account with no grant on this subscription, so the feed would never start.
  if [[ -f "$KEY_FILE" ]] && key_for "$KEY_FILE" "$email"; then pass "key file ready to upload: $KEY_FILE"
  elif [[ -f "$KEY_FILE" ]]; then
    if $CHECK_ONLY; then bad "key file $KEY_FILE belongs to $(key_field "$KEY_FILE" client_email || echo 'an unreadable account'), not $email. Run --step 5 to replace it."
    else
      local aside rv; aside="$KEY_FILE.other-$(date +%Y%m%d%H%M%S)"; rv=$(revoke_hint "$KEY_FILE") || rv=""
      warn "key file $KEY_FILE belongs to $(key_field "$KEY_FILE" client_email || echo 'an unreadable account'), not $email. Moving it to $aside (delete it once you know nothing uses it) and making a key for $email."
      [[ -n "$rv" ]] && why "Its key stays valid in Google after the file is deleted. Once you know nothing uses it: $rv"
      mv "$KEY_FILE" "$aside" && make_key "$email" "$KEY_FILE" KEY_ID
    fi
  else
    local ids n
    if ! ids=$(gcloud iam service-accounts keys list --iam-account="$email" --managed-by=user --format='value(name.basename())' 2>&1); then
      warn "could not list the keys of $email (${ids%%$'\n'*}). No key was made: run this step again."
      return
    fi
    n=$(grep -c . <<<"$ids")
    if (( n > 1 )); then
      warn "$n keys exist for $email. Abstract needs one; every other key is one more credential to the subscription. Step 10 shows ${KEY_ID:+which one ($KEY_ID) was made for Abstract and }the ones you can delete."
    elif [[ -n "$KEY_ID" ]] && grep -qx "$KEY_ID" <<<"$ids"; then
      pass "the key made for Abstract ($KEY_ID) still exists; Abstract uses the one you uploaded. Make another only if it was lost."
    elif (( n == 1 )); then pass "1 key already exists; Abstract uses the one you uploaded. Make another only if it was lost."; fi
    if (( n > 0 )); then ! $CHECK_ONLY && yes_no "Create a new key anyway?" && make_key "$email" "$KEY_FILE" KEY_ID
    else warn "no key yet. Abstract needs one to sign in."; ! $CHECK_ONLY && make_key "$email" "$KEY_FILE" KEY_ID; fi
  fi
}

first_line() { local l="${1%%$'\n'*}"; printf '%s' "${l:-an empty or unreadable reply}"; }
# member_roles <member>: the roles a policy (JSON on stdin) grants that member directly; status 1 if unreadable.
member_roles() {
  python3 -c 'import json, sys
d = json.loads(sys.stdin.read())
print(" ".join(sorted({b["role"] for b in d.get("bindings", []) if sys.argv[1] in b.get("members", [])})))' "$1" 2>/dev/null
}
# key_field <file> <field>: one field of a key file, never the private key itself.
key_field() { python3 -c 'import json, sys
v = json.load(open(sys.argv[1])).get(sys.argv[2], "")
print(v) if v else sys.exit(1)' "$1" "$2" 2>/dev/null; }
# Key files steps 5 and 7 moved aside (they belonged to another account): still live private keys until deleted.
aside_keys() { local f; for f in "$KEY_FILE".other-* "$WS_KEY_FILE".other-*; do [[ -f "$f" ]] && printf '%s\n' "$f"; done; }
key_for() { [[ "$(key_field "$1" client_email)" == "$2" ]]; }   # key_for <file> <service-account email>
# revoke_hint <key file>: the command that deletes, in Google, the key a file holds. Deleting the file leaves
# the key valid, and the file is the only record of which key it was, so this is read before it goes.
revoke_hint() {
  local id email; id=$(key_field "$1" private_key_id) && email=$(key_field "$1" client_email) || return 1
  printf 'gcloud iam service-accounts keys delete %s --iam-account=%s' "$id" "$email"
}

make_key() {  # make_key <service-account email> <file> <variable that records its id>
  why "The key is written to a file only you can read. Upload it to Abstract, then delete it."
  mkdir -p "$KEY_DIR" && chmod 700 "$KEY_DIR"
  if run gcloud iam service-accounts keys create "$2" --iam-account="$1"; then
    chmod 600 "$2"
    # The key id is not a secret (Google lists it); recording it is what lets step 10 tell keys apart.
    local id; id=$(key_field "$2" private_key_id) || id=""
    printf -v "$3" '%s' "$id"; save
    pass "key written to $2 (not printed)${id:+; its id is $id}"
    offer_download "$2" "the key"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
audit_config_json() {  # [resource url, default the scope's]: its auditConfigs as JSON; on failure, why, and status 1
  local url="${1:-}"
  if [[ -z "$url" ]]; then [[ -n "$SCOPE" && -n "$SCOPE_ID" ]] || { printf 'no scope chosen'; return 1; }; url=$(scope_url); fi
  local body; body=$(curl -s -w '\n%{http_code}' -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" \
    -d '{}' "$url:getIamPolicy") || { printf 'the request did not complete'; return 1; }
  # An error, an empty body or a policy with no etag is never read as "no audit settings": a write built on
  # it would replace every audit config at the scope, unguarded by an etag.
  python3 -c 'import json, sys
code, raw = sys.argv[1], sys.stdin.read()
try: d = json.loads(raw)
except Exception: print(f"HTTP {code}, " + ("an empty reply" if not raw.strip() else "a reply that is not JSON")); sys.exit(1)
if not isinstance(d, dict) or "error" in d or code != "200" or not d.get("etag"):
    e = d.get("error", {}) if isinstance(d, dict) else {}
    print(f"HTTP {code}: " + ((e.get("message") if isinstance(e, dict) else str(e)) or "no etag in the reply")); sys.exit(1)
print(json.dumps({"etag": d["etag"], "auditConfigs": d.get("auditConfigs", [])}))' "${body##*$'\n'}" <<<"${body%$'\n'*}"
}

# allServices with DATA_READ logs every read of every service at the scope, and step 4 routes an unrestricted
# Data Access clause for it, so all of it goes to Pub/Sub and Abstract. The Terraform module refuses it without
# acknowledge_data_read; here it needs a yes of its own, recorded as DA_ALL_READ_ACK=1, before step 4 routes it
# or step 6 turns it on. Returns 0 when there is nothing to confirm, or it was confirmed (now or before).
ack_all_services_read() {
  all_services_read_unconfirmed || return 0
  warn "DATA_READ on allServices records every read of every service across the $SCOPE $SCOPE_ID (BigQuery queries,"
  why "Cloud Storage object reads, and the rest), and the sink routes all of it to Pub/Sub and Abstract. On a busy"
  why "estate that moves total volume, and the Pub/Sub and Abstract cost, by one to two orders of magnitude."
  why "Name the services instead, or say yes knowingly."
  if yes_no "Log and route DATA_READ for every service across the $SCOPE, with that volume and cost?"; then
    DA_ALL_READ_ACK=1; return 0
  fi
  say "  switch 1 not changed, and switch 2 not changed either: DATA_READ on allServices was not confirmed"
  return 1
}

# The services and log types step 6 turns on. A no to allServices + DATA_READ asks again at once, offering the
# default services, so a declined answer is never saved and the next run never meets it again.
ask_data_access_services() {
  DA_ALL_READ_ACK=0
  while :; do
    DA_SERVICES=$(csv "$(ask "Services (comma-separated)" "$DA_SERVICES" valid_services)")
    DA_TYPES=$(csv "$(ask "Log types (ADMIN_READ, DATA_WRITE, DATA_READ)" "$DA_TYPES" valid_log_types)")
    ack_all_services_read && break
    say "  Name the services instead (the default services are offered):"
    DA_SERVICES="$DA_DEFAULT_SERVICES"; DA_TYPES="$DA_DEFAULT_TYPES"
  done
  save
}

step6() {
  title 6 "Data Access logs (optional)"
  why "Admin Activity logs are always on. Data Access logs (who read or changed data in BigQuery,"
  why "Cloud Storage, KMS…, and who minted service-account tokens or exchanged federated identities)"
  why "are OFF until you turn them on. It takes TWO switches:"
  why "  switch 1 — generate them: the audit config at the ${SCOPE:-chosen scope}"
  why "  switch 2 — route them:    the sink filter (step 4 adds them when this is on)"
  why "For most services either alone does nothing, silently. BigQuery writes its Data Access logs by default,"
  why "so it needs only the routing switch. DATA_READ is high volume; it is off by default here."
  if [[ "$DATA_ACCESS" != yes ]] && ! $CHECK_ONLY; then
    yes_no "Turn on Data Access logs?" || { say "  skipped — Admin Activity still flows"; return; }
    DATA_ACCESS=yes; DA_CHANGED=0
    why "iam.googleapis.com records service-account impersonation and token minting; sts.googleapis.com"
    why "records Workload Identity Federation (GitHub Actions, AWS, Azure). Keep both unless you have a reason."
    ask_data_access_services
  fi
  [[ "$DATA_ACCESS" == yes ]] || { say "  off (your choice)"; return; }
  [[ -n "$SCOPE" && -n "$SCOPE_ID" ]] || { bad "choose a scope first (step 1)"; return; }
  # Saved answers (an older file, or a run left at the services prompt) are confirmed here, before switch 1 or
  # switch 2 is looked at, whether switch 1 is already on or not. A no asks for the services at once.
  if all_services_read_unconfirmed; then
    if ! interactive; then
      warn "these answers ask for DATA_READ on allServices, which was never confirmed: step 4 routes no Data Access logs for it, and this step changes nothing. Confirm it, or name the services: $(again --step 6)"
      return
    fi
    if ack_all_services_read; then save
    else
      say "  Name the services instead (the default services are offered):"
      DA_SERVICES="$DA_DEFAULT_SERVICES"; DA_TYPES="$DA_DEFAULT_TYPES"
      ask_data_access_services
    fi
  fi

  local cur missing switched; switched=$(audit_services "$DA_SERVICES")
  if ! cur=$(audit_config_json); then
    bad "could not read the audit settings at the $SCOPE ($cur). Switch 1 was not checked, and nothing was changed."
    # Switch 2 decides what leaves Google; with switch 1 unknown, adding a route could start exporting logs
    # nobody checked (BigQuery's are on by default). Report and stop (PR #55 review).
    warn "routing was not changed either. Run step 6 again once the audit settings can be read."
    return
  elif ! missing=$(python3 - "$cur" "$switched" "$DA_TYPES" <<'PY'
import json, sys
cur = json.loads(sys.argv[1]); svcs = sys.argv[2].split(","); types = sys.argv[3].split(",")
have = {}
for c in cur.get("auditConfigs", []):
    have.setdefault(c["service"], set()).update(l["logType"] for l in c.get("auditLogConfigs", []))
allsvc = have.get("allServices", set())
print(" ".join(f"{s}:{t}" for s in svcs for t in types if t not in have.get(s, set()) and t not in allsvc))
PY
); then
    bad "could not compare the audit settings at the $SCOPE with these answers. Nothing was changed."
  elif [[ -z "$missing" ]]; then pass "switch 1: Data Access is generated for ${switched//,/, } ($DA_TYPES)"
  else
    bad "switch 1 is off for: $missing"
    why "This changes ONLY the audit settings at the ${SCOPE:-chosen scope} (updateMask=auditConfigs); role bindings are untouched."
    why "A copy of the current settings is saved first."
    # allServices + DATA_READ was confirmed above, before anything here could act on it.
    if ! $CHECK_ONLY && yes_no "Turn switch 1 on now?"; then
      # Next to the answers file, not in the current folder: clean-up points at it, so it must be findable.
      local backup; backup="$(dirname "$STATE")/abstract-audit-config-backup-$(date +%Y%m%d%H%M%S).json"
      ( umask 077; printf '%s\n' "$cur" > "$backup" ) && say "  saved current settings to $backup"
      offer_download "$backup" "the copy of the current audit settings"
      local body
      if ! body=$(python3 - "$cur" "$switched" "$DA_TYPES" <<'PY'
import json, sys
cur = json.loads(sys.argv[1]); svcs = sys.argv[2].split(","); types = sys.argv[3].split(",")
if not cur.get("etag"):
    sys.exit(1)                     # never write without the etag: it is what stops a lost update
cfgs = {c["service"]: c for c in cur.get("auditConfigs", [])}
for s in svcs:
    c = cfgs.setdefault(s, {"service": s, "auditLogConfigs": []})
    have = {l["logType"] for l in c["auditLogConfigs"]}
    c["auditLogConfigs"] += [{"logType": t} for t in types if t not in have]
print(json.dumps({"policy": {"etag": cur["etag"], "auditConfigs": list(cfgs.values())}, "updateMask": "auditConfigs"}))
PY
); then bad "the audit settings had no etag; nothing was sent"
      else
        local out code; out=$(curl -s -w '\n%{http_code}' -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" \
          -d "$body" "$(scope_url):setIamPolicy"); code=${out##*$'\n'}; out=${out%$'\n'*}
        # On only when Google answers with the policy it stored; an error or an empty reply is not a yes.
        if [[ "$code" == 200 ]] && python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if "auditConfigs" in d and "error" not in d else 1)' <<<"$out" 2>/dev/null; then
          pass "switch 1 on"
          DA_CHANGED=1; DA_BACKUP="$backup"; DA_ADDED="$missing"; save
        else
          bad "Google did not confirm the change (HTTP ${code:-?}: $(python3 -c 'import json,sys
try: print(json.load(sys.stdin)["error"]["message"])
except Exception: print("<empty or unreadable reply>")' <<<"$out")). Check with --step 6 --check before trying again; the copy of the settings stays at $backup."
        fi
      fi
    fi
  fi
  local sf; sf=$(scope_flag); local routed; routed=$(routed_services "$DA_SERVICES")
  local f dropped
  if ! f=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(filter)' 2>/dev/null); then
    bad "switch 2: sink $SINK was not found at the ${SCOPE:-chosen scope}; step 4 creates it"
    $CHECK_ONLY || step4; return
  fi
  # Per service, per OR alternative: a data_access clause naming other services routes none of these.
  local -a services; IFS=',' read -ra services <<<"$routed"
  dropped=$(python3 "$HERE/sink_routes.py" "$f" "${services[@]}")
  if [[ -z "$dropped" ]]; then pass "switch 2: the sink routes Data Access logs for ${routed//,/, }"
  else bad "switch 2 is off for: $dropped"; $CHECK_ONLY || { why "Step 4 updates the filter; running it now."; step4; }; fi
}

# ─────────────────────────────────────────────────────────────────────────────
step7() {
  title 7 "Google Workspace logs (optional)"
  why "Abstract reads sign-ins, admin changes and token grants in Google Workspace from the"
  why "Workspace Reports API, not Cloud Logging, with a separate service account that a"
  why "Workspace SUPER ADMIN allows through domain-wide delegation."
  why "A Google Cloud Owner cannot do that last part; plan for the super admin."
  if [[ "$WORKSPACE" != yes ]] && ! $CHECK_ONLY; then
    yes_no "Set up Google Workspace logs?" || { say "  skipped"; return; }
    WORKSPACE=yes; WS_ADMIN=$(ask "Workspace admin email Abstract should act as" "$WS_ADMIN" valid_email); save
  fi
  [[ "$WORKSPACE" == yes ]] || { say "  off (your choice)"; return; }
  [[ -n "$LOG_PROJECT" ]] || { bad "finish step 3 first"; return; }

  gcloud services list --enabled --project="$LOG_PROJECT" --format='value(config.name)' 2>/dev/null | grep -qx admin.googleapis.com \
    && pass "Admin SDK API enabled" || { warn "Admin SDK API is off"; run gcloud services enable admin.googleapis.com --project="$LOG_PROJECT" && pass "Admin SDK API enabled"; }

  local email="$WS_SA@$LOG_PROJECT.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$email" --project="$LOG_PROJECT" >/dev/null 2>&1; then pass "service account $email"
  else warn "service account $email does not exist"
       run gcloud iam service-accounts create "$WS_SA" --project="$LOG_PROJECT" --display-name="Abstract Security Workspace reader" && { pass "created"; WS_SA_CREATED=1; save; }; fi
  # A new service account can take a few seconds to become readable.
  local cid="" i
  for i in 1 2 3 4 5 6; do
    cid=$(gcloud iam service-accounts describe "$email" --project="$LOG_PROJECT" --format='value(uniqueId)' 2>/dev/null)
    [[ -n "$cid" ]] && break; $CHECK_ONLY && break; sleep 5
  done
  [[ -n "$cid" ]] || { bad "cannot read $email yet. Run this step again in a minute."; return; }
  cat <<EOF

  ${B}Hand this to a Workspace super admin:${O}
    admin.google.com → Security → Access and data control → API controls
      → Domain-wide delegation → Add new
    Client ID     $cid
    OAuth scope   https://www.googleapis.com/auth/admin.reports.audit.readonly
    (read-only, and the only scope Abstract's Workspace integration requests)

EOF
  if [[ -f "$WS_KEY_FILE" ]] && key_for "$WS_KEY_FILE" "$email"; then pass "key file ready: $WS_KEY_FILE"
  elif [[ -f "$WS_KEY_FILE" ]]; then
    if $CHECK_ONLY; then bad "key file $WS_KEY_FILE belongs to $(key_field "$WS_KEY_FILE" client_email || echo 'an unreadable account'), not $email. Run --step 7 to replace it."
    else
      local aside rv; aside="$WS_KEY_FILE.other-$(date +%Y%m%d%H%M%S)"; rv=$(revoke_hint "$WS_KEY_FILE") || rv=""
      warn "key file $WS_KEY_FILE belongs to $(key_field "$WS_KEY_FILE" client_email || echo 'an unreadable account'), not $email. Moving it to $aside and making a key for $email."
      [[ -n "$rv" ]] && why "Its key stays valid in Google after the file is deleted. Once you know nothing uses it: $rv"
      mv "$WS_KEY_FILE" "$aside" && make_key "$email" "$WS_KEY_FILE" WS_KEY_ID
    fi
  else ws_key_gone "$email"; fi
  if [[ -f "$WS_KEY_FILE" && -n "$WS_ADMIN" ]] && key_for "$WS_KEY_FILE" "$email"; then
    verify_workspace "$WS_KEY_FILE" "$WS_ADMIN"
  fi
}

# ws_key_gone <email>: no key file. That is normal once the key is uploaded to Abstract and deleted, so the keys
# in Google decide. A key that exists is never replaced unasked: every Workspace key reads the audit reports as
# the admin, through domain-wide delegation. Only the first key is offered; another needs --step 7 --new-key.
ws_key_gone() {
  local email="$1" ids n old="$WS_KEY_ID" live=false
  if ! ids=$(gcloud iam service-accounts keys list --iam-account="$email" --managed-by=user --format='value(name.basename())' 2>&1); then
    warn "could not list the keys of $email (${ids%%$'\n'*}). No key was made: run this step again."; return
  fi
  n=$(grep -c . <<<"$ids")
  if (( n == 0 )); then
    warn "no key yet. Abstract needs one to sign in."; ! $CHECK_ONLY && make_key "$email" "$WS_KEY_FILE" WS_KEY_ID; return
  fi
  if [[ -n "$old" ]] && grep -qx "$old" <<<"$ids"; then live=true
    pass "the key made for Abstract ($old) still exists in Google. Step 7 wrote it to $WS_KEY_FILE; it is gone from here, as it should be once you downloaded it and uploaded it to Abstract."
    why "Delegation is checked with that file, so it cannot be checked again here: Workspace events in Abstract are the check now."
  else
    warn "$email has $n key(s), and none is the one this setup recorded making for Abstract${old:+ ($old)}. Each one reads your Workspace audit reports as $WS_ADMIN; step 10 lists them."
  fi
  if ! $NEW_KEY; then
    why "Lost the key, or rotating it? Make another only then:  $(again --step 7 --new-key)"; return
  fi
  make_key "$email" "$WS_KEY_FILE" WS_KEY_ID
  if $live && [[ "$WS_KEY_ID" != "$old" ]]; then
    why "Once Abstract has the new key, revoke the old one:  gcloud iam service-accounts keys delete $old --iam-account=$email"
  fi
}

# Prove delegation works: sign a JWT as the service account for the admin, call the Reports API.
verify_workspace() {
  local r; r=$(python3 - "$1" "$2" <<'PY' 2>&1
import json, sys, time, base64, urllib.request, urllib.parse, subprocess, tempfile, os
key = json.load(open(sys.argv[1])); sub = sys.argv[2]
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
now = int(time.time())
head = b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
claim = b64(json.dumps({"iss": key["client_email"], "sub": sub, "aud": "https://oauth2.googleapis.com/token",
    "scope": "https://www.googleapis.com/auth/admin.reports.audit.readonly", "iat": now, "exp": now + 600}).encode())
with tempfile.NamedTemporaryFile("w", delete=False) as f:
    f.write(key["private_key"]); pem = f.name
try:
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", pem], input=head + b"." + claim, capture_output=True, check=True).stdout
finally:
    os.unlink(pem)
jwt = head + b"." + claim + b"." + b64(sig)
data = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": jwt.decode()}).encode()
try:
    tok = json.load(urllib.request.urlopen("https://oauth2.googleapis.com/token", data))["access_token"]
except urllib.error.HTTPError as e:
    desc = json.load(e).get("error_description", str(e))
    # A brand-new key is rejected as "Invalid signature" for about a minute. Never echo the token.
    print("NEWKEY" if "Invalid signature" in desc else "DELEGATION " + desc.split(": ey")[0][:200]); sys.exit()
req = urllib.request.Request("https://admin.googleapis.com/admin/reports/v1/activity/users/all/applications/login?maxResults=1", headers={"Authorization": "Bearer " + tok})
try:
    urllib.request.urlopen(req); print("OK")
except urllib.error.HTTPError as e:
    print(f"REPORTS {e.code}")
PY
)
  case "$r" in
    OK) pass "delegation works: the Reports API answered as $2" ;;
    NEWKEY) warn "the new key is not active yet (Google takes about a minute). Check again shortly: $0 --step 7 --check" ;;
    DELEGATION*) bad "delegation is not in place yet (${r#DELEGATION }). The super admin step above is still needed; it can take a few minutes after saving." ;;
    *) bad "the Reports API refused ($r). Check that $2 is a Workspace admin." ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
step8() {
  title 8 "Health alerts (optional)"
  why "A stopped pipeline is silent. These alerts tell you: sink export errors, no messages,"
  why "and Abstract not consuming. This runs the repo's gcp-monitoring-pipeline-health-alerts template."
  if [[ "$ALERTS" != yes ]] && ! $CHECK_ONLY; then
    yes_no "Set up health alerts?" || { say "  skipped"; return; }
    ALERTS=yes; save
  fi
  [[ "$ALERTS" == yes ]] || { say "  off (your choice)"; return; }
  # Alerts, and the channel they mail, live in the Monitoring API: turn it on before anything is made there.
  local apis
  if ! apis=$(gcloud services list --enabled --project="$LOG_PROJECT" --format='value(config.name)' 2>&1); then
    warn "could not list the APIs on in $LOG_PROJECT (${apis%%$'\n'*}); the Monitoring API was not checked"
  elif ! grep -qx monitoring.googleapis.com <<<"$apis"; then
    warn "the Monitoring API is off in $LOG_PROJECT; alerts need it"
    $CHECK_ONLY && return
    run gcloud services enable monitoring.googleapis.com --project="$LOG_PROJECT" && pass "Monitoring API enabled" \
      || { bad "alerts were not created: the Monitoring API is off"; return; }
  fi
  # REST, not "gcloud alpha": the alpha component may not be installed, and installing it prompts.
  # A listing that failed is not "no alerts" (mon_list says so and counts it).
  mon_list alertPolicies "alert policies" || return
  local before="$MON_NAMES" have; have=$(grep -c . <<<"$before")
  # gcp-monitoring-pipeline-health-alerts makes three policies without a dead-letter topic (this setup uses none).
  if (( have >= 3 )); then pass "$have Abstract alert policies exist"; return; fi
  (( have > 0 )) && warn "only ${have} of 3 alert policies exist" || warn "no Abstract alert policies yet"
  $CHECK_ONLY && return
  need terraform
  while [[ -z "$ALERT_EMAIL" ]]; do
    ALERT_EMAIL=$(ask "Email that receives the alerts (Enter for none)" "" "?valid_email")
    [[ -n "$ALERT_EMAIL" ]] || { yes_no "Create the alerts with nobody to tell?" && break; }
  done; save
  local dir="$ROOT/templates/gcp/gcp-monitoring-pipeline-health-alerts" ch="[]"
  if [[ -n "$ALERT_EMAIL" ]]; then
    # One channel per address: a retry reuses the channel an earlier attempt made, never adds another.
    local cname="" list code
    list=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $(token)" "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/notificationChannels?pageSize=200")
    code=${list##*$'\n'}
    [[ "$code" == 200 ]] && cname=$(python3 -c 'import json, sys
for c in json.loads(sys.argv[1]).get("notificationChannels", []):
    if c.get("type") == "email" and c.get("displayName", "").startswith("Abstract log pipeline") \
       and c.get("labels", {}).get("email_address", "").lower() == sys.argv[2].lower():
        print(c["name"]); break' "${list%$'\n'*}" "$ALERT_EMAIL" 2>/dev/null)
    if [[ -n "$cname" ]]; then pass "email channel for $ALERT_EMAIL already exists ($cname); using it"
    else
      local body; body=$(python3 -c 'import json,sys;print(json.dumps({"type":"email","displayName":"Abstract log pipeline","labels":{"email_address":sys.argv[1]}}))' "$ALERT_EMAIL")
      cname=$(curl -s -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" -d "$body" \
        "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/notificationChannels" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("name",""))' 2>/dev/null)
      [[ -n "$cname" ]] || { bad "could not create the email channel for $ALERT_EMAIL; alerts not created, so none are silent."; return; }
      pass "email channel for $ALERT_EMAIL"
      # Added to what earlier attempts recorded, never in place of it: clean-up removes exactly these.
      ALERT_CHANNELS=$(printf '%s\n' $ALERT_CHANNELS "$cname" | grep . | sort -u | paste -sd' ' -); save
    fi
    ch="[\"$cname\"]"
  fi
  python3 -c 'import json,sys;print(json.dumps({"log_project":sys.argv[1],"topic_id":sys.argv[2],"subscription_id":sys.argv[3],"notification_channels":json.loads(sys.argv[4]),"acknowledge_no_channel":sys.argv[4]=="[]"}, indent=2))' \
    "$LOG_PROJECT" "$TOPIC" "$SUB" "$ch" > "$dir/abstract.auto.tfvars.json"
  terraform -chdir="$dir" init -input=false >/dev/null || { bad "terraform init failed in $dir"; return; }
  terraform -chdir="$dir" plan -input=false -out=abstract.tfplan || { bad "terraform plan failed"; return; }
  # The plan above is the preview; approving it here is the only confirmation.
  local ok=0
  run terraform -chdir="$dir" apply -input=false abstract.tfplan && ok=1
  # Record what this apply added, even when it failed part-way, and keep what earlier attempts
  # recorded: clean-up removes exactly these and never someone else's. A listing that failed records nothing.
  if mon_list alertPolicies "alert policies"; then
    local added; added=$(comm -13 <(printf '%s\n' "$before" | sort) <(printf '%s\n' "$MON_NAMES" | sort))
    ALERT_POLICIES=$(printf '%s\n' $ALERT_POLICIES $added | grep . | sort -u | paste -sd' ' -); save
  else warn "the alerts this apply made were not recorded; clean-up will list them as not made here"; fi
  (( ok )) && pass "alerts created" || bad "terraform apply failed; the alerts it did create are recorded for clean-up"
}

# Where the probe must be written: somewhere the sink can see, with an API that is on. The logging project
# when it sits under the scope, otherwise any active project under it, however deeply nested.
probe_project() {
  case "$SCOPE" in
    project) echo "$SCOPE_ID" ;;
    organization|folder)
      if gcloud projects get-ancestors "$LOG_PROJECT" --format='value(id)' 2>/dev/null | grep -qx "$SCOPE_ID"; then echo "$LOG_PROJECT"
      else project_under "$SCOPE" "$SCOPE_ID"; fi ;;
  esac
}
# project_under <organization|folder> <id>: the first active project found walking down the folders,
# breadth first, at most 30 containers looked at.
project_under() {
  local -a queue=("$1:$2"); local i=0 t id p f
  while (( i < ${#queue[@]} && i < 30 )); do
    t=${queue[$i]%%:*}; id=${queue[$i]#*:}; i=$((i + 1))
    p=$(gcloud projects list --filter="parent.type=$t AND parent.id=$id AND lifecycleState:ACTIVE" --format='value(projectId)' --limit=1 2>/dev/null)
    [[ -n "$p" ]] && { echo "$p"; return; }
    for f in $(gcloud resource-manager folders list "--$t=$id" --format='value(ID)' 2>/dev/null); do queue+=("folder:$f"); done
  done
}

step9() {
  title 9 "Test and verify"
  why "Writes a harmless admin event inside the ${SCOPE:-chosen scope} (creates and deletes a log-based metric),"
  why "then waits for it on a throwaway subscription on the same topic, never on Abstract's."
  why "A new sink routes nothing for about 3 minutes."
  [[ -n "$LOG_PROJECT" ]] || { bad "finish step 3 first"; return; }
  if $CHECK_ONLY; then
    gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" >/dev/null 2>&1 && pass "subscription is readable" || bad "subscription not found"
    return
  fi
  local pp; pp=$(probe_project)
  [[ -n "$pp" ]] || { bad "found no active project under the $SCOPE $SCOPE_ID to write the test event in"; return; }
  yes_no "Send a test event from $pp now?" || return
  local age=$(( $(date +%s) - ${SINK_CREATED_AT:-0} ))
  if (( SINK_CREATED_AT > 0 && age < 240 )); then
    say "  the sink is $age seconds old; waiting $(( 240 - age ))s so it is routing before the test (an earlier event would be lost for good)"
    sleep $(( 240 - age ))
  fi
  local probe got="" i
  send_probe() {
    probe="abstract-probe-$(date +%s)"
    printf '%s   $ gcloud logging metrics create %s --project=%s … && gcloud logging metrics delete %s%s\n' "$D" "$probe" "$pp" "$probe" "$O"
    if gcloud logging metrics create "$probe" --project="$pp" --description="Abstract pipeline test; deleted at once" --log-filter='logName:"abstract-probe"' --quiet >/dev/null 2>&1; then
      gcloud logging metrics delete "$probe" --project="$pp" --quiet >/dev/null 2>&1
    # A log-based metric needs billing on the project. Without it, a Pub/Sub topic create and
    # delete writes the same kind of Admin Activity event.
    elif gcloud pubsub topics create "$probe" --project="$pp" --quiet >/dev/null 2>&1; then
      printf '%s   (no billing on %s, so the test event is a Pub/Sub topic create and delete instead)%s\n' "$D" "$pp" "$O"
      gcloud pubsub topics delete "$probe" --project="$pp" --quiet >/dev/null 2>&1
    else
      bad "could not write the test event in $pp (needs logging.logMetrics.create, or pubsub.topics.create, there)"; return 1
    fi
    say "  test event written ($probe)"
  }
  # Never pull from $SUB: with --auto-ack that deletes events before Abstract reads them, and
  # without it hides them from Abstract for the ack deadline. Read a throwaway subscription on
  # the same topic instead, created BEFORE the test event (it only receives later messages).
  local probe_sub; probe_sub="abstract-probe-sub-$(date +%s)"
  printf '%s   $ gcloud pubsub subscriptions create %s --topic=%s --project=%s --expiration-period=1d --message-retention-duration=10m%s\n' "$D" "$probe_sub" "$TOPIC" "$LOG_PROJECT" "$O"
  if ! gcloud pubsub subscriptions create "$probe_sub" --topic="$TOPIC" --project="$LOG_PROJECT" \
       --expiration-period=1d --message-retention-duration=10m --quiet >/dev/null 2>&1; then
    bad "could not create the probe subscription $probe_sub on $TOPIC (needs pubsub.subscriptions.create in $LOG_PROJECT)"; return
  fi
  send_probe || { gcloud pubsub subscriptions delete "$probe_sub" --project="$LOG_PROJECT" --quiet >/dev/null 2>&1; return; }
  say "  watching the probe subscription $probe_sub (on $TOPIC) for up to 5 minutes…"
  # The probe subscription sees the whole stream at the scope, so each round drains it, up to 1,000 messages a
  # pull, until a pull returns nothing or the deadline passes. --limit is only an upper bound: Pub/Sub may
  # return fewer while a backlog remains, so a short batch is not the end of it.
  local end=$(( $(date +%s) + 330 )) seen raw pull_err="" errfile; errfile=$(mktemp)
  for i in $(seq 1 20); do
    sleep 15
    while :; do
      # Only this script reads the probe subscription, so acknowledging there is safe. A pull that fails, or
      # whose answer cannot be read, is not "nothing yet": it is remembered and reported (PR #55 review).
      if ! raw=$(gcloud pubsub subscriptions pull "$probe_sub" --project="$LOG_PROJECT" --limit=1000 --auto-ack --format=json 2>"$errfile"); then
        [[ "$pull_err" == *"could not be read"* ]] || { pull_err=$(grep -v '^[[:space:]]*$' "$errfile" | head -n1); pull_err="${pull_err:-the pull failed with no message}"; }
        break
      fi
      # A failed pull acknowledges nothing, so a later pull that works clears it. An unreadable answer is kept:
      # with --auto-ack it may have taken the test event with it.
      [[ "$pull_err" == *"could not be read"* ]] || pull_err=""
      seen=$(printf '%s' "$raw" | python3 -c '
import base64, json, sys
raw = sys.stdin.read().strip()
try: msgs = json.loads(raw) if raw else []
except Exception: print("UNREADABLE"); sys.exit()
if not isinstance(msgs, list): print("UNREADABLE"); sys.exit()
for m in msgs:
    d = m.get("message", {}).get("data", "")
    try: d = base64.b64decode(d).decode("utf-8", "replace")
    except Exception: pass
    if sys.argv[1] in d: print("FOUND"); sys.exit()
print(len(msgs))' "$probe")
      [[ "$seen" == FOUND ]] && { got=1; break; }
      [[ "$seen" == UNREADABLE ]] && { pull_err="a pull returned an answer that could not be read"; break; }
      (( ${seen:-0} == 0 )) && break
      (( $(date +%s) >= end )) && break
    done
    [[ -n "$got" ]] && break
    (( $(date +%s) >= end )) && break
    # One more event half way, in case the first was written before routing began.
    [[ $i -eq 10 ]] && { echo; send_probe || true; }
    printf '.'
  done; echo
  gcloud pubsub subscriptions delete "$probe_sub" --project="$LOG_PROJECT" --quiet >/dev/null 2>&1 \
    || warn "could not delete the probe subscription $probe_sub; it expires by itself after 1 day"
  rm -f "$errfile"
  if [[ -z "$got" && -n "$pull_err" ]]; then
    bad "could not read the probe subscription $probe_sub ($pull_err), so this test says nothing either way about routing."
    why "Check you can pull in $LOG_PROJECT (roles/pubsub.subscriber there), then run step 9 again."
  elif [[ -n "$got" ]]; then
    pass "the test event arrived on $TOPIC: the sink routes and the topic receives"
    why "That proves Google's side. Abstract's side is proven in Abstract, once the integration shows events."
  else
    bad "no test event seen on $TOPIC in 5 minutes. Either the sink is not routing, or the topic was too busy to reach it."
    why "Sink errors:  gcloud logging read 'logName:\"logging.googleapis.com%2Fsink_error\"' --project=$LOG_PROJECT --limit=5"
    why "Backlog: in Monitoring, the subscription metric oldest_unacked_message_age for $SUB; a growing age means events arrive and are not read."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
step10() {
  title 10 "Connect Abstract"
  # The Workspace tutorial runs steps 1, 3, 7 and 10 only: with no subscription, there is no Pub/Sub
  # integration to add and no key of its own to hand over.
  # Only Google's NOT_FOUND means there is no subscription. Any other failure (no pubsub.subscriptions.get, a
  # network error) says nothing about it: warn, and still name the Pub/Sub Source, never report it absent.
  local pipeline=false sub_err=""
  if [[ "${SUB_CREATED:-0}" == 1 || -n "$KEY_ID" || -f "$KEY_FILE" ]]; then pipeline=true
  elif sub_err=$(gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" 2>&1 >/dev/null); then pipeline=true
  elif ! grep -q 'NOT_FOUND' <<<"$sub_err"; then
    pipeline=true
    warn "could not check whether subscription $SUB exists in $LOG_PROJECT ($(grep -v '^[[:space:]]*$' <<<"$sub_err" | head -n1)). If steps 4 and 5 (or the Terraform templates) made it, add the Pub/Sub Source below."
  fi
  if $pipeline; then cat <<EOF
  In Abstract, add the ${B}GCP Pub/Sub Source${O} integration:
    Project ID        ${B}$LOG_PROJECT${O}     ← the project with the SUBSCRIPTION, not the ones sending logs
    Subscription ID   ${B}$SUB${O}      ← the short name only
    Credentials       ${B}$(basename "$KEY_FILE")${O}      ← the key file, downloaded below
EOF
  else say "  There is no Pub/Sub pipeline in this setup (subscription $SUB was not found in $LOG_PROJECT; script steps 4 and 5 make it), so there is no GCP Pub/Sub Source to add."
  fi
  [[ "$WORKSPACE" == yes ]] && cat <<EOF

  In Abstract, add the ${B}Google Workspace Audit Log Integration${O}:
    Admin Email       ${B}$WS_ADMIN${O}
    Credentials       ${B}$(basename "$WS_KEY_FILE")${O}      ← the key file, downloaded below
    Application Name  every application is selected by default. To start small, keep
                      Login, Admin, Token, SAML, User Accounts and Groups.
EOF
  # Whoever fills in the Abstract form needs the key on their own computer: upload it, then delete every copy.
  # In Cloud Shell that means downloading it first: a session opened from a link is deleted when it ends.
  local keys=() f; $pipeline && keys+=("$KEY_FILE"); [[ "$WORKSPACE" == yes ]] && keys+=("$WS_KEY_FILE")
  say ""
  if (( ${#keys[@]} == 0 )); then :     # nothing to upload: no heading over an empty list
  elif [[ "${CLOUD_SHELL:-}" == true ]]; then
    say "  ${B}Download the key files.${O} A Cloud Shell session opened from a link is temporary, and its files go with it:"
  else say "  ${B}The key files${O} (upload them to Abstract from here):"; fi
  local acct ids n rec step id t others
  for f in ${keys[@]+"${keys[@]}"}; do
    if [[ "$f" == "$WS_KEY_FILE" ]]; then acct="$WS_SA@$LOG_PROJECT.iam.gserviceaccount.com"; rec="$WS_KEY_ID"; step=7
    else acct="$SA@$LOG_PROJECT.iam.gserviceaccount.com"; rec="$KEY_ID"; step=5; fi
    if [[ -f "$f" ]]; then
      if ! key_for "$f" "$acct"; then
        bad "$f belongs to $(key_field "$f" client_email || echo 'an unreadable account'), not $acct: Abstract would have no access with it. Do not upload it; $(again --step $step) makes the right one."
      elif [[ "${CLOUD_SHELL:-}" == true ]]; then say "    cloudshell download $f"
      else say "    $f"; fi
      continue
    fi
    # No file is normal after the upload: the guide says to delete it. Only a missing key is a problem.
    if ! ids=$(gcloud iam service-accounts keys list --iam-account="$acct" --managed-by=user --format='value(name.basename(),validAfterTime)' 2>&1); then
      warn "could not list the keys of $acct (${ids%%$'\n'*}); which keys exist was not checked"; continue
    fi
    n=$(grep -c . <<<"$ids")
    if (( n == 0 )); then warn "no key for $acct, here or in Google Cloud. Step $step makes one: run it again."; continue; fi
    say "    $(basename "$f") is no longer here, and $acct has $n key(s):"
    others=""
    while IFS=$'\t' read -r id t; do
      [[ -n "$id" ]] || continue
      if [[ -n "$rec" && "$id" == "$rec" ]]; then say "      $id  created ${t:-?}   <- made by this setup for Abstract: keep it"
      else say "      $id  created ${t:-?}"; others+=" $id"; fi
    done <<<"$ids"
    say "    If Abstract already has it, nothing to do."
    # Google keeps only the public half of a key, so a file lost before the upload cannot be downloaded
    # again. The way on is a new key, then deleting the one nobody holds.
    say "    Lost it before Abstract had it? Make a new one: $(again --step $step) (answer y to a new key)."
    if [[ -n "$rec" ]] && grep -q "^${rec}[[:space:]]" <<<"$ids"; then
      if [[ -n "$others" ]]; then
        say "    The other keys are not the one recorded for Abstract. Once you know nothing else uses them, delete them:"
        for id in $others; do say "      gcloud iam service-accounts keys delete $id --iam-account=$acct"; done
      fi
    elif [[ -n "$rec" ]]; then
      warn "the key recorded for Abstract ($rec) is no longer on $acct. Before deleting any key above, match the private_key_id in the file you uploaded to Abstract against these ids."
    else
      say "    This setup has no record of which key Abstract holds (made before keys were recorded, or by hand)."
      say "    Before deleting any key, match the private_key_id in the file you uploaded to Abstract against these ids."
    fi
  done
  why "If someone else fills in the Abstract form, hand the key over through your password manager or"
  why "secret-sharing tool, never by email or chat."
  $pipeline && why "Anyone holding $(basename "$KEY_FILE") can read the subscription $SUB."
  [[ "$WORKSPACE" == yes ]] && why "Anyone holding $(basename "$WS_KEY_FILE") can read your Workspace audit reports as ${WS_ADMIN:-the admin you named}."
  say ""
  if [[ -n "$DA_BACKUP" ]]; then
    say ""
    say "  ${B}Keep the copy of the audit settings step 6 saved${O} (clean-up uses it): $DA_BACKUP"
    [[ "${CLOUD_SHELL:-}" == true ]] && say "    cloudshell download $DA_BACKUP"
  fi
  say ""
  if [[ "${CLOUD_SHELL:-}" == true ]]; then
    say "  ${B}Download your answers too.${O} The clean-up needs them to know what this setup made:"
    say "    cloudshell download $STATE"
  else say "  ${B}Keep your answers file${O}, $STATE: the clean-up needs it to know what this setup made."; fi
  # It is a hidden file, and the guide calls it <answers-file>: name it, and the exact way to load it again.
  say "    In another session, put that file back and load it with:  $0 --state $(printf '%q' "$STATE") --check"
  say ""
  local -a aside=(); while IFS= read -r f; do aside+=("$f"); done < <(aside_keys)
  # No key to hand over and none set aside: no clean-up heading, and never an "rm -f ''".
  if (( ${#keys[@]} + ${#aside[@]} > 0 )); then
    say "  ${B}Once Abstract has saved the integration, delete every copy of the keys.${O} A key file stays on disk until you delete it:"
    local rv
    for f in ${aside[@]+"${aside[@]}"}; do
      rv=$(revoke_hint "$f") && say "    $f holds a key that stays valid in Google after the file is deleted. Once you know nothing uses it: $rv"
    done
    say "    rm -f$(printf ' %q' ${keys[@]+"${keys[@]}"} ${aside[@]+"${aside[@]}"})"
    say "    and delete any copy you downloaded or handed over."
    say ""
  fi
  if [[ -n "$GRANTS" ]]; then
    say "  ${B}Take back the roles --grant added${O} once Abstract shows events: running the pipeline no longer needs them."
    say "  Removing the setup later (--remove, --teardown) needs them again: grant them back first:  $(again --grant EMAIL), with that person's email."
    each_grant grant_say
    say ""
  fi
  say "  Re-check everything any time:  $(again --check)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Clean up. Removes only what this setup recorded creating, plus the probe subscriptions and the
# "Abstract log pipeline" alerts, which carry its names. A dry run unless --confirm. It never
# deletes the logging project, a sink that existed before, or your Data Access audit settings.
gone() {  # gone <what> <command...>
  local what="$1"; shift
  if $CONFIRM; then
    local out; if out=$("$@" 2>&1); then pass "removed $what"
    elif grep -qiE 'NOT_FOUND|not found|does not exist' <<<"$out"; then pass "$what was already gone"
    else bad "could not remove $what: ${out%%$'\n'*}"; fi
  else WOULD=$((WOULD+1)); printf '  %swould remove%s %s\n%s   $' "$Y" "$O" "$what" "$D"; printf ' %q' "$@"; printf '%s\n' "$O"; fi
}
WOULD=0; BYHAND=0   # what a dry run would remove, and what is left for a person: the hints below depend on both
kept()   { printf '  %skept%s    %s\n' "$G" "$O" "$*"; }
byhand() { printf '  %sby hand%s %s\n' "$Y" "$O" "$*"; WARNS=$((WARNS+1)); BYHAND=$((BYHAND+1)); }
# Deletes one Monitoring object by name. Defined as a function so a dry run prints its name, never
# the bearer token the request carries. 404 counts as done, so a retried clean-up can finish.
mon_delete() {
  local out code; out=$(curl -s -w '\n%{http_code}' -X DELETE -H "Authorization: Bearer $(token)" \
    "https://monitoring.googleapis.com/v3/$1${2:+?$2}"); code=${out##*$'\n'}
  [[ "$code" == 200 || "$code" == 404 ]] && return 0
  # The reason, for gone() to print. Never the request: it carries the bearer token.
  printf 'HTTP %s: %s\n' "${code:-?}" "$(python3 -c 'import json, sys
try: print(json.loads(sys.argv[1])["error"]["message"])
except Exception: print("no reason given")' "${out%$'\n'*}")"
  return 1
}
found() { byhand "found, not recorded: $1. Check it is Abstract's, then: $2"; }
# look <what> <how to remove> <describe command...>: found, absent, or COULD NOT CHECK. A denied or
# failed lookup is never read as absent; that false zero once listed nothing beside a live topic.
look() {
  local what="$1" how="$2" out; shift 2
  if out=$("$@" 2>&1); then found "$what" "$how"; return 0
  # Absent only when the error says so and nothing in it says access was refused: Google answers
  # "does not exist or you do not have access" for both, and that is not proof of absence.
  elif grep -qiE 'NOT_FOUND|Resource not found' <<<"$out" \
       && ! grep -qiE 'PERMISSION_DENIED|denied|not authori[sz]ed|do not have access|forbidden' <<<"$out"; then :
  else bad "could not check $what: ${out%%$'\n'*}"; fi
  return 1
}
# mon_list <collection> <what>: sets MON_NAMES to the Monitoring objects named "Abstract log pipeline…",
# or reports a failure. Not called through $(…): a bad() inside a subshell is never counted.
MON_NAMES=""
mon_list() {  # mon_list <collection> <what> [project, default the logging project]
  local p="${3:-$LOG_PROJECT}" body code; body=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $(token)" \
    "https://monitoring.googleapis.com/v3/projects/$p/$1?pageSize=200"); code=${body##*$'\n'}
  if [[ "$code" != 200 ]]; then bad "could not list $2 in $p (HTTP $code)"; MON_NAMES=""; return 1; fi
  MON_NAMES=$(python3 -c '
import json, sys
for o in json.loads(sys.argv[1]).get(sys.argv[2], []):
    if o.get("displayName", "").startswith("Abstract log pipeline"): print(o["name"])' "${body%$'\n'*}" "$1")
}

# Without saved answers (a Cloud Shell session opened from the templates button is temporary), look
# for what the setup makes by its default names, and list it. Nothing found by name is deleted:
# a name is not proof this setup made it.
discover_all() {
  LOG_PROJECT="$FIND_PROJECT"
  why "No saved answers, so nothing is recorded as made here. Listing what carries the setup's names in $LOG_PROJECT."
  look "subscription $SUB" "gcloud pubsub subscriptions delete $SUB --project=$LOG_PROJECT" \
    gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT"
  look "topic $TOPIC" "gcloud pubsub topics delete $TOPIC --project=$LOG_PROJECT" \
    gcloud pubsub topics describe "$TOPIC" --project="$LOG_PROJECT"
  local a; for a in "$SA" "$WS_SA"; do
    look "service account $a" "gcloud iam service-accounts delete $a@$LOG_PROJECT.iam.gserviceaccount.com --project=$LOG_PROJECT" \
      gcloud iam service-accounts describe "$a@$LOG_PROJECT.iam.gserviceaccount.com" --project="$LOG_PROJECT" \
      && sa_keys "$a@$LOG_PROJECT.iam.gserviceaccount.com" ""; done
  local n probes
  if probes=$(gcloud pubsub subscriptions list --project="$LOG_PROJECT" --filter='name:abstract-probe-' --format='value(name.basename())' 2>&1); then
    for n in $probes; do found "probe subscription $n" "gcloud pubsub subscriptions delete $n --project=$LOG_PROJECT"; done
  else bad "could not list probe subscriptions in $LOG_PROJECT: ${probes%%$'\n'*}"; fi
  if mon_list alertPolicies "alert policies"; then
    for n in $MON_NAMES; do found "alert policy $n" "delete it under Monitoring > Alerting in the console"; done; fi
  if mon_list notificationChannels "notification channels"; then
    for n in $MON_NAMES; do found "alert channel $n" "delete it under Monitoring > Alerting > Edit notification channels"; done; fi
  byhand "the log sink lives on your organization, folder or project, not here. Find it with: gcloud logging sinks list --organization=ORG_ID --filter='destination:$TOPIC', with ORG_ID your organization's ID (or --folder=FOLDER_ID / --project=PROJECT_ID)"
  kept "logging project $LOG_PROJECT: this script never deletes it."
}

# sa_keys <service account> <recorded key id>: on an account this setup did not create, the key it recorded
# making is removed; every other user-managed key is listed, never deleted (a key is not proof it is Abstract's).
sa_keys() {
  local ids id
  if ! ids=$(gcloud iam service-accounts keys list --iam-account="$1" --managed-by=user --format='value(name.basename())' 2>&1); then
    bad "could not list the keys of $1: ${ids%%$'\n'*}"; return
  fi
  for id in $ids; do
    if [[ -n "$2" && "$id" == "$2" ]]; then gone "key $id on $1 (made by this setup)" gcloud iam service-accounts keys delete "$id" --iam-account="$1" --quiet
    else byhand "key $id on $1 was not recorded as made here. If it is Abstract's: gcloud iam service-accounts keys delete $id --iam-account=$1"; fi
  done
}

remove_all() {
  title "x" "Clean up"
  why "Removes only what this setup created. Nothing is deleted without --confirm."
  why "Delete the integration in Abstract first, so it stops reading the subscription."
  if [[ -z "$LOG_PROJECT" ]]; then
    [[ -n "$FIND_PROJECT" ]] && { discover_all; return; }
    bad "No saved answers in $STATE, so this session cannot tell what the setup made. Cloud Shell sessions opened from the templates button are temporary. Load the answers file you downloaded with --state ANSWERS_FILE (its path), or run again with --project LOGGING_PROJECT_ID (your logging project's ID) to list what carries the setup's names."
    return
  fi
  local sf; sf=$(scope_flag)
  if (( ${SINK_CREATED_AT:-0} > 0 )); then
    # shellcheck disable=SC2086
    gone "log sink $SINK at the $SCOPE $SCOPE_ID" gcloud logging sinks delete "$SINK" $sf --quiet
  else kept "log sink $SINK: it existed before this setup. Its filter may have been extended; review it."; fi
  local p probes
  if probes=$(gcloud pubsub subscriptions list --project="$LOG_PROJECT" --filter='name:abstract-probe-' --format='value(name.basename())' 2>&1); then
    for p in $probes; do gone "probe subscription $p" gcloud pubsub subscriptions delete "$p" --project="$LOG_PROJECT" --quiet; done
  else bad "could not list probe subscriptions in $LOG_PROJECT: ${probes%%$'\n'*}"; fi
  if [[ "${SUB_CREATED:-0}" == 1 ]]; then gone "subscription $SUB" gcloud pubsub subscriptions delete "$SUB" --project="$LOG_PROJECT" --quiet
  else byhand "subscription $SUB was not recorded as created here. If it is Abstract's: gcloud pubsub subscriptions delete $SUB --project=$LOG_PROJECT"; fi
  if [[ "${TOPIC_CREATED:-0}" == 1 ]]; then gone "topic $TOPIC" gcloud pubsub topics delete "$TOPIC" --project="$LOG_PROJECT" --quiet
  else byhand "topic $TOPIC was not recorded as created here. If it is Abstract's: gcloud pubsub topics delete $TOPIC --project=$LOG_PROJECT"; fi
  if [[ "${SA_CREATED:-0}" == 1 ]]; then gone "service account $SA (and its keys)" gcloud iam service-accounts delete "$SA@$LOG_PROJECT.iam.gserviceaccount.com" --project="$LOG_PROJECT" --quiet
  else byhand "service account $SA was not recorded as created here. If it is Abstract's: gcloud iam service-accounts delete $SA@$LOG_PROJECT.iam.gserviceaccount.com"
       sa_keys "$SA@$LOG_PROJECT.iam.gserviceaccount.com" "$KEY_ID"; fi
  if [[ "${WS_SA_CREATED:-0}" == 1 ]]; then
    gone "Workspace service account $WS_SA (and its keys)" gcloud iam service-accounts delete "$WS_SA@$LOG_PROJECT.iam.gserviceaccount.com" --project="$LOG_PROJECT" --quiet
    byhand "a Workspace super admin removes its entry under admin.google.com > Security > API controls > Domain-wide delegation"
  elif [[ "$WORKSPACE" == yes ]]; then
    byhand "Workspace service account $WS_SA was not recorded as created here. If it is Abstract's: gcloud iam service-accounts delete $WS_SA@$LOG_PROJECT.iam.gserviceaccount.com"
    sa_keys "$WS_SA@$LOG_PROJECT.iam.gserviceaccount.com" "$WS_KEY_ID"
  fi
  local n; for n in $ALERT_POLICIES; do gone "alert policy $n" mon_delete "$n"; done
  for n in $ALERT_CHANNELS; do gone "alert email channel $n" mon_delete "$n" force=true; done
  local others=""
  mon_list alertPolicies "alert policies" && others+=" $MON_NAMES"
  mon_list notificationChannels "notification channels" && others+=" $MON_NAMES"
  for n in $others; do
    [[ " $ALERT_POLICIES $ALERT_CHANNELS " == *" $n "* ]] || kept "alert $n: not made by this setup (Terraform, or another setup)"; done
  local f rv; local -a aside=(); while IFS= read -r f; do aside+=("$f"); done < <(aside_keys)
  for f in ${aside[@]+"${aside[@]}"}; do
    rv=$(revoke_hint "$f") && byhand "$f holds a key that stays valid in Google after the file is deleted. Once you know nothing uses it: $rv"
  done
  for f in "$KEY_FILE" "$WS_KEY_FILE" ${aside[@]+"${aside[@]}"}; do [[ -f "$f" ]] && gone "key file $f" rm -f "$f"; done
  if [[ "${DA_CHANGED:-}" == 1 ]]; then
    byhand "step 6 turned on Data Access logs at the $SCOPE $SCOPE_ID (${DA_ADDED:-see the backup}). The settings before that are in ${DA_BACKUP:-the backup step 6 saved}. To undo, remove those log types with get-iam-policy, edit, then set-iam-policy (keep the etag); never set the whole backup back over changes made since."
  elif [[ "$DATA_ACCESS" == yes && -z "${DA_CHANGED:-}" ]]; then
    byhand "Data Access audit settings may have been changed in step 6 (this answers file predates the record of it). If they were, a copy of the earlier settings was saved as abstract-audit-config-backup-*.json in the folder step 6 ran in. Compare it with get-iam-policy before changing anything."
  fi
  each_grant grant_byhand
  kept "logging project $LOG_PROJECT: this script never deletes it. If you created it only for Abstract: gcloud projects delete $LOG_PROJECT"
  if $CONFIRM && (( FAILS == 0 )); then
    local moved; moved="$STATE.removed-$(date +%Y%m%d%H%M%S)"; mv "$STATE" "$moved"
    if (( BYHAND > 0 )); then
      say "  saved answers moved aside to $moved. The $BYHAND by-hand item(s) above are still in place: act on each."
      say "  To list them again:  $0 --state $(printf '%q' "$moved") --remove"
    else say "  saved answers moved aside to $moved; nothing this setup recorded is left"; fi
  elif ! $CONFIRM; then
    say ""
    if (( WOULD > 0 )); then say "  Nothing was removed. To remove the items marked 'would remove':  $(again --remove --confirm)"
    else say "  Nothing is marked 'would remove', so --confirm would delete nothing. Act on the by-hand lines above yourself."; fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# --grant <principal>: the roles this setup needs, granted by someone who can set IAM policy, one binding per role
# (add-iam-policy-binding; never a write of the whole policy, which would replace every other binding). Each binding this run adds is
# recorded in GRANTS, and only those: a role the principal already held directly is not recorded, so
# --teardown --include-grants never takes away a grant that existed before.
GRANT=""

# A principal as IAM writes it; a bare email is a user. Prints it, or returns 1. ":" and ";" are refused in the
# address, because GRANTS separates its fields with them.
grant_member() {
  local p="$1"; [[ "$p" == *:* ]] || p="user:$p"
  [[ "$p" =~ ^(user|group|serviceAccount):[^@[:space:]:\;]+@[^@[:space:]:\;]+\.[^@[:space:]:\;]+$ ]] || return 1
  printf '%s' "$p"
}

# binding_cmd <organization|folder|project|billing> <id> <role> <member> <add|remove>: sets BCMD to the gcloud
# command for one binding. Billing accounts take no --condition (gcloud billing accounts add-iam-policy-binding
# --help, SDK 588.0.0); the others get --condition=None, so a policy holding conditional bindings never makes
# gcloud stop to ask which one is meant.
binding_cmd() {
  local v="$5-iam-policy-binding"
  case "$1" in
    organization) BCMD=(gcloud organizations "$v" "$2") ;;
    folder)       BCMD=(gcloud resource-manager folders "$v" "$2") ;;
    project)      BCMD=(gcloud projects "$v" "$2") ;;
    billing)      BCMD=(gcloud billing accounts "$v" "$2") ;;
  esac
  BCMD+=("--member=$4" "--role=$3")
  [[ "$1" == billing ]] || BCMD+=(--condition=None)
}

# each_grant <function>: calls <function> <kind> <id> <role> <member> for each binding --grant recorded in GRANTS.
each_grant() {
  [[ -n "$GRANTS" ]] || return 0
  local -a gl; local g kind rest id role member
  IFS=';' read -ra gl <<<"$GRANTS"
  for g in "${gl[@]}"; do
    kind=${g%%:*}; rest=${g#*:}; id=${rest%%:*}; rest=${rest#*:}; role=${rest%%:*}; member=${rest#*:}
    [[ -n "$kind" && -n "$id" && -n "$role" && -n "$member" ]] || continue
    "$1" "$kind" "$id" "$role" "$member"
  done
}
# grant_undo <kind> <id> <role> <member>: prints the one command that takes that binding back. Never run here.
grant_undo() { binding_cmd "$1" "$2" "$3" "$4" remove; printf '%s' "${BCMD[*]}"; }
# The roles --grant added outlive the setup unless someone takes them back, so clean-up and step 10 name each one.
grant_byhand() { byhand "$3 for $4 on the ${1/billing/billing account} $2 was added by --grant. Once the pipeline works and nobody needs it: $(grant_undo "$@")"; }
grant_say()    { say "    $(grant_undo "$@")"; }

# policy_of <organization|folder|project|billing> <id>: that resource's IAM policy as JSON (status 1 and the
# error when it cannot be read). Read-only.
policy_of() {
  case "$1" in
    organization) gcloud organizations get-iam-policy "$2" --format=json 2>&1 ;;
    folder)       gcloud resource-manager folders get-iam-policy "$2" --format=json 2>&1 ;;
    project)      gcloud projects get-iam-policy "$2" --format=json 2>&1 ;;
    billing)      gcloud billing accounts get-iam-policy "$2" --format=json 2>&1 ;;
  esac
}

# The roles, in the order the steps need them: GR_KIND (scope|billing|project), GR_ROLE, GR_NEED, GR_WHY.
# Every role here was checked with `gcloud iam roles describe` (2026-10-12, all GA), and is checked again at run time.
# At the organization the viewer role is roles/browser: roles/resourcemanager.organizationViewer holds only
# resourcemanager.organizations.get, so it cannot list the folders and projects steps 1 and 3 show.
gr() { GR_KIND+=("$1"); GR_ROLE+=("$2"); GR_NEED+=("$3"); GR_WHY+=("$4"); }
grant_plan() {
  GR_KIND=(); GR_ROLE=(); GR_NEED=(); GR_WHY=()
  case "$SCOPE" in
    organization) gr scope roles/browser required "see the organization, its folders and projects (steps 1 and 3)" ;;
    folder)       gr scope roles/resourcemanager.folderViewer required "see the folder and its projects (steps 1 and 3)" ;;
    project)      gr scope roles/browser required "see the project (steps 1 and 3)" ;;
  esac
  gr scope roles/logging.configWriter required "create the log sink (step 4)"
  gr scope roles/orgpolicy.policyViewer required "read the organization policies that can block the key (step 3)"
  gr scope roles/iam.securityReviewer required "read IAM policies and the audit settings (steps 2, 5 and 6)"
  [[ "$SCOPE" != project ]] && gr scope roles/resourcemanager.projectCreator optional "create a new logging project (step 3)"
  gr scope roles/iam.securityAdmin optional "turn on Data Access logs (step 6). Powerful: it can change IAM anywhere at the $SCOPE"
  gr billing roles/billing.user optional "link a billing account to the logging project (step 3)"
  if [[ -n "$LOG_PROJECT" ]]; then
    gr project roles/pubsub.admin required "create the topic and subscription, and grant on them (steps 4 and 5)"
    gr project roles/iam.serviceAccountAdmin required "create Abstract's service accounts (steps 5 and 7)"
    gr project roles/iam.serviceAccountKeyAdmin required "create the key Abstract signs in with (steps 5 and 7)"
    gr project roles/serviceusage.serviceUsageAdmin required "turn on the APIs (steps 3, 7 and 8)"
    gr project roles/monitoring.editor optional "create the health alerts (step 8)"
  fi
  return 0
}
gr_kind() { case "$1" in scope) echo "$SCOPE" ;; project) echo project ;; billing) echo billing ;; esac; }
gr_id()   { case "$1" in scope) echo "$SCOPE_ID" ;; project) echo "$LOG_PROJECT" ;; billing) echo "$BILLING" ;; esac; }
gr_where() { case "$1" in scope) echo "the $SCOPE $SCOPE_ID" ;; project) echo "the logging project $LOG_PROJECT" ;;
  billing) echo "the billing account${BILLING:+ $BILLING}" ;; esac; }
# Who can grant there, for the hand-over line.
gr_admin() { case "$1" in
  scope) case "$SCOPE" in organization) echo "an Organization Admin" ;; folder) echo "a Folder Admin" ;; *) echo "a project Owner or Project IAM Admin" ;; esac ;;
  project) echo "a project Owner or Project IAM Admin" ;; billing) echo "a Billing Account Administrator" ;; esac; }
gr_url() { case "$1" in
  scope) scope_url ;; project) echo "https://cloudresourcemanager.googleapis.com/v3/projects/$LOG_PROJECT" ;;
  billing) echo "https://cloudbilling.googleapis.com/v1/billingAccounts/$BILLING" ;; esac; }
gr_perm() { case "$1" in
  scope) echo "resourcemanager.$( [[ $SCOPE == organization ]] && echo organizations || echo "${SCOPE}s" ).setIamPolicy" ;;
  project) echo resourcemanager.projects.setIamPolicy ;; billing) echo billing.accounts.setIamPolicy ;; esac; }

grant_roles() {
  local member="$GRANT" i k last="" out
  title "+" "Grant the roles the setup needs"
  why "Run by someone who can set IAM policy where each role goes. Each role is one binding, added on its own;"
  why "nothing else in a policy changes. The bindings this run adds are recorded, so --teardown --include-grants removes them."
  if [[ -z "$SCOPE" || -z "$SCOPE_ID" ]]; then
    interactive || { bad "no scope saved: choose one with $(again --step 1), or load an answers file with --state"; return; }
    step1
    [[ -n "$SCOPE" && -n "$SCOPE_ID" ]] || return
  fi
  if [[ -z "$LOG_PROJECT" ]] && interactive; then
    local pick; pick=$(choose_existing project "gcloud projects describe {}" "Which project holds (or will hold) the pipeline?" "$(project_list)" \
      "not chosen yet: skip the logging-project roles" "" '^[a-z][a-z0-9-]{4,28}[a-z0-9]$')
    [[ -n "$pick" && "$pick" != +new ]] && { LOG_PROJECT="$pick"; save; }
  fi
  [[ -n "$LOG_PROJECT" ]] || why "No logging project yet, so its roles are left out. A project you create in step 3 makes you its Owner."
  grant_plan
  say ""; say "  ${B}Roles for $member${O}"
  for ((i = 0; i < ${#GR_ROLE[@]}; i++)); do
    k=${GR_KIND[$i]}
    [[ "$k" != "$last" ]] && { say "   on $(gr_where "$k"):"; last="$k"; }
    printf '    %2d) %-42s %-8s  %s\n' $((i + 1)) "${GR_ROLE[$i]}" "${GR_NEED[$i]}" "${GR_WHY[$i]}"
  done
  # Only roles Google knows are offered. A failed lookup that is not NOT_FOUND says nothing either way.
  GR_OK=()
  for ((i = 0; i < ${#GR_ROLE[@]}; i++)); do
    GR_OK[$i]=1
    if ! out=$(gcloud iam roles describe "${GR_ROLE[$i]}" --format='value(name)' 2>&1); then
      if grep -qiE 'NOT_FOUND|INVALID_ARGUMENT' <<<"$out"; then bad "${GR_ROLE[$i]} was not found in Google Cloud's roles; it is left out"; GR_OK[$i]=0
      else warn "could not confirm ${GR_ROLE[$i]} exists ($(first_line "$out"))"; fi
    fi
  done
  why "Roles held through a group, or inherited from a folder or the organization, do not show in a resource's own IAM"
  why "policy: a role not held directly may still be held that way."
  if $CHECK_ONLY; then grant_check "$member"; else grant_apply "$member"; fi
}

# held_directly <policy JSON> <member> <role>
held_directly() { [[ " $(member_roles "$2" <<<"$1") " == *" $3 "* ]]; }

grant_check() {
  local member="$1" i k pol="" polk="" ok=true
  for ((i = 0; i < ${#GR_ROLE[@]}; i++)); do
    (( GR_OK[i] )) || continue
    k=${GR_KIND[$i]}
    if [[ "$k" != "$polk" ]]; then
      polk="$k"; ok=true
      if [[ "$k" == billing && -z "$BILLING" ]]; then ok=false; say "  - no billing account saved, so roles/billing.user was not checked"
      elif ! pol=$(policy_of "$(gr_kind "$k")" "$(gr_id "$k")") || ! member_roles "$member" <<<"$pol" >/dev/null; then
        ok=false; warn "could not read the IAM policy of $(gr_where "$k") ($(first_line "$pol")); its roles were not checked"
      fi
    fi
    $ok || continue
    if held_directly "$pol" "$member" "${GR_ROLE[$i]}"; then pass "$member holds ${GR_ROLE[$i]} directly on $(gr_where "$k")"
    elif [[ "${GR_NEED[$i]}" == required ]]; then warn "$member does not hold ${GR_ROLE[$i]} directly on $(gr_where "$k")"
    else say "  - $member does not hold ${GR_ROLE[$i]} directly on $(gr_where "$k") (optional)"; fi
  done
  say ""; say "  Nothing was changed. To grant what is missing:  $(again --grant "$member")"
}

grant_apply() {
  local member="$1" i k polk="" pol="" can=false h out def kind id rec accounts
  local -a handover=()
  interactive || warn "no terminal, so nothing can be asked and nothing is granted. Run this in a terminal, or see what is held with --check."
  for ((i = 0; i < ${#GR_ROLE[@]}; i++)); do
    (( GR_OK[i] )) || continue
    k=${GR_KIND[$i]}
    if [[ "$k" == billing ]]; then
      interactive && yes_no "Grant ${GR_ROLE[$i]} (link billing to the logging project; optional) on a billing account?" n || continue
      if [[ -z "$BILLING" ]]; then
        accounts=$(listing gcloud billing accounts list --filter=open=true --format='value(name.basename(),displayName)')
        [[ -n "$accounts" ]] || { warn "no open billing account is visible to you; roles/billing.user was not granted"; continue; }
        BILLING=$(choose "Which billing account?" "$accounts" "" "" '^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$'); save
      fi
      polk=""   # the billing account's own checks follow
    fi
    if [[ "$k" != "$polk" ]]; then
      polk="$k"; can=false
      if ! h=$(held "$(gr_url "$k")" "$(gr_perm "$k")"); then warn "could not check whether you can set the IAM policy of $(gr_where "$k"): $h"
      elif has "$h" "$(gr_perm "$k")"; then can=true
      else warn "you cannot set the IAM policy of $(gr_where "$k") (needs $(gr_perm "$k"), e.g. as $(gr_admin "$k"))"; fi
      $can || { say "  You cannot set the IAM policy of $(gr_where "$k"). Hand these commands to $(gr_admin "$k"):"; handover+=("$k"); }
      pol=$(policy_of "$(gr_kind "$k")" "$(gr_id "$k")") && member_roles "$member" <<<"$pol" >/dev/null || pol=""
    fi
    kind=$(gr_kind "$k"); id=$(gr_id "$k")
    binding_cmd "$kind" "$id" "${GR_ROLE[$i]}" "$member" add
    if ! $can; then
      [[ "${GR_NEED[$i]}" == optional ]] && say "    optional, ${GR_WHY[$i]}:"
      say "      $(printf '%q ' "${BCMD[@]}")"; continue
    fi
    if [[ -n "$pol" ]] && held_directly "$pol" "$member" "${GR_ROLE[$i]}"; then
      pass "$member already holds ${GR_ROLE[$i]} on $(gr_where "$k"); nothing to do"; continue
    fi
    [[ "${GR_NEED[$i]}" == required ]] && def=y || def=n
    interactive || continue
    # Billing was asked already, before the account was chosen.
    [[ "$k" == billing ]] || yes_no "Grant ${GR_ROLE[$i]} on $(gr_where "$k") (${GR_NEED[$i]}: ${GR_WHY[$i]})?" "$def" || { say "  not granted"; continue; }
    BCMD+=(--format=none)
    printf '%s   $' "$D"; printf ' %q' "${BCMD[@]}"; printf '%s\n' "$O"
    if out=$("${BCMD[@]}" 2>&1); then
      pass "granted ${GR_ROLE[$i]} to $member on $(gr_where "$k")"
      rec="$kind:$id:${GR_ROLE[$i]}:$member"
      [[ ";$GRANTS;" == *";$rec;"* ]] || GRANTS="${GRANTS:+$GRANTS;}$rec"
      save
    else bad "could not grant ${GR_ROLE[$i]} on $(gr_where "$k"): $(first_line "$out")"; fi
  done
  (( ${#handover[@]} )) && why "Copy those lines as they are; each adds one binding and changes nothing else."
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# --teardown: a FULL reset, to start from scratch. Unlike --remove (only what the answers file recorded creating),
# it looks across the organization for what this setup and the templates make, by their names and by where sinks
# send. A dry run unless --confirm. Projects and Terraform state are never deleted: their commands are printed.
# Data Access audit settings change only with --include-audit-settings, and --grant's bindings only with
# --include-grants. Deletes run in the order that stops routing first: sinks, subscriptions, topics, service
# accounts, alerts, then the flagged settings and grants.
TEARDOWN=false; TD_ORG=""; TD_AUDIT=false; TD_GRANTS=false; YES_I_MEAN_IT=false; FIND_PROJECTS=""
TD_MAX_CONTAINERS=50; TD_MAX_PROJECTS=200
TD_GROUPS=("Log sinks and what else sends to the topics" "Subscriptions" "Topics" "Service accounts and key files" "Alerts and notification channels"
  "Data Access audit settings" "Role grants made by --grant" "Terraform state" "Projects")
TD_G=(); TD_K=(); TD_WHAT=(); TD_CMD=(); TD_SHOW=(); TD_ARGV=(); TD_OFF=(); TD_LEN=()
# td_add <group 1-9> <remove|byhand|kept> <what> [command...]: one line of the list. The command's words are kept
# as words (TD_ARGV, from TD_OFF for TD_LEN), and td_run runs exactly those words: a name a listing returned is
# never read back as shell. TD_CMD is the same words %q-quoted, only to print. A function (mon_delete,
# td_audit_remove) prints its name and arguments, never the token its request carries.
td_add() {
  local g="$1" k="$2" w="$3"; shift 3
  TD_G+=("$g"); TD_K+=("$k"); TD_WHAT+=("$w")
  TD_OFF+=("${#TD_ARGV[@]}"); TD_LEN+=("$#")
  if (( $# )); then TD_CMD+=("$(printf '%q ' "$@")"); TD_ARGV+=("$@"); else TD_CMD+=(""); fi
  TD_SHOW+=("")
}
td_show() { TD_SHOW[$(( ${#TD_SHOW[@]} - 1 ))]="$1"; }   # what the list prints in place of the last item's command
add_word() { [[ " ${!1} " == *" $2 "* ]] || printf -v "$1" '%s' "${!1:+${!1} }$2"; }

# td_audit_plan <policy JSON> <pairs>: the auditConfigs left once exactly those service:logType pairs are taken off
# (DA_ADDED: what step 6 recorded adding, and Google confirmed). Nothing else changes: a log type that was on before
# step 6, on any service, stays, and so do other services and every exemption not on a removed log type. An entry is
# dropped only when nothing is left in it.
td_audit_plan() {
  python3 - "$1" "$2" <<'PY'
import json, sys
cur = json.loads(sys.argv[1]); drop = {}
for p in sys.argv[2].split():
    svc, _, t = p.rpartition(":")
    if svc and t: drop.setdefault(svc, set()).add(t)
out = []
for c in cur.get("auditConfigs", []):
    off = drop.get(c.get("service"))
    if off:
        keep = [l for l in c.get("auditLogConfigs", []) if l.get("logType") not in off]
        if keep: out.append({**c, "auditLogConfigs": keep})
    else:
        out.append(c)
print(json.dumps(out))
PY
}
# td_audit_record <org>: status 0 when the answers file holds a record of what step 6 added that applies to this
# organization; otherwise prints why not (for the by-hand line) and returns 1.
td_audit_record() {
  if [[ "${DA_CHANGED:-}" != 1 || -z "${DA_ADDED// /}" ]]; then printf 'no record of the log types script step 6 added'; return 1; fi
  if [[ -z "$SCOPE" || -z "$SCOPE_ID" ]]; then printf 'no record of where script step 6 changed them'; return 1; fi
  if [[ "$ORG_ID" != "$1" ]]; then printf 'the answers file records step 6 in organization %s, not %s' "${ORG_ID:-(none)}" "$1"; return 1; fi
  return 0
}
td_policy_kind() { case "$1" in organization) echo organizations ;; folder) echo "resource-manager folders" ;; project) echo projects ;; esac; }
# td_audit_remove <resource url> <label>: re-read the settings (a fresh etag), save a copy next to the answers file,
# then setIamPolicy with that etag and updateMask=auditConfigs, so role bindings are never touched.
td_audit_remove() {
  local cur left backup body out code
  cur=$(audit_config_json "$1") || { printf 'could not read the audit settings: %s\n' "$cur"; return 1; }
  left=$(td_audit_plan "$cur" "$DA_ADDED") || { echo "could not compute the change"; return 1; }
  backup="$(dirname "$STATE")/abstract-audit-config-backup-teardown-$(date +%Y%m%d%H%M%S)-$(tr -c 'a-z0-9' '-' <<<"$2" | tr -s '-' | sed 's/-$//').json"
  ( umask 077; printf '%s\n' "$cur" > "$backup" ) || { echo "could not save a copy of the settings first; nothing was sent"; return 1; }
  body=$(python3 -c 'import json, sys
cur = json.loads(sys.argv[1])
print(json.dumps({"policy": {"etag": cur["etag"], "auditConfigs": json.loads(sys.argv[2])}, "updateMask": "auditConfigs"}))' "$cur" "$left") \
    || { echo "the settings had no etag; nothing was sent"; return 1; }
  out=$(curl -s -w '\n%{http_code}' -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" \
    -d "$body" "$1:setIamPolicy"); code=${out##*$'\n'}; out=${out%$'\n'*}
  # Google answers with the stored policy; with no audit config left it carries none, so the etag is the proof.
  if [[ "$code" == 200 ]] && python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("etag") and "error" not in d else 1)' <<<"$out" 2>/dev/null; then
    printf 'the copy taken first is %s\n' "$backup"; return 0
  fi
  printf 'HTTP %s; the copy taken first is %s\n' "${code:-?}" "$backup"; return 1
}

# td_tree <org>: every folder (breadth first) and project under the organization, bounded and said so.
# Sets TD_FOLDERS and TD_PROJECTS (words), and TD_PNUMS (number:id words, so a topic named by project number is
# recognised). A listing that fails is a failure, never an empty list.
td_tree() {
  local -a queue=("organization:$1"); local i=0 t id out f n num
  TD_FOLDERS=""; TD_PROJECTS=""; TD_PNUMS=""
  while (( i < ${#queue[@]} )); do
    if (( i >= TD_MAX_CONTAINERS )); then
      warn "looked under $TD_MAX_CONTAINERS of ${#queue[@]} organization and folders found; the rest were not checked"; break
    fi
    t=${queue[$i]%%:*}; id=${queue[$i]#*:}; i=$((i + 1))
    if out=$(gcloud resource-manager folders list "--$t=$id" --format='value(ID)' 2>&1); then
      for f in $out; do queue+=("folder:$f"); add_word TD_FOLDERS "$f"; done
    else bad "could not list the folders under $t $id: $(first_line "$out")"; fi
    if out=$(gcloud projects list --filter="parent.type=$t AND parent.id=$id AND lifecycleState:ACTIVE" --format='value(projectId,projectNumber)' 2>&1); then
      while IFS=$'\t' read -r f num; do
        [[ -n "$f" ]] || continue
        add_word TD_PROJECTS "$f"; [[ -n "$num" ]] && add_word TD_PNUMS "$num:$f"
      done <<<"$out"
    else bad "could not list the projects under $t $id: $(first_line "$out")"; fi
  done
  n=$(wc -w <<<"$TD_PROJECTS" | tr -d ' ')
  if (( n > TD_MAX_PROJECTS )); then
    warn "found $n projects; only the first $TD_MAX_PROJECTS are checked for sinks and topics"
    TD_PROJECTS=$(tr ' ' '\n' <<<"$TD_PROJECTS" | head -n "$TD_MAX_PROJECTS" | paste -sd' ' -)
  fi
  say "  looked at the organization, $(wc -w <<<"$TD_FOLDERS" | tr -d ' ') folder(s) and $(wc -w <<<"$TD_PROJECTS" | tr -d ' ') project(s)"
}

# td_sinks <scope flag> <label>: this setup's sinks there: named abstract-*, or sending to a topic named $TOPIC.
td_sinks() {
  local out name dest
  if ! out=$(gcloud logging sinks list "$1" --format='value(name,destination)' 2>&1); then
    bad "could not list the sinks at $2: $(first_line "$out")"; return
  fi
  while IFS=$'\t' read -r name dest; do
    [[ -z "$name" || "$name" == _Required || "$name" == _Default ]] && continue
    [[ "$name" == abstract-* || "$dest" == */topics/"$TOPIC" ]] || continue
    td_add 1 remove "sink $name at $2 (sends to $dest)" gcloud logging sinks delete "$name" "$1" --quiet
    [[ "$dest" =~ ^pubsub\.googleapis\.com/projects/([^/]+)/topics/ ]] && add_word TD_LOGPROJ "${BASH_REMATCH[1]}"
  done <<<"$out"
}

# td_topics <project>: sets TD_TOPIC_LIST to the project's topics, one per line, or reports why they cannot be listed
# and returns 1. A project with the Pub/Sub API off has no topics; that is not an error. Never called through $(...):
# a bad() in a subshell is lost, and its message would be captured into the list instead of shown.
td_topics() {
  local out; TD_TOPIC_LIST=""
  if out=$(gcloud pubsub topics list --project="$1" --format='value(name.basename())' 2>&1); then TD_TOPIC_LIST=$out; return 0; fi
  grep -qiE 'SERVICE_DISABLED|has not been used in project|it is disabled' <<<"$out" && return 0
  bad "could not list the topics in $1: $(first_line "$out")"; return 1
}

# td_scan <project>: list the project's topics once. Each named abstract-* (or the answers' topic name) is kept in
# TD_TOPICS as projects/P/topics/T, and the project joins TD_LOGPROJ: a standalone pipeline (SCC findings, asset
# changes, bucket notifications) has its own topic and no Logging sink, so a topic is the only trace it leaves here.
TD_TOPICS=""; TD_SCANNED=""; TD_SCAN_FAILED=""
td_scan() {
  local p="$1" t mine=false
  has "$TD_SCANNED" "$p" && return 0
  add_word TD_SCANNED "$p"
  td_topics "$p" || { add_word TD_SCAN_FAILED "$p"; return 1; }
  while IFS= read -r t; do
    [[ -n "$t" && ( "$t" == abstract-* || "$t" == "$TOPIC" ) ]] || continue
    add_word TD_TOPICS "projects/$p/topics/$t"; mine=true
  done <<<"$TD_TOPIC_LIST"
  $mine && add_word TD_LOGPROJ "$p"
  return 0
}

# td_senders <org>: what publishes to those topics from the organization without a Logging sink: Security Command
# Center notification configs and Cloud Asset feeds. Only those sending to one of TD_TOPICS are listed, and they go
# in the first group, so they are deleted before their topics. A listing that is refused is never "none" - an API
# that is off names the project gcloud bills the call to, not this organization (measured 2026-10-13: SCC answered
# SERVICE_DISABLED) - but it does not block the teardown either: a config left behind only points at a topic that is
# gone. It becomes a by-hand line that says how to check.
td_senders() {
  local out rows name topic loc
  if [[ -z "$TD_TOPICS" ]]; then
    td_add 1 kept "no abstract-* topic found, so no Security Command Center notification or Cloud Asset feed can send to one; neither was listed"
    return
  fi
  if ! out=$(gcloud scc notifications list --organization="$1" --location=global --format=json 2>&1); then
    td_add 1 byhand "could not list the Security Command Center notification configs at the organization $1 ($(first_line "$out")). If you deployed the SCC template, check with: gcloud scc notifications list --organization=$1 --location=global$(td_quota_hint "Security Command Center")"
  elif ! rows=$(td_rows "$out" notificationConfigs pubsubTopic); then
    bad "could not read the Security Command Center notification configs at the organization $1"
  else
    while IFS=$'\t' read -r name topic; do
      topic=$(td_topic_id "$topic"); [[ -n "$name" ]] && has "$TD_TOPICS" "$topic" || continue
      loc=global; [[ "$name" =~ /locations/([^/]+)/ ]] && loc=${BASH_REMATCH[1]}
      td_add 1 remove "Security Command Center notification config ${name##*/} at the organization $1 (sends to $topic)" \
        gcloud scc notifications delete "${name##*/}" --organization="$1" --location="$loc" --quiet
    done <<<"$rows"
  fi
  # gcloud asset feeds list prints the whole ListFeedsResponse ({"feeds": [...]}), not one row per feed.
  if ! out=$(gcloud asset feeds list --organization="$1" --format=json 2>&1); then
    td_add 1 byhand "could not list the Cloud Asset feeds at the organization $1 ($(first_line "$out")). If you deployed the asset template, check with: gcloud asset feeds list --organization=$1$(td_quota_hint "Cloud Asset")"
  elif ! rows=$(td_rows "$out" feeds feedOutputConfig.pubsubDestination.topic); then
    bad "could not read the Cloud Asset feeds at the organization $1"
  else
    while IFS=$'\t' read -r name topic; do
      topic=$(td_topic_id "$topic"); [[ -n "$name" ]] && has "$TD_TOPICS" "$topic" || continue
      td_add 1 remove "Cloud Asset feed ${name##*/} at the organization $1 (sends to $topic)" \
        gcloud asset feeds delete "${name##*/}" --organization="$1" --quiet
    done <<<"$rows"
  fi
}
# td_topic_id <topic>: projects/NUMBER/topics/T written as projects/ID/topics/T when the walk saw that project.
td_topic_id() {
  local w
  if [[ "$1" =~ ^projects/([0-9]+)/topics/(.+)$ ]]; then
    for w in $TD_PNUMS; do [[ "${w%%:*}" == "${BASH_REMATCH[1]}" ]] && { printf 'projects/%s/topics/%s' "${w#*:}" "${BASH_REMATCH[2]}"; return; }; done
  fi
  printf '%s' "$1"
}
# td_quota_hint <api>: what to do when an organization-level listing is refused. Such a call has no project of its
# own, so gcloud bills it to billing/quota_project, or else the current project (gcloud config set --help).
td_quota_hint() { printf ' - if the %s API is off in the project gcloud bills this call to, turn it on there or name one where it is on (gcloud config set billing/quota_project PROJECT_ID), then run this again' "$1"; }
# td_rows <json> <list key> <dotted topic field>: name<TAB>topic per item, from a JSON list or {"<key>": [...]}.
td_rows() {
  python3 -c 'import json, sys
d = json.loads(sys.argv[1] or "[]")
items = d.get(sys.argv[2], []) if isinstance(d, dict) else d
for i in items:
    t = i
    for k in sys.argv[3].split("."): t = t.get(k, {}) if isinstance(t, dict) else {}
    print(i.get("name", "") + "\t" + (t if isinstance(t, str) else ""))' "$@"
}

# td_project <project>: what the setup makes in a logging project: subscriptions and topics (from td_scan), alerts.
td_project() {
  local p="$1" path t subs s n
  has "$TD_SCAN_FAILED" "$p" && return     # its topics could not be listed: reported once, by td_scan
  for path in $TD_TOPICS; do
    [[ "$path" == "projects/$p/topics/"* ]] || continue
    t=${path##*/}
    if subs=$(gcloud pubsub topics list-subscriptions "$t" --project="$p" --format=json 2>&1) \
       && subs=$(python3 -c 'import json, sys
for s in json.loads(sys.stdin.read().strip() or "[]"):
    print(s if isinstance(s, str) else s.get("name", ""))' <<<"$subs" 2>/dev/null); then
      while IFS= read -r s; do
        [[ -n "$s" ]] || continue
        local note=""; [[ "$s" == "projects/$p/subscriptions/$SUB" ]] && note=" - Abstract reads this one: delete the integration in Abstract first"
        td_add 2 remove "subscription $s (on topic $t)$note" gcloud pubsub subscriptions delete "$s" --quiet
      done <<<"$subs"
    else bad "could not list the subscriptions on topic $t in $p: $(first_line "$subs")"; fi
    td_add 3 remove "topic $t in $p" gcloud pubsub topics delete "$t" --project="$p" --quiet
    td_add 1 byhand "Cloud Storage notifications sending to $path are not listed here: finding them means reading every bucket. The projects whose buckets can send to it are the gs-project-accounts publishers in: gcloud pubsub topics get-iam-policy $t --project=$p. In each such bucket: gcloud storage buckets notifications list gs://BUCKET, then gcloud storage buckets notifications delete with the name of each one whose topic is this one (deleting the topic stops them publishing, but they stay on the bucket)"
  done
  if td_mon alertPolicies "alert policies" "$p"; then
    for n in $MON_NAMES; do td_add 5 remove "alert policy $n" mon_delete "$n"; td_show "DELETE https://monitoring.googleapis.com/v3/$n"; done
    td_mon notificationChannels "notification channels" "$p" && for n in $MON_NAMES; do
      td_add 5 remove "alert channel $n" mon_delete "$n" force=true; td_show "DELETE https://monitoring.googleapis.com/v3/$n?force=true"; done
  fi
  td_add 9 byhand "logging project $p: never deleted here. If it holds nothing else: gcloud projects delete $p (Google keeps a deleted project for 30 days, and gcloud projects undelete $p restores it until then)"
}

# td_sas <project>: the setup's and the templates' reader accounts there (abstract-*-reader, or the answers' names).
# A project with the IAM API off has none of them: the setup and the templates create accounts through that API.
td_sas() {
  local p="$1" out email a
  if ! out=$(gcloud iam service-accounts list --project="$p" --format='value(email)' 2>&1); then
    grep -qiE 'SERVICE_DISABLED|has not been used in project|it is disabled' <<<"$out" && return
    bad "could not list the service accounts in $p: $(first_line "$out")"; return
  fi
  while IFS= read -r email; do
    [[ "$email" == *@"$p".iam.gserviceaccount.com ]] || continue
    a=${email%%@*}
    [[ "$a" == abstract-*-reader || "$a" == "$SA" || "$a" == "$WS_SA" ]] || continue
    td_add 4 remove "service account $email (deleting it deletes its keys, so whatever signs in with them stops)" \
      gcloud iam service-accounts delete "$email" --project="$p" --quiet
  done <<<"$out"
}

# td_mon <collection> <what> <project>: like mon_list, except that a project with the Monitoring API off has no
# alerts (script step 8 is optional, and only it turns the API on): said, and not a failure. Status 1 then, and for
# any other failure, which mon_list reports.
td_mon() {
  local body code
  body=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $(token)" "https://monitoring.googleapis.com/v3/projects/$3/$1?pageSize=200")
  code=${body##*$'\n'}
  if [[ "$code" == 403 ]] && grep -qiE 'SERVICE_DISABLED|has not been used in project|it is disabled' <<<"${body%$'\n'*}"; then
    [[ "$1" == alertPolicies ]] && td_add 5 kept "no alerts in $3: the Monitoring API is off there (script step 8 never ran)"
    MON_NAMES=""; return 1
  fi
  mon_list "$@"
}

# td_audit <resource url> <label>: the Data Access settings there, listed. Never changed here: see td_audit_change.
td_audit() {
  local cur listed
  if ! cur=$(audit_config_json "$1"); then bad "could not read the audit settings at $2: $cur"; return; fi
  listed=$(python3 -c 'import json, sys
for c in json.loads(sys.argv[1]).get("auditConfigs", []):
    print(c["service"] + " (" + ", ".join(l["logType"] for l in c.get("auditLogConfigs", [])) + ")")' "$cur") \
    || { bad "could not read the audit settings at $2"; return; }
  [[ -n "$listed" ]] || { td_add 6 kept "no Data Access settings at $2"; return; }
  local line; while IFS= read -r line; do td_add 6 kept "configured at $2: $line"; done <<<"$listed"
}

# td_audit_change <org>: what --include-audit-settings changes: ONLY the service:logType pairs step 6 recorded adding
# (DA_ADDED), at the scope where it added them. With no record that applies, nothing is changed: the settings are
# listed above, and the by-hand line says how to take log types off and where step 6's copy is.
td_audit_change() {
  local why kind id
  if ! why=$(td_audit_record "$1"); then
    kind="${SCOPE:-organization}"; id="${SCOPE_ID:-$1}"; [[ "$ORG_ID" == "$1" ]] || { kind=organization; id="$1"; }
    local hint; hint="${DA_BACKUP:+ The copy of the settings step 6 saved before its change is $DA_BACKUP; never set it back over changes made since.}"
    if $TD_AUDIT; then
      td_add 6 byhand "Data Access settings: $why, so --include-audit-settings changes nothing (what is on now is listed above).$hint To take off a log type you turned on: gcloud $(td_policy_kind "$kind") get-iam-policy $id --format=json > policy.json, remove only that entry under auditConfigs, then gcloud $(td_policy_kind "$kind") set-iam-policy $id policy.json (the file keeps the etag, so a change made since is refused, not overwritten)"
    else td_add 6 kept "Data Access settings stay: $why, so --include-audit-settings would change nothing either.$hint"; fi
    return
  fi
  local url label cur left same; url=$(scope_url); label="the $SCOPE $SCOPE_ID"
  if ! cur=$(audit_config_json "$url"); then bad "could not read the audit settings at $label: $cur"; return; fi
  left=$(td_audit_plan "$cur" "$DA_ADDED") || { bad "could not work out what to take off the audit settings at $label"; return; }
  same=$(python3 -c 'import json, sys
print("yes" if json.loads(sys.argv[1]).get("auditConfigs", []) == json.loads(sys.argv[2]) else "")' "$cur" "$left") \
    || { bad "could not compare the audit settings at $label with what would be left"; return; }
  if [[ -n "$same" ]]; then td_add 6 kept "Data Access settings at $label: none of what script step 6 added (${DA_ADDED// /, }) is on now"; return; fi
  local what; what="Data Access settings at $label: take off only what script step 6 added (${DA_ADDED// /, }); everything else stays, and a copy is saved first"
  if $TD_AUDIT; then td_add 6 remove "$what" td_audit_remove "$url" "$label"
    td_show "POST $url:getIamPolicy, save a copy, then POST $url:setIamPolicy with its etag and updateMask=auditConfigs"
  else td_add 6 kept "$what - only with --include-audit-settings"; fi
}

# td_state: Terraform state in this repository's template folders. Never deleted; the commands that make Terraform
# forget what was deleted above are printed.
td_state() {
  local d name addrs n=0
  for d in "$ROOT"/templates/gcp/*/; do
    d=${d%/}; name=$(basename "$d")
    if [[ -f "$d/terraform.tfstate" ]]; then
      addrs=$(python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
for r in d.get("resources", []):
    if r.get("mode") != "managed": continue
    a = (r["module"] + "." if r.get("module") else "") + r["type"] + "." + r["name"]
    for i in r.get("instances", [{}]):
        k = i.get("index_key")
        print(a if k is None else a + ("[%d]" % k if isinstance(k, int) else "[\"%s\"]" % k))' "$d/terraform.tfstate" 2>/dev/null) || addrs="?"
      if [[ "$addrs" == "?" ]]; then byhand_td "$name: terraform.tfstate could not be read; look at it with terraform state list in $d"; n=$((n + 1)); continue; fi
      [[ -n "$addrs" ]] || continue
      local rm="terraform state rm"; local a; while IFS= read -r a; do rm+=" '$a'"; done <<<"$addrs"
      td_add 8 byhand "$name holds $(grep -c . <<<"$addrs") resource(s) in its local state. Run in $d (state rm forgets them; it deletes nothing):"$'\n'"      cd $(printf '%q' "$d")"$'\n'"      $rm"
      n=$((n + 1))
    elif [[ -f "$d/backend.tf" || -d "$d/.terraform" ]]; then
      td_add 8 byhand "$name has been initialised and keeps its state elsewhere (backend.tf). In $d, list what it believes exists with terraform state list, then terraform state rm each address"
      n=$((n + 1))
    fi
  done
  (( n )) && td_add 8 byhand "the templates' topic, subscription and sink carry prevent_destroy, so terraform destroy refuses them: state rm is how Terraform forgets what was deleted here, so the next apply creates it again"
  (( n )) || td_add 8 kept "no Terraform state in $ROOT/templates/gcp"
}
byhand_td() { td_add 8 byhand "$1"; }

td_print() {  # td_print <dry|confirm>
  local g i any label
  for ((g = 1; g <= ${#TD_GROUPS[@]}; g++)); do
    any=false
    for ((i = 0; i < ${#TD_WHAT[@]}; i++)); do
      [[ "${TD_G[$i]}" == "$g" ]] || continue
      $any || { say ""; say "  ${B}${TD_GROUPS[$((g - 1))]}${O}"; any=true; }
      case "${TD_K[$i]}" in
        remove) [[ "$1" == dry ]] && label="would remove" || label="will remove"
                WOULD=$((WOULD + 1)); printf '  %s%s%s %s\n' "$Y" "$label" "$O" "${TD_WHAT[$i]}"
                printf '%s   $ %s%s\n' "$D" "${TD_SHOW[$i]:-${TD_CMD[$i]% }}" "$O" ;;
        byhand) byhand "${TD_WHAT[$i]}" ;;
        kept)   kept "${TD_WHAT[$i]}" ;;
      esac
    done
  done
}

# teardown: the full reset. Every failure is counted, wherever it happened (FAIL_LOG): one that went uncounted
# once reported success and moved the answers file aside while resources remained.
teardown() {
  FAIL_LOG=$(mktemp) || { FAIL_LOG=""; bad "could not make a temporary file to count failures in; nothing was listed or deleted"; return; }
  TD_FAILS0=$FAILS
  td_main
  td_count_fails; rm -f "$FAIL_LOG"; FAIL_LOG=""
}
td_count_fails() { FAILS=$(( TD_FAILS0 + $(wc -l <"$FAIL_LOG") )); }

td_main() {
  local org="${TD_ORG:-$ORG_ID}" orgs n f p
  title "x" "Full reset"
  why "Lists what this setup and the templates made across the organization, so you can start from scratch."
  why "Projects and Terraform state are never deleted; their commands are printed. Nothing is deleted without --confirm."
  why "Delete the integrations in Abstract first, so they stop reading."
  if [[ -z "$org" ]]; then
    orgs=$(listing gcloud organizations list --format='value(ID)') || { bad "could not list your organizations; name one with --org ORG_ID"; return; }
    n=$(grep -c . <<<"$orgs")
    if (( n == 1 )); then org=$(trim "$orgs")
    elif (( n == 0 )); then bad "no organization is visible to you; name one with --org ORG_ID"; return
    else bad "$n organizations are visible ($(paste -sd' ' - <<<"$orgs")): name the one to reset with --org ORG_ID"; return; fi
  fi
  say "  organization $org"
  TD_LOGPROJ=""; TD_TOPICS=""; TD_SCANNED=""; TD_SCAN_FAILED=""
  td_tree "$org"
  td_sinks "--organization=$org" "the organization $org"
  for f in $TD_FOLDERS; do td_sinks "--folder=$f" "the folder $f"; done
  for p in $TD_PROJECTS; do td_sinks "--project=$p" "the project $p"; td_scan "$p"; done
  [[ -n "$LOG_PROJECT" ]] && add_word TD_LOGPROJ "$LOG_PROJECT"
  for p in $FIND_PROJECTS; do add_word TD_LOGPROJ "$p"; done
  for p in $TD_LOGPROJ; do td_scan "$p"; done     # outside the walk: a sink's destination, --project, the answers
  td_senders "$org"
  for p in $TD_LOGPROJ; do td_project "$p"; done
  local all="$TD_PROJECTS"; for p in $TD_LOGPROJ; do add_word all "$p"; done
  for p in $all; do td_sas "$p"; done
  for f in "$KEY_FILE" "$WS_KEY_FILE" $(aside_keys); do [[ -f "$f" ]] && td_add 4 remove "key file $f" rm -f "$f"; done
  td_audit "https://cloudresourcemanager.googleapis.com/v3/organizations/$org" "the organization $org"
  [[ "$SCOPE" == folder || ( "$SCOPE" == project && -n "$SCOPE_ID" ) ]] && td_audit "$(scope_url)" "the $SCOPE $SCOPE_ID"
  td_audit_change "$org"
  local g kind rest id role member
  if [[ -n "$GRANTS" ]]; then
    local -a gl; IFS=';' read -ra gl <<<"$GRANTS"
    for g in "${gl[@]}"; do
      kind=${g%%:*}; rest=${g#*:}; id=${rest%%:*}; rest=${rest#*:}; role=${rest%%:*}; member=${rest#*:}
      [[ -n "$kind" && -n "$id" && -n "$role" && -n "$member" ]] || continue
      if $TD_GRANTS; then binding_cmd "$kind" "$id" "$role" "$member" remove
        td_add 7 remove "$role for $member on the ${kind/billing/billing account} $id" "${BCMD[@]}" --format=none
      else td_add 7 kept "$role for $member on the ${kind/billing/billing account} $id (added by --grant) - only with --include-grants, or take it back yourself: $(grant_undo "$kind" "$id" "$role" "$member")"; fi
    done
  else td_add 7 kept "no role grants recorded by --grant in $STATE"; fi
  td_state
  (( ${#TD_LOGPROJ} )) || td_add 9 kept "no logging project found (no topic named abstract-* or $TOPIC, and none named with --project)"

  td_print "$($CONFIRM && echo confirm || echo dry)"
  say ""
  if ! $CONFIRM; then
    local flags="--teardown"; [[ -n "$TD_ORG" ]] && flags+=" --org $TD_ORG"; $TD_AUDIT && flags+=" --include-audit-settings"
    $TD_GRANTS && flags+=" --include-grants"; for p in $FIND_PROJECTS; do flags+=" --project $p"; done
    # shellcheck disable=SC2086  # the flags are words
    if (( WOULD > 0 )); then say "  Nothing was deleted. To delete the items marked 'would remove':  $(again $flags --confirm)"
    else say "  Nothing is marked 'would remove'. Act on the by-hand lines yourself."; fi
    return
  fi
  (( WOULD > 0 )) || { say "  Nothing to delete. Act on the by-hand lines yourself."; return; }
  if $HAVE_TTY; then
    local typed
    to_tty '  %sType the organization ID (%s) to delete the %d item(s) marked "will remove", or press Enter to stop:%s ' "$B" "$org" "$WOULD" "$O"
    IFS= read -r typed </dev/tty || typed=""
    [[ "$(trim "$typed")" == "$org" ]] || { say "  That is not $org. Nothing was deleted."; return; }
  fi
  local i
  for ((g = 1; g <= 7; g++)); do
    for ((i = 0; i < ${#TD_WHAT[@]}; i++)); do
      [[ "${TD_G[$i]}" == "$g" && "${TD_K[$i]}" == remove ]] || continue
      td_run "$i"
    done
  done
  say ""
  td_count_fails
  if (( FAILS == 0 )); then
    if [[ -f "$STATE" ]]; then local moved; moved="$STATE.teardown-$(date +%Y%m%d%H%M%S)"; mv "$STATE" "$moved" && say "  saved answers moved aside to $moved"; fi
    say "  Done. Act on the by-hand lines above (projects, Terraform state), then start again with:  $0"
  else say "  Some items could not be removed; your answers file stays, so this can be run again:  $(again --teardown)"; fi
}

# td_run <item>: one delete, and its result. Already gone counts as removed. It runs the words td_add kept, as an
# argument list: nothing is parsed again, so no name can become a command.
td_run() {
  local i="$1" out what; what="${TD_WHAT[$1]%% (*}"
  (( TD_LEN[i] > 0 )) || { bad "could not remove $what: no command was recorded for it"; return; }
  if out=$("${TD_ARGV[@]:TD_OFF[i]:TD_LEN[i]}" 2>&1); then pass "removed $what"
  elif grep -qiE 'NOT_FOUND|not found|does not exist' <<<"$out"; then pass "$what was already gone"
  else bad "could not remove $what: $(first_line "$out")"; fi
}

# ─────────────────────────────────────────────────────────────────────────────
ARGS=("$@")
RESET=false
# shellcheck disable=SC1090  # the state file is chosen at run time
while [[ $# -gt 0 ]]; do case "$1" in
  --check) CHECK_ONLY=true; shift ;;
  --remove) REMOVE=true; shift ;;
  --confirm) CONFIRM=true; shift ;;
  --step) ONLY_STEP="$2"; shift 2 ;;
  --new-key) NEW_KEY=true; shift ;;
  # A file that is not there is a stop, never the default answers: those may describe a different, live pipeline.
  --state) [[ -n "${2:-}" && -f "$2" ]] || { echo "no answers file at ${2:-(no path given)}: nothing was read, checked or removed"; exit 2; }
           STATE="$2"; defaults; load_answers "$STATE"; shift 2 ;;
  --project) [[ -n "${2:-}" ]] || { echo "--project needs a project ID"; exit 2; }
             [[ -n "$FIND_PROJECT" ]] || FIND_PROJECT="$2"; FIND_PROJECTS="${FIND_PROJECTS:+$FIND_PROJECTS }$2"; shift 2 ;;
  --teardown) TEARDOWN=true; shift ;;
  --org) [[ "${2:-}" =~ ^[0-9]{6,}$ ]] || { echo "--org needs an organization ID (digits): --org 123456789012"; exit 2; }
         TD_ORG="$2"; shift 2 ;;
  --include-audit-settings) TD_AUDIT=true; shift ;;
  --include-grants) TD_GRANTS=true; shift ;;
  --yes-i-mean-it) YES_I_MEAN_IT=true; shift ;;
  --reset) RESET=true; shift ;;
  --grant) [[ -n "${2:-}" && "$2" != --* ]] || { echo "--grant needs a principal: --grant name@example.com (a user), or group:, serviceAccount: before the email"; exit 2; }
           GRANT=$(grant_member "$2") || { echo "\"$2\" is not a principal: use an email address (a user), or user:, group: or serviceAccount: and the email"; exit 2; }
           shift 2 ;;
  -h|--help) sed -n '2,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option $1 (try --help)"; exit 2 ;; esac; done

summary() { printf '\n%s%d passed%s · %s%d to look at%s · %s%d to fix%s\n' "$G" "$PASSES" "$O" "$Y" "$WARNS" "$O" "$R" "$FAILS" "$O"; }
# Signed out, every read fails, and a failed read must never be reported as absent or as fine.
need_sign_in() {
  signed_in && return 0
  bad "$(signed_in_problem). Nothing was $1; run this again once signed in."
  summary; exit 1
}

if $NEW_KEY && { $CHECK_ONLY || [[ "$ONLY_STEP" != 7 ]]; }; then
  echo "--new-key goes only with --step 7, and not with --check: it makes another Workspace key. Nothing was checked or changed."; exit 2
fi
need gcloud; need python3; need curl
if $TEARDOWN && $REMOVE; then echo "--teardown and --remove do not go together: --remove takes away what the answers file recorded, --teardown everything the setup makes"; exit 2; fi
if $TEARDOWN && $CONFIRM && ! $HAVE_TTY && ! $YES_I_MEAN_IT; then
  echo "--teardown --confirm deletes across the organization. With no terminal to type the organization ID into, it also needs --yes-i-mean-it. Nothing was listed or deleted."; exit 2
fi
$RESET && start_over
if $TEARDOWN; then
  signed_in || launch
  need_sign_in "listed or removed"
  python3 "$HERE/brand.py" header "Google Cloud setup" "full reset$($CONFIRM || echo ' - dry run, nothing will be deleted')" "info|answers: $STATE"
  teardown
elif $REMOVE; then
  signed_in || launch
  need_sign_in "listed or removed"
  python3 "$HERE/brand.py" header "Google Cloud setup" "clean-up" "info|answers: $STATE"; remove_all
elif [[ -n "$GRANT" ]]; then
  signed_in || launch
  need_sign_in "checked or granted"
  python3 "$HERE/brand.py" header "Google Cloud setup" "$($CHECK_ONLY && echo 'grant roles - check only, nothing will change' || echo 'grant roles')" "info|answers: $STATE"
  grant_roles
elif $CONFIRM; then echo "--confirm only goes with --remove"; exit 2
else launch; need_sign_in checked
  if [[ -n "$ONLY_STEP" ]]; then "step$ONLY_STEP"; else for s in 1 2 3 4 5 6 7 8 9 10; do "step$s"; done; fi; fi
summary
[[ $FAILS -eq 0 ]]
