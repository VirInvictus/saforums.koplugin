# AGENTS.md: saforums.koplugin

Guidance for coding agents working in this repo. Overrides the global `~/.zcode/AGENTS.md`
where the two conflict; otherwise the global file applies.

## What this is

A KOReader plugin (Lua) that reads the Something Awful Forums on e-ink devices.
Repo root is the plugin root: `main.lua` and `_meta.lua` install as
`koreader/plugins/saforums.koplugin/`.

- `spec.md` is the contract: endpoint table, HTML structure, Typography, Voice,
  Rendering. Parser changes without a matching spec and fixture update are wrong.
- `PARITY.md` is the 1:1 Awful.app parity program (Brandon's directive). Wave A
  reading parity, Wave B lists/bookmarks, Wave C composition (gate open),
  Wave D gated surfaces. This supersedes the old deferred list.
- `roadmap.md` remains the phase ledger for the core loop (Phases 0-6).

## Current state (updated 2026-10-09, late)

v0.3.0 released; v0.3.0 tagged on GitHub with zip asset; CI runs busted on
every push and builds the release zip on every `v*` tag.

**Wave A of PARITY.md is implemented on main** (reading parity): token
retune to the reference's colors, quote collapse at 3 lines, spoiler cards
with per-post tap-to-reveal, mark-read-to-here (setseen POST + live
re-tint), hold-for-post-menu (copy URL / copy text / mark read), role
badges ([admin]/[mod]/[PT]) with per-forum regdate suppression
(26/154/196/268), mention + quoted-you markers, image blocks with
tap-to-view + dead-image message, jump-to-page on the page label,
tweet/bsky/video/linked-image placeholders, smilies as typed codes, and the
centered end marker. 185 tests green. Device-verified in the kodev emulator
on a live thread (spoiler toggle, badges, end marker, page label); quote
collapse, hold menu, jump dialog, and the image viewer have unit coverage
but no device pass yet.

Three hardening bugs Wave A surfaced, all fixed: the native view never ran
sanitize_body before postblocks (raw HTML meant `<br>` never split
paragraphs, images vanished, spoilers stayed unmasked; the view and
post_plain_text now sanitize first); TextBoxWidget fills its own buffer
with a white bgcolor default, which painted over the spoiler card's black
and the seen tint (every card text widget now carries the card's bgcolor);
and session cookies rode on every request host (the cookie header is now
scoped to *.somethingawful.com, sealing a leak to third-party image CDNs).

Interaction plumbing worth knowing: the ScrollableContainer ignores hold
events (they belong to the post menu); ThreadView handles Hold itself by
hit-testing card rects recorded at build time, and taps reach TapArea
widgets (a local InputContainer subclass) inside the scrolled content
because tap is the one gesture the scroll container does not claim. A
throwaway `saforums-devview.koplugin` in the emulator checkout renders the
view on synthetic fixture content without a session (delete whenever).

## Hard-won lessons (each cost a debugging round — do not re-learn)

1. **Plugin main.lua must return a WidgetContainer:extend class.** PluginLoader
   does `pcall(plugin.new, plugin, attr)` — a plain table fails with
   "attempt to call a nil value" and the plugin silently vanishes from the menu.
   Dispatcher actions go in `onDispatcherRegisterActions()`, menu registration
   in `init()` via `self.ui.menu:registerToMainMenu(self)`.

2. **ScrollableContainer requires `show_parent = self`.** Without it,
   `_scrollBy` calls `UIManager:setDirty(nil, ...)` which flags NO widget for
   repaint. The internal offset advances, repaints are enqueued, but
   `paintTo` never runs — the screen shows the same frame forever. Also set
   `self.cropping_widget = scrollable` on the outer widget so UIManager
   confines inner subwidget self-repaints to the scroll area.

3. **Never use `_` as a loop variable in gettext-scoped files** (main.lua,
   saforums/ui.lua). gettext's function is named `_`; the loop index shadows
   it; the next `_("literal")` inside the loop calls a number. Source-hygiene
   spec enforces this. Pure layers (no gettext) keep the idiom.

4. **GET requests must NOT carry a body source.** `ltn12.source.string(nil)`
   fails silently inside LuaSocket's protected wrapper → nil return → no
   error, no scroll, no crash. Only set request.source when a body exists.

5. **KOReader's Archiver `Writer:close()` returns nothing.** Check `.err`
   after close, not the return value. The EPUB was building correctly and
   being thrown away by a `if not epub:close()` check.

6. **DataStorage:getDataDir() returns relative `"."` on the Kindle.** Use
   `getFullDataDir()` for absolute paths.

7. **ScrollableContainer's dimen must have x/y for gesture hit-testing.**
   `ges.pos:intersectWith(self.dimen)` fails against an unpositioned Geom,
   so pans and swipes are silently rejected. Set x=0, y=titlebar height.

8. **mupdf's HTML engine ignores CSS floats entirely** and wraps inline-block
   elements. If you need side-by-side layout in rendered HTML, use a table
   (mupdf renders tables solidly).

9. **The gettext `_` shadow trap** (see item 3) also applies to threadview.lua,
   which has gettext in scope. The source-hygiene spec enforces this — add
   new gettext-scoped files to its file list.

10. **The uimanager stub race between spec files.** busted loads spec files
    alphabetically; the first `package.preload` registration wins. All spec
    files that stub ui/uimanager must have the same shape (show, close,
    nextTick, setDirty, scheduleIn). Currently unified in scroll_spec and
    ui_smoke_spec.

## Hard rules specific to this repo

- **No real SA content in the repo.** Test fixtures are hand-authored HTML
  with fictional text preserving the site's element structure only. Never
  commit scraped pages, posts, usernames, or avatars. The repo is public.
- **Contract, not code, from Awful.app.** The reference clone at
  `~/.gitrepos/Awful.app` is read-only and unlicensed. Take facts (endpoints,
  parameter names, cookie names, HTML structure); copy no code.
- **KOReader-bundled runtime libraries only.** `htmlparser`, the socket stack,
  `util`, `gettext`, `logger`, standard widgets. No luarocks deps at runtime.
  busted is a dev-only exception.
- **Cookies are credentials.** Never in logs, fixtures, commits, or docs.
- **`noseen=1` on every implicit fetch.** Only the explicit continue action
  (goto=newpost without noseen) may touch server-side read state.
- **Never use `_` as a loop variable in gettext-scoped files.** See above.

## Language and API notes

- Lua 5.1 compatible (KOReader runs LuaJIT on device); tests run under
  system Lua 5.4. Stay in the 5.1 subset.
- **Never use `_` as a loop variable in gettext-scoped files** (main.lua,
  saforums/ui.lua, saforums/threadview.lua). See hard-won lesson 3.
- Target API floor: KOReader v2026.03 (Brandon's Kindle Oasis 3). Verify
  APIs exist in the dev checkout at `~/.local/share/koreader-dev/frontend/`
  before using them.
- Match KOReader plugin idiom: `gettext` wrappers on user-facing strings,
  `logger` for diagnostics.

## Build, test, run

- No build step. Keep every file loadable by LuaJIT; tests run under Lua 5.4.
- Tests: `eval "$(luarocks path --local)"; ~/.luarocks/bin/busted spec/unit`
  from the repo root. Fixtures under `spec/fixtures/` (synthetic only);
  stubs in `spec/stubs.lua`; the pinned htmlparser is under
  `spec/vendor/htmlparser/`.
- **Emulator iteration (primary dev loop):**
  ```
  cd ~/.local/share/koreader-dev && ./kodev run
  ```
  The plugin is symlinked at `plugins/saforums.koplugin` → the real repo.
  Edits are live; just restart kodev. The emulator has network, so login
  and thread fetching work. First build took ~15 min; subsequent builds
  are cached. The dev checkout is 2.6 GB at `~/.local/share/koreader-dev`
  (separate from the read-only reference clone at `~/.gitrepos/koreader`).
- Deploy for a Kindle device pass: rsync to
  `/mnt/Kindle/koreader/plugins/saforums.koplugin/` (vfat over sshfs, with
  the excludes from the command in .gitignore comments), restart KOReader,
  read `koreader/crash.log` first. The mount only exists while KOReader is
  running.
- CI: GitHub Actions runs busted on every push to main and builds the zip
  release on every `v*` tag (see `.github/workflows/ci.yml`).

## Architecture

- `main.lua` — plugin entry (WidgetContainer:extend class; registration in
  init, menu in addToMainMenu, sorting_hint "tools", position via
  `inject_saforums_into_tools_menu`)
- `saforums/config.lua` — site constants, version
- `saforums/cp1252.lua` — Windows-1252 codec
- `saforums/json.lua` — JSON decoder (pure Lua 5.1)
- `saforums/cookiejar.lua` — comma-safe Set-Cookie jar
- `saforums/session.lua` — HTTP session (login, redirects, cookies,
  Cloudflare detection, injectable transport)
- `saforums/threadlistparser.lua` — forumdisplay/bookmarkthreads parser
- `saforums/postspageparser.lua` — showthread parser (posts, sidebar,
  pagination, jump targets)
- `saforums/indexparser.lua` — index.php?json=1 parser
- `saforums/htmltext.lua` — entity decode, trim, class helpers
- `saforums/posthtml.lua` — shared sanitizer (bold/italic/quote/spoiler/
  image stripping to placeholders)
- `saforums/postblocks.lua` — sanitized HTML → layout blocks (para/quote/
  image) with PTF bold markers
- `saforums/threadview.lua` — the native full-screen post view (FrameContainer
  cards, ScrollableContainer, ImageWidget avatars, TextWidget header stack)
- `saforums/avatars.lua` — avatar cache (one fetch per poster, raw bytes)
- `saforums/retention.lua` — LRU shelf cap (default 100, enforced at start)
- `saforums/epubbuilder.lua` — DORMANT (EPUB rendering path, kept tested)
- `saforums/threadhtml.lua` — DORMANT (HTML renderer for the EPUB path)

Dormant modules are tested and committed but not called from the active
code path. They exist so the feature can be revived without a rewrite.

## Version

`VERSION` is the single source (currently 0.3.0). `_meta.lua` version and
`saforums/config.lua` version must match (test-pinned in meta_spec and
cookiejar_spec). Release tags `vX.Y.Z` trigger CI to build and attach the
zip. The App Store plugin manager regex-extracts `_meta.lua` version for
update detection.

## References

- `PARITY.md` — the 1:1 Awful.app program (Wave A-D)
- `spec.md` — the full contract (endpoints, HTML, Typography, Voice,
  Rendering, Semantics)
- `~/.gitrepos/Awful.app` — read-only reference clone (scraping facts,
  design tokens, voice register; unlicensed upstream: facts only)
- `~/.gitrepos/koreader` — read-only reference clone (API truth)
- `.repos/` — community plugin shelf (read-only, git-ignored)
