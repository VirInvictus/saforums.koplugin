# roadmap.md: saforums.koplugin

Phases implement slices of `spec.md`. A phase is done when every box is ticked and the
exit criteria hold on the Kindle Oasis 3, not just in the emulator of the mind.

## Phase 0: skeleton

- [x] Repo scaffold: README, spec, roadmap, patchnotes, AGENTS.md, LICENSE, logo, VERSION.
- [x] Plugin loads in KOReader without errors and registers a menu entry.
- [x] Awful.app reference clone seated in `~/.gitrepos/` and recorded in the workspace catalog.

Exit: sideload to the Oasis, launch from the tools menu, see the Phase 0 stub message.

## Phase 1: vertical slice (login to reading one thread)

- [ ] Test rig: busted + synthetic fixtures in `spec/fixtures/` (fictional text, real
      structure); parser and cookie tests green locally before any device work.
- [ ] HTTP session layer: requests over the bundled socket stack, cookie jar, persistent
      session state, Windows-1252 request encoding and response decoding.
- [ ] Login: `account.php?json=1`, JSON parse, session-validity check (`bbuserid`),
      expired-session handling, settings UI (username/password + cookie import fields).
- [ ] Forum index: parse `index.php?json=1`, navigate the forum tree in a menu.
- [ ] Thread list: parse `forumdisplay.php` rows per the spec selector table, paginated
      menu, unread counts shown.
- [ ] Thread reading: fetch a page with `noseen=1`, parse posts, build the per-thread
      EPUB, open in ReaderUI, page through with the hardware buttons.
- [ ] Cloudflare challenge surfaced as a clear error with the cookie-import fallback
      documented in-app.

Exit: on the Oasis, from a cold start: log in, open a forum, open a thread, read it on
e-ink with page turns; `busted` is green; no request in the whole flow lacked `noseen=1`
except the login itself.

## Phase 2: read state and bookmarks (the lurker loop)

- [ ] "Continue reading" action: `goto=newpost` fetch (marks read as a side effect),
      lands on the first unseen post.
- [ ] Mark unread (`action=resetseen`) per thread from the thread list.
- [ ] Bookmarks: list view, add/remove with star colors per spec.
- [ ] Explicit mark-seen-to-index control.
- [ ] Refresh throttling per spec (15 min per forum list; manual refresh bypass).

Exit: the daily phone loop is fully replaceable on the Oasis: check unread counts,
continue where you left off, manage bookmarks, never silently disturbing server-side
read state.

## Phase 3: reading ergonomics

- [ ] Refresh-in-place: refetch the open thread, regenerate the EPUB, restore the
      last-read chapter.
- [ ] Multi-page threads: fetch next page from inside the reader flow.
- [ ] Position-recovery verification across regeneration (chapter alignment).
- [ ] Settings surface: default forum, perpage, spoiler rendering style.
- [ ] Cookie-expiry warning (7-day threshold, from the cookie's own expiry).

Exit: a long thread (hundreds of posts, many pages) survives refresh, page fetch, and
KOReader restarts without losing the reader's place.

## Phase 4: distribution

- [ ] README install instructions (manual sideload path first).
- [ ] Tag and release v0.2.0 (or whatever VERSION has reached) with the release
      procedure followed in full.
- [ ] Decision gate: submit to the App Store plugin catalog (omer-faruq/appstore.koplugin)
      or keep sideload-only. Brandon's call; the catalog row and screenshots are the work.
- [ ] On-device verify pass on a second KOReader install if available (any distro
      desktop KOReader counts).

Exit: a stranger with a Kobo could install and use it from the README alone.

## Deferred (not scheduled, do not start without a fresh decision)

Reply/quote composition, private messages, search, polls, archives time machine,
ignore list, rap sheet, SAclopedia, inline images. Each was cut from v1 on purpose;
the spec's out-of-scope list is the law until a phase amends it.
