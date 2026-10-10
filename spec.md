# spec.md: saforums.koplugin

The contract. Behavior changes start here. Roadmap phases implement slices of this document;
anything not stated here is not promised.

## Purpose

`saforums.koplugin` reads the Something Awful Forums on an e-ink reader running KOReader.
It is a lurker's client: log in with your own account, browse forums, watch unread counts,
and read threads in a native full-screen post view composed from KOReader's own widgets.
Composition (posting, replying, private messages) stays on other devices by design.

Target device for v1 is Brandon's Kindle Oasis 3 (KOReader v2026.03), but nothing in the
design is Kindle-specific. Any KOReader installation with network access is in scope.

## Reference material

The site has no public API. The scraping contract below was reverse-engineered once by the
open-source iOS client Awful.app and is re-derived here as facts. The reference clone lives
at `~/.gitrepos/Awful.app` (read-only).

**Contract, not code.** Awful.app carries no top-level license. Nothing from its source may
be copied into this repo: no Swift, no translated logic. What we take is the unprotectable
factual layer: endpoint URLs, parameter names, cookie names, HTML structure, and site
behaviors, each verified against live responses during development. The selector strings in
this file describe the site's HTML; they are facts about forums.somethingawful.com, not
someone's creative expression.

## Semantics

### Session

- Login is `POST https://forums.somethingawful.com/account.php?json=1` with parameters
  `action=login`, `username`, `password`, `next=/index.php?json=1`. The response is JSON on
  success; a non-JSON body means the login failed and the site returned an HTML page. POST
  bodies are `multipart/form-data` with values Windows-1252 encoded; characters outside the
  Windows-1252 repertoire are escaped as HTML entities.
- A session is valid if and only if the site's `bbuserid` cookie is present for the forums
  host. The site also sets `bbpassword`; both cookies are long-lived.
- Cookies persist across KOReader restarts in the plugin's settings file. They are
  credentials: never logged, never committed, never written to any synced location.
- If `bbuserid` disappears after a request that followed one where it was present, the
  session expired server-side. The plugin clears its stored session state and tells the
  user, it does not silently re-login in a loop.
- Cloudflare challenges (`cf-mitigated: challenge` header, or 403/503 responses with
  challenge markers) cannot be solved on an e-ink reader. The plugin surfaces one clear
  error and stops. The documented fallback is cookie import: the user pastes `bbuserid`
  and `bbpassword` values from a desktop browser session into the plugin's settings
  dialog.

### Read state

The site tracks per-thread read state server-side, keyed to the account. The plugin's
duty is to never disturb that state except on purpose:

- Fetching a thread page normally (no `noseen` parameter) marks it seen, up to the last
  post on the fetched page. This is the site's behavior, not ours.
- Fetching with `noseen=1` leaves the server-side state untouched. Every implicit fetch
  (rendering, prefetching, refreshing a list) uses `noseen=1`.
- Explicit user actions may touch state, and a tap or menu choice is explicit:
  opening a thread the account has seen continues at the first unseen post
  (`goto=newpost`); opening a never-opened thread browses page 1 with `noseen=1`
  (nothing is marked); "mark unread" POSTs `action=resetseen`; "mark read" from a
  list for a never-opened thread fetches `goto=lastpost` (no noseen); bookmark
  star changes POST `action=add` with `category_id`. Thread lists show, per
  thread: title, author, reply count, unread-post count, and a read/unread
  indication, parsed from the row structure below.
- Announcements carry no server-side read state; the plugin tracks them read
  locally, by title.

### Composition (Phase 6)

Composition exists in exactly one tier (Tier 1: reply to a thread, with quote and
preview) and obeys rules stricter than any read path:

- **Submission is one-shot.** A network error mid-post is surfaced and stops; there
  is never an automatic retry, because a retried submission that landed twice is a
  double post. Manual retry happens only from the composer, after the user sees the
  failure.
- **Preview before post, always.** Drafts are BBcode; preview renders them through
  the same reading surface the thread uses before anything is sent.
- **Drafts persist before any network call.** A crash, a battery death, or a closed
  dialog never eats a post. Drafts are plain-text files under the plugin's data dir,
  one per thread.
- **Credentials never leave the device.** Any external editing surface (a file over
  sshfs, a LAN compose form) hands text to the device; the device's session posts
  it. No companion tool ever holds or sees cookies.
- **Closed threads are checked twice**: before the composer opens and again at
  submit time (threads close while you write).
- **One in-flight submission, ever.** No queues, no background sends, no
  post-and-forget.
- The reply form's hidden fields (anti-forgery keys included) are scraped and
  mirrored from the live form at compose time, never hardcoded.
- Per-forum composer quirks are honored, which is where the Voice rules earn their
  keep: a YOSPOS thread's reply control reads "YOSPOS BITHC."

### Politeness

The plugin acts as the user's own browser session, at human pace:

- Honest User-Agent: `saforums.koplugin/<version> (KOReader)`. No browser impersonation.
- One request at a time. No background polling, no prefetch storms.
- Lists render from cache when the cache is fresh: forum lists 15 minutes,
  bookmarks 10 minutes, the forums index 6 hours, announcement bodies 20 hours
  per forum. A stale list renders from cache immediately and refetches in the
  background (stale-while-revalidate); an explicit refresh always bypasses the
  cache. The cache persists with the plugin's settings, so freshness survives
  restarts.
- Read-only through Phase 5: the plugin never issues a request that creates or
  modifies content. The only POSTs are login, `action=setseen`/`action=resetseen`,
  and bookmark add/remove. Phase 6 adds exactly one mutation surface, reply
  submissions, under the Composition rules.

## The endpoints (v1 set)

All relative to `https://forums.somethingawful.com/`.

| Purpose | Request |
|---|---|
| Login | `POST account.php?json=1` (`action=login`, `username`, `password`, `next`) |
| Forum index | `GET index.php?json=1` (JSON: forum tree, current user) |
| Thread list | `GET forumdisplay.php?forumid=N&perpage=40&pagenumber=K` with optional `posticon=<tagid>` when a tag filter is active |
| Bookmarks list | `GET bookmarkthreads.php?action=view&perpage=40&pagenumber=K` |
| Bookmark add/remove | `POST bookmarkthreads.php` (`json=1`, `action=add`/`remove`, `threadid`; `action=add` also takes `category_id=0..5` to set the bookmark star, `-1` to clear it) |
| Thread pages | `GET showthread.php?threadid=N&perpage=40` with optional `goto=newpost` (continue at first unread), `goto=lastpost` (mark a never-opened thread read), `noseen=1`, `pagenumber=K` |
| Announcements | `GET announcement.php?forumid=N` (announcement bodies; reads only) |
| Mark seen to index | `POST showthread.php` (`action=setseen`, `threadid`, `index`) |
| Mark unread | `POST showthread.php` (`threadid`, `action=resetseen`, `json=1`) |
| Reply form / quote | `GET newreply.php?action=newreply&threadid=N[, postid=M for quote]` (the postid quote fetch is live since v0.4.0 for copy-post-BBcode; the form mirror and submission stay Phase 6) |
| Reply submission | `POST newreply.php` (scraped form fields incl. hidden keys, one-shot, Phase 6) |

Out of scope (do not send): `newthread.php`, `editpost.php`, `private.php`,
`query.php` (search is Platinum-gated), `member2.php`, `banlist.php`,
`poll.php`, `dictionary.php`, archives endpoints.
`newreply.php` joined the live set in v0.4.0 for one read-only use, the
quote fetch behind copy-post-BBcode (a GET that submits nothing); its form
mirror and submission path open with Phase 6, under the Composition rules.

## HTML structure contract

The site's HTML is old-school tables. The structures below are what the parsers key on
(CSS selectors against the parsed page). Every selector here gets a synthetic fixture in
`spec/fixtures/` and a busted test; when the live site drifts, the fixture is updated in
the same commit as the parser.

Thread list row (`tr.thread`):

- Thread id: the row's `id` attribute, digits only.
- Title: `td.title a.thread_title` text. A row whose title cell links through
  `a.announcement` instead is a site announcement: it carries the usual
  author, last-post date, and icon cells but no unread state, and it never
  counts as a thread.
- Author: `td.author a` (user id in the href query string).
- Unread count: `div.lastseen a.count b` text (includes the original post). The row is
  fully read when `div.lastseen a.x` exists. A row with no `div.lastseen` cell
  at all has never been opened by the account.
- Replies: `td.replies` text (excludes the original post). Page estimate is
  `replies / 40 + 1` (site perpage is pinned to 40 on every request).
- Rating: `td.rating img[title]`, title text of the form "N votes, average
  X.XX"; both numbers parse out of it.
- Last post: `td.lastpost a.author` and `td.lastpost div.date`.
- Sticky: `td.title` has class `title_sticky`; closed: row has class `closed`.
- Bookmark star color: `td.star` classes `bm0` through `bm5`.
- Filterable tags: `div.thread_tags a[href*='posticon']` enumerates the
  forum's thread tags (id = the `posticon` query parameter).
- Pagination: `div.pages` with `data-current-page`, `data-total-pages`, `data-base-url`,
  `data-per-page`.

Thread page:

- Post container: `table.post` (post id from its `id` attribute minus the `post` prefix);
  1-based index from the `data-idx` attribute.
- Body: `td.postbody` inner HTML.
- Author: `dt.author` text; user id from `ul.profilelinks a[href*='userid']`.
- Date: `td.postdate` text, formats `MMM d, yyyy h:mm a` or 24-hour variant.
- Seen marker: row contains `tr.seen1` or `tr.seen2`.
- Page identity: `body[data-thread]`, `body[data-forum]`; breadcrumbs give the thread
  title; closed state from the reply button image.

Reply form (Phase 6): the `newreply.php` form is parsed as data. Hidden inputs
(form keys, thread id, destination parameters) are captured name-for-name and
mirrored into the submission; the visible field set is the message body, the post
icon choice, and the signature toggle. A quote request (the same URL with `postid`)
prefills the body with the site's own `[quote=...]` block, which the composer treats
as text to preserve, never to re-parse. The submit response's redirect target yields
the new post id, which is the success confirmation.
- `goto=newpost` redirects to the correct page and drops the `perpage` parameter; the
  plugin re-injects `perpage=40` after every redirect.

Encoding: pages are Windows-1252. All HTML is decoded to UTF-8 before parsing and before
it enters an EPUB.

## Rendering

Thread content renders **in the app** as native KOReader widgets, not an EPUB,
not an HTML engine, and not the reader. Two reversals on device evidence
(2026-10-08): crengine's CSS subset could not carry the post-card design, and
mupdf's HTML engine ignored floats, wrapped inline-blocks, and fell back to its
own fonts. The native widget view also has what neither engine route had: no
files, no ReaderUI, no history entries, no sidecars, and refresh is a
re-render.

- Posts render as **native KOReader widgets** (FrameContainer cards,
  TextBoxWidget bodies, ImageWidget avatars, ScrollableContainer scroll, native
  page-selector bar). Decision 2026-10-08, second architecture turn: mupdf's
  HTML engine ignored floats, wrapped inline-blocks, and fell back to its own
  fonts - none of which the design could fight through. `postblocks` turns the
  sanitized HTML into layout blocks; bold runs render through TextBoxWidget's
  PTF markers; the body renders in the user's UI font (the `cfont` face) at
  dense sizes.
- Known v1 limitation of the native renderer: inline italics render as plain
  text (TextBoxWidget's only inline marker is bold); quotes nest flat; scroll
  position is not yet persisted across page changes.
- The design is a grayscale port of Awful.app's posts-view theme (the reference
  clone's `posts-view.less` + `_base.less`), token-tuned to the reference's
  values: page background near-white gray (#f4f3f3 flattened), white post cards
  with hairline `#ddd` rules, seen posts tinted light (the reference's blue
  `#e6eff8` flattened to its luminance) so bright means new-since-last-read,
  meta text at 30% black, quote bars `#999` with `#555` headers, avatar beside
  an inline name-and-date block (username 1.1em bold with `[admin]`/`[mod]`/
  `[PT]`/`[OP]` text badges parsed from the author class list, custom title,
  date and post number at 0.8em in muted ink), and a centered, spaced
  end-of-thread line carrying the frog. Body text renders dense (font size 14
  scaled units, becoming a setting). Registration dates are hidden in the
  forums whose tweaks hide them there (FYAD 26, 154, 196, BYOB 268); YOSPOS
  (219) keeps its regdate despite the folklore.
- Long quotes (more than 3 lines, the reference client's
  QUOTE_COLLAPSED_LINES) render 3 lines plus a "+N lines" control; tapping
  expands, tapping "less" collapses again. Spoiler blocks render as inverted
  (white-on-black) cards, masked until tapped; the tap toggles every spoiler
  in that post (per-spoiler hit-testing comes later). Image blocks carry the
  image URL and open it in the image viewer when tapped; a dead fetch answers
  with "[dead image: name]". Tweet, bluesky, video, and linked-image bare
  links render as labeled placeholders in meta gray (smilies collapse to
  their typed codes). Occurrences of the logged-in username in bodies render
  bold, and quote headers citing the user carry a bold "(you)" tag; both are
  inert presentation. Holding a post opens its action menu (copy post URL,
  copy post text, mark read to here); the permalink follows the reference
  client's format (`showthread.php?threadid=N&perpage=40&noseen=1[&pagenumber=N]#post<id>`)
  and mark-read-to-here POSTs `action=setseen` with that post's index, then
  re-tints the card list locally. The menu also offers the post's BBcode,
  fetched read-only from the site's own quote form. The page selector's
  label doubles as a jump-to-page input.
- Post layout follows the Typography section: bordered post cards, avatar beside
  the bold author, custom title and gray meta line, left-aligned text. Avatars
  embed as data URIs; if the device renders them as broken boxes, a one-line
  switch drops them until the image path is proven.
- Pages: multi-page threads navigate through a native page-selector bar at
  the bottom of the view (newer / page X of Y / older); page changes fetch
  with `noseen=1`. The 3em frog line shows only on the last page.
- Scroll position is not persisted across page changes or app restarts yet
  (known v1 limitation; the persistence helpers exist in `ui.lua` dormant).
  Browse fetches never mark anything read; `noseen=1` discipline is
  unchanged.
- Page keys and swipe scroll the view; back closes it. Site links are inert
  in the lurker view; only the plugin's own actions act.
- Bookmarked threads (the bookmark shelf lists rows with unread counts) open
  with `goto=newpost` WITHOUT `noseen` (the explicit continue-reading
  action): the view lands on the first unseen post, seen posts render tinted,
  and the server marks the page read as the side effect the user asked for.
  Holding a bookmark offers mark-unread (`action=resetseen`).
- The EPUB builder remains in the tree, fully tested but unwired: a future
  "export thread as EPUB" action can revive it without new work.

## Typography

The generated EPUB is rendered by crengine on top of the user's own tuned reading
setup (font, margins, line spacing, style tweaks). The cascade facts that shape every
rule: our author CSS beats crengine's default stylesheet at normal specificity; any
user style tweak declared `!important` beats anything we ship; the render DPI setting
rescales `px`; a specific font named in CSS would override the user's deliberately
chosen face. Therefore:

- Units are `%`, `em`, and `urem` only. Never `px` (rescales under the DPI setting),
  never `rem` (we set no root size; `urem` is "the user's chosen size" and is the
  unit KOReader's own tweaks use).
- No `font-family` declarations, ever, except the generic `monospace` for the YOSPOS
  flavor. No `line-height` anywhere: line spacing belongs to the reader's setting.
- `body { margin: 0; }` and nothing else at the root; page margins belong to the
  reader. Horizontal rhythm is `em` spacing on inner blocks.
- Hierarchy is expressed through size, weight, case, and gray ink only: meta text in
  `#555`, rules and borders in `#888` (never a rule heavier than the type it
  separates), matching KOReader's own menu divider gray. No background colors as
  decoration; they render as gray slabs and die to the pure-black-and-white tweak.
- Post headers use the two-tier pattern: a small italic label line (author name) over
  a value line (date, post index), separated from the body by an em of space and a
  `#888` hairline (`border-bottom`).
- Blockquotes get the e-ink treatment: `border-left` 2px `#888`, `em` padding, no
  background. Links keep the default navy; we never restyle link color.
- Long fields (thread titles, usernames) are budgeted at build time and truncated
  with a real ellipsis character; post chrome must never wrap awkwardly or overflow.
- Prose carries `lang` attributes so hyphenation patterns apply; footnotes, if ever
  rendered inline, will use the standard `type="footnote"` / `role="doc-footnote"`
  hooks so the default in-page-footnote tweaks pick them up with zero extra CSS.
- Known-dead crengine features are never used: counters, `::marker`, `:link`,
  CSS variables, `text-shadow`, logical properties, positioning, multi-value
  `text-decoration`. `::before` content is cosmetic only (one tweak hides all
  pseudo-elements).
- Two type themes ship: **Art-directed** (the default; everything above) and
  **Reader's way** (near-empty CSS, pure semantic structure; newsdownloader's
  `/* Empty */` philosophy). Both respect every rule on this list; they differ in
  how much chrome they draw.

## Voice and humor

The plugin speaks fluent forums. The register (mined from the reference client's
practice): flat deadpan; the Forums are a third party with moods ("The Forums
answered with HTTP 503"); jokes never target the user; partial failure is two
clauses, the second negated ("Thread rendered, images weren't"); congratulations may
be misused exactly once, at end-of-thread; jokes live in permanent surfaces
(strings, empty states, the end-of-thread marker), never in pranks, and are never
explained.

- End-of-thread marker: after the last post, one line of lore. Default text invokes
  the frog the way every thread ends, set once and never explained.
- The composer speaks the same register: submission in progress is stated plainly,
  success confirms with the new post's coordinates, and a double-post guard failure
  is phrased so only the user, who has seen it before, will find it funny.
- Empty states use site vocabulary as membership signals: an empty bookmark list is
  "Nothing to see here." A thread with no new posts says so plainly; only the second
  consecutive visit with nothing new earns a second line.
- Error strings blame the right party: a Cloudflare challenge is Cloudflare's doing
  and says so; a wrong password is between the user and the keyboard, stated
  procedurally without snark.
- Original jokes only, plus factual references to shared community lore. No copied
  site content, no copied client strings: same register, our own sentences (see
  Content and IP policy).
- Every user-facing string is gettext-wrapped like the rest; the jokes are
  translatable or removable like everything else.

## Content and IP policy

No real Something Awful content enters this repository. Test fixtures are hand-authored
minimal HTML that preserves the element structure above with fictional text. Never
commit scraped pages, posts, avatars, or post text. The repo stays public.

## Platform and dependencies

- KOReader plugin: repo root is the plugin root (`main.lua`, `_meta.lua` at top level);
  installs by copying the repo as `koreader/plugins/saforums.koplugin/`.
- API floor: KOReader v2026.03 (verified on device in Phase 1; widen only with evidence).
- Runtime dependencies are KOReader's bundled Lua libraries only: `htmlparser`
  (msva/lua-htmlparser, vendored in koreader-base, supports the selector subset used
  here), the socket stack (`socketutil`, `https`), `util`, `gettext`, `logger`, and the
  standard widget set. No third-party Lua rocks at runtime, ever.
- Dev/test dependency: busted (installed via luarocks), never required at runtime.
- The Windows-1252 decoder is a small in-repo mapping table; no iconv dependency.
- `_meta.lua` carries `name` and `version` as plain quoted strings (never gettext
  wrappers): the on-device marketplaces regex-extract both for install detection
  and update comparison. `version` stays in lockstep with the `VERSION` file and
  the release tag; a distribution release carries a `.zip` asset, which the
  Storefront catalog requires.
