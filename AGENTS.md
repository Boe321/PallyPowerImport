# PallyPowerImport — agent guide

A single-file WoW (TBC) addon. Reads a **PPI1 string** and applies it to
[PallyPower](https://github.com/AznamirWoW/PallyPower) as a direct assignment.
The string comes from the separate generator repo,
[`Boe321/pallypower-preset`](https://github.com/Boe321/pallypower-preset).

## Files

| File | |
|---|---|
| `PallyPowerImport.lua` | the whole addon |
| `PallyPowerImport.toc` | `## Interface: 20506`, `## Version: @project-version@` (packager fills it) |
| `.pkgmeta` | BigWigs packager config |
| `.github/workflows/` | `ci.yml` (Lua 5.1 syntax + ASCII check), `release.yml` (tag → zip + GitHub Release) |

## Conventions

- **ASCII only.** No literal umlauts — spell them out (`ae`, `oe`, `ue`, `ss`).
  CI fails on any non-ASCII byte.
- **Never `loadstring` / `RunScript` on the pasted text.** `parseImport` is
  data-driven on purpose (a paste is untrusted).
- **All user-facing strings go in the `L` table** near the top.
- **WoW runs Lua 5.1.** No `goto`, no integer division, `#t` not `table.getn`,
  `atan2` may be missing (there is a shim), etc.
- After edits: `luac5.1 -p PallyPowerImport.lua` (CI does this) and eyeball
  `end` / brace balance.
- `VERSION` is `@project-version@`, replaced by the packager; it falls back to
  `"dev"` in a raw checkout — don't hardcode a number.

## PPI1 format

The wire contract with the generator:
[`docs/ppi1-format.md`](https://github.com/Boe321/pallypower-preset/blob/main/docs/ppi1-format.md).
`MAX_FORMAT` is the newest `# format` this addon accepts. A shape change to the
format bumps `# format` in the generator **and** `MAX_FORMAT` here, together, and
both repos release together.

## Releasing

Update `CHANGELOG.md`, then `git tag vX.Y.Z && git push --tags`. The release
workflow runs the BigWigs packager: it builds `PallyPowerImport-vX.Y.Z.zip`
(version from the tag) and creates the GitHub Release. No CurseForge/Wago upload
unless you add the API-key secrets and the `-c` / `-w` flags.
