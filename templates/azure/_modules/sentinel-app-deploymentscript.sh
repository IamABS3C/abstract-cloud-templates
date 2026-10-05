#!/usr/bin/env bash
# =============================================================================
#  Abstract Security - Sentinel destination identity, hardened deploymentScript
#
#  Runs inside Microsoft.Resources/deploymentScripts (AzureCLI) as the
#  user-assigned provisioning identity. Tenant bootstrap grants the required
#  Microsoft Graph application permissions with admin consent.
#
#  Replaces the original 16-line inline script in
#  templates/destinations/sentinel-destination-with-app.bicep. Same job, but it
#  survives the three failure modes the inline version did not:
#
#    1. SECRET CHURN. The original called `az ad app credential reset --append`
#       on EVERY deployment. Re-run the template and you got a brand-new secret
#       and a new Key Vault version while the value already configured in
#       Abstract kept working - until someone assumed the newest version was
#       correct. Now: only mint a secret when the vault holds none with more than
#       30 days left.
#    2. SILENT PARTIAL SUCCESS. Every step was unguarded, so an app created
#       without a service principal still reported success and the DCR role
#       assignment failed later with an opaque PrincipalNotFound.
#    3. NO OUTPUT VERIFICATION. Nothing read back what it had created.
#
#  The app being created is Abstract's runtime identity. It receives DCR RBAC
#  (Monitoring Metrics Publisher, plus Monitoring Contributor only if the template
#  is told to) from the template;
#  it is distinct from the provisioning identity running this script.
#
#  Environment (set by the template):
#    APP_NAME       app display name - ALSO the idempotency key
#    KEY_VAULT_MODE Create, Existing, or None
#    KV_NAME        Key Vault that receives the secret (Create/Existing only)
#    VAULT_URI      vault URI, for the returned secret reference (optional)
#    SECRET_NAME    secret name in the vault
#    SECRET_YEARS   secret lifetime in years
#    FORCE_ROTATE   'true' to mint a new secret regardless of the existing one
# =============================================================================
set -euo pipefail

log()  { printf '==> %s\n' "$*"; }
ok()   { printf '    + %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*"; }
die()  { printf '    X %s\n' "$*" >&2; exit 1; }

: "${APP_NAME:?APP_NAME not set}"
: "${KEY_VAULT_MODE:=Create}"
: "${KV_NAME:=}"
: "${VAULT_URI:=}"
: "${SECRET_NAME:=abstract-sentinel-client-secret}"
: "${SECRET_YEARS:=1}"
: "${FORCE_ROTATE:=false}"

case "$KEY_VAULT_MODE" in
  Create|Existing|None) ;;
  *) die "KEY_VAULT_MODE must be Create, Existing, or None" ;;
esac

if [ "$KEY_VAULT_MODE" != "None" ] && { [ -z "$KV_NAME" ] || [ -z "$VAULT_URI" ]; }; then
  die "Key Vault name and URI are required when KEY_VAULT_MODE is $KEY_VAULT_MODE"
fi

TENANT_ID=$(az account show --query tenantId -o tsv) || die "cannot read tenant - is the script identity attached?"
ok "tenant $TENANT_ID"

# --- App registration -------------------------------------------------------
# The display name is the idempotency key, but a name proves nothing: any app in
# the tenant can carry it, and this identity can add credentials to any app. So
# an existing app is reused only when exactly one has the name and it carries the
# marker tag this template writes.
MARKER="abstract:sentinel-destination"
log "Ensuring app registration '$APP_NAME'"
# A Graph permission granted to the identity in the same deployment can take a few
# minutes to reach its tokens, so a refused list is retried before it is fatal.
MATCHES=""
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if MATCHES=$(az ad app list --filter "displayName eq '${APP_NAME}'" --query "[].{appId:appId, tags:tags}" -o json 2>/tmp/app-list.err); then
    break
  fi
  MATCHES=""
  [ "$attempt" -lt 10 ] && { warn "cannot list app registrations yet (attempt $attempt/10), retrying in 30s"; sleep 30; }
done
[ -n "$MATCHES" ] || die "cannot list app registrations - does the script identity hold Application.ReadWrite.All (or, for an app it owns, Application.ReadWrite.OwnedBy) with admin consent? $(head -c 300 /tmp/app-list.err)"
read -r MATCH_COUNT APP_ID MARKED <<<"$(printf '%s' "$MATCHES" | python3 -c "
import json, sys
apps = json.load(sys.stdin) or []
first = apps[0] if apps else {}
print(len(apps), first.get('appId') or '-', 'yes' if '$MARKER' in (first.get('tags') or []) else 'no')")"
if [ "$MATCH_COUNT" -gt 1 ]; then
  die "$MATCH_COUNT app registrations are named '$APP_NAME' - choose a unique appDisplayName"
elif [ "$MATCH_COUNT" -eq 1 ]; then
  if [ "$MARKED" != yes ]; then
    die "an app named '$APP_NAME' ($APP_ID) exists but was not created by this template, so it will not be reused or given a credential. Choose another appDisplayName, or, if an earlier version of this template created it, mark it: az rest --method PATCH --url \"https://graph.microsoft.com/v1.0/applications(appId='$APP_ID')\" --body '{\"tags\":[\"$MARKER\"]}'"
  fi
  ok "reusing existing app $APP_ID"
else
  APP_ID=$(az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv) \
    || die "app creation failed - does the script identity hold Application.ReadWrite.All with admin consent?"
  ok "created app $APP_ID"
  sleep 15   # directory replication before the tag and the SP create
  az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications(appId='${APP_ID}')" \
    --headers "Content-Type=application/json" --body "{\"tags\":[\"${MARKER}\"]}" -o none \
    || die "could not mark app $APP_ID as created by this template"
fi
[ -z "$APP_ID" ] && die "app id resolved empty"
APP_OBJ_ID=$(az ad app show --id "$APP_ID" --query id -o tsv) || die "cannot read app object id for $APP_ID"

# --- Service principal ----------------------------------------------------
# The DCR role assignments target the SP object id, so if this is skipped the
# template's own roleAssignments fail with PrincipalNotFound.
log "Ensuring service principal"
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)
if [ -z "$SP_ID" ] || [ "$SP_ID" = "None" ]; then
  SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv) || die "service principal creation failed"
  ok "created SP $SP_ID"
  # Longer wait here on purpose: the template assigns DCR RBAC to this object id
  # immediately afterwards, and RBAC on a freshly created SP is the classic
  # PrincipalNotFound race.
  sleep 30
else
  ok "reusing SP $SP_ID"
fi
[ -z "$SP_ID" ] && die "service principal id resolved empty"

# --- Secret: rotate only when necessary, or defer to the customer ----------
NEED_SECRET=false
SECRET_URI=""
if [ "$KEY_VAULT_MODE" = "None" ]; then
  warn "Key Vault skipped. No client secret will be generated or emitted."
  warn "After deployment, create a client secret for app $APP_ID in Entra and copy its value once into Abstract."
else
  log "Checking for a usable secret in $KV_NAME"
  NEED_SECRET=true
  # The existing secret is always read, even for a forced rotation, so a same-named
  # secret that belongs to another app is never overwritten.
  if true; then
    # Only a SecretNotFound answer means "absent". Any other failure (most often a
    # 403 while the Key Vault role assignment made moments ago propagates) is
    # retried, then fatal - treating it as absent would mint a secret that the
    # vault then refuses, leaving a live credential nobody captured.
    SHOW="{}" ; SHOW_ERR="" ; FOUND=false
    for attempt in 1 2 3 4 5 6; do
      if SHOW=$(az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET_NAME" \
                 --query '{expires:attributes.expires, appId:tags.appId}' -o json 2>/tmp/kv-show.err); then
        FOUND=true; break
      fi
      SHOW_ERR=$(cat /tmp/kv-show.err)
      if printf '%s' "$SHOW_ERR" | grep -q 'SecretNotFound'; then break; fi
      warn "Key Vault read failed (attempt $attempt/6), retrying in 20s"
      sleep 20
    done
    if [ "$FOUND" != true ] && ! printf '%s' "$SHOW_ERR" | grep -q 'SecretNotFound'; then
      die "cannot read $KV_NAME: ${SHOW_ERR:-unknown error} - is Key Vault Secrets Officer granted to the script identity, and does the vault use RBAC authorization?"
    fi
    if [ "$FOUND" = true ]; then
      # A vault secret is only a stored copy of a client secret. Reuse it only when
      # it was stored for this app and the app still holds a matching credential;
      # after an app is recreated, or in an existing vault another app also uses,
      # its expiry alone proves nothing.
      CREDS=$(az ad app credential list --id "$APP_ID" \
                --query "[?displayName=='${SECRET_NAME}'].endDateTime" -o json 2>/dev/null || echo '[]')
      VERDICT=$(python3 - "$SHOW" "$CREDS" "$APP_ID" <<'PY'
import datetime, json, re, sys
secret, creds, app_id = json.loads(sys.argv[1] or "{}"), json.loads(sys.argv[2] or "[]"), sys.argv[3]
now = datetime.datetime.now(datetime.timezone.utc)
def days_left(ts):
    if not ts or ts == "None":
        return -1
    ts = re.sub(r"(\.\d{6})\d+", r"\1", str(ts)).replace("Z", "+00:00")
    return (datetime.datetime.fromisoformat(ts) - now).days
if secret.get("appId") and secret["appId"] != app_id:
    print("other-app")
elif not secret.get("appId"):
    print("untagged")
elif days_left(secret.get("expires")) <= 30:
    print("expiring")
elif not any(days_left(c) > 30 for c in creds):
    print("no-credential")
else:
    print("reuse")
PY
)
      if [ "$FORCE_ROTATE" = "true" ] && [ "$VERDICT" != "other-app" ]; then
        [ "$VERDICT" = "untagged" ] && warn "the vault secret $SECRET_NAME has no appId tag - replacing it because forceSecretRotation is set"
        VERDICT=forced
      fi
      case "$VERDICT" in
        forced)        warn "forceSecretRotation - minting a new secret. Update Abstract with the new value." ;;
        untagged)      die "the vault secret $SECRET_NAME has no appId tag, so it may belong to something else - refusing to overwrite it. Choose a different secretName, or set forceSecretRotation if it is this app's secret." ;;
        reuse)         NEED_SECRET=false
                       ok "existing secret belongs to app $APP_ID and is valid for >30 days - NOT rotating (re-running this template is safe)" ;;
        other-app)     die "the vault secret $SECRET_NAME belongs to another app - refusing to overwrite it. Choose a different secretName or vault." ;;
        expiring)      warn "existing secret expires within 30 days - rotating" ;;
        no-credential) warn "app $APP_ID holds no matching credential for the vault secret (was the app recreated?) - minting a new one" ;;
        *)             die "could not evaluate the existing secret" ;;
      esac
    else
      ok "no existing secret in the vault"
    fi
  fi

  if [ "$NEED_SECRET" = true ]; then
    log "Generating a client secret (${SECRET_YEARS} year(s))"
    BEFORE=$(az ad app credential list --id "$APP_ID" --query "[].keyId" -o tsv 2>/dev/null | sort || true)
    SECRET=$(az ad app credential reset --id "$APP_ID" --append \
      --display-name "$SECRET_NAME" --years "$SECRET_YEARS" --query password -o tsv) \
      || die "secret generation failed"
    [ -z "$SECRET" ] && die "secret generation returned empty"
    END=$(python3 -c "
import datetime
print((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=365*int('$SECRET_YEARS'))).strftime('%Y-%m-%dT%H:%M:%SZ'))")
    STORED=false
    for attempt in 1 2 3; do
      # The value goes through a 0600 file, never the command line, so it cannot be read
      # from the process list.
      SECRET_FILE=$(mktemp); chmod 600 "$SECRET_FILE"; printf '%s' "$SECRET" > "$SECRET_FILE"
      if az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME" \
           --file "$SECRET_FILE" --encoding utf-8 --expires "$END" --tags appId="$APP_ID" -o none; then
        rm -f "$SECRET_FILE"
        STORED=true; break
      fi
      rm -f "$SECRET_FILE"
      warn "Key Vault write failed (attempt $attempt/3), retrying in 20s"
      sleep 20
    done
    unset SECRET
    if [ "$STORED" != true ]; then
      # Never leave a live credential that exists nowhere but in Entra - but delete
      # only a key that is provably the new one. The credential list can lag, and
      # deleting an older key would revoke the secret Abstract is already using.
      NEW_KEYS=""
      for attempt in 1 2 3; do
        AFTER=$(az ad app credential list --id "$APP_ID" --query "[].keyId" -o tsv 2>/dev/null | sort || true)
        NEW_KEYS=$(comm -13 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | sed '/^$/d')
        [ -n "$NEW_KEYS" ] && break
        sleep 10
      done
      if [ "$(printf '%s\n' "$NEW_KEYS" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ]; then
        az ad app credential delete --id "$APP_ID" --key-id "$NEW_KEYS" \
          && warn "removed the unstored credential $NEW_KEYS" \
          || warn "could not remove credential $NEW_KEYS - delete it in Entra (app $APP_ID)"
      else
        warn "could not identify the new credential unambiguously - delete the newest '$SECRET_NAME' credential on app $APP_ID in Entra"
      fi
      die "could not write the secret to $KV_NAME - is Key Vault Secrets Officer granted to the script identity?"
    fi
    ok "secret stored at ${KV_NAME}/${SECRET_NAME}, expires ${END}"
    ok "never emitted to deployment outputs or logs"
  fi
  SECRET_URI="${VAULT_URI%/}/secrets/${SECRET_NAME}"
fi

# --- Verify what we actually created -------------------------------------
log "Verifying"
az ad app show --id "$APP_ID" --query displayName -o tsv >/dev/null || die "app not readable after creation"
az ad sp show --id "$APP_ID" --query id -o tsv >/dev/null || die "service principal not readable after creation"
if [ "$KEY_VAULT_MODE" != "None" ]; then
  az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET_NAME" --query id -o tsv >/dev/null \
    || die "secret not present in $KV_NAME after creation"
  ok "app, service principal and Key Vault secret all verified"
else
  ok "app and service principal verified; no secret was generated"
fi

cat > "$AZ_SCRIPTS_OUTPUT_PATH" <<JSON
{
  "appId": "${APP_ID}",
  "appObjectId": "${APP_OBJ_ID}",
  "spObjectId": "${SP_ID}",
  "tenantId": "${TENANT_ID}",
  "keyVaultSecretUri": "${SECRET_URI}",
  "secretRotated": ${NEED_SECRET},
  "keyVaultMode": "${KEY_VAULT_MODE}",
  "verified": true
}
JSON
ok "done"
