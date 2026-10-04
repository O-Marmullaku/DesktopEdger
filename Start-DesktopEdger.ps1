#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Menu', 'Arrange', 'Restore', 'DumpToTxt')][string]$Action = 'Menu')

function Assert-DesktopEdgerSession {
    if ($env:OS -ne 'Windows_NT') { throw 'Desktop-Edger requires Windows.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Open PowerShell normally, without Run as administrator. Only tool setup requests elevation.'
        }
    } finally { $identity.Dispose() }
}

function Invoke-DesktopEdgerAction {
    param([Parameter(Mandatory = $true)][ValidateSet('Arrange', 'Restore', 'DumpToTxt')][string]$Action)
    Assert-DesktopEdgerSession
    if ($Action -eq 'DumpToTxt') {
        Write-Host 'DumpToTxt Full: install or update with the setup wizard. Administrator approval is required.'
        Write-Host 'For an existing installation, choose Update or reinstall to keep your settings.'
        $previousTls = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = $previousTls -bor [Net.SecurityProtocolType]::Tls12
            & {
                $ErrorActionPreference = 'Stop'
                Invoke-RestMethod 'https://marmullaku.ch/dumptotxt' -TimeoutSec 30 | Invoke-Expression
            }
        } finally { [Net.ServicePointManager]::SecurityProtocol = $previousTls }
        return
    }

    $arranger = Join-Path $PSScriptRoot 'Arrange-DesktopIcons.ps1'
    if (-not (Test-Path -LiteralPath $arranger -PathType Leaf)) { throw "Missing arranger: $arranger" }
    $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$arranger`"", '-Mode', $Action) -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        throw "$Action failed (exit code $($process.ExitCode)). If a backup was recorded, use Restore before arranging again."
    }
}

function Show-DesktopEdgerMenu {
    Assert-DesktopEdgerSession
    do {
        Write-Host "`nDesktop-Edger"
        Write-Host '1  Arrange desktop icons'
        Write-Host '2  Restore desktop icons from the latest backup'
        Write-Host '3  Install or update DumpToTxt Full'
        Write-Host 'Q  Quit'
        $choice = Read-Host 'Choose an action'
        $selected = switch ($choice.Trim()) {
            '1' { 'Arrange' }
            '2' { 'Restore' }
            '3' { 'DumpToTxt' }
            'q' { return }
            default { Write-Host 'Choose 1, 2, 3, or Q.' }
        }
        if ($selected) {
            try { Invoke-DesktopEdgerAction -Action $selected }
            catch { Write-Host $_.Exception.Message -ForegroundColor Red }
        }
    } while ($true)
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ($Action -eq 'Menu') { Show-DesktopEdgerMenu }
        else { Invoke-DesktopEdgerAction -Action $Action }
        exit 0
    } catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
