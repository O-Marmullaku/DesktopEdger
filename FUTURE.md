# Future product intent

**Not implemented; not an executable setup profile.** The current utility's contract is in [README.md](README.md). These requests must not silently expand an icon-positioning fix into machine provisioning.

The primary intent comes from the owner's **2026-09-09 founder edit**. The accompanying product/design notes contribute design considerations, but supply no separate approval record or implementation priority. The workstation values below describe that reinstall; they are neither a current machine inventory nor universally safe defaults. They remain here because they are not recoverable from the arranger's source.

## Requested capabilities and unresolved scope

**Broader display support.** The owner wrote “multiple windows”; the accompanying notes interpreted this as multiple monitors. The display preferences below make that interpretation plausible, but application windows, monitors, and Windows virtual desktops are distinct. Confirm the intended scope before removing the single-monitor guard. Multi-monitor design would need region ownership, Recycle Bin placement, negative/offset coordinates, topology-change and disconnect behavior, and backup/restore acceptance across those changes.

**GUI placement rules.** The owner wants to decide what goes where instead of accepting confusing mixtures of shortcuts, folders, and files. The design considerations are stable identities with readable labels, per-item/category rules, preview and conflict validation, persistence/migration, and handling new or unknown items. This concerns visual layout, not moving underlying files.

**Personal Windows re-setup.** After an OS reinstall, reconstruct selected workstation preferences, applications, and supported profile/configuration state with less manual setup and fewer repeated sign-ins. It is undecided which actions are automatic, preview-and-confirm, or always interactive; whether profiles are personal/machine-specific or reusable; and which capability should be implemented first.

## Candidate workstation preferences

These are concrete discovery inputs, not a sequence of instructions to replay.

### Applications and supported profile migration

The owner named Firefox, Chrome, Thunderbird, Everything (Voidtools), Steam, NVIDIA App, EXPERTool, Driver Easy, Revo Uninstaller Pro, Office, f.lux, qBittorrent, Photoshop, VEGAS/media tooling, Focusrite Control 2, and OBS Studio. Preserve the desired software outcomes, not the old acquisition methods; exact supported versions, licenses, and install sources need confirmation.

Apollo and Moonlight require special care: the owner deliberately reused **specific versions and old configurations**, but did not record those version numbers or configuration paths. Do not substitute arbitrary newer versions or claim that profile migration has been verified.

Observed package identifiers help disambiguate the request, without pinning a future installer: EXPERTool v11.13 (lighting set to **off**), an Office x64 English installer identified as `O365AppsBasicRetail` / `O16GA`, and Photoshop 2026. The notebook calls the editor “Sony Vegas” and associates it with Boris FX Hub; confirm the intended product/vendor rather than assuming that association is correct.

The owner wanted browser/mail/application account state to survive so sign-ins need not be repeated. No supported mechanism, permission scope, or guarantee of retaining authentication was established. Prefer vendor-supported sync, export/import, or approved profile migration; do not scrape protected credentials or put passwords, tokens, private keys, or license secrets in the repository or setup profiles. Authentication, licensing, and consent may remain interactive.

### Storage and paths

- Restore preferred drive letters, but first resolve conflicts: the drive named **Elements** occupied a required letter during the reinstall. The full desired mapping was not supplied.
- Relocate user folders to the **2 TB WD Black** drive; exact destination paths were not supplied.
- Put **FFmpeg on PATH without installing deprecated JohnnyTools**. The previous setup unexpectedly installed that unrelated toolset.
- Retain the Steam library preference `B:\GAMES_permanent\MiddleMan\Steamapps`, validating the actual library root and available volume before use.

External setup inputs mentioned by the owner were **not supplied with this project**: `I:\SOFTWARE\.Scriptz\Set_Drive_Letters.bat`, `set_user_folders_2tb_wd_black.bat`, and an FFmpeg setup script recorded as `setup_ffmpeg_pathb.at` (spelling unconfirmed). They are provenance for recovering missing mappings, not runnable repository commands. Do not infer their behavior from their names.

### Taskbar, Start, search, and personalization

Hide taskbar search; pin Everything; unpin Edge and Microsoft Store; disable taskbar-app flashing. Keep Start pins only for **Calculator, Settings, WhatsApp, Notepad, and Paint**. Hide recently added apps, recommended/recommendation content, and all folders next to Start's power button.

Enable clipboard history. Use enhanced file search with `C:\Windows` left excluded, and index the desired drives except **Elements**, observed then as `K:`. Drive identities must be checked rather than treating that historical letter as permanent.

Use `E:\FamilyMedia\Wallpapers\Wallpapers 2023` as a slideshow and save/select the resulting theme. The owner reported that saving the theme avoids problems when opening a new desktop; this is owner-observed rationale, not a verified Windows guarantee. The selected profile-picture reference was [this image](https://static1.bigstockphoto.com/7/0/2/large1500/207582136.jpg); availability and reuse rights have not been established.

### Input, Bluetooth, and displays

Disable mouse acceleration. For the **ASUS USB-BT500**, the notebook names driver input `I:\SOFTWARE\DR_USB-BT500_v1009` and reports a need to disable an older Bluetooth adapter/driver. The keyboard and game controller needed pairing again. Preserve the desire to reduce re-pairing, but hardware IDs, driver compatibility, and whether supported pairing-state migration is possible remain unknown.

The recorded display preference is **Zowie XL LCD at 240 Hz**, with **Denon AVR at 800×600**. When the projector is active, make it the main display and disable other displays except the projector and Denon AVR; the owner wants that configuration remembered. Confirm device identities and modes on the target machine, and define recovery from a lost display before automating this.

### Windows features and security-sensitive choices

The owner selected a private network profile, optional .NET Framework 2/3/4 components, Hyper-V, Windows Sandbox, verbose crash/login/logout information, and classic Explorer context-menu/command-bar behavior. Revalidate feature availability and UI/registry mechanisms against the target Windows version; preserve the desired effect rather than replaying old registry commands or remote scripts.

The reinstall also recorded **automatic logon**, **UAC “never notify”**, and **CurrentUser RemoteSigned** execution policy. These observations are not approved automation defaults. Their security consequences, privilege model, and any credential handling need a separate decision; this utility's process-only execution-policy setting does not authorize persistent policy changes.

## Conditions before setup automation

Use legitimate, authorized software sources and licensing. The reinstall notes included unvalidated activation/crack/torrent acquisition methods; those methods are not product requirements or authorization to reproduce them.

Separate portable preferences from machine-specific paths, drive identities, display IDs, and device state. Each consequential installer, registry, policy, driver, drive-letter, user-folder, network, or display action needs explicit scope, preflight/preview, privilege and consent boundaries, repeat-run behavior, and proportionate recovery/rollback. Preserve user data. A future setup assistant needs its own design rather than adding these responsibilities to the Explorer adapter.
