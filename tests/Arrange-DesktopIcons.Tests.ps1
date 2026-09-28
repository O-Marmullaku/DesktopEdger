# Pester 5 separates discovery from execution: initialize functions in BeforeAll
# and keep TestCases as data, constructing fixtures inside each It block.
BeforeAll {
    $ErrorActionPreference = 'Stop'
    $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Arrange-DesktopIcons.ps1'
    . $scriptPath

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

        $extension = ''
        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            $extension = [System.IO.Path]::GetExtension($Path)
        }

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
}

Describe 'Desktop item classification' {
    BeforeEach {
        $emptyOverrides = New-OverrideMap
    }

    It 'pins Recycle Bin by canonical shell identity' {
        $item = New-TestItem -Name 'Recycle Bin' -CanonicalIdentity '::{645FF040-5081-101B-9F08-00AA002F954E}'
        Get-DesktopItemCategory -Item $item -OverrideMap $emptyOverrides | Should -Be 'RecycleBin'
    }

    It 'places folders, scripts, text, ordinary URLs, and unresolved shortcuts on the right' -TestCases @(
        @{ Item = @{ Name = 'Folder'; Path = 'C:\Users\Me\Desktop\Folder'; IsFolder = $true } }
        @{ Item = @{ Name = 'Build.bat'; Path = 'C:\Users\Me\Desktop\Build.bat' } }
        @{ Item = @{ Name = 'Build.cmd'; Path = 'C:\Users\Me\Desktop\Build.cmd' } }
        @{ Item = @{ Name = 'Notes.txt'; Path = 'C:\Users\Me\Desktop\Notes.txt' } }
        @{ Item = @{ Name = 'Website.url'; Path = 'C:\Users\Me\Desktop\Website.url'; Url = 'https://example.com' } }
        @{ Item = @{ Name = 'Unknown.lnk'; Path = 'C:\Users\Me\Desktop\Unknown.lnk' } }
    ) {
        param($Item)
        Get-DesktopItemCategory -Item (New-TestItem @Item) -OverrideMap $emptyOverrides | Should -Be 'Right'
    }

    It 'places recognized music files on the bottom' -TestCases @(
        @{ Ext = '.mp3' }, @{ Ext = '.wav' }, @{ Ext = '.flac' }, @{ Ext = '.m4a' },
        @{ Ext = '.aac' }, @{ Ext = '.ogg' }, @{ Ext = '.opus' }, @{ Ext = '.wma' }
    ) {
        param($Ext)
        $item = New-TestItem -Name "Track$Ext" -Path "C:\Users\Me\Desktop\Track$Ext"
        Get-DesktopItemCategory -Item $item -OverrideMap $emptyOverrides | Should -Be 'Bottom'
    }

    It 'places executable shortcuts on the top' {
        $item = New-TestItem -Name 'Editor.lnk' -Path 'C:\Users\Me\Desktop\Editor.lnk' -ShortcutTarget 'C:\Program Files\Editor\Editor.exe'
        Get-DesktopItemCategory -Item $item -OverrideMap $emptyOverrides | Should -Be 'Application'
    }

    It 'recognizes conservative game launcher indicators' -TestCases @(
        @{ Target = 'C:\Program Files (x86)\Steam\steam.exe'; LaunchArguments = '-applaunch 123' }
        @{ Target = 'C:\Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe'; LaunchArguments = 'com.epicgames.launcher://apps/game?action=launch' }
        @{ Target = 'C:\Program Files\EA Games\Game\game.exe'; LaunchArguments = '' }
        @{ Target = 'C:\GOG Games\Game\game.exe'; LaunchArguments = '' }
        @{ Target = 'C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games\Game\game.exe'; LaunchArguments = '' }
    ) {
        param($Target, $LaunchArguments)
        $item = New-TestItem -Name 'Game.lnk' -Path 'C:\Users\Me\Desktop\Game.lnk' -ShortcutTarget $Target -ShortcutArguments $LaunchArguments
        Get-DesktopItemCategory -Item $item -OverrideMap $emptyOverrides | Should -Be 'Bottom'
    }

    It 'applies explicit overrides before automatic classification' {
        $item = New-TestItem -Name 'Custom Game' -Path 'C:\Users\Me\Desktop\Custom Game.lnk'
        $map = New-OverrideMap -ForceGame @('Custom Game')
        Get-DesktopItemCategory -Item $item -OverrideMap $map | Should -Be 'Bottom'
    }

    It 'rejects the same override token in conflicting groups' {
        { New-OverrideMap -ForceApplication @('Same') -ForceRight @('same') } | Should -Throw
    }

    It 'rejects the same token in ForceGame and ForceMusic even though both use the bottom edge' {
        { New-OverrideMap -ForceGame @('Same') -ForceMusic @('same') } | Should -Throw
    }

    It 'rejects one item matched by different identity forms in conflicting groups' {
        $item = New-TestItem -Name 'Editor' -CanonicalIdentity 'C:\Users\Me\Desktop\Editor.lnk'
        {
            Test-OverrideConfiguration -Items @($item) -ForceApplication @('Editor') -ForceRight @('C:\Users\Me\Desktop\Editor.lnk')
        } | Should -Throw
    }

    It 'keeps a bare game launcher on the application edge' {
        $item = New-TestItem -Name 'Steam' -Path 'C:\Users\Me\Desktop\Steam.lnk' -ShortcutTarget 'C:\Program Files (x86)\Steam\steam.exe'
        Get-DesktopItemCategory -Item $item -OverrideMap $emptyOverrides | Should -Be 'Application'
    }

    It 'keeps other bare game launchers on the application edge' -TestCases @(
        @{ Name = 'Epic'; Target = 'C:\Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe' }
        @{ Name = 'EA'; Target = 'C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe' }
        @{ Name = 'GOG'; Target = 'C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe' }
        @{ Name = 'Ubisoft'; Target = 'C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe' }
        @{ Name = 'Rockstar'; Target = 'C:\Program Files\Rockstar Games\Launcher\Launcher.exe' }
        @{ Name = 'Battle.net'; Target = 'C:\Program Files (x86)\Battle.net\Battle.net Launcher.exe' }
        @{ Name = 'Riot'; Target = 'C:\Riot Games\Riot Client\RiotClientServices.exe' }
    ) {
        param($Name, $Target)
        $item = New-TestItem -Name $Name -Path "C:\Users\Me\Desktop\$Name.lnk" -ShortcutTarget $Target
        Get-DesktopItemCategory -Item $item -OverrideMap $emptyOverrides | Should -Be 'Application'
    }
}

Describe 'Desktop edge layout planner' {
    It 'preserves singleton categories when item Count is unavailable' {
        $items = @(
            (New-TestItem -Name 'Recycle Bin' -CanonicalIdentity 'recycle' -Category 'RecycleBin'),
            (New-TestItem -Name 'App' -CanonicalIdentity 'app' -Category 'Application'),
            (New-TestItem -Name 'Game' -CanonicalIdentity 'game' -Category 'Bottom'),
            (New-TestItem -Name 'Folder' -CanonicalIdentity 'folder' -Category 'Right')
        )
        foreach ($item in $items) {
            $item | Add-Member -NotePropertyName Count -NotePropertyValue $null -Force
        }

        $plan = @(New-DesktopLayoutPlan -Items $items -ColumnCount 5 -RowCount 4 -OriginX 0 -OriginY 0 -SpacingX 80 -SpacingY 80)
        $plan.Count | Should -Be 4
        @($plan | Where-Object Category -eq 'RecycleBin').Count | Should -Be 1
        @($plan | Where-Object Category -eq 'Application').Count | Should -Be 1
        @($plan | Where-Object Category -eq 'Bottom').Count | Should -Be 1
        @($plan | Where-Object Category -eq 'Right').Count | Should -Be 1
    }

    It 'places Recycle Bin, top applications, centered bottom items, and right items deterministically' {
        $items = @(
            (New-TestItem -Name 'Recycle Bin' -CanonicalIdentity 'recycle' -Category 'RecycleBin'),
            (New-TestItem -Name 'App A' -CanonicalIdentity 'app-a' -Category 'Application'),
            (New-TestItem -Name 'App B' -CanonicalIdentity 'app-b' -Category 'Application'),
            (New-TestItem -Name 'Game' -CanonicalIdentity 'game' -Category 'Bottom'),
            (New-TestItem -Name 'Music' -CanonicalIdentity 'music' -Category 'Bottom'),
            (New-TestItem -Name 'Folder' -CanonicalIdentity 'folder' -Category 'Right')
        )

        $plan = New-DesktopLayoutPlan -Items $items -ColumnCount 6 -RowCount 4 -OriginX 10 -OriginY 20 -SpacingX 100 -SpacingY 80
        ($plan | Where-Object CanonicalIdentity -eq 'recycle').Column | Should -Be 0
        ($plan | Where-Object CanonicalIdentity -eq 'recycle').Row | Should -Be 0
        ($plan | Where-Object CanonicalIdentity -eq 'app-a').Column | Should -Be 1
        ($plan | Where-Object CanonicalIdentity -eq 'app-b').Column | Should -Be 2
        ($plan | Where-Object CanonicalIdentity -eq 'game').Row | Should -Be 3
        ($plan | Where-Object CanonicalIdentity -eq 'music').Row | Should -Be 3
        ($plan | Where-Object CanonicalIdentity -eq 'game').Column | Should -Be 2
        ($plan | Where-Object CanonicalIdentity -eq 'music').Column | Should -Be 3
        ($plan | Where-Object CanonicalIdentity -eq 'folder').Column | Should -Be 5
        ($plan | Where-Object CanonicalIdentity -eq 'folder').Row | Should -Be 0
        ($plan | Where-Object CanonicalIdentity -eq 'folder').X | Should -Be 510
        ($plan | Where-Object CanonicalIdentity -eq 'folder').Y | Should -Be 20
        { Test-DesktopLayoutPlan -Plan $plan -ExpectedItems $items -ColumnCount 6 -RowCount 4 } | Should -Not -Throw
    }

    It 'wraps applications downward while keeping column zero empty' {
        $items = @((New-TestItem -Name 'Recycle Bin' -CanonicalIdentity 'recycle' -Category 'RecycleBin'))
        1..5 | ForEach-Object { $items += New-TestItem -Name "App $_" -CanonicalIdentity "app-$_" -Category 'Application' }
        $plan = New-DesktopLayoutPlan -Items $items -ColumnCount 4 -RowCount 4 -OriginX 0 -OriginY 0 -SpacingX 80 -SpacingY 80
        ($plan | Where-Object CanonicalIdentity -eq 'app-4').Row | Should -Be 1
        ($plan | Where-Object CanonicalIdentity -eq 'app-4').Column | Should -Be 1
        @($plan | Where-Object { $_.Column -eq 0 -and $_.CanonicalIdentity -ne 'recycle' }).Count | Should -Be 0
    }

    It 'grows bottom rows upward' {
        $items = @((New-TestItem -Name 'Recycle Bin' -CanonicalIdentity 'recycle' -Category 'RecycleBin'))
        1..7 | ForEach-Object { $items += New-TestItem -Name "Bottom $_" -CanonicalIdentity "bottom-$_" -Category 'Bottom' }
        $plan = New-DesktopLayoutPlan -Items $items -ColumnCount 5 -RowCount 4 -OriginX 0 -OriginY 0 -SpacingX 80 -SpacingY 80
        @($plan | Where-Object { $_.Category -eq 'Bottom' -and $_.Row -eq 3 }).Count | Should -Be 4
        @($plan | Where-Object { $_.Category -eq 'Bottom' -and $_.Row -eq 2 }).Count | Should -Be 3
    }

    It 'uses every unoccupied cell on the right edge before moving inward' {
        $items = @(
            (New-TestItem -Name 'Recycle Bin' -CanonicalIdentity 'recycle' -Category 'RecycleBin'),
            (New-TestItem -Name 'App' -CanonicalIdentity 'app' -Category 'Application'),
            (New-TestItem -Name 'Bottom' -CanonicalIdentity 'bottom' -Category 'Bottom')
        )
        1..4 | ForEach-Object { $items += New-TestItem -Name "Right $_" -CanonicalIdentity "right-$_" -Category 'Right' }
        $plan = New-DesktopLayoutPlan -Items $items -ColumnCount 4 -RowCount 4 -OriginX 0 -OriginY 0 -SpacingX 80 -SpacingY 80
        ($plan | Where-Object CanonicalIdentity -eq 'right-1').Column | Should -Be 3
        ($plan | Where-Object CanonicalIdentity -eq 'right-1').Row | Should -Be 0
        ($plan | Where-Object CanonicalIdentity -eq 'right-4').Column | Should -Be 3
        ($plan | Where-Object CanonicalIdentity -eq 'right-4').Row | Should -Be 3
    }

    It 'skips occupied top and bottom cells while filling the right edge inward' {
        $items = @((New-TestItem -Name 'Recycle Bin' -CanonicalIdentity 'recycle' -Category 'RecycleBin'))
        1..3 | ForEach-Object { $items += New-TestItem -Name "App $_" -CanonicalIdentity "app-$_" -Category 'Application' }
        1..3 | ForEach-Object { $items += New-TestItem -Name "Bottom $_" -CanonicalIdentity "bottom-$_" -Category 'Bottom' }
        1..4 | ForEach-Object { $items += New-TestItem -Name "Right $_" -CanonicalIdentity "right-$_" -Category 'Right' }

        $plan = New-DesktopLayoutPlan -Items $items -ColumnCount 4 -RowCount 4 -OriginX 0 -OriginY 0 -SpacingX 80 -SpacingY 80
        ($plan | Where-Object CanonicalIdentity -eq 'right-1').Column | Should -Be 3
        ($plan | Where-Object CanonicalIdentity -eq 'right-1').Row | Should -Be 1
        ($plan | Where-Object CanonicalIdentity -eq 'right-2').Column | Should -Be 3
        ($plan | Where-Object CanonicalIdentity -eq 'right-2').Row | Should -Be 2
        ($plan | Where-Object CanonicalIdentity -eq 'right-3').Column | Should -Be 2
        ($plan | Where-Object CanonicalIdentity -eq 'right-3').Row | Should -Be 1
        ($plan | Where-Object CanonicalIdentity -eq 'right-4').Column | Should -Be 2
        ($plan | Where-Object CanonicalIdentity -eq 'right-4').Row | Should -Be 2
        { Test-DesktopLayoutPlan -Plan $plan -ExpectedItems $items -ColumnCount 4 -RowCount 4 } | Should -Not -Throw
    }

    It 'fails before returning a partial plan when perimeter capacity is insufficient' {
        $items = @((New-TestItem -Name 'Recycle Bin' -CanonicalIdentity 'recycle' -Category 'RecycleBin'))
        1..10 | ForEach-Object { $items += New-TestItem -Name "App $_" -CanonicalIdentity "app-$_" -Category 'Application' }
        { New-DesktopLayoutPlan -Items $items -ColumnCount 3 -RowCount 2 -OriginX 0 -OriginY 0 -SpacingX 80 -SpacingY 80 } | Should -Throw
    }

    It 'rejects a plan that silently omits an expected item' {
        $items = @(
            (New-TestItem -Name 'Recycle Bin' -CanonicalIdentity 'recycle' -Category 'RecycleBin'),
            (New-TestItem -Name 'One' -CanonicalIdentity 'one' -Category 'Application'),
            (New-TestItem -Name 'Two' -CanonicalIdentity 'two' -Category 'Right')
        )
        $partial = @(
            [pscustomobject]@{ CanonicalIdentity = 'recycle'; Category = 'RecycleBin'; Column = 0; Row = 0 },
            [pscustomobject]@{ CanonicalIdentity = 'one'; Category = 'Application'; Column = 1; Row = 0 }
        )
        { Test-DesktopLayoutPlan -Plan $partial -ExpectedItems $items -ColumnCount 4 -RowCount 4 } | Should -Throw
    }
}

Describe 'Desktop grid geometry' {
    It 'reserves a complete spacing cell inside each margin' {
        $snapshot = [pscustomobject]@{
            Left = 0; Top = 0; Width = 616; Height = 416; SpacingX = 100; SpacingY = 100
        }
        $geometry = Get-DesktopGridGeometry -Snapshot $snapshot -Margin 8
        $geometry.ColumnCount | Should -Be 6
        $geometry.RowCount | Should -Be 4
        $geometry.OriginX | Should -Be 8
        $geometry.OriginY | Should -Be 8
    }

    It 'does not count a partial trailing cell' {
        $snapshot = [pscustomobject]@{
            Left = 0; Top = 0; Width = 615; Height = 415; SpacingX = 100; SpacingY = 100
        }
        $geometry = Get-DesktopGridGeometry -Snapshot $snapshot -Margin 8
        $geometry.ColumnCount | Should -Be 5
        $geometry.RowCount | Should -Be 3
    }
}

Describe 'Backup and restore planning' {
    It 'round-trips a timestamped backup and latest manifest' {
        $items = @(
            (New-TestItem -Name 'One' -CanonicalIdentity 'one' -X 10 -Y 20),
            (New-TestItem -Name 'Two' -CanonicalIdentity 'two' -X 30 -Y 40)
        )
        $path = Write-DesktopLayoutBackup -Items $items -BackupRoot $TestDrive
        Test-Path -LiteralPath $path | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $TestDrive 'latest.json') | Should -BeTrue
        (Get-LatestDesktopLayoutBackup -BackupRoot $TestDrive) | Should -Be $path
        $entries = Read-DesktopLayoutBackup -Path $path
        $entries.Count | Should -Be 2
        ($entries | Where-Object CanonicalIdentity -eq 'two').X | Should -Be 30
        ($entries | Where-Object CanonicalIdentity -eq 'two').Y | Should -Be 40
    }

    It 'rejects malformed backups' {
        $path = Join-Path $TestDrive 'bad.json'
        [System.IO.File]::WriteAllText($path, '{"SchemaVersion":1,"Items":[{"CanonicalIdentity":"","X":"bad","Y":1}]}')
        { Read-DesktopLayoutBackup -Path $path } | Should -Throw
    }

    It 'rejects a latest manifest that points outside the backup directory' {
        $manifestPath = Join-Path $TestDrive 'latest.json'
        [System.IO.File]::WriteAllText(
            $manifestPath,
            '{"SchemaVersion":1,"BackupFile":"..\\outside.json"}'
        )
        { Get-LatestDesktopLayoutBackup -BackupRoot $TestDrive } | Should -Throw
    }

    It 'matches restore entries by canonical identity and skips missing items' {
        $current = @(
            (New-TestItem -Name 'One' -CanonicalIdentity 'ONE'),
            (New-TestItem -Name 'New' -CanonicalIdentity 'new')
        )
        $backup = @(
            [pscustomobject]@{ DisplayName = 'One'; CanonicalIdentity = 'one'; X = 10; Y = 20 },
            [pscustomobject]@{ DisplayName = 'Gone'; CanonicalIdentity = 'gone'; X = 30; Y = 40 }
        )
        $restore = New-RestorePlan -CurrentItems $current -BackupEntries $backup
        $restore.Requests.Count | Should -Be 1
        $restore.Requests[0].CanonicalIdentity | Should -Be 'ONE'
        $restore.Requests[0].X | Should -Be 10
        $restore.Skipped.Count | Should -Be 1
        $restore.Skipped[0] | Should -Be 'gone'
    }
}

Describe 'One-shot command orchestration' {
    BeforeEach {
        $script:CommandCallLog = New-Object 'System.Collections.Generic.List[string]'
        $script:AppliedEntries = @()
        $script:LastDesktopEdgeArrangerBackup = $null
        $script:SnapshotForCommandTest = [pscustomobject]@{
            MonitorCount = 1
            Left = 0
            Top = 0
            Width = 1200
            Height = 800
            SpacingX = 100
            SpacingY = 100
            Items = @(
                (New-TestItem -Name 'Recycle Bin' -CanonicalIdentity '::{645FF040-5081-101B-9F08-00AA002F954E}' -X 0 -Y 0),
                (New-TestItem -Name 'Editor.exe' -CanonicalIdentity 'C:\Desktop\Editor.exe' -Path 'C:\Desktop\Editor.exe' -X 100 -Y 100),
                (New-TestItem -Name 'Track.mp3' -CanonicalIdentity 'C:\Desktop\Track.mp3' -Path 'C:\Desktop\Track.mp3' -X 200 -Y 200),
                (New-TestItem -Name 'Notes.txt' -CanonicalIdentity 'C:\Desktop\Notes.txt' -Path 'C:\Desktop\Notes.txt' -X 300 -Y 300)
            )
        }

        Mock Assert-DesktopEdgeArrangerEnvironment {
            [void]$script:CommandCallLog.Add('environment')
        }
        Mock Get-DesktopEdgeArrangerBackupRoot { $TestDrive }
        Mock Get-DesktopShellSnapshot {
            [void]$script:CommandCallLog.Add('snapshot')
            return $script:SnapshotForCommandTest
        }
        Mock Write-DesktopLayoutBackup {
            [void]$script:CommandCallLog.Add('backup')
            return (Join-Path $TestDrive 'backup.json')
        }
        Mock Disable-DesktopAutoArrange {
            [void]$script:CommandCallLog.Add('disable')
        }
        Mock Set-DesktopIconPositions {
            param($Entries)
            [void]$script:CommandCallLog.Add('apply')
            $script:AppliedEntries = @($Entries)
        }
    }

    It 'backs up before disabling auto-arrange and applies exactly once' {
        Invoke-DesktopEdgeArranger -Mode Arrange

        ($script:CommandCallLog -join ',') | Should -Be 'environment,snapshot,backup,disable,apply'
        Assert-MockCalled Write-DesktopLayoutBackup -Times 1 -Exactly
        Assert-MockCalled Disable-DesktopAutoArrange -Times 1 -Exactly
        Assert-MockCalled Set-DesktopIconPositions -Times 1 -Exactly
        $script:AppliedEntries.Count | Should -Be 4
        @($script:AppliedEntries | Where-Object Category -eq 'RecycleBin').Count | Should -Be 1
    }

    It 'does not mutate Explorer when verified backup creation fails' {
        Mock Write-DesktopLayoutBackup {
            [void]$script:CommandCallLog.Add('backup')
            throw 'simulated backup failure'
        }

        { Invoke-DesktopEdgeArranger -Mode Arrange } | Should -Throw

        ($script:CommandCallLog -join ',') | Should -Be 'environment,snapshot,backup'
        Assert-MockCalled Disable-DesktopAutoArrange -Times 0 -Exactly
        Assert-MockCalled Set-DesktopIconPositions -Times 0 -Exactly
    }

    It 'restores matching identities once and leaves unmatched current items alone' {
        Mock Get-LatestDesktopLayoutBackup {
            [void]$script:CommandCallLog.Add('latest')
            return (Join-Path $TestDrive 'backup.json')
        }
        Mock Read-DesktopLayoutBackup {
            [void]$script:CommandCallLog.Add('read')
            return @(
                [pscustomobject]@{ DisplayName = 'Editor.exe'; CanonicalIdentity = 'c:\desktop\editor.exe'; X = 11; Y = 22 },
                [pscustomobject]@{ DisplayName = 'Missing'; CanonicalIdentity = 'c:\desktop\missing.txt'; X = 33; Y = 44 }
            )
        }

        Invoke-DesktopEdgeArranger -Mode Restore

        ($script:CommandCallLog -join ',') | Should -Be 'environment,snapshot,latest,read,disable,apply'
        Assert-MockCalled Write-DesktopLayoutBackup -Times 0 -Exactly
        Assert-MockCalled Set-DesktopIconPositions -Times 1 -Exactly
        $script:AppliedEntries.Count | Should -Be 1
        $script:AppliedEntries[0].CanonicalIdentity | Should -Be 'C:\Desktop\Editor.exe'
        $script:AppliedEntries[0].X | Should -Be 11
        $script:AppliedEntries[0].Y | Should -Be 22
        $script:LastDesktopEdgeArrangerBackup | Should -Be (Join-Path $TestDrive 'backup.json')
    }

    It 'does not mutate Explorer when no current icon matches a restore backup' {
        Mock Get-LatestDesktopLayoutBackup { Join-Path $TestDrive 'backup.json' }
        Mock Read-DesktopLayoutBackup {
            @([pscustomobject]@{ DisplayName = 'Missing'; CanonicalIdentity = 'missing'; X = 1; Y = 2 })
        }

        { Invoke-DesktopEdgeArranger -Mode Restore } | Should -Throw

        Assert-MockCalled Disable-DesktopAutoArrange -Times 0 -Exactly
        Assert-MockCalled Set-DesktopIconPositions -Times 0 -Exactly
    }

    It 'aborts a multi-monitor snapshot before backup or mutation' {
        $script:SnapshotForCommandTest.MonitorCount = 2

        { Invoke-DesktopEdgeArranger -Mode Arrange } | Should -Throw

        Assert-MockCalled Write-DesktopLayoutBackup -Times 0 -Exactly
        Assert-MockCalled Disable-DesktopAutoArrange -Times 0 -Exactly
        Assert-MockCalled Set-DesktopIconPositions -Times 0 -Exactly
    }
}
