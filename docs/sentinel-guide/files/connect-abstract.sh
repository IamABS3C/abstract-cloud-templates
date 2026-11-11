#!/usr/bin/env bash
# Create or update the Abstract "Azure Sentinel Destination" from this solution's deployment outputs, so no endpoint,
# rule id or tenant id is copied by hand.
#
#   connect-abstract.sh --resource-group RG --deployment NAME --name "Destination name" --vendor-account ID \
#       [--api https://api.abstractsecurity.app] [--client-id GUID] \
#       [--client-secret-uri KEY_VAULT_SECRET_URI | env AZURE_CLIENT_SECRET] \
#       [--api-key-uri KEY_VAULT_SECRET_URI | env ABSTRACT_API_KEY] \
#       [--integration-id default.azure_sentinel_destination.0_1_1 | latest] [--inactive] [--dry-run]
#
# --deployment is the name the solution was deployed under (deploy.sh uses azure-destination-sentinel-solution).
# --vendor-account is your Abstract instance id, sent as the X-AS-Vendor-Account-ID header.
# --client-id is the application (client) id of the Entra app Abstract signs in as. Left out, it is looked up from the
#   deployment's principalId with `az ad sp show`.
# --integration-id: the default is pinned so a run is repeatable. "latest" asks GET /v2/integrations/versions/ for the
#   version marked is_latest.
# --inactive creates the destination switched off (an instance has a cap on active configurations); an update keeps
#   whatever state the destination is already in.
# --dry-run prints the plan (create or update, every parameter that is not a secret) and sends nothing that writes. It
#   does not read the Entra client secret (the plan shows "(will be read)"); it still needs the Abstract API key, because
#   the plan looks the destination up by name.
# --api must be https.
# An existing destination with the same --name is updated in place; otherwise one is created. Run it twice: still one.
# The existing one must be an Azure Sentinel Destination (integration default.azure_sentinel_destination.*), and the name
# must match exactly one configuration across every page of results; otherwise nothing is written.
# Secrets are held in shell variables and sent through a private temp file (mode 600, removed on exit), never on a
# command line. Nothing here prints them.
set -euo pipefail
umask 077

usage() { sed -n '2,27p' "$0" >&2; exit 2; }
die() { echo "error: $*" >&2; exit 1; }
KIND_PREFIX="default.azure_sentinel_destination"

rg=""; dep=""; name=""; api="https://api.abstractsecurity.app"; vendor=""; client_id=""
secret_uri=""; apikey_uri=""; integration="default.azure_sentinel_destination.0_1_1"; dry=0; new_active="true"
while [ $# -gt 0 ]; do
  case "$1" in
    --resource-group) rg="${2:-}"; shift 2 || usage ;;
    --deployment) dep="${2:-}"; shift 2 || usage ;;
    --name) name="${2:-}"; shift 2 || usage ;;
    --api) api="${2:-}"; shift 2 || usage ;;
    --vendor-account) vendor="${2:-}"; shift 2 || usage ;;
    --client-id) client_id="${2:-}"; shift 2 || usage ;;
    --client-secret-uri) secret_uri="${2:-}"; shift 2 || usage ;;
    --api-key-uri) apikey_uri="${2:-}"; shift 2 || usage ;;
    --integration-id) integration="${2:-}"; shift 2 || usage ;;
    --inactive) new_active="false"; shift ;;
    --dry-run) dry=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done
missing=""
[ -n "$rg" ] || missing="$missing --resource-group"
[ -n "$dep" ] || missing="$missing --deployment"
[ -n "$name" ] || missing="$missing --name"
[ -n "$vendor" ] || missing="$missing --vendor-account"
if [ -n "$missing" ]; then echo "missing required:$missing" >&2; usage; fi
api="${api%/}"
case "$api" in
  https://?*) ;;
  *) die "--api must be an https:// address (got '$api'); the API key is sent with every call" ;;
esac
# Take the secrets that came in through the environment into variables, then drop them from the environment so no
# az or curl child inherits them.
env_client_secret="${AZURE_CLIENT_SECRET:-}"; env_api_key="${ABSTRACT_API_KEY:-}"
unset AZURE_CLIENT_SECRET ABSTRACT_API_KEY

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- 1. what was deployed -----------------------------------------------------------------------------------------
dj="$(az deployment group show -g "$rg" -n "$dep" \
  --query "{outputs: properties.outputs, principalId: properties.parameters.principalId.value}" -o json)" \
  || die "could not read deployment '$dep' in resource group '$rg'"
# Newer deployments carry one object, outputs.abstractDestination. Older ones carry the three separate outputs and no
# tenant id, so the tenant comes from the signed-in az account.
dest="$(printf '%s' "$dj" | python3 -c '
import json, sys
d = json.load(sys.stdin) or {}
o = d.get("outputs") or {}
def v(k):
    x = o.get(k)
    return x.get("value") if isinstance(x, dict) else None
a = v("abstractDestination") or {}
r = {
  "tenant_id": a.get("tenant_id") or "",
  "client_id": a.get("client_id") or "",
  "data_collection_endpoint": a.get("data_collection_endpoint") or v("dataCollectionEndpointUrl") or "",
  "data_collection_rule_id": a.get("data_collection_rule_id") or v("dataCollectionRuleImmutableId") or "",
  "log_stream_name": a.get("log_stream_name") or v("logStreamName") or "",
  "principal_id": d.get("principalId") or "",
}
json.dump(r, sys.stdout)')" || die "deployment outputs were not valid JSON"
field() { printf '%s' "$dest" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
tenant_id="$(field tenant_id)"; endpoint="$(field data_collection_endpoint)"
rule_id="$(field data_collection_rule_id)"; stream="$(field log_stream_name)"
[ -n "$client_id" ] || client_id="$(field client_id)"
[ -n "$tenant_id" ] || tenant_id="$(az account show --query tenantId -o tsv)" || die "could not read the tenant id"
if [ -z "$client_id" ]; then
  pid="$(field principal_id)"
  [ -n "$pid" ] || die "no --client-id given and the deployment has no principalId parameter to look it up from"
  client_id="$(az ad sp show --id "$pid" --query appId -o tsv)" || die "could not look up the app id of principal $pid"
fi
for k in tenant_id client_id endpoint rule_id stream; do
  [ -n "${!k}" ] || die "deployment '$dep' has no value for $k; deploy the solution first"
done

# --- 2. secrets (variables only) ----------------------------------------------------------------------------------
kv() { az keyvault secret show --id "$1" --query value -o tsv; }
# A dry run writes nothing, so it does not need the Entra secret and does not read it.
client_secret=""; secret_shown="(set, hidden)"
[ -n "$secret_uri" ] || [ -n "$env_client_secret" ] || die "no client secret: pass --client-secret-uri or set AZURE_CLIENT_SECRET"
if [ "$dry" -eq 1 ]; then secret_shown="(will be read)"
elif [ -n "$secret_uri" ]; then client_secret="$(kv "$secret_uri")" || die "could not read the client secret from Key Vault"
else client_secret="$env_client_secret"; fi
[ "$dry" -eq 1 ] || [ -n "$client_secret" ] || die "the client secret read from Key Vault is empty"
if [ -n "$apikey_uri" ]; then api_key="$(kv "$apikey_uri")" || die "could not read the Abstract API key from Key Vault"
else api_key="$env_api_key"; fi
[ -n "$api_key" ] || die "no Abstract API key: pass --api-key-uri or set ABSTRACT_API_KEY"
# Neither secret is exported: az and curl must not inherit them, so only the python helpers get them, per command.

# --- 3. HTTP helper: headers, secrets and form values go in a private config file, never argv ----------------------
# call METHOD PATH [form-fields-json]   sets $status and $body_file; fields is {"name":"value",...} sent as multipart
call() {
  local method="$1" path="$2" fields="${3:-}"
  AK="$api_key" VA="$vendor" M="$method" U="$api$path" F="$fields" python3 - >"$tmp/curl.cfg" <<'PY'
import json, os
def q(s): return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
print("url = " + q(os.environ["U"]))
print("request = " + q(os.environ["M"]))
print("header = " + q("Authorization: Bearer " + os.environ["AK"]))
print("header = " + q("X-AS-Vendor-Account-ID: " + os.environ["VA"]))
print("header = " + q("Accept: application/json"))
if os.environ.get("F"):
    for k, v in json.loads(os.environ["F"]).items():
        print("form-string = " + q(k + "=" + v))
PY
  status="$(curl -sS -K "$tmp/curl.cfg" -o "$tmp/body" -w '%{http_code}')" || die "$method $path: could not reach $api"
  rm -f "$tmp/curl.cfg"
  body_file="$tmp/body"
}
ok() { case "$status" in 2??) return 0 ;; *) return 1 ;; esac; }
fail() {  # fail "what" : prints status and the response with both secrets removed, in raw, JSON-escaped and URL forms
  local txt; txt="$(CS_SECRET="$client_secret" AK_SECRET="$api_key" python3 -c '
import json, os, sys, urllib.parse as u
t = open(sys.argv[1], errors="replace").read()
for k in ("CS_SECRET", "AK_SECRET"):
    v = os.environ.get(k)
    if v:
        j = json.dumps(v)[1:-1]   # also twice, for a parameters string echoed inside a JSON error body
        for f in sorted({v, j, json.dumps(j)[1:-1], u.quote(v, safe=""), u.quote_plus(v)}, key=len, reverse=True):
            t = t.replace(f, "***")
print(t[:600])' "$body_file")"
  die "$1 failed: HTTP $status $txt"
}
jget() { python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for p in sys.argv[2].split("."):
    d = d.get(p) if isinstance(d, dict) else None
print("" if d is None else (json.dumps(d) if isinstance(d, (dict, list, bool)) else d))' "$body_file" "$1"; }

# --- 4. integration version -----------------------------------------------------------------------------------------
if [ "$integration" = "latest" ]; then
  prefix="$KIND_PREFIX"
  call GET "/v2/integrations/versions/?prefixes=$prefix"
  ok || fail "looking up the latest integration version"
  integration="$(python3 -c '
import json, sys
for p in json.load(open(sys.argv[1])):
    for v in p.get("versions", []):
        if v.get("is_latest"): print(v["integration_id"]); raise SystemExit
' "$body_file")"
  [ -n "$integration" ] || die "the API reported no latest version for $prefix"
fi

# --- 5. existing destination with this name ---------------------------------------------------------------------------
# Every page is read and the exact-name matches are totalled, so a duplicate on a later page is still caught.
enc="$(python3 -c 'import sys, urllib.parse as u; print(u.quote(sys.argv[1], safe=""))' "$name")"
total=0; cid=""; cur_active="true"; cur_integration=""; page=1
while :; do
  call GET "/v2/configurations/?name=$enc&page_number=$page&page_size=100"
  ok || fail "listing configurations"
  hit="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1])); n = sys.argv[2]
items = d.get("items") or []
m = [i for i in items if i.get("name") == n]
more = bool(items) and d.get("page_number", 1) * d.get("page_size", 0) < d.get("total_count", 0)
print(json.dumps({"n": len(m), "id": m[0]["nanoid"] if m else "", "active": m[0].get("active", True) if m else True,
                  "integration": m[0].get("integration_id") or "" if m else "", "more": more}))' "$body_file" "$name")"
  n="$(printf '%s' "$hit" | python3 -c 'import json,sys; print(json.load(sys.stdin)["n"])')"
  total=$((total + n))
  [ "$total" -le 1 ] || die "$total configurations are already named '$name'; refusing to guess which to update"
  if [ "$n" -eq 1 ]; then
    cid="$(printf '%s' "$hit" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
    cur_active="$(printf '%s' "$hit" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["active"]).lower())')"
    cur_integration="$(printf '%s' "$hit" | python3 -c 'import json,sys; print(json.load(sys.stdin)["integration"])')"
  fi
  [ "$(printf '%s' "$hit" | python3 -c 'import json,sys; print(json.load(sys.stdin)["more"])')" = "True" ] || break
  page=$((page + 1))
done
# A name is not an identity: refuse to overwrite a configuration of another kind that happens to share it.
if [ -n "$cid" ]; then
  case "$cur_integration" in
    "$KIND_PREFIX".*) ;;
    *) die "configuration $cid is named '$name' but is not an Azure Sentinel Destination (integration '${cur_integration:-none}'); choose another --name" ;;
  esac
fi

action="create"; [ -z "$cid" ] || action="update"
echo "plan: $action destination '$name' on $api (vendor account $vendor)"
echo "  integration_id            $integration"
[ -n "$cid" ] || echo "  active                    $new_active"
[ -z "$cid" ] || echo "  existing configuration    $cid (active=$cur_active, integration $cur_integration)"
[ -z "$cid" ] || [ "$cur_integration" = "$integration" ] || \
  echo "  note: the existing destination runs $cur_integration; an update does not change the version (upgrade is a separate call)"
echo "  tenant_id                 $tenant_id"
echo "  client_id                 $client_id"
echo "  client_secret             $secret_shown"
echo "  data_collection_endpoint  $endpoint"
echo "  data_collection_rule_id   $rule_id"
echo "  log_stream_name           $stream"
if [ "$dry" -eq 1 ]; then echo "dry run: nothing was written"; exit 0; fi

# --- 6. write, then read back ------------------------------------------------------------------------------------------
params="$(TI="$tenant_id" CI="$client_id" CS="$client_secret" EP="$endpoint" RI="$rule_id" LS="$stream" python3 -c '
import json, os
e = os.environ
print(json.dumps({"tenant_id": e["TI"], "client_id": e["CI"], "client_secret": e["CS"],
  "data_collection_endpoint": e["EP"], "data_collection_rule_id": e["RI"], "log_stream_name": e["LS"]}))')"
fields() {  # fields MODE ACTIVE: a create sends name and integration_id too; a PATCH has neither
  P="$params" N="$name" I="$integration" MODE="$1" A="$2" python3 -c '
import json, os
e = os.environ
f = {"parameters": e["P"], "active": e["A"]}
if e["MODE"] == "create":
    f.update({"name": e["N"], "integration_id": e["I"], "store_raw_event": "false"})
print(json.dumps(f))'
}
if [ -z "$cid" ]; then
  call POST "/v2/configurations/" "$(fields create "$new_active")"
  ok || fail "creating the destination"
  cid="$(jget nanoid)"; [ -n "$cid" ] || die "created, but the response carried no configuration id"
  echo "created $cid (HTTP $status)"
else
  # PATCH always needs `active`; echo the current value. parameters carries the real secret, never the masked one.
  call PATCH "/v2/configurations/$cid" "$(fields update "$cur_active")"
  ok || fail "updating the destination"
  echo "updated $cid (HTTP $status)"
fi

call GET "/v2/configurations/$cid"
ok || fail "reading the destination back"
for k in tenant_id client_id data_collection_endpoint data_collection_rule_id log_stream_name; do
  want="$(printf '%s' "$params" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$k")"
  got="$(jget "parameters.$k")"
  [ "$got" = "$want" ] || die "read-back mismatch on $k: the platform holds '$got', expected '$want'"
done
echo "read back: verified the non-secret parameters (tenant_id, client_id, data_collection_endpoint, data_collection_rule_id, log_stream_name) match the deployment; client_secret is masked by the API, so it cannot be read back"
echo "configuration id: $cid"
