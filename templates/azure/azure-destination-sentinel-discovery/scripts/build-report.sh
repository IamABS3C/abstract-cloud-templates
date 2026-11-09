#!/bin/bash
# Bootstrap for the report deployment script (kind AzureCLI, which has Python 3). Runs as the same managed identity:
#   1. unpacks the report bundle from REPORT_BUNDLE_B64 after checking its SHA-256 (nothing is downloaded);
#   2. downloads inventory.zip that the inventory script wrote to the customer's storage account;
#   3. builds report.html with build_html_report.py. Its only outbound call is the anonymous Azure Retail Prices API
#      (prices.azure.com), which receives the region name and nothing from the tenant;
#   4. uploads report.html, prices.json and this log next to the inventory;
#   5. only when SEND_TO_ABSTRACT is true: PUTs inventory.zip and report.html to the SAS URL Abstract gave you.
set -euo pipefail
W=$(mktemp -d)
LOG="$W/report.log"
exec > >(tee -a "$LOG") 2>&1
put_blob() { az storage blob upload --auth-mode login --only-show-errors --overwrite --account-name "$STORAGE_ACCOUNT" -c "$CONTAINER" -n "$RUN_PREFIX/$2" -f "$1" --content-type "$3" -o none; }
finish() { code=$?; put_blob "$LOG" report.log text/plain || echo "could not upload report.log"; exit $code; }
trap finish EXIT

echo "Report for $RUN_PREFIX in $STORAGE_ACCOUNT/$CONTAINER"
echo "$REPORT_BUNDLE_B64" | base64 -d > "$W/report.tgz"
SHA=$(sha256sum "$W/report.tgz" | cut -d' ' -f1)
[ "$SHA" = "$REPORT_BUNDLE_SHA256" ] || { echo "Report bundle SHA-256 $SHA does not match the template's $REPORT_BUNDLE_SHA256"; exit 1; }
# This container has no tar binary (measured).
mkdir -p "$W/report" && python3 -I -c 'import sys,tarfile; tarfile.open(sys.argv[1]).extractall(sys.argv[2], filter="data")' "$W/report.tgz" "$W/report"
echo "Report bundle verified (sha256 $SHA)."

az storage blob download --auth-mode login --only-show-errors --account-name "$STORAGE_ACCOUNT" -c "$CONTAINER" -n "$RUN_PREFIX/inventory.zip" -f "$W/inventory.zip" -o none
python3 -I "$W/report/build_html_report.py" "$W/inventory.zip" --out "$W/report.html" --prices-json "$W/prices.json" --logo "$W/report/abstract-logo-black.svg" | tee "$W/result.json"
put_blob "$W/report.html" report.html "text/html; charset=utf-8"
put_blob "$W/prices.json" prices.json application/json
echo "Uploaded report.html and prices.json."

SENT=false
if [ "${SEND_TO_ABSTRACT:-false}" = "true" ]; then
  [ -n "${ABSTRACT_SAS_URL:-}" ] || { echo "sendToAbstract is true but no SAS URL was given"; exit 1; }
  case "$ABSTRACT_SAS_URL" in https://*\?*) ;; *) echo "The Abstract SAS URL must be an https container URL with a SAS query string"; exit 1;; esac
  BASE="${ABSTRACT_SAS_URL%%\?*}"; QUERY="${ABSTRACT_SAS_URL#*\?}"
  HOST=$(echo "$BASE" | cut -d/ -f3)
  NAME="$(echo "$RUN_PREFIX" | tr '/' '_')"
  for f in inventory.zip report.html; do
    src="$W/$f"; [ "$f" = inventory.zip ] && src="$W/inventory.zip"
    curl -sS --fail --max-time 300 -X PUT -H "x-ms-blob-type: BlockBlob" -H "x-ms-version: 2021-08-06" --data-binary "@$src" "$BASE/${NAME}_$f?$QUERY" -o /dev/null
    echo "Sent $f to $HOST (SAS token not logged)."
  done
  SENT=true
fi

python3 -I - "$W/result.json" "$SENT" "$STORAGE_ACCOUNT" "$CONTAINER" "$RUN_PREFIX" "$STORAGE_SUFFIX" > "$AZ_SCRIPTS_OUTPUT_PATH" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
acct, cont, pre, suffix = sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
print(json.dumps({'reportUrl': f'https://{acct}.blob.{suffix}/{cont}/{pre}/report.html', 'sentToAbstract': sys.argv[2] == 'true',
                  'pricesLive': r['prices_live'], 'region': r['region'], 'tables': r['tables'], 'billableGbPerDay': str(r['billable_gb_day']),
                  'listCostPerMonthNow': str(r['now_month'])}))  # ARM's string() refuses a float, so floats leave here as text
EOF
echo "Done."
