# shellcheck shell=bash disable=SC2034  # GID_LINE is set here and read by the scripts that source this file
# Who gcloud's token acts as, and why that may not be the configured account. Sourced by
# abstract-gcp-setup.sh, audit-gcp-estate.sh and preflight.sh, so all three decide it alike. bash 3.2.
#
# A configured account is not proof of who the token is (measured 2026-10-11: gcloud listed one account while
# its stored sign-in belonged to another that could see nothing). Two settings make the token someone else's
# ON PURPOSE, and `gcloud auth login` changes neither, so each is named instead of prescribing a sign-in:
#   auth/impersonate_service_account  (CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT)  every token is that service
#                                     account's; a comma-separated delegation chain acts as its LAST account
#   auth/access_token_file            (CLOUDSDK_AUTH_ACCESS_TOKEN_FILE)  gcloud uses the token in that file

# gid_setting <property> <environment variable>: "value<TAB>where it is set", or nothing when unset. The
# variable is read first, so the message can name the thing the person actually set.
gid_setting() {
  local v="${!2:-}"
  if [[ -n "$v" ]]; then printf '%s\t%s' "$v" "$2"; return 0; fi
  v=$(gcloud config get-value "$1" 2>/dev/null | grep -v '^(unset)$' | head -n1)
  [[ -n "$v" ]] && printf '%s\t%s' "$v" "$1"
  return 0
}

# gid_clear <property or variable>: the command that clears it.
gid_clear() { case "$1" in CLOUDSDK_*) printf 'unset %s' "$1" ;; *) printf 'gcloud config unset %s' "$1" ;; esac; }

# gid_token_email <token>: the account Google says the token acts as (tokeninfo); empty when it cannot be asked.
gid_token_email() {
  [[ -n "${1:-}" ]] || return 0
  curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=$1" 2>/dev/null | python3 -c '
import json, sys
try: print(json.load(sys.stdin).get("email", ""))
except Exception: print("")' 2>/dev/null
}

# gid_check <configured account> <token email>: 0 when the token may be used, with GID_LINE saying who acts
# ("signed in as A", or "acting as SA (impersonated by A)"); 1 when not, with GID_LINE saying why and what
# clears it. An empty token email (Google could not be asked) never blocks.
gid_check() {
  local acct="$1" who="$2" imp sa tf src
  GID_LINE="signed in as $acct"
  [[ -z "$who" || "$who" == "$acct" ]] && return 0
  imp=$(gid_setting auth/impersonate_service_account CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT)
  sa="${imp%%$'\t'*}"; sa="${sa##*,}"
  if [[ -n "$imp" && "$who" == "$sa" ]]; then GID_LINE="acting as $sa (impersonated by $acct)"; return 0; fi
  tf=$(gid_setting auth/access_token_file CLOUDSDK_AUTH_ACCESS_TOKEN_FILE)
  if [[ -n "$tf" ]]; then
    src="${tf##*$'\t'}"
    GID_LINE="gcloud is set to $acct, but the access token in $src (${tf%%$'\t'*}) decides who it acts as, and that token acts as $who. Signing in again does not change it: point $src at a token for $acct, or clear it: $(gid_clear "$src")"
  elif [[ -n "$imp" ]]; then
    src="${imp##*$'\t'}"
    GID_LINE="gcloud impersonates $sa ($src is set), but its token acts as $who. Signing in again does not change it: correct that setting, or clear it: $(gid_clear "$src")"
  else
    GID_LINE="gcloud is set to $acct, but its stored sign-in acts as $who. Sign in again as $acct: gcloud auth login $acct"
  fi
  return 1
}
