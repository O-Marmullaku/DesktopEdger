<#
.SYNOPSIS
    Arranges Windows desktop icons once and exits.

.DESCRIPTION
    Changes only Explorer's visual desktop-icon coordinates. It never moves,
    renames, copies, edits, or deletes the underlying desktop files, folders,
    shortcuts, or their contents.

    Arrange and Restore are one-shot operations. This script installs no
    watcher, service, scheduled task, startup entry, event subscription, or
    background loop.
#>
#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Arrange', 'Restore')]
    [string]$Mode = 'Arrange'
)

# Hybrid classification overrides. Each value can be an icon display name,
# canonical Shell identity, filesystem path, resolved shortcut target, shortcut
# argument string, or URL. Matching is case-insensitive. Keep each item in only
# one override array.
$ForceApplication = @()
$ForceGame = @()
$ForceMusic = @()
$ForceRight = @()

$script:RecycleBinCanonicalGuid = '645FF040-5081-101B-9F08-00AA002F954E'
$script:MusicExtensions = @('.mp3', '.wav', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wma')
$script:ApplicationExtensions = @('.exe', '.com', '.msc', '.cpl', '.appref-ms', '.application', '.jar')
$script:LastDesktopEdgeArrangerBackup = $null

#region General helpers

function Get-ObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [object]$Default = $null
    )

    if ($null -eq $InputObject) {
        return $Default
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function ConvertTo-NormalizedOverrideToken {
    [CmdletBinding()]
    param([AllowNull()][object]$Token)

    if ($null -eq $Token) {
        return $null
    }

    $text = [Environment]::ExpandEnvironmentVariables(([string]$Token)).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text
}

#endregion General helpers

#region Classification and overrides

function Add-OverrideTokens {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map,

        [AllowNull()]
        [string[]]$Tokens,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Application', 'Bottom', 'Right')]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$SourceName
    )

    foreach ($token in @($Tokens)) {
        $normalized = ConvertTo-NormalizedOverrideToken -Token $token
        if ($null -eq $normalized) {
            continue
        }

        if ($Map.ContainsKey($normalized)) {
            $existing = $Map[$normalized]
            if ([string]$existing.Source -ne $SourceName) {
                throw "Override '$normalized' occurs in both '$($existing.Source)' and '$SourceName'. Keep each override in only one list."
            }
            continue
        }

        $Map[$normalized] = [pscustomobject][ordered]@{
            Category = $Category
            Source   = $SourceName
        }
    }
}

function New-OverrideMap {
    [CmdletBinding()]
    param(
        [AllowNull()][string[]]$ForceApplication = @(),
        [AllowNull()][string[]]$ForceGame = @(),
        [AllowNull()][string[]]$ForceMusic = @(),
        [AllowNull()][string[]]$ForceRight = @()
    )

    # PowerShell hashtable string keys are case-insensitive by default.
    $map = @{}
    Add-OverrideTokens -Map $map -Tokens $ForceApplication -Category 'Application' -SourceName 'ForceApplication'
    Add-OverrideTokens -Map $map -Tokens $ForceGame -Category 'Bottom' -SourceName 'ForceGame'
    Add-OverrideTokens -Map $map -Tokens $ForceMusic -Category 'Bottom' -SourceName 'ForceMusic'
    Add-OverrideTokens -Map $map -Tokens $ForceRight -Category 'Right' -SourceName 'ForceRight'
    return $map
}

function Get-DesktopItemIdentityCandidates {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Item)

    $propertyNames = @(
        'DisplayName',
        'CanonicalIdentity',
        'FileSystemPath',
        'ShortcutTarget',
        'ShortcutArguments',
        'ShortcutWorkingDirectory',
        'Url'
    )

    $seen = @{}
    foreach ($propertyName in $propertyNames) {
        $candidate = ConvertTo-NormalizedOverrideToken -Token (Get-ObjectPropertyValue -InputObject $Item -Name $propertyName)
        if ($null -ne $candidate -and -not $seen.ContainsKey($candidate)) {
            $seen[$candidate] = $true
            $candidate
        }
    }
}

function Get-DesktopItemOverrideCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][hashtable]$OverrideMap
    )

    $matchedSources = @{}
    $matchedCategory = $null

    foreach ($candidate in @(Get-DesktopItemIdentityCandidates -Item $Item)) {
        if (-not $OverrideMap.ContainsKey($candidate)) {
            continue
        }

        $match = $OverrideMap[$candidate]
        $source = [string]$match.Source
        $category = [string]$match.Category
        $matchedSources[$source] = $true

        if ($null -eq $matchedCategory) {
            $matchedCategory = $category
        }
        elseif ($matchedCategory -ne $category) {
            $displayName = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'DisplayName' -Default '<unnamed>')
            throw "Desktop item '$displayName' matches override identities assigned to different layout categories."
        }
    }

    if ($matchedSources.Count -gt 1) {
        $displayName = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'DisplayName' -Default '<unnamed>')
        $sourceList = (@($matchedSources.Keys) | Sort-Object) -join ', '
        throw "Desktop item '$displayName' matches more than one override list: $sourceList. Keep it in only one list."
    }

    return $matchedCategory
}

function Test-OverrideConfiguration {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Items = @(),
        [AllowNull()][hashtable]$OverrideMap,
        [AllowNull()][string[]]$ForceApplication = @(),
        [AllowNull()][string[]]$ForceGame = @(),
        [AllowNull()][string[]]$ForceMusic = @(),
        [AllowNull()][string[]]$ForceRight = @()
    )

    if ($null -eq $OverrideMap) {
        $OverrideMap = New-OverrideMap `
            -ForceApplication $ForceApplication `
            -ForceGame $ForceGame `
            -ForceMusic $ForceMusic `
            -ForceRight $ForceRight
    }

    foreach ($item in @($Items)) {
        [void](Get-DesktopItemOverrideCategory -Item $item -OverrideMap $OverrideMap)
    }

    return $true
}

function Get-DesktopItemEffectiveExtension {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Item)

    foreach ($value in @(
        (Get-ObjectPropertyValue -InputObject $Item -Name 'ShortcutTarget'),
        (Get-ObjectPropertyValue -InputObject $Item -Name 'FileSystemPath')
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            continue
        }

        try {
            $extension = [IO.Path]::GetExtension([string]$value)
            if (-not [string]::IsNullOrWhiteSpace($extension)) {
                return $extension.ToLowerInvariant()
            }
        }
        catch {
            # Some Shell parsing names are not filesystem paths. Later rules
            # handle those identities without treating this as an error.
        }
    }

    return ([string](Get-ObjectPropertyValue -InputObject $Item -Name 'Extension' -Default '')).ToLowerInvariant()
}

function Test-IsRecycleBinItem {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Item)

    $canonical = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'CanonicalIdentity' -Default '')
    return $canonical.IndexOf($script:RecycleBinCanonicalGuid, [StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Test-IsMusicItem {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Item)

    return $script:MusicExtensions -contains (Get-DesktopItemEffectiveExtension -Item $Item)
}

function Test-IsGameItem {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Item)

    $target = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'ShortcutTarget' -Default '')
    $arguments = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'ShortcutArguments' -Default '')
    $workingDirectory = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'ShortcutWorkingDirectory' -Default '')
    $url = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'Url' -Default '')
    $canonical = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'CanonicalIdentity' -Default '')

    $launchText = @($arguments, $url, $canonical) -join "`n"
    $launchPatterns = @(
        '(?i)steam://(?:run|rungameid|launch)|-applaunch\s+\d+',
        '(?i)com\.epicgames\.launcher://apps/.+?(?:action=launch|%3Faction%3Dlaunch)',
        '(?i)origin://|link2ea:',
        '(?i)goggalaxy://(?:openGameView|launch)/',
        '(?i)uplay://launch/',
        '(?i)rockstar://launch/',
        '(?i)battlenet://(?:game|launch)/',
        '(?i)riotclient://|--launch-product(?:=|\s+)[^\s]+',
        '(?i)ms-xbl-|xbox://'
    )
    foreach ($pattern in $launchPatterns) {
        if ($launchText -match $pattern) {
            return $true
        }
    }

    # Direct game executables commonly live in launcher-managed install roots.
    # Exclude the launcher/client executables themselves so a bare Steam, Epic,
    # EA, GOG, Ubisoft, Rockstar, Battle.net, or Riot launcher stays with apps.
    $pathText = @($target, $workingDirectory, $canonical) -join "`n"
    $installPatterns = @(
        '(?i)[\\/]steamapps[\\/](?:common|sourcemods)[\\/]',
        '(?i)[\\/]Epic Games[\\/](?!Launcher(?:[\\/]|$))[^\r\n]+',
        '(?i)[\\/](?:EA Games|Origin Games)[\\/](?!EA Desktop(?:[\\/]|$))[^\r\n]+',
        '(?i)[\\/]GOG Games[\\/][^\r\n]+',
        '(?i)[\\/]Ubisoft Games[\\/][^\r\n]+',
        '(?i)[\\/]Ubisoft[\\/]Ubisoft Game Launcher[\\/]games[\\/][^\r\n]+',
        '(?i)[\\/]Rockstar Games[\\/](?!Launcher(?:[\\/]|$)|Social Club(?:[\\/]|$))[^\r\n]+',
        '(?i)[\\/]Battle\.net[\\/](?!Battle\.net(?: Launcher)?\.exe(?:\r?$|[\r\n]))[^\r\n]+',
        '(?i)[\\/]Riot Games[\\/](?!Riot Client(?:[\\/]|$))[^\r\n]+',
        '(?i)[\\/]XboxGames[\\/][^\r\n]+'
    )
    foreach ($pattern in $installPatterns) {
        if ($pathText -match $pattern) {
            return $true
        }
    }

    return $false
}

function Test-IsApplicationProtocol {
    [CmdletBinding()]
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z][A-Za-z0-9+.-]*:') {
        return $false
    }

    $scheme = $Value.Substring(0, $Value.IndexOf(':')).ToLowerInvariant()
    return @('http', 'https', 'ftp', 'file', 'mailto') -notcontains $scheme
}

function Test-IsApplicationItem {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Item)

    $target = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'ShortcutTarget' -Default '')
    $path = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'FileSystemPath' -Default '')
    $url = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'Url' -Default '')
    $canonical = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'CanonicalIdentity' -Default '')

    foreach ($candidate in @($target, $path)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            if ($script:ApplicationExtensions -contains [IO.Path]::GetExtension($candidate).ToLowerInvariant()) {
                return $true
            }
        }
        catch {
            # Continue with URL and Shell parsing-name rules.
        }
    }

    if (Test-IsApplicationProtocol -Value $url) {
        return $true
    }

    if ($canonical -match '(?i)^shell:AppsFolder' -or $canonical -match '(?i)\\Applications\\') {
        return $true
    }

    return $false
}

function Get-DesktopItemCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [AllowNull()][hashtable]$OverrideMap = @{}
    )

    if (Test-IsRecycleBinItem -Item $Item) {
        return 'RecycleBin'
    }

    $override = Get-DesktopItemOverrideCategory -Item $Item -OverrideMap $OverrideMap
    if ($null -ne $override) {
        return $override
    }

    if ([bool](Get-ObjectPropertyValue -InputObject $Item -Name 'IsFolder' -Default $false)) {
        return 'Right'
    }

    if (Test-IsMusicItem -Item $Item) {
        return 'Bottom'
    }

    if (Test-IsGameItem -Item $Item) {
        return 'Bottom'
    }

    if (Test-IsApplicationItem -Item $Item) {
        return 'Application'
    }

    return 'Right'
}

function Add-DesktopItemCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][hashtable]$OverrideMap
    )

    $properties = [ordered]@{}
    foreach ($property in $Item.PSObject.Properties) {
        $properties[$property.Name] = $property.Value
    }
    $properties['Category'] = Get-DesktopItemCategory -Item $Item -OverrideMap $OverrideMap
    return [pscustomobject]$properties
}

#endregion Classification and overrides

#region Deterministic layout planner

function Get-SortedDesktopItems {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Items = @())

    return @($Items | Sort-Object -Property `
        @{ Expression = { [string](Get-ObjectPropertyValue -InputObject $_ -Name 'DisplayName' -Default '') }; Ascending = $true }, `
        @{ Expression = { [string](Get-ObjectPropertyValue -InputObject $_ -Name 'CanonicalIdentity' -Default '') }; Ascending = $true })
}

function Test-DesktopLayoutPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Plan,
        [AllowNull()][object[]]$ExpectedItems = @(),
        [Parameter(Mandatory = $true)][ValidateRange(3, 10000)][int]$ColumnCount,
        [Parameter(Mandatory = $true)][ValidateRange(2, 10000)][int]$RowCount
    )

    $cells = @{}
    $identities = @{}
    $recycleCount = 0

    foreach ($entry in @($Plan)) {
        $identity = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'CanonicalIdentity' -Default '')
        $category = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'Category' -Default '')
        $column = [int](Get-ObjectPropertyValue -InputObject $entry -Name 'Column' -Default -1)
        $row = [int](Get-ObjectPropertyValue -InputObject $entry -Name 'Row' -Default -1)

        if ([string]::IsNullOrWhiteSpace($identity)) {
            throw 'A layout-plan entry has no canonical identity.'
        }
        if ($identities.ContainsKey($identity)) {
            throw "Canonical identity '$identity' occurs more than once in the layout plan."
        }
        $identities[$identity] = $true

        if ($column -lt 0 -or $column -ge $ColumnCount -or $row -lt 0 -or $row -ge $RowCount) {
            throw "Layout-plan cell ($column,$row) is outside the desktop grid."
        }
        if ($column -eq 0 -and $row -ne 0) {
            throw "Layout-plan cell ($column,$row) violates the empty left-column rule."
        }

        $cellKey = "$column,$row"
        if ($cells.ContainsKey($cellKey)) {
            throw "More than one item occupies layout-plan cell ($column,$row)."
        }
        $cells[$cellKey] = $true

        if ($category -eq 'RecycleBin') {
            $recycleCount++
            if ($column -ne 0 -or $row -ne 0) {
                throw 'Recycle Bin must occupy grid cell (0,0).'
            }
        }
        elseif ($column -eq 0 -and $row -eq 0) {
            throw 'Only Recycle Bin may occupy grid cell (0,0).'
        }
    }

    if ($recycleCount -ne 1) {
        throw "The layout plan must contain exactly one Recycle Bin entry; found $recycleCount."
    }

    if (@($ExpectedItems).Count -gt 0) {
        $expectedIdentities = @{}
        foreach ($expected in @($ExpectedItems)) {
            $identity = [string](Get-ObjectPropertyValue -InputObject $expected -Name 'CanonicalIdentity' -Default '')
            if ([string]::IsNullOrWhiteSpace($identity)) {
                throw 'An expected desktop item has no canonical identity.'
            }
            if ($expectedIdentities.ContainsKey($identity)) {
                throw "Expected desktop items contain duplicate canonical identity '$identity'."
            }
            $expectedIdentities[$identity] = $true
        }

        if ($expectedIdentities.Count -ne $identities.Count) {
            throw "Layout plan contains $($identities.Count) item(s), but $($expectedIdentities.Count) were expected."
        }
        foreach ($identity in $expectedIdentities.Keys) {
            if (-not $identities.ContainsKey($identity)) {
                throw "Layout plan is missing expected desktop item '$identity'."
            }
        }
    }

    return $true
}

function New-DesktopLayoutPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Items,
        [Parameter(Mandatory = $true)][ValidateRange(3, 10000)][int]$ColumnCount,
        [Parameter(Mandatory = $true)][ValidateRange(2, 10000)][int]$RowCount,
        [Parameter(Mandatory = $true)][int]$OriginX,
        [Parameter(Mandatory = $true)][int]$OriginY,
        [Parameter(Mandatory = $true)][ValidateRange(1, 10000)][int]$SpacingX,
        [Parameter(Mandatory = $true)][ValidateRange(1, 10000)][int]$SpacingY
    )

    $allItems = @($Items)
    $allowedCategories = @('RecycleBin', 'Application', 'Bottom', 'Right')
    $inputIdentities = @{}

    foreach ($item in $allItems) {
        $identity = [string](Get-ObjectPropertyValue -InputObject $item -Name 'CanonicalIdentity' -Default '')
        $category = [string](Get-ObjectPropertyValue -InputObject $item -Name 'Category' -Default '')
        $name = [string](Get-ObjectPropertyValue -InputObject $item -Name 'DisplayName' -Default '<unnamed>')

        if ([string]::IsNullOrWhiteSpace($identity)) {
            throw "Desktop item '$name' has no canonical identity."
        }
        if ($inputIdentities.ContainsKey($identity)) {
            throw "Desktop items contain duplicate canonical identity '$identity'."
        }
        $inputIdentities[$identity] = $true

        if ($allowedCategories -notcontains $category) {
            throw "Desktop item '$name' has unsupported category '$category'."
        }
    }

    # Force array shape at the assignment boundary. Windows PowerShell 5.1
    # can expose singleton PSCustomObject .Count as $null, which would make
    # one-item categories look empty to the planner.
    $recycleItems = @(Get-SortedDesktopItems -Items @($allItems | Where-Object { $_.Category -eq 'RecycleBin' }))
    $applicationItems = @(Get-SortedDesktopItems -Items @($allItems | Where-Object { $_.Category -eq 'Application' }))
    $bottomItems = @(Get-SortedDesktopItems -Items @($allItems | Where-Object { $_.Category -eq 'Bottom' }))
    $rightItems = @(Get-SortedDesktopItems -Items @($allItems | Where-Object { $_.Category -eq 'Right' }))

    if ($recycleItems.Count -ne 1) {
        throw "Exactly one visible Recycle Bin is required; detected $($recycleItems.Count). Enable the Recycle Bin desktop icon and run again."
    }

    $usableColumns = $ColumnCount - 1
    $bottomRowCount = 0
    if ($bottomItems.Count -gt 0) {
        $bottomRowCount = [int][Math]::Ceiling($bottomItems.Count / [double]$usableColumns)
    }
    if ($bottomRowCount -gt $RowCount) {
        throw 'Desktop layout capacity is insufficient for the games/music band.'
    }

    $applicationRowsAvailable = $RowCount - $bottomRowCount
    if ($applicationItems.Count -gt ($applicationRowsAvailable * $usableColumns)) {
        throw 'Desktop layout capacity is insufficient for the application band while preserving the bottom band.'
    }

    $plan = New-Object 'System.Collections.Generic.List[object]'
    $occupied = @{}

    $addEntry = {
        param([object]$Item, [int]$Column, [int]$Row)

        $cellKey = "$Column,$Row"
        if ($occupied.ContainsKey($cellKey)) {
            $name = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'DisplayName' -Default '<unnamed>')
            throw "Desktop layout collision while placing '$name' at cell ($Column,$Row)."
        }

        $occupied[$cellKey] = $true
        [void]$plan.Add([pscustomobject][ordered]@{
            CanonicalIdentity = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'CanonicalIdentity' -Default '')
            DisplayName       = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'DisplayName' -Default '')
            Category          = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'Category' -Default '')
            Column            = $Column
            Row               = $Row
            X                 = $OriginX + ($Column * $SpacingX)
            Y                 = $OriginY + ($Row * $SpacingY)
        })
    }

    & $addEntry $recycleItems[0] 0 0

    for ($index = 0; $index -lt $applicationItems.Count; $index++) {
        $row = [int][Math]::Floor($index / [double]$usableColumns)
        $column = 1 + ($index % $usableColumns)
        & $addEntry $applicationItems[$index] $column $row
    }

    $bottomOffset = 0
    for ($bottomBandIndex = 0; $bottomBandIndex -lt $bottomRowCount; $bottomBandIndex++) {
        $row = ($RowCount - 1) - $bottomBandIndex
        $remaining = $bottomItems.Count - $bottomOffset
        $chunkCount = [Math]::Min($usableColumns, $remaining)
        $startColumn = 1 + [int][Math]::Floor(($usableColumns - $chunkCount) / 2.0)

        for ($columnOffset = 0; $columnOffset -lt $chunkCount; $columnOffset++) {
            & $addEntry $bottomItems[$bottomOffset + $columnOffset] ($startColumn + $columnOffset) $row
        }
        $bottomOffset += $chunkCount
    }

    $rightIndex = 0
    for ($column = $ColumnCount - 1; $column -ge 1 -and $rightIndex -lt $rightItems.Count; $column--) {
        for ($row = 0; $row -lt $RowCount -and $rightIndex -lt $rightItems.Count; $row++) {
            $cellKey = "$column,$row"
            if ($occupied.ContainsKey($cellKey)) {
                continue
            }

            & $addEntry $rightItems[$rightIndex] $column $row
            $rightIndex++
        }
    }

    if ($rightIndex -ne $rightItems.Count) {
        throw "Desktop layout capacity is insufficient for right-edge items: placed $rightIndex of $($rightItems.Count)."
    }

    $result = $plan.ToArray()
    [void](Test-DesktopLayoutPlan -Plan $result -ExpectedItems $allItems -ColumnCount $ColumnCount -RowCount $RowCount)
    return ,$result
}

function Get-DesktopGridGeometry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Snapshot,
        [ValidateRange(0, 100)][int]$Margin = 8
    )

    $width = [int](Get-ObjectPropertyValue -InputObject $Snapshot -Name 'Width' -Default 0)
    $height = [int](Get-ObjectPropertyValue -InputObject $Snapshot -Name 'Height' -Default 0)
    $left = [int](Get-ObjectPropertyValue -InputObject $Snapshot -Name 'Left' -Default 0)
    $top = [int](Get-ObjectPropertyValue -InputObject $Snapshot -Name 'Top' -Default 0)
    $spacingX = [int](Get-ObjectPropertyValue -InputObject $Snapshot -Name 'SpacingX' -Default 0)
    $spacingY = [int](Get-ObjectPropertyValue -InputObject $Snapshot -Name 'SpacingY' -Default 0)

    if ($width -le 0 -or $height -le 0 -or $spacingX -le 0 -or $spacingY -le 0) {
        throw 'Explorer returned invalid desktop bounds or icon spacing.'
    }

    $usableWidth = $width - (2 * $Margin)
    $usableHeight = $height - (2 * $Margin)
    if ($usableWidth -le 0 -or $usableHeight -le 0) {
        throw 'The desktop work area is smaller than the configured layout margin.'
    }

    $columns = [int][Math]::Floor($usableWidth / [double]$spacingX)
    $rows = [int][Math]::Floor($usableHeight / [double]$spacingY)

    if ($columns -lt 3 -or $rows -lt 2) {
        throw "The desktop view is too small for edge placement ($columns column(s), $rows row(s))."
    }

    return [pscustomobject][ordered]@{
        ColumnCount = $columns
        RowCount    = $rows
        OriginX     = $left + $Margin
        OriginY     = $top + $Margin
        SpacingX    = $spacingX
        SpacingY    = $spacingY
    }
}

#endregion Deterministic layout planner

#region Backup and restore data service

function ConvertTo-ValidatedBackupEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Entry)

    $identity = [string](Get-ObjectPropertyValue -InputObject $Entry -Name 'CanonicalIdentity' -Default '')
    if ([string]::IsNullOrWhiteSpace($identity)) {
        throw 'A backup entry has no canonical identity.'
    }

    $x = 0
    $y = 0
    $rawX = Get-ObjectPropertyValue -InputObject $Entry -Name 'X'
    $rawY = Get-ObjectPropertyValue -InputObject $Entry -Name 'Y'
    if ($null -eq $rawX -or -not [int]::TryParse([string]$rawX, [ref]$x) -or
        $null -eq $rawY -or -not [int]::TryParse([string]$rawY, [ref]$y)) {
        throw "Backup entry '$identity' has invalid coordinates."
    }

    return [pscustomobject][ordered]@{
        CanonicalIdentity = $identity
        DisplayName       = [string](Get-ObjectPropertyValue -InputObject $Entry -Name 'DisplayName' -Default '')
        X                 = $x
        Y                 = $y
    }
}

function Write-Utf8JsonAtomically {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateRange(2, 20)][int]$Depth = 6
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($fullPath)
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "Cannot determine the directory for '$Path'."
    }
    if (-not [IO.Directory]::Exists($directory)) {
        [void][IO.Directory]::CreateDirectory($directory)
    }

    $json = $Value | ConvertTo-Json -Depth $Depth
    $baseName = [IO.Path]::GetFileName($fullPath)
    $temporaryPath = Join-Path $directory ('.' + $baseName + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    # Do not pass PowerShell $null to the File.Replace string backup-path
    # parameter. Windows PowerShell 5.1 can bind it as an empty string, which
    # .NET rejects as an illegal path. A real sibling backup path keeps the
    # replacement atomic and is deleted immediately after a successful swap.
    $replacementBackupPath = Join-Path $directory ('.' + $baseName + '.' + [Guid]::NewGuid().ToString('N') + '.replace.bak')
    $encoding = New-Object Text.UTF8Encoding($false)

    try {
        [IO.File]::WriteAllText($temporaryPath, $json, $encoding)
        if ([IO.File]::Exists($fullPath)) {
            [IO.File]::Replace($temporaryPath, $fullPath, $replacementBackupPath, $true)
        }
        else {
            [IO.File]::Move($temporaryPath, $fullPath)
        }
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) {
            [IO.File]::Delete($temporaryPath)
        }
        if ([IO.File]::Exists($replacementBackupPath)) {
            [IO.File]::Delete($replacementBackupPath)
        }
    }
}

function Read-DesktopLayoutBackupDocument {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not [IO.File]::Exists($fullPath)) {
        throw "Desktop-layout backup does not exist: $fullPath"
    }

    try {
        $document = [IO.File]::ReadAllText($fullPath) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Desktop-layout backup is not valid JSON: $fullPath. $($_.Exception.Message)"
    }

    $schemaVersion = [int](Get-ObjectPropertyValue -InputObject $document -Name 'SchemaVersion' -Default 0)
    if ($schemaVersion -ne 1) {
        throw "Unsupported desktop-layout backup schema version '$schemaVersion'."
    }

    if ($null -eq $document.PSObject.Properties['Items']) {
        throw 'Desktop-layout backup is missing its Items collection.'
    }

    $entries = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($rawItem in @($document.Items)) {
        $entry = ConvertTo-ValidatedBackupEntry -Entry $rawItem
        if ($seen.ContainsKey($entry.CanonicalIdentity)) {
            throw "Backup contains duplicate canonical identity '$($entry.CanonicalIdentity)'."
        }
        $seen[$entry.CanonicalIdentity] = $true
        [void]$entries.Add($entry)
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        CreatedUtc     = [string](Get-ObjectPropertyValue -InputObject $document -Name 'CreatedUtc' -Default '')
        Items          = $entries.ToArray()
        Path           = $fullPath
    }
}

function Read-DesktopLayoutBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $document = Read-DesktopLayoutBackupDocument -Path $Path
    return ,@($document.Items)
}

function Write-DesktopLayoutBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Items,
        [Parameter(Mandatory = $true)][string]$BackupRoot
    )

    if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
        throw 'BackupRoot cannot be empty.'
    }

    $root = [IO.Path]::GetFullPath($BackupRoot)
    if (-not [IO.Directory]::Exists($root)) {
        [void][IO.Directory]::CreateDirectory($root)
    }

    $entries = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($item in @($Items)) {
        $entry = ConvertTo-ValidatedBackupEntry -Entry $item
        if ($seen.ContainsKey($entry.CanonicalIdentity)) {
            throw "Cannot back up duplicate canonical identity '$($entry.CanonicalIdentity)'."
        }
        $seen[$entry.CanonicalIdentity] = $true
        [void]$entries.Add($entry)
    }

    $createdUtc = [DateTime]::UtcNow
    $fileName = $createdUtc.ToString('yyyy-MM-dd_HHmmss_fff', [Globalization.CultureInfo]::InvariantCulture) + '.json'
    $backupPath = Join-Path $root $fileName
    if ([IO.File]::Exists($backupPath)) {
        $fileName = $createdUtc.ToString('yyyy-MM-dd_HHmmss_fff', [Globalization.CultureInfo]::InvariantCulture) + '_' + [Guid]::NewGuid().ToString('N') + '.json'
        $backupPath = Join-Path $root $fileName
    }

    $document = [ordered]@{
        SchemaVersion = 1
        CreatedUtc     = $createdUtc.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        Items          = $entries.ToArray()
    }

    Write-Utf8JsonAtomically -Value $document -Path $backupPath -Depth 6
    $verified = Read-DesktopLayoutBackupDocument -Path $backupPath
    if (@($verified.Items).Count -ne $entries.Count) {
        throw 'Backup read-after-write verification failed: item count changed.'
    }

    for ($index = 0; $index -lt $entries.Count; $index++) {
        $expected = $entries[$index]
        $actual = $verified.Items[$index]
        if ($expected.CanonicalIdentity -ne $actual.CanonicalIdentity -or
            [int]$expected.X -ne [int]$actual.X -or
            [int]$expected.Y -ne [int]$actual.Y) {
            throw "Backup read-after-write verification failed at item index $index."
        }
    }

    $manifest = [ordered]@{
        SchemaVersion = 1
        BackupFile    = $fileName
        UpdatedUtc    = [DateTime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }
    Write-Utf8JsonAtomically -Value $manifest -Path (Join-Path $root 'latest.json') -Depth 4

    $resolvedLatest = Get-LatestDesktopLayoutBackup -BackupRoot $root
    if (-not [string]::Equals(
        [IO.Path]::GetFullPath($backupPath),
        [IO.Path]::GetFullPath($resolvedLatest),
        [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Backup latest-manifest read-after-write verification failed.'
    }

    return [IO.Path]::GetFullPath($backupPath)
}

function Get-LatestDesktopLayoutBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$BackupRoot)

    $root = [IO.Path]::GetFullPath($BackupRoot)
    $manifestPath = Join-Path $root 'latest.json'
    if (-not [IO.File]::Exists($manifestPath)) {
        throw "No latest desktop-layout backup manifest exists under $root."
    }

    try {
        $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The latest desktop-layout backup manifest is invalid: $($_.Exception.Message)"
    }

    $schemaVersion = [int](Get-ObjectPropertyValue -InputObject $manifest -Name 'SchemaVersion' -Default 0)
    $backupFile = [string](Get-ObjectPropertyValue -InputObject $manifest -Name 'BackupFile' -Default '')
    if ($schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace($backupFile) -or [IO.Path]::GetFileName($backupFile) -ne $backupFile) {
        throw 'The latest backup manifest contains invalid data.'
    }

    $backupPath = [IO.Path]::GetFullPath((Join-Path $root $backupFile))
    $allowedPrefix = $root
    if (-not $allowedPrefix.EndsWith([string][IO.Path]::DirectorySeparatorChar) -and
        -not $allowedPrefix.EndsWith([string][IO.Path]::AltDirectorySeparatorChar)) {
        $allowedPrefix += [IO.Path]::DirectorySeparatorChar
    }
    if (-not $backupPath.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The latest backup manifest points outside the backup directory.'
    }

    [void](Read-DesktopLayoutBackupDocument -Path $backupPath)
    return $backupPath
}

function New-RestorePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$CurrentItems,
        [Parameter(Mandatory = $true)][object[]]$BackupEntries
    )

    $currentByIdentity = @{}
    foreach ($item in @($CurrentItems)) {
        $identity = [string](Get-ObjectPropertyValue -InputObject $item -Name 'CanonicalIdentity' -Default '')
        if ([string]::IsNullOrWhiteSpace($identity)) {
            continue
        }
        if ($currentByIdentity.ContainsKey($identity)) {
            throw "Current desktop contains duplicate canonical identity '$identity'."
        }
        $currentByIdentity[$identity] = $item
    }

    $requests = New-Object 'System.Collections.Generic.List[object]'
    $skipped = New-Object 'System.Collections.Generic.List[string]'
    $seenBackup = @{}

    foreach ($rawEntry in @($BackupEntries)) {
        $entry = ConvertTo-ValidatedBackupEntry -Entry $rawEntry
        if ($seenBackup.ContainsKey($entry.CanonicalIdentity)) {
            throw "Restore backup contains duplicate canonical identity '$($entry.CanonicalIdentity)'."
        }
        $seenBackup[$entry.CanonicalIdentity] = $true

        if ($currentByIdentity.ContainsKey($entry.CanonicalIdentity)) {
            $current = $currentByIdentity[$entry.CanonicalIdentity]
            [void]$requests.Add([pscustomobject][ordered]@{
                CanonicalIdentity = [string](Get-ObjectPropertyValue -InputObject $current -Name 'CanonicalIdentity' -Default $entry.CanonicalIdentity)
                DisplayName       = [string](Get-ObjectPropertyValue -InputObject $current -Name 'DisplayName' -Default $entry.DisplayName)
                X                 = $entry.X
                Y                 = $entry.Y
            })
        }
        else {
            [void]$skipped.Add($entry.CanonicalIdentity)
        }
    }

    return [pscustomobject][ordered]@{
        Requests = $requests.ToArray()
        Skipped  = $skipped.ToArray()
    }
}

#endregion Backup and restore data service

#region Shortcut metadata enrichment

function Resolve-DesktopItemMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Item)

    $properties = [ordered]@{}
    foreach ($property in $Item.PSObject.Properties) {
        $properties[$property.Name] = $property.Value
    }

    $properties['ShortcutTarget'] = ''
    $properties['ShortcutArguments'] = ''
    $properties['ShortcutWorkingDirectory'] = ''
    $properties['Url'] = ''

    $path = [string](Get-ObjectPropertyValue -InputObject $Item -Name 'FileSystemPath' -Default '')
    $extension = ''
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        try {
            $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
        }
        catch {
            $extension = ''
        }
    }
    $properties['Extension'] = $extension

    if ($extension -eq '.lnk' -and [IO.File]::Exists($path)) {
        $shell = $null
        $shortcut = $null
        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($path)
            $properties['ShortcutTarget'] = [string]$shortcut.TargetPath
            $properties['ShortcutArguments'] = [string]$shortcut.Arguments
            $properties['ShortcutWorkingDirectory'] = [string]$shortcut.WorkingDirectory
        }
        catch {
            Write-Verbose "Could not resolve shortcut '$path': $($_.Exception.Message)"
        }
        finally {
            if ($null -ne $shortcut -and [Runtime.InteropServices.Marshal]::IsComObject($shortcut)) {
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
            }
            if ($null -ne $shell -and [Runtime.InteropServices.Marshal]::IsComObject($shell)) {
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
            }
        }
    }
    elseif ($extension -eq '.url' -and [IO.File]::Exists($path)) {
        try {
            foreach ($line in [IO.File]::ReadAllLines($path)) {
                if ($line -match '^\s*URL\s*=\s*(.+?)\s*$') {
                    $properties['Url'] = $Matches[1]
                    break
                }
            }
        }
        catch {
            Write-Verbose "Could not read URL shortcut '$path': $($_.Exception.Message)"
        }
    }

    return [pscustomobject]$properties
}

#endregion Shortcut metadata enrichment

#region Windows Shell interop

$script:ShellInteropSource = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using System.Runtime.InteropServices;

namespace DesktopEdgeArranger
{
    public sealed class DesktopItemSnapshot
    {
        public string CanonicalIdentity { get; set; }
        public string DisplayName { get; set; }
        public string FileSystemPath { get; set; }
        public bool IsFolder { get; set; }
        public int X { get; set; }
        public int Y { get; set; }
    }

    public sealed class DesktopSnapshot
    {
        public int MonitorCount { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int SpacingX { get; set; }
        public int SpacingY { get; set; }
        public DesktopItemSnapshot[] Items { get; set; }
    }

    public sealed class PositionRequest
    {
        public string CanonicalIdentity { get; set; }
        public int X { get; set; }
        public int Y { get; set; }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct POINT
    {
        public int X;
        public int Y;

        public POINT(int x, int y)
        {
            X = x;
            Y = y;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    internal enum SIGDN : uint
    {
        NORMALDISPLAY = 0x00000000,
        DESKTOPABSOLUTEPARSING = 0x80028000,
        FILESYSPATH = 0x80058000
    }

    [ComImport, Guid("6D5140C1-7436-11CE-8034-00AA006009FA"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IServiceProvider
    {
        [return: MarshalAs(UnmanagedType.IUnknown)]
        object QueryService(
            [MarshalAs(UnmanagedType.LPStruct)] Guid service,
            [MarshalAs(UnmanagedType.LPStruct)] Guid riid);
    }

    [ComImport, Guid("000214E2-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellBrowser
    {
        void _VtblGap1_12();

        [return: MarshalAs(UnmanagedType.IUnknown)]
        object QueryActiveShellView();
    }

    [ComImport, Guid("000214E6-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellFolder
    {
    }

    [ComImport, Guid("000214F2-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IEnumIDList
    {
        [PreserveSig]
        int Next(uint count, out IntPtr pidl, out uint fetched);

        void Skip(uint count);
        void Reset();
        IEnumIDList Clone();
    }

    [ComImport, Guid("CDE725B0-CCC9-4519-917E-325D72FAB4CE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFolderView
    {
        void _VtblGap1_2();

        [return: MarshalAs(UnmanagedType.IUnknown)]
        object GetFolder([MarshalAs(UnmanagedType.LPStruct)] Guid riid);

        IntPtr Item(int itemIndex);
        int ItemCount(uint flags);

        [return: MarshalAs(UnmanagedType.Interface)]
        IEnumIDList Items(uint flags, [MarshalAs(UnmanagedType.LPStruct)] Guid riid);

        void _VtblGap2_2();
        void GetItemPosition(IntPtr pidl, out POINT point);
        void GetSpacing(ref POINT point);
        void GetDefaultSpacing(out POINT point);
        void _VtblGap3_2();
        void SelectAndPositionItems(
            uint count,
            [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] IntPtr[] pidls,
            [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] POINT[] points,
            uint flags);
    }

    [ComImport, Guid("1AF3A467-214F-4298-908E-06B03E0B39F9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFolderView2
    {
        void _VtblGap1_21();

        [PreserveSig]
        int SetCurrentFolderFlags(uint mask, uint flags);
    }

    [ComImport, Guid("3CC974D2-B302-4D36-AD3E-06D93F695D3F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFolderViewOptions
    {
        // Windows ShObjIdl.idl declares SetFolderViewOptions first, followed by
        // GetFolderViewOptions. COM method order is ABI-significant.
        [PreserveSig]
        int SetFolderViewOptions(uint mask, uint options);

        [PreserveSig]
        int GetFolderViewOptions(out uint options);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItem
    {
        [return: MarshalAs(UnmanagedType.IUnknown)]
        object BindToHandler(
            System.Runtime.InteropServices.ComTypes.IBindCtx bindContext,
            [MarshalAs(UnmanagedType.LPStruct)] Guid handler,
            [MarshalAs(UnmanagedType.LPStruct)] Guid riid);

        IShellItem GetParent();

        [return: MarshalAs(UnmanagedType.LPWStr)]
        string GetDisplayName(SIGDN kind);

        void GetAttributes(uint mask, out uint attributes);
    }

    [ComImport, Guid("00000114-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IOleWindow
    {
        [PreserveSig]
        int GetWindow(out IntPtr windowHandle);

        [PreserveSig]
        int ContextSensitiveHelp([MarshalAs(UnmanagedType.Bool)] bool enterMode);
    }

    internal sealed class DesktopViewContext : IDisposable
    {
        internal object ShellApplication;
        internal object ShellWindows;
        internal object DesktopDispatch;
        internal object ShellBrowserObject;
        internal object ShellViewObject;
        internal object ShellFolderObject;
        internal IFolderView FolderView;
        internal IFolderView2 FolderView2;
        internal IShellFolder ShellFolder;

        public void Dispose()
        {
            FolderView = null;
            FolderView2 = null;
            ShellFolder = null;
            ReleaseComObject(ref ShellFolderObject);
            ReleaseComObject(ref ShellViewObject);
            ReleaseComObject(ref ShellBrowserObject);
            ReleaseComObject(ref DesktopDispatch);
            ReleaseComObject(ref ShellWindows);
            ReleaseComObject(ref ShellApplication);
        }

        private static void ReleaseComObject(ref object value)
        {
            if (value != null && Marshal.IsComObject(value))
            {
                Marshal.FinalReleaseComObject(value);
            }
            value = null;
        }
    }

    public static class ShellDesktopAdapter
    {
        private const int CSIDL_DESKTOP = 0;
        private const int SWC_DESKTOP = 8;
        private const int SWFO_NEEDDISPATCH = 1;
        private const uint SVGIO_ALLVIEW = 0x2;
        private const uint SVSI_POSITIONITEM = 0x80;
        private const uint SVSI_NOTAKEFOCUS = 0x40000000;
        private const uint SVSI_NOSTATECHANGE = 0x80000000;
        private const uint SFGAO_FOLDER = 0x20000000;
        private const uint FWF_AUTOARRANGE = 0x1;
        private const uint FVO_CUSTOMPOSITION = 0x2;
        private const int E_NOTIMPL = unchecked((int)0x80004001);
        private const int SM_CMONITORS = 80;
        private const uint SPI_GETWORKAREA = 0x0030;

        private static DesktopViewContext OpenDesktopView()
        {
            DesktopViewContext context = new DesktopViewContext();
            try
            {
                Type shellType = Type.GetTypeFromProgID("Shell.Application", true);
                context.ShellApplication = Activator.CreateInstance(shellType);
                context.ShellWindows = context.ShellApplication.GetType().InvokeMember(
                    "Windows",
                    BindingFlags.InvokeMethod | BindingFlags.GetProperty | BindingFlags.OptionalParamBinding,
                    null,
                    context.ShellApplication,
                    null,
                    CultureInfo.InvariantCulture);

                // This late-bound invocation calls IShellWindows.FindWindowSW.
                // The first location variant identifies CSIDL_DESKTOP; the root remains VT_EMPTY.
                object[] arguments = new object[]
                {
                    CSIDL_DESKTOP,
                    null,
                    SWC_DESKTOP,
                    0,
                    SWFO_NEEDDISPATCH
                };
                ParameterModifier byReference = new ParameterModifier(arguments.Length);
                byReference[0] = true;
                byReference[1] = true;
                byReference[3] = true;
                context.DesktopDispatch = context.ShellWindows.GetType().InvokeMember(
                    "FindWindowSW",
                    BindingFlags.InvokeMethod | BindingFlags.OptionalParamBinding,
                    null,
                    context.ShellWindows,
                    arguments,
                    new ParameterModifier[] { byReference },
                    CultureInfo.InvariantCulture,
                    null);

                if (context.DesktopDispatch == null)
                {
                    throw new InvalidOperationException("Explorer did not return the desktop dispatch object.");
                }

                IServiceProvider serviceProvider = (IServiceProvider)context.DesktopDispatch;
                Guid topLevelBrowserService = new Guid("4C96BE40-915C-11CF-99D3-00AA004AE837");
                context.ShellBrowserObject = serviceProvider.QueryService(topLevelBrowserService, typeof(IShellBrowser).GUID);
                context.ShellViewObject = ((IShellBrowser)context.ShellBrowserObject).QueryActiveShellView();
                context.FolderView = (IFolderView)context.ShellViewObject;
                context.FolderView2 = (IFolderView2)context.ShellViewObject;
                context.ShellFolderObject = context.FolderView.GetFolder(typeof(IShellFolder).GUID);
                context.ShellFolder = (IShellFolder)context.ShellFolderObject;
                return context;
            }
            catch
            {
                context.Dispose();
                throw;
            }
        }

        public static DesktopSnapshot Capture()
        {
            string stage = "opening the Explorer desktop view";
            try
            {
                using (DesktopViewContext context = OpenDesktopView())
                {
                    stage = "reading desktop icon spacing";
                    POINT spacing = new POINT(0, 0);
                    context.FolderView.GetSpacing(ref spacing);
                    if (spacing.X <= 0 || spacing.Y <= 0)
                    {
                        context.FolderView.GetDefaultSpacing(out spacing);
                    }
                    if (spacing.X <= 0 || spacing.Y <= 0)
                    {
                        throw new InvalidOperationException("Explorer returned invalid desktop icon spacing.");
                    }

                    stage = "retrieving the desktop view window";
                    IntPtr viewWindow;
                    int hr = IUnknown_GetWindow(context.ShellViewObject, out viewWindow);
                    ThrowIfFailed(hr, "IUnknown_GetWindow");
                    if (viewWindow == IntPtr.Zero)
                    {
                        throw new InvalidOperationException("Explorer returned an empty desktop view window handle.");
                    }

                    stage = "reading the desktop work area";
                    RECT client;
                    if (!GetClientRect(viewWindow, out client))
                    {
                        throw new System.ComponentModel.Win32Exception(
                            Marshal.GetLastWin32Error(),
                            "GetClientRect failed for the desktop view.");
                    }

                    RECT workArea;
                    if (!SystemParametersInfo(SPI_GETWORKAREA, 0, out workArea, 0))
                    {
                        throw new System.ComponentModel.Win32Exception(
                            Marshal.GetLastWin32Error(),
                            "SystemParametersInfo(SPI_GETWORKAREA) failed.");
                    }

                    POINT workTopLeft = new POINT(workArea.Left, workArea.Top);
                    POINT workBottomRight = new POINT(workArea.Right, workArea.Bottom);
                    if (!ScreenToClient(viewWindow, ref workTopLeft) ||
                        !ScreenToClient(viewWindow, ref workBottomRight))
                    {
                        throw new System.ComponentModel.Win32Exception(
                            Marshal.GetLastWin32Error(),
                            "ScreenToClient failed for the desktop work area.");
                    }

                    int left = Math.Max(client.Left, workTopLeft.X);
                    int top = Math.Max(client.Top, workTopLeft.Y);
                    int right = Math.Min(client.Right, workBottomRight.X);
                    int bottom = Math.Min(client.Bottom, workBottomRight.Y);
                    if (right <= left || bottom <= top)
                    {
                        throw new InvalidOperationException("The usable desktop work area is empty.");
                    }

                    stage = "enumerating desktop item PIDLs";
                    List<DesktopItemSnapshot> items = new List<DesktopItemSnapshot>();
                    IEnumIDList enumerator = null;
                    try
                    {
                        enumerator = context.FolderView.Items(SVGIO_ALLVIEW, typeof(IEnumIDList).GUID);
                        while (true)
                        {
                            IntPtr pidl = IntPtr.Zero;
                            uint fetched = 0;
                            int enumHr = enumerator.Next(1, out pidl, out fetched);
                            if (enumHr == 1 || fetched == 0)
                            {
                                if (pidl != IntPtr.Zero)
                                {
                                    Marshal.FreeCoTaskMem(pidl);
                                }
                                break;
                            }
                            ThrowIfFailed(enumHr, "IEnumIDList.Next");
                            if (fetched != 1)
                            {
                                throw new InvalidOperationException("Explorer returned an invalid desktop item enumeration count.");
                            }
                            if (pidl == IntPtr.Zero)
                            {
                                throw new InvalidOperationException("Explorer returned an empty PIDL while enumerating desktop items.");
                            }

                            IShellItem shellItem = null;
                            try
                            {
                                stage = "reading a desktop item position";
                                POINT position;
                                context.FolderView.GetItemPosition(pidl, out position);

                                stage = "creating a Shell item from a desktop PIDL";
                                shellItem = CreateShellItem(context.ShellFolder, pidl);

                                stage = "reading desktop item metadata";
                                string canonical = shellItem.GetDisplayName(SIGDN.DESKTOPABSOLUTEPARSING);
                                string displayName = shellItem.GetDisplayName(SIGDN.NORMALDISPLAY);
                                string fileSystemPath = null;
                                try
                                {
                                    fileSystemPath = shellItem.GetDisplayName(SIGDN.FILESYSPATH);
                                }
                                catch (COMException)
                                {
                                    fileSystemPath = null;
                                }
                                catch (ArgumentException)
                                {
                                    fileSystemPath = null;
                                }

                                uint attributes;
                                shellItem.GetAttributes(SFGAO_FOLDER, out attributes);
                                items.Add(new DesktopItemSnapshot
                                {
                                    CanonicalIdentity = canonical,
                                    DisplayName = displayName,
                                    FileSystemPath = fileSystemPath,
                                    IsFolder = (attributes & SFGAO_FOLDER) != 0,
                                    X = position.X,
                                    Y = position.Y
                                });
                            }
                            finally
                            {
                                if (shellItem != null && Marshal.IsComObject(shellItem))
                                {
                                    Marshal.FinalReleaseComObject(shellItem);
                                }
                                if (pidl != IntPtr.Zero)
                                {
                                    Marshal.FreeCoTaskMem(pidl);
                                }
                            }
                        }
                    }
                    finally
                    {
                        if (enumerator != null && Marshal.IsComObject(enumerator))
                        {
                            Marshal.FinalReleaseComObject(enumerator);
                        }
                    }

                    return new DesktopSnapshot
                    {
                        MonitorCount = GetSystemMetrics(SM_CMONITORS),
                        Left = left,
                        Top = top,
                        Width = right - left,
                        Height = bottom - top,
                        SpacingX = spacing.X,
                        SpacingY = spacing.Y,
                        Items = items.ToArray()
                    };
                }
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException(
                    "Desktop capture failed while " + stage +
                    " (HRESULT 0x" + ex.HResult.ToString("X8", CultureInfo.InvariantCulture) + "): " +
                    ex.Message,
                    ex);
            }
        }

        public static void DisableAutoArrange()
        {
            using (DesktopViewContext context = OpenDesktopView())
            {
                EnableCustomPositioning(context);
            }
        }

        public static void ApplyPositions(PositionRequest[] requests)
        {
            if (requests == null)
            {
                throw new ArgumentNullException("requests");
            }
            if (requests.Length == 0)
            {
                return;
            }

            Dictionary<string, PositionRequest> requested =
                new Dictionary<string, PositionRequest>(StringComparer.OrdinalIgnoreCase);
            for (int index = 0; index < requests.Length; index++)
            {
                PositionRequest request = requests[index];
                if (request == null || String.IsNullOrWhiteSpace(request.CanonicalIdentity))
                {
                    throw new ArgumentException(
                        "Every position request must have a canonical identity.",
                        "requests");
                }
                if (requested.ContainsKey(request.CanonicalIdentity))
                {
                    throw new ArgumentException(
                        "Duplicate position request: " + request.CanonicalIdentity,
                        "requests");
                }
                requested.Add(request.CanonicalIdentity, request);
            }

            using (DesktopViewContext context = OpenDesktopView())
            {
                Dictionary<string, IntPtr> matchedPidls =
                    new Dictionary<string, IntPtr>(StringComparer.OrdinalIgnoreCase);
                IEnumIDList enumerator = null;

                try
                {
                    enumerator = context.FolderView.Items(SVGIO_ALLVIEW, typeof(IEnumIDList).GUID);
                    while (true)
                    {
                        IntPtr pidl = IntPtr.Zero;
                        uint fetched = 0;
                        int enumHr = enumerator.Next(1, out pidl, out fetched);
                        if (enumHr == 1 || fetched == 0)
                        {
                            if (pidl != IntPtr.Zero)
                            {
                                Marshal.FreeCoTaskMem(pidl);
                            }
                            break;
                        }
                        ThrowIfFailed(enumHr, "IEnumIDList.Next");
                        if (fetched != 1 || pidl == IntPtr.Zero)
                        {
                            throw new InvalidOperationException("Explorer returned an invalid desktop item enumeration result.");
                        }

                        bool keepPidl = false;
                        IShellItem shellItem = null;
                        try
                        {
                            shellItem = CreateShellItem(context.ShellFolder, pidl);
                            string canonical = shellItem.GetDisplayName(SIGDN.DESKTOPABSOLUTEPARSING);
                            if (String.IsNullOrWhiteSpace(canonical))
                            {
                                throw new InvalidOperationException(
                                    "Explorer returned an item without a canonical identity.");
                            }
                            if (requested.ContainsKey(canonical))
                            {
                                if (matchedPidls.ContainsKey(canonical))
                                {
                                    throw new InvalidOperationException(
                                        "Explorer returned duplicate canonical identity: " + canonical);
                                }
                                matchedPidls.Add(canonical, pidl);
                                keepPidl = true;
                            }
                        }
                        finally
                        {
                            if (shellItem != null && Marshal.IsComObject(shellItem))
                            {
                                Marshal.FinalReleaseComObject(shellItem);
                            }
                            if (!keepPidl && pidl != IntPtr.Zero)
                            {
                                Marshal.FreeCoTaskMem(pidl);
                            }
                        }
                    }

                    List<string> missing = new List<string>();
                    foreach (string identity in requested.Keys)
                    {
                        if (!matchedPidls.ContainsKey(identity))
                        {
                            missing.Add(identity);
                        }
                    }
                    if (missing.Count > 0)
                    {
                        throw new InvalidOperationException(
                            "Desktop item(s) disappeared before positioning: " +
                            String.Join("; ", missing.ToArray()));
                    }

                    IntPtr[] pidls = new IntPtr[requests.Length];
                    POINT[] points = new POINT[requests.Length];
                    for (int index = 0; index < requests.Length; index++)
                    {
                        pidls[index] = matchedPidls[requests[index].CanonicalIdentity];
                        points[index] = new POINT(requests[index].X, requests[index].Y);
                    }

                    EnableCustomPositioning(context);
                    context.FolderView.SelectAndPositionItems(
                        (uint)requests.Length,
                        pidls,
                        points,
                        SVSI_POSITIONITEM | SVSI_NOTAKEFOCUS | SVSI_NOSTATECHANGE);
                }
                finally
                {
                    if (enumerator != null && Marshal.IsComObject(enumerator))
                    {
                        Marshal.FinalReleaseComObject(enumerator);
                    }
                    foreach (IntPtr pidl in matchedPidls.Values)
                    {
                        if (pidl != IntPtr.Zero)
                        {
                            Marshal.FreeCoTaskMem(pidl);
                        }
                    }
                }
            }
        }

        private static IShellItem CreateShellItem(IShellFolder parent, IntPtr pidl)
        {
            Guid iid = typeof(IShellItem).GUID;
            IShellItem item;
            int hr = SHCreateItemWithParent(IntPtr.Zero, parent, pidl, ref iid, out item);
            ThrowIfFailed(hr, "SHCreateItemWithParent");
            if (item == null)
            {
                throw new InvalidOperationException("SHCreateItemWithParent returned no Shell item.");
            }
            return item;
        }

        private static void ThrowIfFailed(int hr, string operation)
        {
            if (hr < 0)
            {
                throw new COMException(
                    operation + " failed with HRESULT 0x" + hr.ToString("X8", CultureInfo.InvariantCulture) + ".",
                    hr);
            }
        }

        private static void EnableCustomPositioning(DesktopViewContext context)
        {
            // Microsoft documents FVO_CUSTOMPOSITION as the companion option for
            // SetCurrentFolderFlags on Windows 7 and later. Some desktop shell
            // views return E_NOTIMPL for this option even though desktop icon
            // positioning itself is supported, so tolerate only that exact result.
            IFolderViewOptions options = (IFolderViewOptions)context.ShellViewObject;
            int optionHr = options.SetFolderViewOptions(FVO_CUSTOMPOSITION, FVO_CUSTOMPOSITION);
            if (optionHr < 0 && optionHr != E_NOTIMPL)
            {
                ThrowIfFailed(optionHr, "IFolderViewOptions.SetFolderViewOptions");
            }

            int hr = context.FolderView2.SetCurrentFolderFlags(FWF_AUTOARRANGE, 0);
            ThrowIfFailed(hr, "IFolderView2.SetCurrentFolderFlags");
        }

        [DllImport("shell32.dll")]
        private static extern int SHCreateItemWithParent(
            IntPtr pidlParent,
            [MarshalAs(UnmanagedType.Interface)] IShellFolder parentFolder,
            IntPtr pidl,
            ref Guid riid,
            [MarshalAs(UnmanagedType.Interface)] out IShellItem item);

        [DllImport("shlwapi.dll")]
        private static extern int IUnknown_GetWindow(
            [MarshalAs(UnmanagedType.IUnknown)] object unknown,
            out IntPtr windowHandle);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetClientRect(IntPtr windowHandle, out RECT rect);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ScreenToClient(IntPtr windowHandle, ref POINT point);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SystemParametersInfo(
            uint action,
            uint parameter,
            out RECT value,
            uint flags);

        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);
    }
}
'@

function Initialize-DesktopShellInterop {
    [CmdletBinding()]
    param()

    if ($null -eq ('DesktopEdgeArranger.ShellDesktopAdapter' -as [type])) {
        Add-Type -TypeDefinition $script:ShellInteropSource -Language CSharp -ErrorAction Stop
    }
}

function Get-DesktopShellSnapshot {
    [CmdletBinding()]
    param()

    Initialize-DesktopShellInterop
    return [DesktopEdgeArranger.ShellDesktopAdapter]::Capture()
}

function ConvertTo-PositionRequestArray {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Entries = @())

    Initialize-DesktopShellInterop
    $entryArray = @($Entries)
    $requestType = 'DesktopEdgeArranger.PositionRequest' -as [type]
    $array = [Array]::CreateInstance($requestType, $entryArray.Count)

    for ($index = 0; $index -lt $entryArray.Count; $index++) {
        $entry = $entryArray[$index]
        $request = New-Object DesktopEdgeArranger.PositionRequest
        $request.CanonicalIdentity = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'CanonicalIdentity' -Default '')
        $request.X = [int](Get-ObjectPropertyValue -InputObject $entry -Name 'X' -Default 0)
        $request.Y = [int](Get-ObjectPropertyValue -InputObject $entry -Name 'Y' -Default 0)
        $array.SetValue($request, $index)
    }

    return ,$array
}

function Disable-DesktopAutoArrange {
    [CmdletBinding()]
    param()

    Initialize-DesktopShellInterop
    [DesktopEdgeArranger.ShellDesktopAdapter]::DisableAutoArrange()
}

function Set-DesktopIconPositions {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Entries)

    $requests = ConvertTo-PositionRequestArray -Entries $Entries
    [DesktopEdgeArranger.ShellDesktopAdapter]::ApplyPositions($requests)
}

#endregion Windows Shell interop

#region Command orchestration

function Get-DesktopEdgeArrangerBackupRoot {
    [CmdletBinding()]
    param()

    $localApplicationData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        $localApplicationData = $env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        throw 'Windows did not provide a Local Application Data directory.'
    }

    return Join-Path $localApplicationData 'DesktopEdgeArranger\Backups'
}

function Assert-DesktopEdgeArrangerEnvironment {
    [CmdletBinding()]
    param()

    if ($env:OS -ne 'Windows_NT') {
        throw 'Desktop Edge Arranger must be run on Windows 10 or Windows 11.'
    }

    $version = $PSVersionTable.PSVersion
    if ($version.Major -lt 5 -or ($version.Major -eq 5 -and $version.Minor -lt 1)) {
        throw 'Desktop Edge Arranger requires Windows PowerShell 5.1 or later.'
    }

    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
        throw 'Desktop Edge Arranger requires an STA PowerShell process. Use Arrange-DesktopIcons.bat.'
    }
}

function Assert-DesktopSnapshotIdentityIntegrity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Items)

    $seen = @{}
    foreach ($item in @($Items)) {
        $identity = [string](Get-ObjectPropertyValue -InputObject $item -Name 'CanonicalIdentity' -Default '')
        $name = [string](Get-ObjectPropertyValue -InputObject $item -Name 'DisplayName' -Default '<unnamed>')
        if ([string]::IsNullOrWhiteSpace($identity)) {
            throw "Explorer returned no canonical identity for '$name'."
        }
        if ($seen.ContainsKey($identity)) {
            throw "Explorer returned duplicate canonical identity '$identity'."
        }
        $seen[$identity] = $true
    }
}

function Invoke-DesktopEdgeArranger {
    [CmdletBinding()]
    param(
        [ValidateSet('Arrange', 'Restore')][string]$Mode = 'Arrange',
        [AllowNull()][string[]]$ForceApplication = @(),
        [AllowNull()][string[]]$ForceGame = @(),
        [AllowNull()][string[]]$ForceMusic = @(),
        [AllowNull()][string[]]$ForceRight = @()
    )

    Assert-DesktopEdgeArrangerEnvironment
    $backupRoot = Get-DesktopEdgeArrangerBackupRoot
    $snapshot = Get-DesktopShellSnapshot

    if ($snapshot.MonitorCount -ne 1) {
        throw "This release supports exactly one active monitor; Windows reported $($snapshot.MonitorCount). No icons were moved."
    }

    $currentItems = @($snapshot.Items | ForEach-Object { Resolve-DesktopItemMetadata -Item $_ })
    Assert-DesktopSnapshotIdentityIntegrity -Items $currentItems

    if ($Mode -eq 'Restore') {
        $backupPath = Get-LatestDesktopLayoutBackup -BackupRoot $backupRoot
        $script:LastDesktopEdgeArrangerBackup = $backupPath
        $backupEntries = Read-DesktopLayoutBackup -Path $backupPath
        $restorePlan = New-RestorePlan -CurrentItems $currentItems -BackupEntries $backupEntries

        if ($restorePlan.Requests.Count -eq 0) {
            throw 'No current desktop icons match the latest backup; nothing was changed.'
        }

        Disable-DesktopAutoArrange
        Set-DesktopIconPositions -Entries $restorePlan.Requests

        Write-Host "Restored: $($restorePlan.Requests.Count)"
        Write-Host "Skipped missing or renamed: $($restorePlan.Skipped.Count)"
        Write-Host "Backup: $backupPath"
        Write-Host 'Desktop icon positions restored once. No background process was started.'
        return
    }

    $overrideMap = New-OverrideMap `
        -ForceApplication $ForceApplication `
        -ForceGame $ForceGame `
        -ForceMusic $ForceMusic `
        -ForceRight $ForceRight
    [void](Test-OverrideConfiguration -Items $currentItems -OverrideMap $overrideMap)

    $classifiedItems = @($currentItems | ForEach-Object {
        Add-DesktopItemCategory -Item $_ -OverrideMap $overrideMap
    })

    $geometry = Get-DesktopGridGeometry -Snapshot $snapshot
    $plan = New-DesktopLayoutPlan `
        -Items $classifiedItems `
        -ColumnCount $geometry.ColumnCount `
        -RowCount $geometry.RowCount `
        -OriginX $geometry.OriginX `
        -OriginY $geometry.OriginY `
        -SpacingX $geometry.SpacingX `
        -SpacingY $geometry.SpacingY

    # The verified pre-change backup is complete before any Explorer view flag
    # or icon coordinate is changed.
    $backupPath = Write-DesktopLayoutBackup -Items $currentItems -BackupRoot $backupRoot
    $script:LastDesktopEdgeArrangerBackup = $backupPath

    Disable-DesktopAutoArrange
    Set-DesktopIconPositions -Entries $plan

    Write-Host "Recycle Bin: $(@($classifiedItems | Where-Object { $_.Category -eq 'RecycleBin' }).Count)"
    Write-Host "Applications: $(@($classifiedItems | Where-Object { $_.Category -eq 'Application' }).Count)"
    Write-Host "Games and music: $(@($classifiedItems | Where-Object { $_.Category -eq 'Bottom' }).Count)"
    Write-Host "Right edge: $(@($classifiedItems | Where-Object { $_.Category -eq 'Right' }).Count)"
    Write-Host "Backup: $backupPath"
    Write-Host 'Desktop icons arranged once. No background process was started.'
}

#endregion Command orchestration

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-DesktopEdgeArranger `
            -Mode $Mode `
            -ForceApplication $ForceApplication `
            -ForceGame $ForceGame `
            -ForceMusic $ForceMusic `
            -ForceRight $ForceRight
        exit 0
    }
    catch {
        Write-Error $_.Exception.Message
        if (-not [string]::IsNullOrWhiteSpace([string]$script:LastDesktopEdgeArrangerBackup)) {
            Write-Host "A verified pre-change backup is available at: $script:LastDesktopEdgeArrangerBackup"
            Write-Host 'Restore with: Arrange-DesktopIcons.bat -Mode Restore'
        }
        exit 1
    }
}
