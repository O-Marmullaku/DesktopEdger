# Desktop Edge Arranger working constraints

This file contains repository-specific safety and evidence boundaries. Keep assistant-, model-, skill-, and orchestration-specific policy outside this file.

- `README.md` owns product behavior, restore/recovery, classification, safety, and verification procedures. `FUTURE.md` is future intent, not current product behavior.
- The utility changes only Explorer desktop icon coordinates. It must not move, rename, copy, edit, or delete underlying desktop files/folders/shortcuts or install persistent background components.
- Arrange must complete validation, classification, full-layout/collision/capacity checks, and verified backup creation before mutation. Invalid preconditions are not permission to weaken these guards.
- Do not run elevated. Do not use Arrange as recovery after a failed Arrange; use the verified Restore path so the failed/current positions do not become the new latest backup.
- Auto Arrange is intentionally disabled by the operation; icon size and Align to grid are not changed.
- Source/unit/mock checks do not establish live Explorer behavior. Shell/positioning changes require the disposable supported-Windows acceptance path described in README.
- Backups contain Shell identities, display names, and coordinates and may reveal filenames/paths. Treat them as local potentially sensitive evidence.
