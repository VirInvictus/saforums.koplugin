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
- [x] Live verification on the Oasis (2026-10-08 device pass): login, forum index,
      thread list, and thread reading all confirmed against the real site; every
      thread fetch logged with `noseen=1`; `busted` green throughout. Three real
      bugs found and fixed on-device (plugin class shape, a GET body-source bug,
      an archiver close-semantics misread), each now pinned by a test. The
      Cloudflare error path is unit-tested but was never exercised live (no
      challenge occurred; it is episodic by nature) and gets re-checked whenever
      one does.

Exit: met on the Oasis, 2026-10-08: from a cold start: log in, open a forum, open a
thread, read it on e-ink with page turns; no request in the whole flow lacked
`noseen=1` except the login itself.

## Phase 2: read state and bookmarks (the lurker loop)

- [x] "Continue reading" action (2026-10-08): `goto=newpost` fetch (marks read
      as a side effect), landing on the first unseen post via the redirect's
      `#pti` jump target, seen tint approximating the pre-view state.
- [x] Mark unread (`action=resetseen`) per thread from the bookmark shelf hold
      menu (2026-10-08).
- [x] Bookmarks: list view with unread counts and pagination (2026-10-08);
      tapping a bookmark is the continue action. Still open: add-bookmark from
      the thread view and star-color display.
- [ ] Explicit mark-seen-to-index control.
- [ ] Refresh throttling per spec (15 min per forum list; manual refresh bypass).
      Deferred until thread lists are cached on device: a throttle with nothing
      to reuse is theater.
- [ ] Voice pass on every string the loop touches (spec: Voice and humor): empty
      bookmark list, no-new-posts state, session expiry. Deadpan, membership
      vocabulary, no snark at the user.

Exit: the daily phone loop is fully replaceable on the Oasis: check unread counts,
continue where you left off, manage bookmarks, never silently disturbing server-side
read state.

## Phase 3: the typography pass (art-directed, deferential)

The default type theme ships per spec: designed structure, inherited typography.
The first slice landed live on 2026-10-08 after Brandon saw the unstyled output and
pulled this phase forward: bordered post cards, two-tier post heads, left-aligned
body text, and avatars (pulled from "v1 never" to first-class by the same verdict).

**Architecture notes, same day, verdicts two and three:** the EPUB-in-ReaderUI
route lost to reality twice over (crengine's CSS ceiling made the cards look wrong
on device, and every thread polluted the bookshelf history). Threads then moved to
a ScrollHtmlWidget view - which lost the third round when mupdf's CSS gaps (no
floats, wrapped inline-blocks, ignored font-family) capped the design again.
Threads now render as **native KOReader widgets** (`postblocks` block model +
`threadview` composition); both the EPUB builder and the HTML renderer are
dormant-but-tested. Spec (Rendering) is the contract for the native surface.

- [x] Post anatomy (2026-10-08): bordered post cards, avatar + bold author +
      italic custom title + gray meta line (date, post #), left-aligned body with
      paragraph spacing, styled edited-by lines, blockquote left rules.
- [x] Avatars: parsed from the userinfo sidebar, cached per user id on device,
      embedded beside the author (data URIs in the in-app view; the EPUB builder
      embeds them as zip assets); failures are cosmetic.
- [x] In-app ThreadView: full-screen scrollable HTML view with page keys, swipe,
      back-to-close, per-thread scroll-position memory, zero reader side effects
      (no history, no sidecars). Replaces EPUB-in-ReaderUI as the reading surface
      (2026-10-08, Brandon's call after the on-device verdict).
- [x] Awful.app design port: the posts-view theme transcribed to grayscale
      (post cards, seen tint, avatar/name-and-date header, OP badge, dense
      14-unit body text, frog end marker) per Brandon's "a port of THAT"
      direction; the LESS files in the reference clone are the design law.
- [ ] The thread-EPUB stylesheet to spec (spec: Typography): em/urem units only,
      no font-family, no line-height, `body { margin: 0 }`, #555 meta ink, #888
      hairlines, two-tier post headers, blockquote left rules, no background
      decoration, none of the known-dead crengine features. (First version of
      everything above is in and on the device; this box closes on Brandon's
      on-device verdict.)
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

- [x] Multi-page threads: in-view page navigation (pseudo-link page nav above
      and below the posts, `noseen=1` fetches, frog line only on the last page;
      2026-10-08). Still open: Trapper-wrapped cancellable fetches.
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
- [x] Retention: LRU cap on the thread-book shelf (default 100, enforced at
      plugin start, sidecar + history + collection cleanup), policy and cap
      recorded in spec (2026-10-08).
- [ ] Settings surface: default forum, perpage, spoiler rendering style, type
      theme, end-of-thread marker, forum flavors, retention cap.
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

## Phase 6: composition, Tier 1 (gated)

**Gate: this phase does not start until Phase 2's exit holds AND the lurker loop has
survived real daily use long enough for Brandon to still want it.** Opening the gate
is his call, made out loud, not an automatic successor of Phase 5. Scope is exactly
one tier: reply to a thread with quote and preview. Edit-own-post, new threads,
attachments, and polls stay Deferred (spec: Composition rules govern everything
here).

- [ ] BBcode-to-HTML converter, pure Lua, fixture-first, targeting the exact output
      shapes the post fixtures already capture (quotes, spoilers, basic tags).
- [ ] Reply form as data: scrape `newreply.php`, mirror hidden fields name-for-name,
      capture the quote prefill via `postid`.
- [ ] Draft persistence: one plain-text BBcode draft per thread under the plugin's
      data dir, written before any network call, editable over sshfs or in the
      device text editor.
- [ ] Preview through the reading surface: the draft renders as a document in the
      same EPUB styling before anything is sent.
- [ ] Submit with one-shot semantics: no auto-retry ever, closed-thread check at
      both ends, one in-flight submission, new-post-id confirmation on success
      (spec: Composition).
- [ ] Composer voice and quirks: YOSPOS reply control reads "YOSPOS BITHC"; all
      composer strings pass the Voice rules.
- [ ] On-device verify: a real reply posted from the Oasis, drafted over sshfs,
      previewed, submitted once, confirmed in the thread.

Exit: Brandon posts a reply from the couch, drafted on a real keyboard, previewed
on e-ink, exactly once.

## Deferred (not scheduled, do not start without a fresh decision)

Edit-own-post, new threads, attachments (Platinum-gated), polls, private messages,
search, archives time machine, ignore list, rap sheet, SAclopedia reader, inline
images, custom-designed thread-list widgets beyond KOReader's Menu (the
bookshelf-grade region system is the model if ever approved), charts and
reading-stat tie-ins, LAN compose server (the draft-file workflow covers the need;
the server is the upgrade if drafts ever feel clumsy).
