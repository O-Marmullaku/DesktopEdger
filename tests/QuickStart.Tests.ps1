#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Start-DesktopEdger.ps1')

function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Expect-Failure([scriptblock]$action, [string]$message) {
    try { & $action } catch {
        Assert ($_.Exception.Message -like "*$message*") "Unexpected failure: $_"
        return
    }
    throw "Expected failure: $message"
}

# Mock every launch and download. These checks never change Explorer or install tools.
$script:launches = @()
$script:exitCode = 0
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru, [switch]$NoNewWindow, $Verb)
    Assert ($Wait -and $PassThru -and $NoNewWindow -and -not $Verb) 'Child must wait without elevation.'
    $script:launches += ,@($FilePath, $ArgumentList)
    return [pscustomobject]@{ ExitCode = $script:exitCode }
}
$script:urls = @()
function Invoke-RestMethod {
    param($Uri, $TimeoutSec)
    $script:urls += $Uri
    if ($script:networkFailure) { throw 'Network failure' }
    return '$script:dumpInvoked = $true'
}

Invoke-DesktopEdgerAction Arrange
Invoke-DesktopEdgerAction Restore
Assert ($script:launches.Count -eq 2) 'Arrange and Restore must launch once each.'
foreach ($launch in $script:launches) {
    $arguments = $launch[1]
    Assert ($arguments[1] -eq '-STA' -and $arguments[3] -eq 'Bypass') 'Missing process-scoped STA/bypass.'
    Assert ($arguments[5] -eq ('"' + (Join-Path $root 'Arrange-DesktopIcons.ps1') + '"')) 'Wrong sibling script or quoting.'
}
Assert ($script:launches[0][1][-1] -eq 'Arrange') 'Wrong Arrange mode.'
Assert ($script:launches[1][1][-1] -eq 'Restore') 'Wrong Restore mode.'
$script:exitCode = 1
Expect-Failure { Invoke-DesktopEdgerAction Arrange } 'use Restore'
$script:exitCode = 0

$tls = [Net.ServicePointManager]::SecurityProtocol
Invoke-DesktopEdgerAction DumpToTxt
Assert ($script:dumpInvoked) 'DumpToTxt loader was not invoked.'
Assert ($script:urls[0] -eq 'https://marmullaku.ch/dumptotxt') 'Must reuse the existing tool endpoint.'
Assert ([Net.ServicePointManager]::SecurityProtocol -eq $tls) 'TLS settings changed.'
$script:networkFailure = $true
Expect-Failure { Invoke-DesktopEdgerAction DumpToTxt } 'Network failure'
Assert ([Net.ServicePointManager]::SecurityProtocol -eq $tls) 'TLS settings changed on failure.'
Expect-Failure { Invoke-DesktopEdgerAction 'Unknown' } 'ValidateSet'

$script:choices = New-Object 'System.Collections.Generic.Queue[string]'
@('invalid', 'q') | ForEach-Object { $script:choices.Enqueue($_) }
function Read-Host { param($Prompt) return $script:choices.Dequeue() }
$count = $script:launches.Count
Show-DesktopEdgerMenu
Assert ($script:launches.Count -eq $count) 'Invalid choice or quit launched an action.'
$script:choices.Enqueue('2')
$script:choices.Enqueue('q')
Show-DesktopEdgerMenu
Assert ($script:launches[-1][1][-1] -eq 'Restore') 'Menu did not dispatch Restore.'
Write-Host 'Quick-start checks passed (downloads and launches mocked).'
