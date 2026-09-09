# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) ·
versioning: [semver](https://semver.org/).

## [1.0.0] - 2026-09-09

First public release. Packaged via the BigWigs packager into a GitHub Release zip.

- `/ppi` → paste a PPI1 string → **Import**: a direct assignment (like clicking
  the PallyPower grid). Sets `PallyPower_Assignments` /
  `PallyPower_NormalAssignments` / `PallyPower_AuraAssignments` and broadcasts
  `PASSIGN` / `NASSIGN` / `AASSIGN`. `PallyPower_SavedPresets` is never touched.
- Authoritative only for the paladins named in the string; others untouched.
- Broadcasts to other paladins when you are leader / assist or PallyPower's
  "Free Assign" is on; your own assignments always apply.
- Hard error checks only (combat, `# format`, client/expansion, id ranges,
  syntax) — no in-game preview. Data-driven parser, no `loadstring`.
- Accepts the multi-line string or the `PPI1:<base64>` one-liner
  (`/ppi PPI1:<base64>`).
- Minimap button (`/ppi minimap` or the window checkbox), `/ppi version`.
- `## Interface: 20506`.

### Pre-release history

- **0.3.1** - full English pass, `L` string table, `createUI` split into widget
  helpers.
- **0.3** - Import switched from preset-load to direct assignment; preset code
  and the in-game preview removed; `/ppi` opens on the first call.
- **0.2** - combat guard, format / client checks, raid name match, broadcast
  status, remembered window position.
- **0.1** - first prototype.

[1.0.0]: https://github.com/Boe321/PallyPowerImport/releases/tag/v1.0.0
