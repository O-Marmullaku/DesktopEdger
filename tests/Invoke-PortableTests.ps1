[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'Arrange-DesktopIcons.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT TRUE FAILED: $Message" }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "ASSERT EQUAL FAILED: $Message. Expected '$Expected', got '$Actual'."
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw "ASSERT THROWS FAILED: $Message" }
}

function New-TestItem {
    param(
        [string]$Name,
        [string]$CanonicalIdentity = $Name,
        [string]$Path = '',
        [bool]$IsFolder = $false,
        [string]$ShortcutTarget = '',
        [string]$ShortcutArguments = '',
        [string]$ShortcutWorkingDirectory = '',
        [string]$Url = '',
        [int]$X = 0,
        [int]$Y = 0,
        [string]$Category = ''
    )
    $extension = if ($Path) { [System.IO.Path]::GetExtension($Path) } else { '' }
    [pscustomobject]@{
        DisplayName = $Name
        CanonicalIdentity = $CanonicalIdentity
        FileSystemPath = $Path
        IsFolder = $IsFolder
        Extension = $extension
        ShortcutTarget = $ShortcutTarget
        ShortcutArguments = $ShortcutArguments
        ShortcutWorkingDirectory = $ShortcutWorkingDirectory
        Url = $Url
        X = $X
        Y = $Y
        Category = $Category
    }
}

Assert-True (Test-Path -LiteralPath $scriptPath) 'main script exists'
. $scriptPath

$empty = New-OverrideMap
Assert-Equal 'RecycleBin' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Recycle Bin' -CanonicalIdentity '::{645FF040-5081-101B-9F08-00AA002F954E}') -OverrideMap $empty) 'Recycle Bin classification'
Assert-Equal 'Right' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Folder' -Path 'C:\Desktop\Folder' -IsFolder $true) -OverrideMap $empty) 'folder classification'
Assert-Equal 'Right' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Run.bat' -Path 'C:\Desktop\Run.bat') -OverrideMap $empty) 'batch classification'
Assert-Equal 'Right' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Notes.txt' -Path 'C:\Desktop\Notes.txt') -OverrideMap $empty) 'text classification'
Assert-Equal 'Bottom' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Track.flac' -Path 'C:\Desktop\Track.flac') -OverrideMap $empty) 'music classification'
Assert-Equal 'Application' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Editor.lnk' -Path 'C:\Desktop\Editor.lnk' -ShortcutTarget 'C:\Program Files\Editor\editor.exe') -OverrideMap $empty) 'application classification'
Assert-Equal 'Bottom' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Game.lnk' -Path 'C:\Desktop\Game.lnk' -ShortcutTarget 'C:\Program Files (x86)\Steam\steam.exe' -ShortcutArguments '-applaunch 123') -OverrideMap $empty) 'game classification'
Assert-Equal 'Bottom' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Ubisoft Game.lnk' -Path 'C:\Desktop\Ubisoft Game.lnk' -ShortcutTarget 'C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games\Game\game.exe') -OverrideMap $empty) 'Ubisoft install-path game classification'
Assert-Equal 'Right' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Web.url' -Path 'C:\Desktop\Web.url' -Url 'https://example.com') -OverrideMap $empty) 'ordinary URL classification'
Assert-Throws { New-OverrideMap -ForceApplication @('Same') -ForceRight @('same') } 'conflicting override token'
Assert-Throws { New-OverrideMap -ForceGame @('Same') -ForceMusic @('same') } 'same bottom-edge token in two force lists'
Assert-Equal 'Application' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Steam' -Path 'C:\Desktop\Steam.lnk' -ShortcutTarget 'C:\Program Files (x86)\Steam\steam.exe') -OverrideMap $empty) 'bare launcher stays application'
Assert-Equal 'Application' (Get-DesktopItemCategory -Item (New-TestItem -Name 'Epic' -Path 'C:\Desktop\Epic.lnk' -ShortcutTarget 'C:\Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe') -OverrideMap $empty) 'bare Epic launcher stays application'

$singletonLayoutItems = @(
    (New-TestItem -Name 'Recycle Bin' -CanonicalIdentity 'recycle-single' -Category 'RecycleBin'),
    (New-TestItem -Name 'App' -CanonicalIdentity 'app-single' -Category 'Application'),
    (New-TestItem -Name 'Game' -CanonicalIdentity 'game-single' -Category 'Bottom'),
    (New-TestItem -Name 'Folder' -CanonicalIdentity 'folder-single' -Category 'Right')
)
foreach ($item in $singletonLayoutItems) {
    $item | Add-Member -NotePropertyName Count -NotePropertyValue $null -Force
}
$singletonLayout = @(New-DesktopLayoutPlan -Items $singletonLayoutItems -ColumnCount 5 -RowCount 4 -OriginX 0 -OriginY 0 -SpacingX 80 -SpacingY 80)
Assert-Equal 4 $singletonLayout.Count 'singleton category item count'
Assert-Equal 1 @($singletonLayout | Where-Object Category -eq 'RecycleBin').Count 'singleton Recycle Bin preserved'
Assert-Equal 1 @($singletonLayout | Where-Object Category -eq 'Application').Count 'singleton application preserved'
Assert-Equal 1 @($singletonLayout | Where-Object Category -eq 'Bottom').Count 'singleton bottom item preserved'
Assert-Equal 1 @($singletonLayout | Where-Object Category -eq 'Right').Count 'singleton right item preserved'

$layoutItems = @(
    (New-TestItem -Name 'Recycle Bin' -CanonicalIdentity 'recycle' -Category 'RecycleBin'),
    (New-TestItem -Name 'App A' -CanonicalIdentity 'app-a' -Category 'Application'),
    (New-TestItem -Name 'App B' -CanonicalIdentity 'app-b' -Category 'Application'),
    (New-TestItem -Name 'Game' -CanonicalIdentity 'game' -Category 'Bottom'),
    (New-TestItem -Name 'Music' -CanonicalIdentity 'music' -Category 'Bottom'),
    (New-TestItem -Name 'Folder' -CanonicalIdentity 'folder' -Category 'Right')
)
$layout = New-DesktopLayoutPlan -Items $layoutItems -ColumnCount 6 -RowCount 4 -OriginX 10 -OriginY 20 -SpacingX 100 -SpacingY 80
Assert-Equal 0 (($layout | Where-Object CanonicalIdentity -eq 'recycle').Column) 'Recycle Bin column'
Assert-Equal 0 (($layout | Where-Object CanonicalIdentity -eq 'recycle').Row) 'Recycle Bin row'
Assert-Equal 1 (($layout | Where-Object CanonicalIdentity -eq 'app-a').Column) 'first app column'
Assert-Equal 3 (($layout | Where-Object CanonicalIdentity -eq 'game').Row) 'bottom row'
Assert-Equal 2 (($layout | Where-Object CanonicalIdentity -eq 'game').Column) 'centered bottom start'
Assert-Equal 5 (($layout | Where-Object CanonicalIdentity -eq 'folder').Column) 'right edge column'
Assert-Equal 0 (($layout | Where-Object CanonicalIdentity -eq 'folder').Row) 'right edge uses first available edge cell'
Test-DesktopLayoutPlan -Plan $layout -ExpectedItems $layoutItems -ColumnCount 6 -RowCount 4

$geometry = Get-DesktopGridGeometry -Snapshot ([pscustomobject]@{
    Left = 0; Top = 0; Width = 616; Height = 416; SpacingX = 100; SpacingY = 100
}) -Margin 8
Assert-Equal 6 $geometry.ColumnCount 'full-width grid-cell count'
Assert-Equal 4 $geometry.RowCount 'full-height grid-cell count'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('DesktopEdgeArrangerTests-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
try {
    $backupPath = Write-DesktopLayoutBackup -Items @(
        (New-TestItem -Name 'One' -CanonicalIdentity 'one' -X 10 -Y 20),
        (New-TestItem -Name 'Two' -CanonicalIdentity 'two' -X 30 -Y 40)
    ) -BackupRoot $tempRoot
    Assert-True (Test-Path -LiteralPath $backupPath) 'backup exists'
    Assert-Equal $backupPath (Get-LatestDesktopLayoutBackup -BackupRoot $tempRoot) 'latest manifest resolves backup'
    $entries = Read-DesktopLayoutBackup -Path $backupPath
    Assert-Equal 2 $entries.Count 'backup item count'
} finally {
    if ([System.IO.Directory]::Exists($tempRoot)) {
        [System.IO.Directory]::Delete($tempRoot, $true)
    }
}

$source = [System.IO.File]::ReadAllText($scriptPath)
foreach ($token in @(
    'IFolderView', 'GetSpacing', 'GetItemPosition', 'SelectAndPositionItems',
    'FindWindowSW', 'QueryActiveShellView', 'ThrowIfFailed',
    'Marshal.FreeCoTaskMem', 'SetCurrentFolderFlags', 'FVO_CUSTOMPOSITION',
    'SVSI_NOSTATECHANGE'
)) {
    Assert-True ($source.Contains($token)) "interop token $token"
}
foreach ($forbidden in @(
    'Register-ScheduledTask', 'New-ScheduledTask', 'Start-Job', 'Register-ObjectEvent',
    'FileSystemWatcher', 'CurrentVersion\\Run', 'Set-ExecutionPolicy', 'Move-Item',
    'Rename-Item', 'Copy-Item', 'Remove-Item'
)) {
    Assert-True (-not $source.Contains($forbidden)) "forbidden token $forbidden absent"
}

$launcherPath = Join-Path $root 'Arrange-DesktopIcons.bat'
$readmePath = Join-Path $root 'README.md'
Assert-True (Test-Path -LiteralPath $launcherPath) 'batch launcher exists'
Assert-True (Test-Path -LiteralPath $readmePath) 'README exists'
$launcher = [System.IO.File]::ReadAllText($launcherPath)
Assert-True ($launcher.Contains('-STA')) 'launcher uses STA'
Assert-True ($launcher.Contains('-ExecutionPolicy Bypass')) 'launcher policy is process-scoped'
$readme = [System.IO.File]::ReadAllText($readmePath)
foreach ($token in @('Arrange-DesktopIcons.bat', '-Mode Restore', '%LOCALAPPDATA%\DesktopEdgeArranger\Backups', '$ForceApplication', '$ForceGame', '$ForceMusic', '$ForceRight', 'single-monitor')) {
    Assert-True ($readme.Contains($token)) "README token $token"
}

Write-Host 'Portable tests passed.'
