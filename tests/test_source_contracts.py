from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Arrange-DesktopIcons.ps1"


def source() -> str:
    assert SCRIPT.exists(), "Arrange-DesktopIcons.ps1 has not been implemented"
    return SCRIPT.read_text(encoding="utf-8")


def test_classifier_contract_exists() -> None:
    text = source()
    for name in (
        "function New-OverrideMap",
        "function Test-OverrideConfiguration",
        "function Get-DesktopItemCategory",
    ):
        assert name in text


def test_classifier_contains_approved_music_types() -> None:
    text = source().lower()
    for ext in (".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg", ".opus", ".wma"):
        assert ext in text


def test_recycle_bin_is_canonical_not_display_name_only() -> None:
    assert "645FF040-5081-101B-9F08-00AA002F954E" in source()


def test_planner_contract_exists() -> None:
    text = source()
    assert "function New-DesktopLayoutPlan" in text
    assert "function Test-DesktopLayoutPlan" in text


def test_planner_mentions_all_approved_regions() -> None:
    text = source()
    for category in ("RecycleBin", "Application", "Bottom", "Right"):
        assert category in text


def test_backup_restore_contract_exists() -> None:
    text = source()
    for name in (
        "function Write-DesktopLayoutBackup",
        "function Read-DesktopLayoutBackup",
        "function Get-LatestDesktopLayoutBackup",
        "function New-RestorePlan",
    ):
        assert name in text


def test_backup_contract_uses_local_json_manifest_concepts() -> None:
    text = source()
    assert "latest.json" in text
    assert "ConvertTo-Json" in text
    assert "ConvertFrom-Json" in text


def _powershell_pattern_array(variable_name: str) -> list[str]:
    text = source()
    match = __import__("re").search(
        rf"\${variable_name}\s*=\s*@\((?P<body>.*?)\n\s*\)",
        text,
        __import__("re").DOTALL,
    )
    assert match, f"PowerShell pattern array ${variable_name} not found"
    return [
        value.replace("''", "'")
        for value in __import__("re").findall(r"'((?:''|[^'])*)'", match.group("body"))
    ]


def _matches_any(patterns: list[str], value: str) -> bool:
    regex = __import__("re")
    return any(regex.search(pattern, value) is not None for pattern in patterns)


def test_game_patterns_recognize_launch_entries_but_not_bare_launchers() -> None:
    launch_patterns = _powershell_pattern_array("launchPatterns")
    install_patterns = _powershell_pattern_array("installPatterns")

    launches = (
        r"C:\Program Files (x86)\Steam\steam.exe\n-applaunch 123",
        "com.epicgames.launcher://apps/game?action=launch",
        r"C:\Program Files\EA Games\Game\game.exe",
        r"C:\GOG Games\Game\game.exe",
        r"C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games\Game\game.exe",
    )
    for value in launches:
        assert _matches_any(launch_patterns + install_patterns, value), value

    bare_launchers = (
        r"C:\Program Files (x86)\Steam\steam.exe",
        r"C:\Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe",
        r"C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe",
        r"C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe",
        r"C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe",
    )
    for value in bare_launchers:
        assert not _matches_any(launch_patterns + install_patterns, value), value


def test_planner_forces_singleton_category_results_to_arrays() -> None:
    """Windows PowerShell 5.1 can expose singleton PSCustomObject Count as $null."""
    text = source()
    regex = __import__('re')
    for variable, category in (
        ('recycleItems', 'RecycleBin'),
        ('applicationItems', 'Application'),
        ('bottomItems', 'Bottom'),
        ('rightItems', 'Right'),
    ):
        pattern = (
            rf"\${variable}\s*=\s*@\(\s*Get-SortedDesktopItems\s+-Items\s+@\("
            rf".*?Category\s+-eq\s+'{category}'.*?\)\s*\)"
        )
        assert regex.search(pattern, text, regex.DOTALL), (
            f"${variable} must wrap Get-SortedDesktopItems in @() so a one-item "
            "category remains an array under Windows PowerShell 5.1"
        )


def test_atomic_json_replace_never_passes_null_backup_path() -> None:
    """Windows PowerShell 5.1 can coerce $null to an empty string for .NET string args."""
    text = source()
    assert "[IO.File]::Replace($temporaryPath, $fullPath, $null, $true)" not in text
    assert "$replacementBackupPath" in text
    assert "[IO.File]::Replace($temporaryPath, $fullPath, $replacementBackupPath, $true)" in text



def test_custom_positioning_tolerates_ifolderviewoptions_enotimpl() -> None:
    """Desktop views may return E_NOTIMPL for FVO_CUSTOMPOSITION; that exact result must be non-fatal."""
    text = source()
    start = text.find("private static void EnableCustomPositioning(DesktopViewContext context)")
    end = text.find('[DllImport("shell32.dll")]', start)
    assert start >= 0 and end > start, "EnableCustomPositioning implementation not found"
    body = text[start:end]
    assert "SetFolderViewOptions(FVO_CUSTOMPOSITION, FVO_CUSTOMPOSITION)" in body
    assert "private const int E_NOTIMPL = unchecked((int)0x80004001);" in text
    assert "optionHr < 0 && optionHr != E_NOTIMPL" in body
    assert "SetCurrentFolderFlags(FWF_AUTOARRANGE, 0)" in body
