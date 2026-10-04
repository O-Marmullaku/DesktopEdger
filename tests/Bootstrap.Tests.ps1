#requires -Version 5.1
param([switch]$PublicDownload)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bootstrap = Join-Path $root 'Bootstrap-DesktopEdger.ps1'
$source = Get-Content -LiteralPath $bootstrap -Raw
if ($source -notmatch "\`$revision = '([a-f0-9]{40})'") { throw 'Bootstrap must pin an immutable commit.' }
$revision = $Matches[1]
function Assert($condition, $message) { if (-not $condition) { throw $message } }

# All downloads and launches are intercepted; hashing and cleanup use real files.
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec, $MaximumRedirection)
    $script:downloads++
    $name = Split-Path -Leaf $OutFile
    Assert ($Uri -eq "https://raw.githubusercontent.com/O-Marmullaku/DesktopEdger/$revision/$name") 'Wrong source URL.'
    Assert ($UseBasicParsing -and $TimeoutSec -eq 60 -and $MaximumRedirection -eq 0) 'Unexpected download options.'
    if ($PublicDownload) { Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters; return }
    if ($script:mode -eq "network$script:downloads") { throw 'Test download failure' }
    $content = ((& git -C $root show ("{0}:{1}" -f $revision, $name)) -join "`n") + "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Pinned source is missing.' }
    if ($script:mode -eq "corrupt$script:downloads") { $content += 'tampered' }
    [IO.File]::WriteAllText($OutFile, $content, (New-Object Text.UTF8Encoding($false)))
}
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru, [switch]$NoNewWindow, $Verb)
    $script:launches++
    Assert ($script:downloads -eq 2) 'Launch happened before all downloads.'
    Assert ($Wait -and $PassThru -and $NoNewWindow -and -not $Verb) 'Incorrect process/elevation behavior.'
    Assert ($ArgumentList[1] -eq '-STA' -and $ArgumentList[3] -eq 'Bypass') 'Missing STA/process-scoped bypass.'
    Assert ($ArgumentList[5] -match '^".+\\Start-DesktopEdger.ps1"$') 'Launcher path must be quoted.'
    if ($script:mode -eq 'launchFailure') { throw 'Test launch failure' }
    return [pscustomobject]@{ ExitCode = $(if ($script:mode -eq 'childFailure') { 1 } else { 0 }) }
}

$scratch = Join-Path $PSScriptRoot ('.bootstrap-check-' + [guid]::NewGuid())
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$tls = [Net.ServicePointManager]::SecurityProtocol
try {
    New-Item -ItemType Directory -Path $scratch | Out-Null
    $env:TEMP = $scratch
    $env:TMP = $scratch
    $cases = if ($PublicDownload) { @('success') } else { @('success', 'corrupt1', 'corrupt2', 'network1', 'network2', 'childFailure', 'launchFailure') }
    foreach ($case in $cases) {
        $script:mode = $case
        $script:downloads = 0
        $script:launches = 0
        $failure = $null
        try { . $bootstrap } catch { $failure = $_.Exception.Message }
        if ($case -eq 'success') { Assert (-not $failure) "Success failed: $failure" }
        elseif ($case -like 'corrupt*') { Assert ($failure -like '*checksum mismatch*') "Wrong checksum failure: $failure" }
        elseif ($case -like 'network*') { Assert ($failure -eq 'Test download failure') "Wrong download failure: $failure" }
        elseif ($case -eq 'childFailure') { Assert ($failure -like '*exit code 1*') "Wrong child failure: $failure" }
        else { Assert ($failure -eq 'Test launch failure') "Wrong launch failure: $failure" }
        $expectedLaunches = if ($case -in 'success', 'childFailure', 'launchFailure') { 1 } else { 0 }
        Assert ($script:launches -eq $expectedLaunches) "Unexpected launch: $case"
        Assert (@(Get-ChildItem -LiteralPath $scratch -Force).Count -eq 0) "Temporary copy leaked: $case"
        Assert ([Net.ServicePointManager]::SecurityProtocol -eq $tls) "TLS changed: $case"
    }
} finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($scratch))) -ne $PSScriptRoot) { throw 'Unexpected test directory.' }
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
if ($PublicDownload) { Write-Host 'Public downloads verified; launch intercepted and temporary copy cleaned.' }
else { Write-Host 'Bootstrap checks passed (downloads and launches mocked; hashes and cleanup exercised).' }
