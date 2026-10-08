# AGENTS.md: saforums.koplugin

Guidance for coding agents working in this repo. Overrides the global `~/.zcode/AGENTS.md`
where the two conflict; otherwise the global file applies.

## What this is

A KOReader plugin (Lua) that reads the Something Awful Forums as EPUBs. Repo root is the
plugin root: `main.lua` and `_meta.lua` install as `koreader/plugins/saforums.koplugin/`.

- `spec.md` is the contract. The endpoint table and the HTML structure section are the
  law; parser changes without a matching spec and fixture update are wrong.
- `roadmap.md` phases are the worklist. Deferred features (posting, PMs, search, polls)
  are cut on purpose; do not start them without a fresh decision from Brandon.

## Hard rules specific to this repo

- **No real SA content in the repo.** Test fixtures are hand-authored HTML with fictional
  text that preserves the site's element structure only. Never commit scraped pages,
  posts, usernames, or avatars. The repo is public.
- **Contract, not code, from Awful.app.** The reference clone at `~/.gitrepos/Awful.app`
  is read-only and unlicensed upstream. Take facts (endpoints, parameter names, cookie
  names, HTML structure); copy no code from it in any language.
- **KOReader-bundled runtime libraries only.** `htmlparser`, the socket stack, `util`,
  `gettext`, `logger`, standard widgets. No luarocks dependencies at runtime. busted is
  a dev-only exception (below).
- **Cookies are credentials.** `bbuserid`/`bbpassword` never appear in logs, fixtures,
  commits, or docs. The plugin settings file is the only place they live on device.
- **`noseen=1` on every implicit fetch.** Only explicit user actions may touch
  server-side read state. See spec Semantics.

## Language and API notes

- Lua 5.1 compatible (KOReader runs LuaJIT). No `goto`, no integer division `//`, no
  5.2+ stdlib assumptions.
- **Never use `_` as a loop variable in files where gettext is in scope**
  (`main.lua`, `saforums/ui.lua`): gettext's function is named `_`, the loop index
  shadows it, and the next `_("literal")` inside the loop calls a number. Name the
  placeholder (`for _idx, ...`). A source-hygiene spec enforces this.
- Target API floor: KOReader v2026.03 (Brandon's Kindle Oasis 3). When reaching for a
  KOReader API, verify it exists in a checkout of that vintage or newer; the local
  reference checkout for API truth is the koreader upstream source.
- Match KOReader plugin idiom: `gettext` wrappers on all user-facing strings, `logger`
  for diagnostics, `Trapper`/`ConfirmBox` for anything that needs an answer.

## Build, test, run

- There is no build step. Keep every file loadable by LuaJIT (the device
  runtime); tests run under the system Lua 5.4, so stay in the 5.1 subset.
- Tests: busted, installed once as a dev-only luarock
  (`luarocks --local install busted`), run from the repo root:
  `eval "$(luarocks path --local)"; ~/.luarocks/bin/busted spec/unit`.
  Every parser has synthetic fixtures under `spec/fixtures/`; new parsing
  behavior lands fixture-first. `spec/stubs.lua` provides the KOReader module
  stubs and the fake archiver; `spec/vendor/htmlparser/` is the test-only
  pin of the parser KOReader bundles at runtime (same commit as
  koreader-base; see its PROVENANCE.md, do not modify).
- Deploy for a device pass: copy the repo to
  `/mnt/Kindle/koreader/plugins/saforums.koplugin/` (vfat over sshfs:
  `rsync -rc --delete --no-perms --no-owner --no-group --modify-window=2
  --exclude=.git --exclude=.repos`), restart KOReader, read `koreader/crash.log`
  first when anything misbehaves. The mount only exists while KOReader is running;
  do not write `settings.reader.lua` or plugin settings while KOReader is live.
- `.repos/` is the reference shelf: community plugins mined for the typography,
  design, humor, and marketplace research (plus Awful.app at
  `~/.gitrepos/Awful.app` for voice). Read-only, git-ignored, never deployed,
  never modified. Conclusions already live in `spec.md`; do not re-mine them.

## Version

`VERSION` is the single source (currently 0.1.0). There is no pyproject/Cargo here;
release tags `vX.Y.Z` carry versions, which is also how the App Store plugin manager
detects updates. Bump `VERSION` and add a `patchnotes.md` entry in the same commit.
