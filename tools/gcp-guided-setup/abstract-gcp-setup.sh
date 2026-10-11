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
#    9  Test and verify                 a fresh event, end to end
#   10  Connect Abstract                the exact values to enter
#
#  Usage
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh              guided: every step, asks before each change
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6     one step
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --check      verify everything, change nothing
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --reset      forget the saved answers and start over
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --remove     list what clean-up would delete; --remove --confirm deletes it
#    ... --remove --project <id>                                 no saved answers: list what carries the setup's names
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

# Defaults; anything in the state file wins. A function, so "start over" can put every answer back.
defaults() {
  TOPIC="abstract-audit-logs"; SUB="abstract-audit-logs-sub"; SINK="abstract-org-audit-sink"  # the Terraform and deploy-script default
  SA="abstract-pubsub-reader"; WS_SA="abstract-workspace-reader"; RETENTION_DAYS=7
  # iam and sts record service-account token minting and Workload Identity Federation token exchange.
  DA_SERVICES="bigquery.googleapis.com,storage.googleapis.com,cloudkms.googleapis.com,iam.googleapis.com,sts.googleapis.com"; DA_TYPES="ADMIN_READ,DATA_WRITE"
  DATA_ACCESS=no; WORKSPACE=no; ALERTS=no
  ORG_ID=""; SCOPE=""; SCOPE_ID=""; LOG_PROJECT=""; BILLING=""; WS_ADMIN=""; ALERT_EMAIL=""
  ALERT_POLICIES=""; ALERT_CHANNELS=""   # the alerts step 8 made, recorded by name
  SINK_CREATED_AT=0
  # Set to 1 only when THIS script creates the piece, so --remove never deletes something it found.
  TOPIC_CREATED=0; SUB_CREATED=0; SA_CREATED=0; WS_SA_CREATED=0
}
defaults; FIND_PROJECT=""
# Keys go outside any checkout, in a folder only you can read, so they cannot be committed by accident.
KEY_DIR="${ABSTRACT_KEY_DIR:-$HOME/abstract-keys}"
KEY_FILE="$KEY_DIR/abstract-pubsub-key.json"; WS_KEY_FILE="$KEY_DIR/abstract-workspace-key.json"
# shellcheck disable=SC1090
[[ -f "$STATE" ]] && source "$STATE"

B=$'\033[1m'; P=$'\033[38;5;198m'; G=$'\033[0;32m'; Y=$'\033[0;33m'; R=$'\033[0;31m'; D=$'\033[2m'; O=$'\033[0m'
title() { printf '\n%s━━ %s %s━━%s\n' "$P" "$1" "$2" "$O"; }
say()   { printf '%s\n' "$*"; }
why()   { printf '%s   %s%s\n' "$D" "$*" "$O"; }
pass()  { printf '  %s✓%s %s\n' "$G" "$O" "$*"; PASSES=$((PASSES+1)); }
warn()  { printf '  %s!%s %s\n' "$Y" "$O" "$*"; WARNS=$((WARNS+1)); }
bad()   { printf '  %s✗%s %s\n' "$R" "$O" "$*"; FAILS=$((FAILS+1)); }
PASSES=0; WARNS=0; FAILS=0
CHECK_ONLY=false; ONLY_STEP=""; REMOVE=false; CONFIRM=false

save() {
  $CHECK_ONLY && return 0
  umask 077
  # %q escapes every value, so an answer containing shell syntax is stored as text, never run.
  { echo "# Abstract GCP guided setup — your answers. Safe to delete; nothing secret is kept here."
    local v; for v in ORG_ID SCOPE SCOPE_ID LOG_PROJECT BILLING TOPIC SUB SINK SA RETENTION_DAYS DATA_ACCESS DA_SERVICES DA_TYPES \
      WORKSPACE WS_SA WS_ADMIN ALERTS ALERT_EMAIL SINK_CREATED_AT TOPIC_CREATED SUB_CREATED SA_CREATED WS_SA_CREATED \
      ALERT_POLICIES ALERT_CHANNELS; do printf '%s=%q\n' "$v" "${!v}"; done; } > "$STATE"
}

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
  curl -s -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" -d "$body" "$url:testIamPermissions" \
    | python3 -c 'import json,sys
try: print(" ".join(json.load(sys.stdin).get("permissions",[])))
except Exception: print("")'
}
scope_url() { case "$SCOPE" in
  organization) echo "https://cloudresourcemanager.googleapis.com/v3/organizations/$SCOPE_ID" ;;
  folder)       echo "https://cloudresourcemanager.googleapis.com/v3/folders/$SCOPE_ID" ;;
  project)      echo "https://cloudresourcemanager.googleapis.com/v3/projects/$SCOPE_ID" ;; esac; }
scope_flag() { case "$SCOPE" in organization) echo "--organization=$SCOPE_ID" ;; folder) echo "--folder=$SCOPE_ID" ;; project) echo "--project=$SCOPE_ID" ;; esac; }
has() { [[ " $1 " == *" $2 "* ]]; }

# ── Launch: who you are, what is saved, and a way to change either ──────────────────
MIRROR_URL="https://github.com/IamABS3C/abstract-cloud-templates"

# A listed account is not a working sign-in: gcloud keeps showing an account as active after its sign-in
# has expired (measured 2026-10-09). Only a token proves it.
signed_in() { [[ -n "$(gcloud config get-value account 2>/dev/null)" ]] && gcloud auth print-access-token >/dev/null 2>&1; }

sign_in() {
  say "  Signing in. A browser opens, or gcloud prints a link to open; finish there and come back."
  why "--update-adc also refreshes the credentials Terraform uses, for the template path."
  # The one command allowed to ask questions: it may need a code pasted back.
  CLOUDSDK_CORE_DISABLE_PROMPTS=0 gcloud auth login --update-adc </dev/tty >/dev/tty 2>&1 \
    && signed_in && pass "signed in as $(gcloud config get-value account 2>/dev/null)" || bad "sign-in did not finish"
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
  # Moved, never deleted: it records what this script created, which --remove --state <that file> still cleans up.
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
  say "  without your credentials, and its home folder (saved answers, and the key file step 5 makes) is"
  say "  deleted when the session ends. Either:"
  say "    - sign in here, and download the key in step 5 before you close Cloud Shell, or"
  say "    - open Cloud Shell from the Google Cloud console (the >_ button, top right) and run:"
  say "        git clone $MIRROR_URL && cd abstract-cloud-templates && ./tools/gcp-guided-setup/abstract-gcp-setup.sh"
}

launch() {
  local acct st=() ok=false a
  acct=$(gcloud config get-value account 2>/dev/null)
  signed_in && ok=true
  if $ok; then st+=("ok|signed in as $acct")
  elif [[ -n "$acct" ]]; then st+=("bad|$acct must sign in again")
  else st+=("bad|not signed in to gcloud"); fi
  [[ -n "$ORG_ID$SCOPE$LOG_PROJECT" ]] && st+=("info|saved: organization ${ORG_ID:-?}, scope ${SCOPE:-?} ${SCOPE_ID}, logging project ${LOG_PROJECT:-not chosen}")
  python3 "$HERE/brand.py" header "Google Cloud setup" "$($CHECK_ONLY && echo 'check only - nothing will change' || echo 'guided setup')" ${st[@]+"${st[@]}"}
  interactive || return 0
  while true; do
    if ! signed_in; then
      explain_cloud_shell
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
  signed_in && pass "signed in as $acct" || { bad "not signed in, or the sign-in has expired. Start the script again and choose to sign in, or run: gcloud auth login --update-adc"; return; }

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

# ─────────────────────────────────────────────────────────────────────────────
step2() {
  title 2 "What you can change"
  why "Each later step needs a specific permission. This asks Google directly which ones you hold."
  [[ -n "$SCOPE" && -n "$SCOPE_ID" ]] || { bad "choose a scope first (step 1)"; return; }
  local h; h=$(held "$(scope_url)" logging.sinks.create "resourcemanager.$( [[ $SCOPE == organization ]] && echo organizations || echo "${SCOPE}s" ).setIamPolicy")
  has "$h" logging.sinks.create && pass "create the log sink at the $SCOPE (step 4)" \
    || { bad "you cannot create a sink at the $SCOPE. You need roles/logging.configWriter there — not included in Organization Admin."
         why "An Organization Admin can grant it:  gcloud organizations add-iam-policy-binding $ORG_ID --member=user:$(gcloud config get-value account 2>/dev/null) --role=roles/logging.configWriter"; }
  has "$h" "resourcemanager.$( [[ $SCOPE == organization ]] && echo organizations || echo "${SCOPE}s" ).setIamPolicy" \
    && pass "turn on Data Access logs at the $SCOPE (step 6, optional)" \
    || warn "you cannot turn on Data Access logs at the $SCOPE (needs Organization Admin or Security Admin). Skip step 6 or ask them."
  if [[ -n "$ORG_ID" ]]; then
    local o; o=$(held "https://cloudresourcemanager.googleapis.com/v3/organizations/$ORG_ID" resourcemanager.projects.create)
    has "$o" resourcemanager.projects.create && pass "create a new logging project (step 3)" || warn "you cannot create projects in the organization; pick an existing logging project in step 3"
  fi
  if [[ -n "$LOG_PROJECT" ]]; then project_checks
  else
    warn "not checked yet: your rights in the logging project, and whether an org policy blocks the key step 5 makes. Step 3 checks both as soon as the project is chosen, before step 4 builds anything."
  fi
}

# What steps 4 and 5 need in the logging project. Step 2 runs it when the project is already known,
# and step 3 runs it again, so a blocked key shows up before step 4 creates the sink, not after.
# Called directly, never through $(...): a subshell would lose the pass and fail counts.
project_checks() {
  local p; p=$(held "https://cloudresourcemanager.googleapis.com/v3/projects/$LOG_PROJECT" pubsub.topics.create pubsub.subscriptions.create iam.serviceAccounts.create iam.serviceAccountKeys.create serviceusage.services.enable pubsub.topics.setIamPolicy)
  local miss=""; for x in pubsub.topics.create pubsub.subscriptions.create pubsub.topics.setIamPolicy iam.serviceAccounts.create iam.serviceAccountKeys.create serviceusage.services.enable; do
    has "$p" "$x" || miss+=" $x"; done
  [[ -z "$miss" ]] && pass "build the pipeline in $LOG_PROJECT (steps 3-5)" \
    || bad "missing in $LOG_PROJECT:$miss — Owner, or Pub/Sub Admin + Service Account Admin + Service Account Key Admin + Service Usage Admin"
  # The org policy that most often blocks the key in step 5.
  # A lookup that fails is not an answer: it is reported as unknown, never as "allowed".
  local kp
  if ! kp=$(gcloud resource-manager org-policies describe iam.disableServiceAccountKeyCreation --project="$LOG_PROJECT" --effective --format='value(booleanPolicy.enforced)' 2>/dev/null); then
    warn "could not read the org policy iam.disableServiceAccountKeyCreation on $LOG_PROJECT (it needs Organization Policy Viewer). If it is enforced, step 5 cannot create a key; ask your organization admin before step 4."
  elif [[ "$kp" == "True" ]]; then
    bad "org policy iam.disableServiceAccountKeyCreation is enforced on $LOG_PROJECT: step 5 cannot create a key. Ask for an exception on this project before step 4."
  else
    pass "service-account keys are allowed on $LOG_PROJECT (org policy iam.disableServiceAccountKeyCreation is not enforced)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
step3() {
  title 3 "Logging project"
  why "One dedicated project holds the topic, subscription and Abstract's service account."
  why "Not a workload project: whoever owns that project could read or break the pipeline."
  while [[ -z "$LOG_PROJECT" ]] && interactive; do
    # Suggest the project an existing Abstract sink already sends to, as the estate audit does.
    local sent; sent=$(gcloud logging sinks list "$(scope_flag)" --format='value(destination)' 2>/dev/null \
      | sed -n "s|^pubsub.googleapis.com/projects/\([^/]*\)/topics/$TOPIC\$|\1|p" | head -n1)
    [[ -n "$sent" ]] && say "  The existing sink already sends to $sent: choosing it keeps one pipeline."
    local pick; pick=$(choose_existing project "gcloud projects describe {}" "Which project holds the pipeline?" "$(project_list)" "create a new project for Abstract (recommended when none exists)" "$sent" '^[a-z][a-z0-9-]{4,28}[a-z0-9]$')
    if [[ "$pick" == +new ]]; then
      local new; new=$(ask "New project ID (globally unique, e.g. <company>-security-logging)" "" valid_project_id)
      local parent="--organization=$ORG_ID"; [[ "$SCOPE" == folder ]] && parent="--folder=$SCOPE_ID"
      # Saved only once it exists: an ID Google refused (taken, quota, no right) must not be kept.
      if run gcloud projects create "$new" "$parent" --name="Abstract security logging"; then LOG_PROJECT="$new"
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
    why "Link billing only if you will use Infrastructure Manager or high-volume logs."
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

filter() {
  local f='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy"'
  if [[ "$DATA_ACCESS" == yes ]]; then
    local c=""; IFS=',' read -ra S <<<"$(routed_services "$DA_SERVICES")"; for s in "${S[@]}"; do c+="${c:+ OR }\"$s\""; done
    f+=" OR (logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND protoPayload.serviceName=($c))"
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
    run gcloud pubsub subscriptions create "$SUB" --topic="$TOPIC" --project="$LOG_PROJECT" \
      --ack-deadline=60 --message-retention-duration="${RETENTION_DAYS}d" --expiration-period=never && { pass "subscription created"; SUB_CREATED=1; save; }
  fi

  local sf; sf=$(scope_flag); local want; want=$(filter)
  local dest="pubsub.googleapis.com/projects/$LOG_PROJECT/topics/$TOPIC"
  # A sink already sending to this topic under another name is adopted, never duplicated:
  # two sinks to one topic deliver every event twice.
  if ! gcloud logging sinks describe "$SINK" "$sf" >/dev/null 2>&1; then
    local other; other=$(gcloud logging sinks list "$sf" --format='value(name,destination)' 2>/dev/null | awk -v d="$dest" '$2==d{print $1; exit}')
    [[ -n "$other" ]] && { say "  found sink $other already sending to $TOPIC; using it"; SINK="$other"; SINK_CREATED_AT=0; save; }
  fi
  if gcloud logging sinks describe "$SINK" "$sf" >/dev/null 2>&1; then
    local d f ic; d=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(destination)'); f=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(filter)')
    ic=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(includeChildren)')
    [[ "$d" == "$dest" ]] && pass "sink $SINK sends to $TOPIC" || bad "sink $SINK sends to $d, not $dest"
    if [[ "$SCOPE" != project ]]; then
      [[ "$ic" == True ]] && pass "sink covers every project under the $SCOPE (includeChildren)" \
        || bad "sink $SINK does not include child projects: logs from projects under the $SCOPE never reach Abstract. Recreate it with --include-children (or set include_children in Terraform)."
    fi
    # Only ever ADD what is missing. An existing sink may route more (firewall, DNS…); that is kept.
    local missing_clauses; missing_clauses=$(python3 - "$f" "$want" <<'PY'
import re, sys
have, want = sys.argv[1], sys.argv[2]
parts = [p.strip() for p in re.split(r"\s+OR\s+(?![^()]*\))", want) if p.strip()]
norm = lambda x: re.sub(r"\s+", " ", x)
print(" OR ".join(p for p in parts if norm(p) not in norm(have)))
PY
)
    if [[ -z "$missing_clauses" ]]; then pass "sink filter routes everything these answers need"
    else warn "the sink does not yet route: $missing_clauses"
         why "Its existing filter is kept; only the missing part is added. If Terraform manages this sink, add it there and answer no."
         run gcloud logging sinks update "$SINK" "$sf" --log-filter="($f) OR $missing_clauses" && pass "sink filter extended"; fi
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
      run gcloud pubsub topics add-iam-policy-binding "$TOPIC" --project="$LOG_PROJECT" --member="$w" --role=roles/pubsub.publisher >/dev/null && pass "publisher granted to the sink identity"
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

  if gcloud pubsub subscriptions get-iam-policy "$SUB" --project="$LOG_PROJECT" --format=json 2>/dev/null | grep -q "serviceAccount:$email"; then
    pass "it can read $SUB (roles/pubsub.subscriber on the subscription)"
  else
    bad "it cannot read $SUB yet"
    run gcloud pubsub subscriptions add-iam-policy-binding "$SUB" --project="$LOG_PROJECT" --member="serviceAccount:$email" --role=roles/pubsub.subscriber >/dev/null && pass "subscriber granted"
  fi
  # Anything broader than that one subscription is a finding, not a convenience.
  if gcloud projects get-iam-policy "$LOG_PROJECT" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$email" --format='value(bindings.role)' 2>/dev/null | grep -q .; then
    warn "$email also holds project-wide roles on $LOG_PROJECT. It needs none; remove them."
  else pass "no project-wide roles (least privilege)"; fi

  local n; n=$(gcloud iam service-accounts keys list --iam-account="$email" --managed-by=user --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')
  if [[ -f "$KEY_FILE" ]]; then pass "key file ready to upload: $KEY_FILE"
  elif [[ "${n:-0}" -gt 0 ]]; then pass "$n key(s) already exist; Abstract uses the one you uploaded. Make another only if it was lost."
    ! $CHECK_ONLY && yes_no "Create a new key anyway?" && make_key "$email" "$KEY_FILE"
  else warn "no key yet. Abstract needs one to sign in."; ! $CHECK_ONLY && make_key "$email" "$KEY_FILE"; fi
}

make_key() {
  why "The key is written to a file only you can read. Upload it to Abstract, then delete it."
  mkdir -p "$KEY_DIR" && chmod 700 "$KEY_DIR"
  run gcloud iam service-accounts keys create "$2" --iam-account="$1" && { chmod 600 "$2"; pass "key written to $2 (not printed)"; }
}

# ─────────────────────────────────────────────────────────────────────────────
audit_config_json() {  # the current auditConfigs at the scope, as JSON
  curl -s -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" -d '{}' "$(scope_url):getIamPolicy" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"etag":d.get("etag"),"auditConfigs":d.get("auditConfigs",[])}))'
}

step6() {
  title 6 "Data Access logs (optional)"
  why "Admin Activity logs are always on. Data Access logs (who read or changed data in BigQuery,"
  why "Cloud Storage, KMS…, and who minted service-account tokens or exchanged federated identities)"
  why "are OFF until you turn them on. It takes TWO switches:"
  why "  switch 1 — generate them: the audit config at the ${SCOPE:-chosen scope}"
  why "  switch 2 — route them:    the sink filter (step 4 adds them when this is on)"
  why "Either alone does nothing, silently. DATA_READ is high volume; it is off by default here."
  if [[ "$DATA_ACCESS" != yes ]] && ! $CHECK_ONLY; then
    yes_no "Turn on Data Access logs?" || { say "  skipped — Admin Activity still flows"; return; }
    DATA_ACCESS=yes
    why "iam.googleapis.com records service-account impersonation and token minting; sts.googleapis.com"
    why "records Workload Identity Federation (GitHub Actions, AWS, Azure). Keep both unless you have a reason."
    DA_SERVICES=$(csv "$(ask "Services (comma-separated)" "$DA_SERVICES" valid_services)")
    DA_TYPES=$(csv "$(ask "Log types (ADMIN_READ, DATA_WRITE, DATA_READ)" "$DA_TYPES" valid_log_types)")
    save
  fi
  [[ "$DATA_ACCESS" == yes ]] || { say "  off (your choice)"; return; }

  local cur; cur=$(audit_config_json); local switched; switched=$(audit_services "$DA_SERVICES")
  local missing; missing=$(python3 - "$cur" "$switched" "$DA_TYPES" <<'PY'
import json, sys
cur = json.loads(sys.argv[1]); svcs = sys.argv[2].split(","); types = sys.argv[3].split(",")
have = {}
for c in cur.get("auditConfigs", []):
    have.setdefault(c["service"], set()).update(l["logType"] for l in c.get("auditLogConfigs", []))
allsvc = have.get("allServices", set())
print(" ".join(f"{s}:{t}" for s in svcs for t in types if t not in have.get(s, set()) and t not in allsvc))
PY
)
  if [[ -z "$missing" ]]; then pass "switch 1: Data Access is generated for ${switched//,/, } ($DA_TYPES)"
  else
    bad "switch 1 is off for: $missing"
    why "This changes ONLY the audit settings at the ${SCOPE:-chosen scope} (updateMask=auditConfigs); role bindings are untouched."
    why "A copy of the current settings is saved first."
    if ! $CHECK_ONLY && yes_no "Turn switch 1 on now?"; then
      local backup; backup="$PWD/abstract-audit-config-backup-$(date +%Y%m%d%H%M%S).json"
      printf '%s\n' "$cur" > "$backup"; say "  saved current settings to $backup"
      local body; body=$(python3 - "$cur" "$switched" "$DA_TYPES" <<'PY'
import json, sys
cur = json.loads(sys.argv[1]); svcs = sys.argv[2].split(","); types = sys.argv[3].split(",")
cfgs = {c["service"]: c for c in cur.get("auditConfigs", [])}
for s in svcs:
    c = cfgs.setdefault(s, {"service": s, "auditLogConfigs": []})
    have = {l["logType"] for l in c["auditLogConfigs"]}
    c["auditLogConfigs"] += [{"logType": t} for t in types if t not in have]
print(json.dumps({"policy": {"etag": cur["etag"], "auditConfigs": list(cfgs.values())}, "updateMask": "auditConfigs"}))
PY
)
      local out; out=$(curl -s -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" -d "$body" "$(scope_url):setIamPolicy")
      grep -q '"error"' <<<"$out" && bad "Google refused: $(python3 -c 'import json,sys;print(json.load(sys.stdin)["error"]["message"])' <<<"$out")" || pass "switch 1 on"
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
  why "Sign-ins, admin changes and token grants in Google Workspace do NOT go through Cloud"
  why "Logging. Abstract reads them from the Workspace Reports API with a separate service"
  why "account that a Workspace SUPER ADMIN allows through domain-wide delegation."
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
    OAuth scopes  https://www.googleapis.com/auth/admin.reports.audit.readonly,https://www.googleapis.com/auth/admin.reports.usage.readonly
    (one line, comma-separated, no spaces; both are read-only)

EOF
  [[ -f "$WS_KEY_FILE" ]] && pass "key file ready: $WS_KEY_FILE" || { ! $CHECK_ONLY && make_key "$email" "$WS_KEY_FILE"; }
  if [[ -f "$WS_KEY_FILE" && -n "$WS_ADMIN" ]]; then
    verify_workspace "$WS_KEY_FILE" "$WS_ADMIN"
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
  # REST, not "gcloud alpha": the alpha component may not be installed, and installing it prompts.
  local have; have=$(curl -s -H "Authorization: Bearer $(token)" "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/alertPolicies?pageSize=200" \
    | python3 -c 'import json,sys;print(sum(1 for p in json.load(sys.stdin).get("alertPolicies",[]) if p.get("displayName","").startswith("Abstract log pipeline")))' 2>/dev/null)
  # gcp-monitoring-pipeline-health-alerts makes three policies without a dead-letter topic (this setup uses none).
  if [[ "${have:-0}" -ge 3 ]]; then pass "$have Abstract alert policies exist"; return; fi
  [[ "${have:-0}" -gt 0 ]] && warn "only ${have} of 3 alert policies exist" || warn "no Abstract alert policies yet"
  $CHECK_ONLY && return
  need terraform
  while [[ -z "$ALERT_EMAIL" ]]; do
    ALERT_EMAIL=$(ask "Email that receives the alerts (Enter for none)" "" "?valid_email")
    [[ -n "$ALERT_EMAIL" ]] || { yes_no "Create the alerts with nobody to tell?" && break; }
  done; save
  local dir="$ROOT/templates/gcp/gcp-monitoring-pipeline-health-alerts" ch="[]"
  if [[ -n "$ALERT_EMAIL" ]]; then
    local body; body=$(python3 -c 'import json,sys;print(json.dumps({"type":"email","displayName":"Abstract log pipeline","labels":{"email_address":sys.argv[1]}}))' "$ALERT_EMAIL")
    local cname; cname=$(curl -s -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" -d "$body" \
      "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/notificationChannels" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("name",""))')
    [[ -n "$cname" ]] || { bad "could not create the email channel for $ALERT_EMAIL; alerts not created, so none are silent. Check that the Monitoring API is on (step 3)."; return; }
    pass "email channel for $ALERT_EMAIL"; ch="[\"$cname\"]"; ALERT_CHANNELS="$cname"; save
  fi
  python3 -c 'import json,sys;print(json.dumps({"log_project":sys.argv[1],"topic_id":sys.argv[2],"subscription_id":sys.argv[3],"notification_channels":json.loads(sys.argv[4]),"acknowledge_no_channel":sys.argv[4]=="[]"}, indent=2))' \
    "$LOG_PROJECT" "$TOPIC" "$SUB" "$ch" > "$dir/abstract.auto.tfvars.json"
  terraform -chdir="$dir" init -input=false >/dev/null || { bad "terraform init failed in $dir"; return; }
  terraform -chdir="$dir" plan -input=false -out=abstract.tfplan || { bad "terraform plan failed"; return; }
  # The plan above is the preview; approving it here is the only confirmation.
  local before ok=0; before=$(alert_policy_names)
  run terraform -chdir="$dir" apply -input=false abstract.tfplan && ok=1
  # Record what this apply added, even when it failed part-way, and keep what earlier attempts
  # recorded: clean-up removes exactly these and never someone else's.
  local added; added=$(comm -13 <(printf '%s\n' "$before" | sort) <(alert_policy_names | sort))
  ALERT_POLICIES=$(printf '%s\n' $ALERT_POLICIES $added | sort -u | tr '\n' ' '); save
  (( ok )) && pass "alerts created" || bad "terraform apply failed; the alerts it did create are recorded for clean-up"
}

# Where the probe must be written: somewhere the sink can see, with an API that is on.
probe_project() {
  case "$SCOPE" in
    project) echo "$SCOPE_ID" ;;
    organization) echo "$LOG_PROJECT" ;;
    folder) if gcloud projects get-ancestors "$LOG_PROJECT" --format='value(id)' 2>/dev/null | grep -qx "$SCOPE_ID"; then echo "$LOG_PROJECT"
            else gcloud projects list --filter="parent.type=folder AND parent.id=$SCOPE_ID" --format='value(projectId)' --limit=1 2>/dev/null; fi ;;
  esac
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
  [[ -n "$pp" ]] || { bad "found no project inside folder $SCOPE_ID to write the test event in"; return; }
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
  for i in $(seq 1 20); do
    sleep 15
    # Only this script reads the probe subscription, so acknowledging there is safe.
    got=$(gcloud pubsub subscriptions pull "$probe_sub" --project="$LOG_PROJECT" --limit=50 --auto-ack --format=json 2>/dev/null | python3 -c '
import base64, json, sys
for m in json.load(sys.stdin) or []:
    d = m.get("message", {}).get("data", "")
    try: d = base64.b64decode(d).decode("utf-8", "replace")
    except Exception: pass
    if sys.argv[1] in d: print(sys.argv[1]); break' "$probe")
    [[ -n "$got" ]] && break
    # One more event half way, in case the first was written before routing began.
    [[ $i -eq 10 ]] && { echo; send_probe || true; }
    printf '.'
  done; echo
  gcloud pubsub subscriptions delete "$probe_sub" --project="$LOG_PROJECT" --quiet >/dev/null 2>&1 \
    || warn "could not delete the probe subscription $probe_sub; it expires by itself after 1 day"
  [[ -n "$got" ]] && pass "the test event arrived on $TOPIC — the pipeline works end to end" \
    || bad "no test event after 5 minutes. Check sink errors: gcloud logging read 'logName:\"logging.googleapis.com%2Fsink_error\"' --project=$LOG_PROJECT --limit=5"
}

# ─────────────────────────────────────────────────────────────────────────────
step10() {
  title 10 "Connect Abstract"
  cat <<EOF
  In Abstract, add the ${B}GCP Pub/Sub Source${O} integration:
    Project ID        ${B}$LOG_PROJECT${O}     ← the project with the SUBSCRIPTION, not the ones sending logs
    Subscription ID   ${B}$SUB${O}      ← the short name only
    Credentials       ${B}$(basename "$KEY_FILE")${O}      ← the key file, downloaded below
EOF
  [[ "$WORKSPACE" == yes ]] && cat <<EOF

  In Abstract, add the ${B}Google Workspace Audit Log Integration${O}:
    Admin Email       ${B}$WS_ADMIN${O}
    Credentials       ${B}$(basename "$WS_KEY_FILE")${O}      ← the key file, downloaded below
    Application Name  every application is selected by default. To start small, keep
                      Login, Admin, Token, SAML, User Accounts and Groups.
EOF
  # The keys exist only in this Cloud Shell session, which is temporary. Whoever fills in the
  # Abstract form needs them on their own computer: download, upload to Abstract, delete everywhere.
  local keys=("$KEY_FILE") f; [[ "$WORKSPACE" == yes ]] && keys+=("$WS_KEY_FILE")
  say ""
  say "  ${B}Download the key files.${O} They exist only in this Cloud Shell session, which is temporary:"
  local acct n
  for f in "${keys[@]}"; do
    if [[ -f "$f" ]]; then say "    cloudshell download $f"; continue; fi
    # No file is normal after the upload: the guide says to delete it. Only a missing key is a problem.
    if [[ "$f" == "$WS_KEY_FILE" ]]; then acct="$WS_SA@$LOG_PROJECT.iam.gserviceaccount.com"; else acct="$SA@$LOG_PROJECT.iam.gserviceaccount.com"; fi
    local step; step=$([[ "$f" == "$WS_KEY_FILE" ]] && echo 7 || echo 5)
    local ids; ids=$(gcloud iam service-accounts keys list --iam-account="$acct" --managed-by=user --format='value(name.basename())' 2>/dev/null)
    n=$(grep -c . <<<"$ids")
    if [[ "${n:-0}" -gt 0 ]]; then
      say "    $(basename "$f") is no longer in Cloud Shell, and $acct has $n key(s). If Abstract already has it, nothing to do."
      # Google keeps only the public half of a key, so a file lost before the upload cannot be
      # downloaded again. The way on is a new key, then deleting the one nobody holds.
      say "    Lost it before Abstract had it? Make a new one: $0 --step $step (answer y to a new key)."
      say "    Then delete the lost one, once the new key is in Abstract:"
      local id; for id in $ids; do say "      gcloud iam service-accounts keys delete $id --iam-account=$acct"; done
    else
      warn "no key for $acct, here or in Google Cloud. Step $step makes one: run it again."
    fi
  done
  why "If someone else fills in the Abstract form, hand the key over through your password manager or"
  why "secret-sharing tool, never by email or chat. Anyone holding it can read the subscription."
  say ""
  say "  ${B}Download your answers too.${O} The clean-up needs them to know what this setup made:"
  say "    cloudshell download $STATE"
  say ""
  say "  ${B}Once Abstract has saved the integration, delete every copy of the keys:${O}"
  say "    rm -f$(printf ' %q' "${keys[@]}")"
  say "    and delete the downloaded copies from your computer."
  say ""
  say "  Re-check everything any time:  $0 --check"
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
  else printf '  %swould remove%s %s\n%s   $' "$Y" "$O" "$what" "$D"; printf ' %q' "$@"; printf '%s\n' "$O"; fi
}
kept()   { printf '  %skept%s    %s\n' "$G" "$O" "$*"; }
byhand() { printf '  %sby hand%s %s\n' "$Y" "$O" "$*"; WARNS=$((WARNS+1)); }
api_names() {  # api_names <url> <collection> <display-name prefix>: names of matching monitoring objects
  curl -s -H "Authorization: Bearer $(token)" "$1" | python3 -c '
import json, sys
for o in json.load(sys.stdin).get(sys.argv[1], []):
    if o.get("displayName", "").startswith(sys.argv[2]): print(o["name"])' "$2" "$3" 2>/dev/null
}
# Deletes one Monitoring object by name. Defined as a function so a dry run prints its name, never
# the bearer token the request carries. 404 counts as done, so a retried clean-up can finish.
mon_delete() {
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE -H "Authorization: Bearer $(token)" \
    "https://monitoring.googleapis.com/v3/$1${2:+?$2}")
  [[ "$code" == 200 || "$code" == 404 ]]
}
alert_policy_names() { api_names "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/alertPolicies?pageSize=200" alertPolicies "Abstract log pipeline"; }
alert_channel_names() { api_names "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/notificationChannels?pageSize=200" notificationChannels "Abstract log pipeline"; }
found() { byhand "found, not recorded: $1. Check it is Abstract's, then: $2"; }
# look <what> <how to remove> <describe command...>: found, absent, or COULD NOT CHECK. A denied or
# failed lookup is never read as absent; that false zero once listed nothing beside a live topic.
look() {
  local what="$1" how="$2" out; shift 2
  if out=$("$@" 2>&1); then found "$what" "$how"
  # Absent only when the error says so and nothing in it says access was refused: Google answers
  # "does not exist or you do not have access" for both, and that is not proof of absence.
  elif grep -qiE 'NOT_FOUND|Resource not found' <<<"$out" \
       && ! grep -qiE 'PERMISSION_DENIED|denied|not authori[sz]ed|do not have access|forbidden' <<<"$out"; then :
  else bad "could not check $what: ${out%%$'\n'*}"; fi
}
# mon_list <collection> <what>: sets MON_NAMES to the Monitoring objects named "Abstract log pipeline…",
# or reports a failure. Not called through $(…): a bad() inside a subshell is never counted.
MON_NAMES=""
mon_list() {
  local body code; body=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $(token)" \
    "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/$1?pageSize=200"); code=${body##*$'\n'}
  if [[ "$code" != 200 ]]; then bad "could not list $2 in $LOG_PROJECT (HTTP $code)"; MON_NAMES=""; return 1; fi
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
      gcloud iam service-accounts describe "$a@$LOG_PROJECT.iam.gserviceaccount.com" --project="$LOG_PROJECT"; done
  local n probes
  if probes=$(gcloud pubsub subscriptions list --project="$LOG_PROJECT" --filter='name:abstract-probe-' --format='value(name.basename())' 2>&1); then
    for n in $probes; do found "probe subscription $n" "gcloud pubsub subscriptions delete $n --project=$LOG_PROJECT"; done
  else bad "could not list probe subscriptions in $LOG_PROJECT: ${probes%%$'\n'*}"; fi
  if mon_list alertPolicies "alert policies"; then
    for n in $MON_NAMES; do found "alert policy $n" "delete it under Monitoring > Alerting in the console"; done; fi
  if mon_list notificationChannels "notification channels"; then
    for n in $MON_NAMES; do found "alert channel $n" "delete it under Monitoring > Alerting > Edit notification channels"; done; fi
  byhand "the log sink lives on your organization, folder or project, not here. Find it with: gcloud logging sinks list --organization=<org-id> --filter='destination:$TOPIC' (or --folder / --project)"
  kept "logging project $LOG_PROJECT: this script never deletes it."
}

remove_all() {
  title "x" "Clean up"
  why "Removes only what this setup created. Nothing is deleted without --confirm."
  why "Delete the integration in Abstract first, so it stops reading the subscription."
  if [[ -z "$LOG_PROJECT" ]]; then
    [[ -n "$FIND_PROJECT" ]] && { discover_all; return; }
    bad "No saved answers in $STATE, so this session cannot tell what the setup made. Cloud Shell sessions opened from the templates button are temporary. Load the answers file you downloaded with --state <file>, or run again with --project <logging-project-id> to list what carries the setup's names."
    return
  fi
  local sf; sf=$(scope_flag)
  if (( ${SINK_CREATED_AT:-0} > 0 )); then
    # shellcheck disable=SC2086
    gone "log sink $SINK at the $SCOPE $SCOPE_ID" gcloud logging sinks delete "$SINK" $sf --quiet
  else kept "log sink $SINK: it existed before this setup. Its filter may have been extended; review it."; fi
  local p; for p in $(gcloud pubsub subscriptions list --project="$LOG_PROJECT" --filter='name:abstract-probe-' --format='value(name.basename())' 2>/dev/null); do
    gone "probe subscription $p" gcloud pubsub subscriptions delete "$p" --project="$LOG_PROJECT" --quiet; done
  if [[ "${SUB_CREATED:-0}" == 1 ]]; then gone "subscription $SUB" gcloud pubsub subscriptions delete "$SUB" --project="$LOG_PROJECT" --quiet
  else byhand "subscription $SUB was not recorded as created here. If it is Abstract's: gcloud pubsub subscriptions delete $SUB --project=$LOG_PROJECT"; fi
  if [[ "${TOPIC_CREATED:-0}" == 1 ]]; then gone "topic $TOPIC" gcloud pubsub topics delete "$TOPIC" --project="$LOG_PROJECT" --quiet
  else byhand "topic $TOPIC was not recorded as created here. If it is Abstract's: gcloud pubsub topics delete $TOPIC --project=$LOG_PROJECT"; fi
  if [[ "${SA_CREATED:-0}" == 1 ]]; then gone "service account $SA (and its keys)" gcloud iam service-accounts delete "$SA@$LOG_PROJECT.iam.gserviceaccount.com" --project="$LOG_PROJECT" --quiet
  else byhand "service account $SA was not recorded as created here. If it is Abstract's: gcloud iam service-accounts delete $SA@$LOG_PROJECT.iam.gserviceaccount.com"; fi
  if [[ "${WS_SA_CREATED:-0}" == 1 ]]; then
    gone "Workspace service account $WS_SA (and its keys)" gcloud iam service-accounts delete "$WS_SA@$LOG_PROJECT.iam.gserviceaccount.com" --project="$LOG_PROJECT" --quiet
    byhand "a Workspace super admin removes its entry under admin.google.com > Security > API controls > Domain-wide delegation"
  fi
  local n; for n in $ALERT_POLICIES; do gone "alert policy $n" mon_delete "$n"; done
  for n in $ALERT_CHANNELS; do gone "alert email channel $n" mon_delete "$n" force=true; done
  for n in $(alert_policy_names) $(alert_channel_names); do
    [[ " $ALERT_POLICIES $ALERT_CHANNELS " == *" $n "* ]] || kept "alert $n: not made by this setup (Terraform, or another setup)"; done
  local f; for f in "$KEY_FILE" "$WS_KEY_FILE"; do [[ -f "$f" ]] && gone "key file $f" rm -f "$f"; done
  [[ "$DATA_ACCESS" == yes ]] && byhand "Data Access audit settings were changed in step 6. A copy of the earlier settings was saved as abstract-audit-config-backup-*.json where step 6 ran. Restore it with get-iam-policy, edit, then set-iam-policy, keeping the etag."
  kept "logging project $LOG_PROJECT: this script never deletes it. If you created it only for Abstract: gcloud projects delete $LOG_PROJECT"
  if $CONFIRM && (( FAILS == 0 )); then mv "$STATE" "$STATE.removed-$(date +%Y%m%d%H%M%S)"; say "  saved answers moved aside; running --remove again lists nothing"
  elif ! $CONFIRM; then say ""; say "  Nothing was removed. Run again with --remove --confirm to remove the items marked 'would remove'."; fi
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
  --state) STATE="$2"; shift 2; [[ -f "$STATE" ]] && source "$STATE" ;;
  --project) FIND_PROJECT="$2"; shift 2 ;;
  --reset) RESET=true; shift ;;
  -h|--help) sed -n '2,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option $1 (try --help)"; exit 2 ;; esac; done

need gcloud; need python3; need curl
$RESET && start_over
if $REMOVE; then python3 "$HERE/brand.py" header "Google Cloud setup" "clean-up"; remove_all
elif $CONFIRM; then echo "--confirm only goes with --remove"; exit 2
else launch; if [[ -n "$ONLY_STEP" ]]; then "step$ONLY_STEP"; else for s in 1 2 3 4 5 6 7 8 9 10; do "step$s"; done; fi; fi
printf '\n%s%d passed%s · %s%d to look at%s · %s%d to fix%s\n' "$G" "$PASSES" "$O" "$Y" "$WARNS" "$O" "$R" "$FAILS" "$O"
[[ $FAILS -eq 0 ]]
