# Desktop Edge Arranger

A one-shot Windows utility that changes only the **visual coordinates** of icons in Explorer's Desktop view. It **does not move, rename, copy, edit, or delete** the underlying desktop files, folders, shortcuts, or their contents. It installs no watcher, service, scheduled task, startup entry, or background process.

The current release arranges and restores icons on a **single monitor**. A GUI, broader display support, and personal Windows re-setup are [future intent](FUTURE.md), not features of this release.

## Layout

Recycle Bin occupies the top-left grid cell `(0,0)`; the left column below it stays empty. Applications fill the top from left to right, starting in column `1`, and wrap downward. Games and music fill centered rows from the bottom upward. Folders, scripts, text, and miscellaneous items fill the remaining cells from the right inward, top to bottom, skipping occupied cells. The center stays clear as far as capacity permits.

Placement is deterministic for the same items and grid geometry. If the full layout cannot fit without violating these regions, Arrange aborts rather than returning a partial plan.

## Requirements

- Windows 10 or Windows 11, with a normal Explorer desktop session.
- Windows PowerShell 5.1 or later in STA; the supplied launcher uses Windows PowerShell.
- Exactly one active monitor. This single-monitor release rejects other monitor counts in both modes.
- The **Recycle Bin desktop icon must be visible**.
- Run normally, not elevated. Do **not** use **Run as administrator**.

## Arrange once

Keep [Arrange-DesktopIcons.bat](Arrange-DesktopIcons.bat) beside [Arrange-DesktopIcons.ps1](Arrange-DesktopIcons.ps1), then double-click the batch file normally. There is no installer or build step.

The utility reads Explorer, validates and computes the complete layout, writes and verifies a pre-change position backup, applies the coordinates once, reports the result, and exits. On failure, the launcher keeps the diagnostic window open until you press a key and returns the script's nonzero exit code.

Equivalent command, run from the folder containing the script:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Arrange-DesktopIcons.ps1 -Mode Arrange
```

`-ExecutionPolicy Bypass` affects only that PowerShell process; the utility does not change the persistent execution policy.

## Restore and recovery

Run from the same folder:

```powershell
.\Arrange-DesktopIcons.bat -Mode Restore
```

Or invoke PowerShell directly:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Arrange-DesktopIcons.ps1 -Mode Restore
```

Position backups are stored in `%LOCALAPPDATA%\DesktopEdgeArranger\Backups`. Each Arrange writes a timestamped JSON file and updates `latest.json` to identify it. Both are verified before Arrange changes Explorer view flags or icon coordinates. Backups contain canonical Shell identities, display names, and X/Y coordinates; they are **not filesystem backups** and can reveal filenames and paths.

Restore uses the latest manifest and matches current icons by canonical Shell identity, not by display name or enumeration order. Missing or renamed items are reported and skipped; unrelated current icons remain in place. If nothing matches, Restore aborts without applying positions. Restore neither creates a new backup nor restores view settings.

Do not run Arrange again to recover from a failed Arrange: it would make the then-current positions the latest backup. When a verified backup has been recorded, the error output identifies it and gives the Restore command. Existing timestamped backups are retained; there is no automatic pruning or command-line selector for an older backup.

## Classification and overrides

Automatic classification is conservative. Recycle Bin is recognized by its canonical identity, regardless of its localized display name. Folders go right; recognized music and games go bottom; applications go top; unknown items go right. Game heuristics recognize common Steam, Epic, EA/Origin, GOG, Ubisoft, Rockstar, Battle.net, Riot, and Xbox install paths or explicit launch arguments/protocols. A bare launcher such as Steam or Epic remains an application.

Music extensions include `.mp3`, `.wav`, `.flac`, `.m4a`, `.aac`, `.ogg`, `.opus`, and `.wma`. Executables and resolved application shortcuts go top. Ordinary web bookmarks, unresolved shortcuts, scripts, documents, and archives go right unless overridden.

To correct a classification, edit the four arrays near the top of `Arrange-DesktopIcons.ps1`:

```powershell
$ForceApplication = @('Firefox')
$ForceGame = @('Poker Night 2', 'C:\Users\YourName\Desktop\Sims.exe - Shortcut.lnk')
$ForceMusic = @('Mix Playlist.m3u')
$ForceRight = @('Tools', 'notes.txt')
```

Overrides take precedence over automatic classification, except for Recycle Bin. Matching is case-insensitive and accepts the displayed name, canonical Shell identity, filesystem path, resolved shortcut target, shortcut arguments, working directory, or URL. Keep each item in only one array, including when both arrays would place it at the bottom. Conflicting tokens or different identity forms matching multiple arrays abort before mutation.

## Safety boundary and troubleshooting

Arrange must finish environment/identity/override validation, classification, full layout/collision/capacity checks, and verified backup creation before mutation. Restore validates the saved data and identity matches before applying positions. Invalid preconditions are not permission to weaken these checks.

**Auto arrange icons** is disabled because Explorer would otherwise override explicit coordinates, and it **remains disabled** after Arrange or Restore. **Align icons to grid**, icon size, and selection/focus state are to remain unchanged. Positioning uses Explorer's folder-view APIs, not filesystem organization.

Preflight rejection and a later Shell failure are different: the script has no transactional rollback of Explorer flags or a failed positioning call. A failure after mutation begins can require Restore. Keep the desktop stable during a run; requested items disappearing before positioning cause an abort rather than guessed identity matches.

| Symptom | Action |
| --- | --- |
| STA-process error | Start through `Arrange-DesktopIcons.bat`. |
| More than one active monitor | Use one active display for this release. |
| Recycle Bin or capacity error | Make Recycle Bin visible, or provide enough usable grid space; do not bypass validation. |
| Incorrect classification | Adjust the relevant override array. |
| Need the pre-Arrange positions | Use Restore, not another Arrange. |
| Shell capture failure | Read the stage and HRESULT in the error; use the supported desktop session, not elevation as a workaround. |

## Development and verification

The batch file only launches the script. PowerShell owns classification, planning, JSON backup/restore, and orchestration; the embedded C# `ShellDesktopAdapter` owns Explorer COM/Win32 access and native resource lifetime. The source's regions and local comments describe that boundary and its non-obvious compatibility constraints. Dot-sourcing the script loads functions without invoking Arrange or Restore.

Run checks from the repository root. The full Python suite needs Python 3.9+ and `pytest` available in the selected environment:

```text
python -m pytest -q
```

Without third-party Python dependencies, the smaller release smoke suite is available separately:

```text
python tests/test_release.py
```

The dependency-free PowerShell checks exercise classification, layout, and backup data without moving icons:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-PortableTests.ps1
```

For the broader pure-function and mocked orchestration suite, use Pester 5 in a Windows PowerShell session:

```powershell
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.999 -ErrorAction Stop
$result = Invoke-Pester -Path .\tests\Arrange-DesktopIcons.Tests.ps1 -Output Detailed -PassThru
if ($result.Result -ne 'Passed') { throw 'Desktop Edge Arranger tests failed.' }
```

Python checks detect source/release regressions; the PowerShell suites exercise data logic and mocked boundaries. Neither proves live Explorer behavior. For Shell/positioning changes, run Arrange and Restore on a disposable supported Windows profile: check the regions, backup/restore identity behavior, unchanged selection/focus, unchanged icon size and align-to-grid setting, and persistent Auto Arrange disablement. Confirm both processes exit and underlying Desktop item names, paths, and contents stay unchanged. Test invalid preconditions separately without bypassing the guards.
