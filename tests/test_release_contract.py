from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Arrange-DesktopIcons.ps1"
LAUNCHER = ROOT / "Arrange-DesktopIcons.bat"
README = ROOT / "README.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing release file: {path.name}"
    return path.read_text(encoding="utf-8")


def test_release_files_exist() -> None:
    for path in (SCRIPT, LAUNCHER, README):
        assert path.is_file(), f"missing release file: {path.name}"


def test_script_exposes_required_pure_functions() -> None:
    source = read(SCRIPT)
    required = [
        "New-OverrideMap",
        "Test-OverrideConfiguration",
        "Get-DesktopItemCategory",
        "New-DesktopLayoutPlan",
        "Test-DesktopLayoutPlan",
        "Write-DesktopLayoutBackup",
        "Read-DesktopLayoutBackup",
        "Get-LatestDesktopLayoutBackup",
        "New-RestorePlan",
        "Invoke-DesktopEdgeArranger",
    ]
    for name in required:
        assert re.search(rf"(?im)^function\s+{re.escape(name)}\b", source), name


def test_each_powershell_function_is_declared_once() -> None:
    source = read(SCRIPT)
    names = re.findall(r"(?im)^function\s+([A-Za-z][A-Za-z0-9-]*)\b", source)
    duplicates = sorted({name for name in names if names.count(name) > 1})
    assert not duplicates, f"duplicate function declarations: {duplicates}"


def test_interop_contract_is_present() -> None:
    source = read(SCRIPT)
    required_tokens = [
        "namespace DesktopEdgeArranger",
        "ShellDesktopAdapter",
        "FindWindowSW",
        "QueryActiveShellView",
        "GetItemPosition",
        "GetSpacing",
        "SelectAndPositionItems",
        "SetCurrentFolderFlags",
        "FVO_CUSTOMPOSITION",
        "ThrowIfFailed",
        "Marshal.FinalReleaseComObject",
        "Marshal.FreeCoTaskMem",
        "ParameterModifier",
    ]
    for token in required_tokens:
        assert token in source, token

    assert re.search(
        r"SelectAndPositionItems\([^;]+SVSI_POSITIONITEM\s*\|\s*"
        r"SVSI_NOTAKEFOCUS\s*\|\s*SVSI_NOSTATECHANGE\s*\)",
        source,
        re.DOTALL,
    ), "positioning should preserve selection/focus state"


def test_one_shot_safety_contract() -> None:
    source = read(SCRIPT).lower()
    prohibited = [
        "register-scheduledtask",
        "new-scheduledtask",
        "filesystemwatcher",
        "while ($true)",
        "for (;;) ",
        "currentversion\\run",
        "set-executionpolicy",
        "start-job",
    ]
    for token in prohibited:
        assert token not in source, f"prohibited persistent behavior: {token}"


def test_launcher_uses_process_scoped_bypass_and_sta() -> None:
    source = read(LAUNCHER).lower()
    assert "%systemroot%\\system32\\windowspowershell\\v1.0\\powershell.exe" in source
    assert "-noprofile" in source
    assert "-sta" in source
    assert "-executionpolicy bypass" in source
    assert '"%~dp0arrange-desktopicons.ps1"' in source
    assert 'set "exitcode=%errorlevel%"' in source
    assert 'if not "%exitcode%"=="0"' in source
    assert "pause" in source
    assert "exit /b %exitcode%" in source


def test_readme_documents_user_contract() -> None:
    source = read(README)
    required = [
        "Arrange-DesktopIcons.bat",
        "-Mode Restore",
        "%LOCALAPPDATA%\\DesktopEdgeArranger\\Backups",
        "$ForceApplication",
        "$ForceGame",
        "$ForceMusic",
        "$ForceRight",
        "single monitor",
        "does not move",
        "Recycle Bin desktop icon must be visible",
        "remains disabled",
        "Align icons to grid",
    ]
    for token in required:
        assert token.lower() in source.lower(), token


def test_arrange_mutates_only_after_backup() -> None:
    source = read(SCRIPT)
    match = re.search(
        r"(?ims)^function\s+Invoke-DesktopEdgeArranger\b(?P<body>.*?)(?=^if\s*\(\$MyInvocation\.InvocationName)",
        source,
    )
    assert match, "Invoke-DesktopEdgeArranger body not found"
    body = match.group("body")
    backup = body.rfind("Write-DesktopLayoutBackup")
    disable = body.rfind("Disable-DesktopAutoArrange")
    apply = body.rfind("Set-DesktopIconPositions")
    assert -1 not in (backup, disable, apply)
    assert backup < disable < apply


def test_positioning_preserves_selection_state() -> None:
    source = read(SCRIPT)
    assert "SVSI_POSITIONITEM | SVSI_NOTAKEFOCUS | SVSI_NOSTATECHANGE" in source


def test_position_request_array_keeps_its_runtime_type() -> None:
    source = read(SCRIPT)
    assert "function ConvertTo-PositionRequestArray" in source
    assert "return ,$array" in source


def test_conservative_game_detection_does_not_match_a_bare_steam_folder() -> None:
    source = read(SCRIPT)
    assert "steam(apps)?([\\/]|$)" not in source
    assert "-applaunch\\s+\\d+" in source
    assert "steamapps" in source.lower()


def test_grid_capacity_reserves_a_full_spacing_cell_at_each_edge() -> None:
    source = read(SCRIPT)
    assert "$usableWidth / [double]$spacingX" in source
    assert "$usableHeight / [double]$spacingY" in source
    assert "($usableWidth - 1)" not in source
    assert "($usableHeight - 1)" not in source


def test_position_request_array_is_returned_without_pipeline_unrolling() -> None:
    source = read(SCRIPT)
    match = re.search(
        r"(?ims)^function\s+ConvertTo-PositionRequestArray\b(?P<body>.*?)(?=^function\s+)",
        source,
    )
    assert match, "ConvertTo-PositionRequestArray body not found"
    assert re.search(r"(?im)^\s*return\s+,\$array\s*$", match.group("body"))


def test_com_find_window_marks_hwnd_as_a_byref_parameter() -> None:
    source = read(SCRIPT)
    assert "ParameterModifier" in source
    assert re.search(r"[A-Za-z_][A-Za-z0-9_]*\s*\[\s*3\s*\]\s*=\s*true", source)


def test_find_window_sw_identifies_the_desktop_and_uses_an_empty_root_variant() -> None:
    source = read(SCRIPT)
    match = re.search(
        r"object\[\]\s+arguments\s*=\s*new\s+object\[\]\s*\{(?P<body>.*?)\};",
        source,
        re.DOTALL,
    )
    assert match, "FindWindowSW argument array not found"
    tokens = [token.strip() for token in match.group("body").split(",") if token.strip()]
    assert tokens[:5] == [
        "CSIDL_DESKTOP",
        "null",
        "SWC_DESKTOP",
        "0",
        "SWFO_NEEDDISPATCH",
    ]


def test_capture_declares_each_work_area_point_once() -> None:
    source = read(SCRIPT)
    start = source.index("public static DesktopSnapshot Capture()")
    end = source.index("public static void DisableAutoArrange()", start)
    capture = source[start:end]
    assert capture.count("POINT workTopLeft") == 1
    assert capture.count("POINT workBottomRight") == 1


def test_folder_view_options_matches_windows_idl_vtable_order() -> None:
    source = read(SCRIPT)
    match = re.search(
        r"interface\s+IFolderViewOptions\s*\{(?P<body>.*?)\n\s*\}",
        source,
        re.DOTALL,
    )
    assert match, "IFolderViewOptions declaration not found"
    body = match.group("body")
    assert "_VtblGap" not in body, "SetFolderViewOptions is the first method after IUnknown"
    setter = body.index("SetFolderViewOptions")
    getter = body.index("GetFolderViewOptions")
    assert setter < getter, "Windows IDL declares SetFolderViewOptions before GetFolderViewOptions"


def test_capture_rejects_an_empty_pidl_before_reading_its_position() -> None:
    source = read(SCRIPT)
    start = source.index("public static DesktopSnapshot Capture()")
    end = source.index("public static void DisableAutoArrange()", start)
    capture = source[start:end]
    null_check = capture.index("if (pidl == IntPtr.Zero)") if "if (pidl == IntPtr.Zero)" in capture else -1
    position_read = capture.index("context.FolderView.GetItemPosition(pidl, out position)")
    assert null_check >= 0
    assert null_check < position_read


def test_restore_remembers_the_backup_before_explorer_mutation() -> None:
    source = read(SCRIPT)
    match = re.search(
        r"(?ims)^function\s+Invoke-DesktopEdgeArranger\b(?P<body>.*?)(?=^if\s*\(\$MyInvocation\.InvocationName)",
        source,
    )
    assert match, "Invoke-DesktopEdgeArranger body not found"
    body = match.group("body")
    restore_start = body.index("if ($Mode -eq 'Restore')")
    restore_end = body.index("$overrideMap = New-OverrideMap", restore_start)
    restore = body[restore_start:restore_end]
    latest = restore.index("Get-LatestDesktopLayoutBackup")
    remember = restore.index("$script:LastDesktopEdgeArrangerBackup = $backupPath")
    disable = restore.index("Disable-DesktopAutoArrange")
    apply = restore.index("Set-DesktopIconPositions")
    assert latest < remember < disable < apply


def test_capture_uses_iunknown_getwindow_for_shell_view_handle() -> None:
    source = read(SCRIPT)
    start = source.index("public static DesktopSnapshot Capture()")
    end = source.index("public static void DisableAutoArrange()", start)
    capture = source[start:end]
    assert 'DllImport("shlwapi.dll"' in source
    assert "IUnknown_GetWindow" in source
    assert "IUnknown_GetWindow(context.ShellViewObject, out viewWindow)" in capture
    assert "((IOleWindow)context.ShellViewObject).GetWindow" not in capture


def test_capture_enumerates_pidls_instead_of_indexing_ifolderview2_getitem() -> None:
    source = read(SCRIPT)
    start = source.index("public static DesktopSnapshot Capture()")
    end = source.index("public static void DisableAutoArrange()", start)
    capture = source[start:end]

    assert "IEnumIDList" in source
    assert "SHCreateItemWithParent" in source
    assert "context.FolderView.Items(SVGIO_ALLVIEW" in capture
    assert "context.FolderView2.GetItem(" not in capture


def test_apply_positions_matches_requests_by_enumerated_pidls() -> None:
    source = read(SCRIPT)
    start = source.index("public static void ApplyPositions(PositionRequest[] requests)")
    end = source.index("private static void EnableCustomPositioning", start)
    apply = source[start:end]

    assert "context.FolderView.Items(SVGIO_ALLVIEW" in apply
    assert "SHCreateItemWithParent" in source
    assert "context.FolderView2.GetItem(" not in apply


def test_capture_com_failures_include_stage_context() -> None:
    source = read(SCRIPT)
    start = source.index("public static DesktopSnapshot Capture()")
    end = source.index("public static void DisableAutoArrange()", start)
    capture = source[start:end]
    assert "Desktop capture failed while" in capture


def test_getspacing_interop_preserves_native_inout_point_contract() -> None:
    source = read(SCRIPT)
    assert "void GetSpacing(ref POINT point);" in source
    start = source.index("public static DesktopSnapshot Capture()")
    end = source.index("public static void DisableAutoArrange()", start)
    capture = source[start:end]
    assert "POINT spacing = new POINT(0, 0);" in capture
    assert "context.FolderView.GetSpacing(ref spacing);" in capture
