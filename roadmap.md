# roadmap.md: saforums.koplugin

Phases implement slices of `spec.md`. A phase is done when every box is ticked and the
exit criteria hold on the Kindle Oasis 3, not just in the emulator of the mind.

Three standing emphases shape every phase below, per Brandon's direction: excellent
typography and design, forum-culture humor in permanent surfaces, and first-class
KOReader ecosystem citizenship. The research base for all three lives in `.repos/`
(read-only reference shelf, git-ignored): bookends, bookshelf, webbrowser,
readinginsights, appstore, storefront, hardcoverapp, plus the stock wallabag,
newsdownloader, and coverbrowser in the koreader checkout, and Awful.app for voice.

## Phase 0: skeleton

- [x] Repo scaffold: README, spec, roadmap, patchnotes, AGENTS.md, LICENSE, logo, VERSION.
- [x] Plugin loads in KOReader without errors and registers a menu entry.
- [x] Awful.app reference clone seated in `~/.gitrepos/` and recorded in the workspace catalog.

Exit: sideload to the Oasis, launch from the tools menu, see the Phase 0 stub message.

## Phase 1: vertical slice (login to reading one thread)

- [x] Test rig: busted + synthetic fixtures in `spec/fixtures/` (fictional
      text, real structure); parser and cookie tests green locally before any device work.
- [x] HTTP session layer: requests over the bundled socket stack, cookie jar, persistent
      session state, Windows-1252 request encoding and response decoding. (Transport
      code written against socketutil/ssl.https; live-network pass pending below.)
- [ ] Live verification of login, forum index, thread list, thread reading, and the
      Cloudflare error path on the Oasis. Code for all of it is in place; nothing
      gets ticked until it has talked to the real site once.

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
- [ ] Voice pass on every string the loop touches (spec: Voice and humor): empty
      bookmark list, no-new-posts state, session expiry. Deadpan, membership
      vocabulary, no snark at the user.

Exit: the daily phone loop is fully replaceable on the Oasis: check unread counts,
continue where you left off, manage bookmarks, never silently disturbing server-side
read state.

## Phase 3: the typography pass (art-directed, deferential)

The default type theme ships per spec: designed structure, inherited typography.

- [ ] The thread-EPUB stylesheet to spec (spec: Typography): em/urem units only,
      no font-family, no line-height, `body { margin: 0 }`, #555 meta ink, #888
      hairlines, two-tier post headers, blockquote left rules, no background
      decoration, none of the known-dead crengine features.
- [ ] Two themes behind one setting: Art-directed (default) and Reader's way
      (near-empty CSS). Theme switch requires no rebuild wizardry: the next
      regeneration picks it up.
- [ ] Build-time truncation budgets for titles, usernames, and signature blocks,
      with real ellipsis characters; post chrome never wraps into orphans.
- [ ] `lang` attributes on post prose; balanced-HTML sanitizer upgrade: prefer
      `cre.getBalancedHTML` (pcall-guarded, as newsdownloader uses it) over our
      regex repair, keeping the regex path as fallback.
- [ ] End-of-thread marker line after the last post (setting, default on).
- [ ] YOSPOS flavor: threads from forum 219 render post bodies in generic
      monospace when the flavor setting is on (spec: Rendering).
- [ ] Typography exit review against the Oasis with the production reading setup
      (Libron R, tuned margins, style tweaks on): no fight with any user setting,
      no px-sized anything, blockquotes and spoilers legible at a glance.

Exit: a thread EPUB read cold looks deliberate: clear post rhythm, quiet chrome,
author/date hierarchy, and nothing that breaks when the user changes their reading
font or enables a style tweak.

## Phase 4: reading ergonomics and refresh

- [ ] Multi-page threads: fetch next/previous page from inside the reader flow,
      chapters appended to the same EPUB (Trapper-wrapped, tap-to-cancel fetches
      with the throttled progress-message pattern).
- [ ] Refresh-in-place: refetch the open thread, regenerate through `.tmp` +
      rename, restore the last-read chapter (chapter-anchored position recovery;
      the `.sdr` sidecar is never deleted).
- [ ] Skip-if-fresher guard: per-thread last-post stamp in settings compared before
      refetch (wallabag's updated-times-mtime model, no database).
- [ ] Refresh summary as one quiet InfoMessage box (downloaded / skipped / failed),
      never a wall of dialogs.
- [ ] Stale-while-revalidate list rendering: paint the cached list instantly,
      refresh behind it, and deep-compare results so unchanged data triggers no
      e-ink redraw.
- [ ] Settings surface: default forum, perpage, spoiler rendering style, type
      theme, end-of-thread marker, forum flavors.
- [ ] Cookie-expiry warning (7-day threshold, from the cookie's own expiry).

Exit: a long thread (hundreds of posts, many pages) survives refresh, page fetch, and
KOReader restarts without losing the reader's place, and a 40-thread refresh reads as
one quiet message.

## Phase 5: distribution

- [ ] Marketplace contract, all of it (spec: Platform): `_meta.lua` name + plain-string
      version in lockstep with VERSION and the tag (done 2026-10-08, test-pinned);
      GitHub topic `koreader-plugin`; repo named `saforums.koplugin` (the `.koplugin`
      suffix is a discovery path in both catalogs); repo About description written
      (it is the catalog description, not `_meta.lua`); every release carries a
      `.zip` asset (mandatory for Storefront, first zip asset wins).
- [ ] README install instructions (manual sideload path first).
- [ ] Tag and release with the release procedure followed in full; verify the
      App Store update check sees the tag (version-based, not mtime).
- [ ] Voice polish pass on everything a stranger hits first: first-login copy, the
      Cloudflare error, the About screen ("not endorsed by Something Awful" line
      included).
- [ ] Submit/confirm listing in the App Store catalog, then Storefront; verify a
      cold install from each on a second KOReader install (desktop KOReader counts).
- [ ] Stretch, only after everything above: one deliberately rare, harmless easter
      egg in the Magic Cake pattern (found, not sought; never documented in-app).

Exit: a stranger with a Kobo installs it from a catalog, reads a thread, and one in
ten grins at the right moment.

## Deferred (not scheduled, do not start without a fresh decision)

Reply/quote composition, private messages, search, polls, archives time machine,
ignore list, rap sheet, SAclopedia reader, inline images, custom-designed thread-list
widgets beyond KOReader's Menu (the bookshelf-grade region system is the model if
ever approved), charts and reading-stat tie-ins.
