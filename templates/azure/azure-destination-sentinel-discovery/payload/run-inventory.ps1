# Bootstrap for the inventory deployment script (kind AzurePowerShell). Runs inside Azure's deployment-script container as
# the user-assigned managed identity the template creates. It:
#   1. unpacks the kit bundle from KIT_BUNDLE_B64 after checking its SHA-256 (nothing is downloaded);
#   2. puts az-shim.ps1 on PATH as `az`, because this container has no Azure CLI and the kit reads through `az rest`;
#   3. waits until every role the template assigned is in effect (role assignments take minutes to apply), and fails
#      the deployment if they are not, rather than letting the kit record 403s and produce an inventory that looks complete;
#   4. runs Get-SentinelInventory.ps1 unchanged, with -SkipEntra (the identity cannot hold Entra Global Reader);
#   5. uploads the zip, every CSV, summary.json and this transcript to the customer's storage account.
# The only writes it makes are blobs in that storage account.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$stamp = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$work = Join-Path ([IO.Path]::GetTempPath()) "sentinel-discovery-$stamp"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$transcript = Join-Path $work 'inventory.log'
Start-Transcript -Path $transcript | Out-Null

$sub = $env:WS_SUBSCRIPTION_ID; $rg = $env:WS_RESOURCE_GROUP; $wsName = $env:WS_NAME
$prefix = "runs/$($wsName)/$stamp"
$wsPath = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$wsName"
# The template passes the deployment cloud's endpoints: ARM_ENDPOINT ends in "/", which the token resource keeps and a path does not.
$armResource = $env:ARM_ENDPOINT
$arm = $armResource.TrimEnd('/')
Write-Output "Sentinel discovery: workspace $wsPath"
Write-Output "Output: https://$($env:STORAGE_ACCOUNT).blob.$($env:STORAGE_SUFFIX)/$($env:CONTAINER)/$prefix/"

function Get-PlainToken([string]$Resource) {
    $t = Get-AzAccessToken -ResourceUrl $Resource
    if ($t.Token -is [securestring]) { return [System.Net.NetworkCredential]::new('', $t.Token).Password }
    return [string]$t.Token
}

$ctx = Get-AzContext
$storage = New-AzStorageContext -StorageAccountName $env:STORAGE_ACCOUNT -UseConnectedAccount
function Send-Blob([string]$File, [string]$Name, [string]$Type = 'application/octet-stream') {
    Set-AzStorageBlobContent -File $File -Container $env:CONTAINER -Blob "$prefix/$Name" -Context $storage -Properties @{ ContentType = $Type } -Force | Out-Null
}

$uploaded = $false
try {
    # 1. unpack the kit
    $bundle = [Convert]::FromBase64String($env:KIT_BUNDLE_B64)
    $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bundle)).Replace('-', '').ToLowerInvariant()
    if ($sha -ne $env:KIT_BUNDLE_SHA256) { throw "Kit bundle SHA-256 $sha does not match the template's $($env:KIT_BUNDLE_SHA256)." }
    $kitDir = Join-Path $work 'kit'
    New-Item -ItemType Directory -Path $kitDir -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $work 'kit.tgz'), $bundle)
    tar -xzf (Join-Path $work 'kit.tgz') -C $kitDir
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the kit bundle.' }
    chmod 0755 (Join-Path $kitDir 'az')
    Write-Output "Kit bundle verified (sha256 $sha)."

    # 2. az shim
    $env:PATH = "$kitDir$([IO.Path]::PathSeparator)$($env:PATH)"
    $env:SENTINV_SHIM_SUBSCRIPTION = $sub
    $env:SENTINV_SHIM_TENANT = $ctx.Tenant.Id
    $env:SENTINV_SHIM_CLIENT_ID = $ctx.Account.Id
    $env:SENTINV_TOKEN_ARM = Get-PlainToken $armResource
    $env:SENTINV_TOKEN_LA = Get-PlainToken 'https://api.loganalytics.io'

    # 3. wait for the role assignments
    $armH = @{ Authorization = "Bearer $($env:SENTINV_TOKEN_ARM)" }
    $laH = @{ Authorization = "Bearer $($env:SENTINV_TOKEN_LA)" }
    $deadline = [datetime]::UtcNow.AddMinutes([int]$env:RBAC_WAIT_MINUTES)
    $probeFile = Join-Path $work 'probe.txt'
    Set-Content -Path $probeFile -Value "role check $stamp"
    $round = 0; $clean = 0
    while ($true) {
        $round++
        $fail = [System.Collections.Generic.List[string]]::new()
        $customerId = $null
        # Only 401/403 mean "not in effect yet". A 404 on the workspace is a wrong name; anything else (for example a workspace
        # without Sentinel) is left for the kit to record, so it cannot hold the deployment until the deadline.
        $denied = { param($c) $c -eq 401 -or $c -eq 403 }
        $r = Invoke-WebRequest -Uri "$arm$($wsPath)?api-version=2025-07-01" -Headers $armH -SkipHttpErrorCheck
        if ($r.StatusCode -eq 404) { throw "Workspace not found: $wsPath" }
        if ($r.StatusCode -eq 200) { $customerId = ($r.Content | ConvertFrom-Json).properties.customerId } elseif (& $denied $r.StatusCode) { $fail.Add("workspace GET $($r.StatusCode) (Reader / Log Analytics Reader)") }
        $r = Invoke-WebRequest -Uri "$arm$($wsPath)/providers/Microsoft.SecurityInsights/alertRules?api-version=2025-07-01-preview" -Headers $armH -SkipHttpErrorCheck
        if (& $denied $r.StatusCode) { $fail.Add("Sentinel alertRules $($r.StatusCode) (Microsoft Sentinel Reader)") }
        if ($customerId) {
            # Measured: right after assignment, some table queries get 403 while others succeed, and "print" needs no table at all.
            # So read real tables, several times a round. A table the workspace lacks answers 400, which is not a refusal.
            foreach ($q in @('Usage | take 1', 'Operation | take 1', 'Heartbeat | take 1', 'Usage | take 1', 'Operation | take 1', 'Heartbeat | take 1')) {
                $qb = @{ query = $q; timespan = 'P1D' } | ConvertTo-Json -Compress
                $r = Invoke-WebRequest -Method POST -Uri "https://api.loganalytics.io/v1/workspaces/$customerId/query" -Headers $laH -ContentType 'application/json' -Body $qb -SkipHttpErrorCheck
                if (& $denied $r.StatusCode) { $fail.Add("Log Analytics query '$q' $($r.StatusCode) (Log Analytics Reader)"); break }
            }
        }
        $body = @{ subscriptions = @($sub); query = "resources | where id =~ '$wsPath' | project id" } | ConvertTo-Json -Compress
        $r = Invoke-WebRequest -Method POST -Uri "$arm/providers/Microsoft.ResourceGraph/resources?api-version=2024-04-01" -Headers $armH -ContentType 'application/json' -Body $body -SkipHttpErrorCheck
        if ((& $denied $r.StatusCode) -or ($r.StatusCode -eq 200 -and (($r.Content | ConvertFrom-Json).count -lt 1))) { $fail.Add("Resource Graph $($r.StatusCode), workspace not visible (Reader on the subscription)") }
        try { Send-Blob $probeFile '.role-check.txt' 'text/plain' } catch { $fail.Add("storage write (Storage Blob Data Contributor): $($_.Exception.Message)") }
        if ($fail.Count -eq 0) {
            $clean++
            if ($clean -ge 3) {
                Remove-AzStorageBlob -Container $env:CONTAINER -Blob "$prefix/.role-check.txt" -Context $storage -Force -ErrorAction SilentlyContinue
                Write-Output "Roles in effect: $clean clean rounds in a row, after $round round(s)."; break
            }
            Start-Sleep -Seconds 30; continue
        }
        $clean = 0
        if ([datetime]::UtcNow -gt $deadline) { throw "Roles not in effect after $($env:RBAC_WAIT_MINUTES) minutes: $($fail -join '; '). Not running the kit, so no partial inventory is produced." }
        Write-Output ("Waiting for role assignments (check {0}): {1}" -f $round, ($fail -join '; '))
        Start-Sleep -Seconds 20
    }

    # 4. run the kit unchanged, in its own process (it exits on preflight failure). If any read was still refused, run it once more.
    $forbidden = 0
    foreach ($attempt in 1..2) {
        $out = Join-Path $work "sentinel-inventory-$($wsName)-$stamp-$attempt"
        $kitArgs = @('-NoProfile', '-File', (Join-Path $kitDir 'Get-SentinelInventory.ps1'), '-SubscriptionId', $sub, '-ResourceGroup', $rg, '-WorkspaceName', $wsName,
                     '-OutDir', $out, '-SkipEntra', '-Days', $env:DAYS, '-DeviceDays', $env:DEVICE_DAYS, '-ProfileTopTables', $env:PROFILE_TOP_TABLES)
        if ($env:SKIP_RULE_TEXT -eq 'true') { $kitArgs += '-SkipRuleQueryText' }
        if ($env:SKIP_CONTENT_TEXT -eq 'true') { $kitArgs += '-SkipContentQueryText' }
        $ErrorActionPreference = 'Continue'   # the kit reports through its own files; a stderr line must not end this script
        & pwsh @kitArgs 2>&1 | ForEach-Object { Write-Output "$_" }
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($code -ne 0 -or -not (Test-Path "$out.zip")) { throw "The inventory kit exited with $code." }
        $forbidden = @(Import-Csv (Join-Path $out 'read_errors.csv') | Where-Object { $_.FailureClass -in @('403', 'auth') }).Count
        if ($forbidden -eq 0 -or $attempt -eq 2) { break }
        Write-Output "Run $attempt had $forbidden refused read(s). Waiting 3 minutes, then running the kit once more."
        Start-Sleep -Seconds 180
    }

    # 5. upload
    Send-Blob "$out.zip" 'inventory.zip' 'application/zip'
    foreach ($f in Get-ChildItem -Path $out -File) {
        $type = if ($f.Extension -eq '.json') { 'application/json' } else { 'text/csv' }
        $name = if ($f.Name -in @('summary.json', 'read_errors.csv')) { $f.Name } else { "csv/$($f.Name)" }
        Send-Blob $f.FullName $name $type
    }
    $summary = Get-Content (Join-Path $out 'summary.json') -Raw | ConvertFrom-Json
    $errs = @(Import-Csv (Join-Path $out 'read_errors.csv'))
    $areas = @($summary.areas.PSObject.Properties)
    $ok = @($areas | Where-Object { $_.Value.status -eq 'ok' }).Count
    if ($forbidden -gt 0) { Write-Warning "$forbidden read(s) were refused (403/auth) after the role check passed: see read_errors.csv." }
    Write-Output "Inventory done: $ok of $($areas.Count) areas read completely, $($errs.Count) read error(s), $forbidden refused."
    $DeploymentScriptOutputs = @{
        runPrefix = $prefix; storageAccount = $env:STORAGE_ACCOUNT; container = $env:CONTAINER
        areasOk = $ok; areasTotal = $areas.Count; readErrors = $errs.Count; readsRefused = $forbidden
        kitVersion = $summary.kitVersion; apiCalls = $summary.azCalls
    }
    $uploaded = $true
}
finally {
    Stop-Transcript | Out-Null
    try { Send-Blob $transcript 'inventory.log' 'text/plain' } catch { Write-Warning "Could not upload the transcript: $($_.Exception.Message)" }
    if (-not $uploaded) { Write-Output 'Inventory did not complete; see inventory.log in the storage account.' }
}
