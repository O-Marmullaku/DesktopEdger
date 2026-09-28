from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Arrange-DesktopIcons.ps1"
LAUNCHER = ROOT / "Arrange-DesktopIcons.bat"
README = ROOT / "README.md"


class ReleaseContractTests(unittest.TestCase):
    def test_required_release_files_exist(self) -> None:
        for path in (SCRIPT, LAUNCHER, README):
            self.assertTrue(path.is_file(), f"missing release file: {path.name}")

    def test_script_contains_public_contract(self) -> None:
        text = SCRIPT.read_text(encoding="utf-8")
        required = [
            "param(",
            "[ValidateSet('Arrange', 'Restore')]",
            "$ForceApplication",
            "$ForceGame",
            "$ForceMusic",
            "$ForceRight",
            "function New-OverrideMap",
            "function Test-OverrideConfiguration",
            "function Get-DesktopItemCategory",
            "function New-DesktopLayoutPlan",
            "function Test-DesktopLayoutPlan",
            "function Write-DesktopLayoutBackup",
            "function Read-DesktopLayoutBackup",
            "function Get-LatestDesktopLayoutBackup",
            "function New-RestorePlan",
            "function Invoke-DesktopEdgeArranger",
            "DesktopEdgeArranger.ShellDesktopAdapter",
            "IFolderView",
            "GetSpacing",
            "GetItemPosition",
            "SelectAndPositionItems",
            "FindWindowSW",
            "QueryActiveShellView",
            "ThrowIfFailed",
            "Marshal.FreeCoTaskMem",
            "SetCurrentFolderFlags",
            "FVO_CUSTOMPOSITION",
            "SVSI_NOSTATECHANGE",
        ]
        for token in required:
            self.assertIn(token, text, f"script missing contract token: {token}")

    def test_script_is_one_shot_and_does_not_move_files(self) -> None:
        text = SCRIPT.read_text(encoding="utf-8")
        forbidden = [
            r"\bRegister-ScheduledTask\b",
            r"\bNew-ScheduledTask\b",
            r"\bStart-Job\b",
            r"\bRegister-ObjectEvent\b",
            r"\bFileSystemWatcher\b",
            r"CurrentVersion\\Run",
            r"Set-ExecutionPolicy",
            r"while\s*\(\s*\$true\s*\)",
            r"for\s*\(\s*;;\s*\)",
            r"\bMove-Item\b",
            r"\bRename-Item\b",
            r"\bCopy-Item\b",
            r"\bRemove-Item\b",
        ]
        for pattern in forbidden:
            self.assertIsNone(re.search(pattern, text, re.IGNORECASE), pattern)

    def test_launcher_runs_sibling_script_once_in_sta(self) -> None:
        text = LAUNCHER.read_text(encoding="utf-8")
        self.assertIn("WindowsPowerShell\\v1.0\\powershell.exe", text)
        self.assertIn("-NoProfile", text)
        self.assertIn("-STA", text)
        self.assertIn("-ExecutionPolicy Bypass", text)
        self.assertIn('"%~dp0Arrange-DesktopIcons.ps1"', text)
        self.assertIn("%*", text)
        self.assertIn('set "exitCode=%errorlevel%"', text)
        self.assertIn('if not "%exitCode%"=="0"', text)
        self.assertIn("pause >nul", text)
        self.assertRegex(text, r"(?im)^exit\s+/b\s+%exitCode%\s*$")

    def test_readme_documents_safety_and_restore(self) -> None:
        text = README.read_text(encoding="utf-8")
        for token in [
            "Arrange-DesktopIcons.bat",
            "-Mode Restore",
            "%LOCALAPPDATA%\\DesktopEdgeArranger\\Backups",
            "$ForceApplication",
            "$ForceGame",
            "$ForceMusic",
            "$ForceRight",
            "single-monitor",
            "does not move",
            "Auto arrange",
        ]:
            self.assertIn(token.lower(), text.lower())

    def test_powershell_and_csharp_delimiters_are_balanced(self) -> None:
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertEqual(text.count("@'"), text.count("'@"), "single-quoted here-string mismatch")
        self.assertEqual(text.count('@"'), text.count('"@'), "double-quoted here-string mismatch")

        # Lightweight lexical balance check; ignores quoted text and comments.
        scrubbed = []
        in_single = in_double = False
        i = 0
        while i < len(text):
            ch = text[i]
            nxt = text[i + 1] if i + 1 < len(text) else ""
            if not in_single and not in_double and ch == "#":
                while i < len(text) and text[i] not in "\r\n":
                    i += 1
                continue
            if ch == "'" and not in_double:
                if in_single and nxt == "'":
                    i += 2
                    continue
                in_single = not in_single
                i += 1
                continue
            if ch == '"' and not in_single:
                if i > 0 and text[i - 1] == "`":
                    i += 1
                    continue
                in_double = not in_double
                i += 1
                continue
            if not in_single and not in_double:
                scrubbed.append(ch)
            i += 1
        clean = "".join(scrubbed)
        pairs = {"(": ")", "[": "]", "{": "}"}
        stack: list[str] = []
        for ch in clean:
            if ch in pairs:
                stack.append(ch)
            elif ch in pairs.values():
                self.assertTrue(stack, f"unexpected closing delimiter: {ch}")
                opening = stack.pop()
                self.assertEqual(pairs[opening], ch, f"delimiter mismatch: {opening} ... {ch}")
        self.assertFalse(stack, f"unclosed delimiters: {stack[-10:]}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
