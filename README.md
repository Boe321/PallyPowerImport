# PallyPowerImport

A WoW (TBC) companion addon for
[**pallypower-preset**](https://github.com/Boe321/pallypower-preset). Paste a
**PPI1 string** in game and it writes the blessing / aura assignments straight
into [PallyPower](https://github.com/AznamirWoW/PallyPower) and broadcasts them to
the raid — no client restart, no saved preset touched.

> First release. The core works; the multi-paladin raid path (name matching in a
> live raid, broadcasting to a second paladin, the Free-Assign path) still wants
> testing — please open an issue if something misbehaves.

## Install

Download `PallyPowerImport-vX.Y.Z.zip` from
[Releases](https://github.com/Boe321/PallyPowerImport/releases) and extract it
into `Interface/AddOns/`. It loads after PallyPower (`## Dependencies: PallyPower`).

`## Interface: 20506`. On a different client, enable "Load out of date AddOns" or
edit the line in `PallyPowerImport.toc`.

## Usage

1. Generate a string with
   [pallypower-preset](https://github.com/Boe321/pallypower-preset):
   `npx pallypower-preset <raid-helper-event-id>` (add `--b64` for a one-liner).
2. In game: `/ppi` → paste → **Import**. The window closes on success.
   A one-liner also works directly: `/ppi PPI1:<base64>`.

Slash: `/ppi` (window) · `/ppi PPI1:<b64>` (direct) · `/ppi minimap` (toggle the
minimap button) · `/ppi version`.

The addon is **deliberately lean**: no blessing / diff preview in game. It runs
hard error checks and then imports.

## Import = direct assignment (not a preset)

Import behaves like **clicking the PallyPower grid**: it sets
`PallyPower_Assignments` / `PallyPower_NormalAssignments` /
`PallyPower_AuraAssignments` and broadcasts them (`PASSIGN` / `NASSIGN` /
`AASSIGN`).

- **`PallyPower_SavedPresets` is never touched** — everyone's saved presets stay
  intact.
- **Authoritative only for the paladins named in the string.** Each gets the full
  9-class row + aura + overrides (overrides cleared first). Paladins not in the
  string are left alone.
- **Broadcasting to other paladins** needs raid leader / assist **or** PallyPower's
  "Free Assign". Your own assignments always apply. If neither: yellow hint, and
  Import still runs locally (other clients ignore the messages).
- Not in a raid → local only.

## Checks (hard errors → red, Import disabled)

| Check | |
|---|---|
| Combat | disabled while `InCombatLockdown()` |
| Format version | `# format N` newer than this addon supports (`MAX_FORMAT`) |
| Client / expansion | `# expansion bcc` vs. `PallyPower.Spells`; blessing IDs over the client max |
| Ranges | blessing 0-6, aura 0-8, class 1-9 |
| Syntax | malformed `pala` / `bless` / `over` lines |

The name match runs silently (realm suffix ignored, case-insensitive); matched
paladins get their real in-game name as the key. The parser is **data-driven** —
never `loadstring` on the pasted text.

## PPI1 format

The full spec is
[`docs/ppi1-format.md`](https://github.com/Boe321/pallypower-preset/blob/main/docs/ppi1-format.md)
in the generator repo. It is a versioned wire contract — a shape change bumps
`# format` there and `MAX_FORMAT` here, together.

## Contributing

See [`AGENTS.md`](AGENTS.md). Releases: bump `## Version` is automatic (the
packager fills `@project-version@` from the git tag); update
[`CHANGELOG.md`](CHANGELOG.md), then `git tag vX.Y.Z && git push --tags` — the
[release workflow](.github/workflows/release.yml) builds the zip and the GitHub
Release.

## License

MIT — see [`LICENSE`](LICENSE).
