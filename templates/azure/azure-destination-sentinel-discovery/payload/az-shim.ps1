#!/usr/bin/env pwsh
# Stand-in for the three Azure CLI commands Get-SentinelInventory.ps1 runs, for the Azure deployment-script
# PowerShell container, which has no Azure CLI. Installed on PATH as `az` by run-inventory.ps1, so the kit runs
# unchanged and sees a real process: stdout, stderr and the exit code behave as they do for az.
#
#   az account show ...   prints the signed-in identity (from SENTINV_SHIM_* environment variables)
#   az version ...        prints {"azure-cli": "<this shim>"} so summary.json records that the CLI was not used
#   az rest --method get|post --url <url> [--url-parameters @file] [--resource <aud>] [--body @file]
#           [--headers @file] --output-file <file> [--only-show-errors]
#
# Bearer tokens come from SENTINV_TOKEN_ARM, SENTINV_TOKEN_LA and SENTINV_TOKEN_GRAPH, fetched once by
# run-inventory.ps1 for the managed identity. Only GET and POST reach the network: the kit's own allow-list
# (Test-AllowedRequest) has already refused anything else before this runs, and this script refuses it again.
# Errors go to stderr as "ERROR: <status> <reason>(<body>)", the shape az rest prints, so the kit's
# Get-FailureClass patterns (Forbidden, 403, Failed to resolve table, Not Found ...) still match.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ShimVersion = 'deployment-script az shim 1.0 (az rest over Invoke-WebRequest; Azure CLI not installed)'

function Fail([string]$Text, [int]$Code = 1) { [Console]::Error.WriteLine($Text); exit $Code }

$a = @($args)
if ($a.Count -ge 2 -and $a[0] -eq 'account' -and $a[1] -eq 'show') {
    [ordered]@{
        id = $env:SENTINV_SHIM_SUBSCRIPTION; name = $env:SENTINV_SHIM_SUBSCRIPTION; tenantId = $env:SENTINV_SHIM_TENANT
        user = [ordered]@{ name = $env:SENTINV_SHIM_CLIENT_ID; type = 'servicePrincipal' }
        environmentName = 'AzureCloud'; isDefault = $true; state = 'Enabled'
    } | ConvertTo-Json -Depth 4
    exit 0
}
if ($a.Count -ge 1 -and $a[0] -eq 'version') {
    [ordered]@{ 'azure-cli' = $ShimVersion } | ConvertTo-Json
    exit 0
}
if ($a.Count -lt 1 -or $a[0] -ne 'rest') { Fail "ERROR: az shim supports only 'rest', 'account show' and 'version' (got: $($a -join ' '))" 2 }

$opt = @{}
for ($i = 1; $i -lt $a.Count; $i++) {
    $k = [string]$a[$i]
    if ($k -eq '--only-show-errors') { continue }
    if ($k -notlike '--*' -or $i + 1 -ge $a.Count) { Fail "ERROR: az shim: unexpected argument '$k'" 2 }
    $opt[$k.Substring(2)] = [string]$a[++$i]
}
function Read-At([string]$v) { if ($v -and $v.StartsWith('@')) { return [System.IO.File]::ReadAllText($v.Substring(1)) } return $v }

$method = ([string]$opt['method']).ToUpperInvariant()
if ($method -notin @('GET', 'POST')) { Fail "ERROR: az shim refuses method '$method': read-only" 2 }
$url = [string]$opt['url']
if (-not $url) { Fail 'ERROR: az shim: --url is required' 2 }
if ($opt['url-parameters']) {
    $p = (Read-At $opt['url-parameters']) | ConvertFrom-Json -AsHashtable
    $q = ($p.GetEnumerator() | ForEach-Object { [uri]::EscapeDataString([string]$_.Key) + '=' + [uri]::EscapeDataString([string]$_.Value) }) -join '&'
    $url = $url + $(if ($url.Contains('?')) { '&' } else { '?' }) + $q
}
$uri = [uri]$url
$aud = [string]$opt['resource']
$token = if ($aud -match 'loganalytics' -or $uri.Host -eq 'api.loganalytics.io') { $env:SENTINV_TOKEN_LA }
         elseif ($aud -match 'graph\.microsoft' -or $uri.Host -eq 'graph.microsoft.com') { $env:SENTINV_TOKEN_GRAPH }
         elseif ($uri.Host -eq 'management.azure.com') { $env:SENTINV_TOKEN_ARM }
         else { Fail "ERROR: az shim: no token for host $($uri.Host)" 2 }
if (-not $token) { Fail "ERROR: az shim: no token available for $($uri.Host). Run az login (InvalidAuthenticationToken)" 1 }

$headers = @{ Authorization = "Bearer $token" }
if ($opt['headers']) {
    $h = (Read-At $opt['headers']) | ConvertFrom-Json -AsHashtable
    foreach ($k in $h.Keys) { $headers[$k] = [string]$h[$k] }
}
$req = @{ Uri = $uri; Method = $method; Headers = $headers; SkipHttpErrorCheck = $true; TimeoutSec = 900; UseBasicParsing = $true }
if ($opt['body']) { $req.Body = [System.Text.Encoding]::UTF8.GetBytes((Read-At $opt['body'])); $req.ContentType = 'application/json' }
# Log Analytics refuses some table queries for minutes after a role is assigned, while others succeed (measured), so a 403 there
# is retried a few times. A real lack of access costs at most a minute per query; run-inventory.ps1 has already proved the roles.
$attempt = 0
while ($true) {
    $attempt++
    try { $resp = Invoke-WebRequest @req }
    catch { Fail ("ERROR: " + $_.Exception.Message + $(if ($_.Exception.Message -match 'Timeout|timed out') { ' (timed out)' } else { '' })) 1 }
    if ([int]$resp.StatusCode -eq 403 -and $uri.Host -eq 'api.loganalytics.io' -and $attempt -lt 4) { Start-Sleep -Seconds 20; continue }
    break
}

$code = [int]$resp.StatusCode
$text = if ($resp.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($resp.Content) } else { [string]$resp.Content }
if ($code -ge 200 -and $code -lt 300) {
    if ($opt['output-file']) { [System.IO.File]::WriteAllText($opt['output-file'], $text, [System.Text.UTF8Encoding]::new($false)) }
    else { [Console]::Out.Write($text) }
    exit 0
}
$reason = switch ($code) { 400 { 'Bad Request' } 401 { 'Unauthorized' } 403 { 'Forbidden' } 404 { 'Not Found' } 408 { 'Request Timeout' }
    409 { 'Conflict' } 429 { 'Too Many Requests' } 500 { 'Internal Server Error' } 502 { 'Bad Gateway' } 503 { 'Service Unavailable' }
    504 { 'Gateway Timeout' } default { 'HTTP error' } }
Fail ("ERROR: $code $reason($text)") 1
