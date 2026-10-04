# Run a temporary, verified Desktop-Edger copy; no persistent installation.
#requires -Version 5.1
& {
    $ErrorActionPreference = 'Stop'
    if ($env:OS -ne 'Windows_NT') { throw 'Desktop-Edger requires Windows.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Open PowerShell normally, without Run as administrator.'
        }
    } finally { $identity.Dispose() }

    $revision = 'b0b0cb747fb5773daf3e8670fc26e1652fbbc3ba'
    $files = [ordered]@{
        'Start-DesktopEdger.ps1' = '7ca155c35ab0dfaa61264009f8aed5f59eccec6a9f44294af15b2ecdd4cfa83f'
        'Arrange-DesktopIcons.ps1' = '81f8cd560238746d049d7859ff5d7852fafbef8c1914491229dac852090ff0f4'
    }
    $previousTls = [Net.ServicePointManager]::SecurityProtocol
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $temporary = [IO.Path]::GetFullPath((Join-Path $tempRoot ('DesktopEdger-' + [guid]::NewGuid())))
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousTls -bor [Net.SecurityProtocolType]::Tls12
        New-Item -ItemType Directory -Path $temporary | Out-Null
        foreach ($name in $files.Keys) {
            $path = Join-Path $temporary $name
            $url = "https://raw.githubusercontent.com/O-Marmullaku/DesktopEdger/$revision/$name"
            Invoke-WebRequest $url -OutFile $path -UseBasicParsing -TimeoutSec 60 -MaximumRedirection 0
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $files[$name]) {
                throw "Desktop-Edger checksum mismatch: $name. Nothing was started."
            }
        }
        $launcher = Join-Path $temporary 'Start-DesktopEdger.ps1'
        $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$launcher`"") -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) { throw "Desktop-Edger failed (exit code $($process.ExitCode))." }
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousTls
        if ((Split-Path -Parent $temporary) -ne $tempRoot.TrimEnd('\', '/')) { throw 'Unexpected temporary directory.' }
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
}
