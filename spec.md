# spec.md: saforums.koplugin

The contract. Behavior changes start here. Roadmap phases implement slices of this document;
anything not stated here is not promised.

## Purpose

`saforums.koplugin` reads the Something Awful Forums on an e-ink reader running KOReader.
It is a lurker's client: log in with your own account, browse forums, watch unread counts,
and read threads as EPUBs rendered by KOReader's normal reading engine. Composition
(posting, replying, private messages) stays on other devices by design.

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
- Explicit user actions may touch state: "Continue reading" fetches with
  `goto=newpost` (the site redirects to the first page containing unseen posts and marks
  seen as a side effect of the view), and "mark unread" POSTs `action=resetseen`.
- Thread lists show, per thread: title, author, reply count, unread-post count, and a
  read/unread indication, parsed from the row structure below.

### Politeness

The plugin acts as the user's own browser session, at human pace:

- Honest User-Agent: `saforums.koplugin/<version> (KOReader)`. No browser impersonation.
- One request at a time. No background polling, no prefetch storms.
- List refreshes are throttled (15 minutes per forum list, matching the iOS client's
  observed courtesy ceiling); a manual refresh always wins.
- Read-only: the plugin never issues a request that creates or modifies content. The
  only POSTs in v1 are login, `action=setseen`/`action=resetseen`, and bookmark
  add/remove.

## The endpoints (v1 set)

All relative to `https://forums.somethingawful.com/`.

| Purpose | Request |
|---|---|
| Login | `POST account.php?json=1` (`action=login`, `username`, `password`, `next`) |
| Forum index | `GET index.php?json=1` (JSON: forum tree, current user) |
| Thread list | `GET forumdisplay.php?forumid=N&perpage=40&pagenumber=K` |
| Bookmarks list | `GET bookmarkthreads.php?action=view&perpage=40&pagenumber=K` |
| Bookmark add/remove | `POST bookmarkthreads.php` (`json=1`, `action=add`/`remove`, `threadid`) |
| Thread pages | `GET showthread.php?threadid=N&perpage=40` with optional `goto=newpost`, `noseen=1`, `pagenumber=K` |
| Mark seen to index | `POST showthread.php` (`action=setseen`, `threadid`, `index`) |
| Mark unread | `POST showthread.php` (`threadid`, `action=resetseen`, `json=1`) |

Out of scope for v1 (do not send): `newreply.php`, `newthread.php`, `editpost.php`,
`private.php`, `query.php` (search is Platinum-gated), `member2.php`, `banlist.php`,
`poll.php`, `dictionary.php`, `announcement.php`, archives endpoints.

## HTML structure contract

The site's HTML is old-school tables. The structures below are what the parsers key on
(CSS selectors against the parsed page). Every selector here gets a synthetic fixture in
`spec/fixtures/` and a busted test; when the live site drifts, the fixture is updated in
the same commit as the parser.

Thread list row (`tr.thread`):

- Thread id: the row's `id` attribute, digits only.
- Title: `td.title a.thread_title` text.
- Author: `td.author a` (user id in the href query string).
- Unread count: `div.lastseen a.count b` text (includes the original post). The row is
  fully read when `div.lastseen a.x` exists.
- Replies: `td.replies` text (excludes the original post).
- Last post: `td.lastpost a.author` and `td.lastpost div.date`.
- Sticky: `td.title` has class `title_sticky`; closed: row has class `closed`.
- Bookmark star color: `td.star` classes `bm0` through `bm5`.
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
- `goto=newpost` redirects to the correct page and drops the `perpage` parameter; the
  plugin re-injects `perpage=40` after every redirect.

Encoding: pages are Windows-1252. All HTML is decoded to UTF-8 before parsing and before
it enters an EPUB.

## Rendering

Thread content renders as EPUB inside KOReader's ReaderUI. One EPUB per thread,
deterministic path `saforums/thread-<threadid>.epub` under the plugin's data directory
(the filesystem is the thread index, wallabag-style; no database), so KOReader's own
progress, dictionary, highlights, and statistics attach to it and survive refetches.

- One chapter per fetched site page (40 posts per page), so chapter boundaries align
  with SA pagination and regeneration is additive. Each spine file is one DocFragment,
  which crengine breaks onto a fresh page by default.
- Post layout: author, date, and index header per post, then the post body. Signature
  text included; avatars, images, and embeds become bracketed link placeholders in v1
  (`[image: host.tld/foo.png]`, `[video: youtube ...]`). Spoilers render as marked,
  de-emphasized spans, not hidden.
- Refresh rewrites the EPUB through a `.tmp` file and renames only on success (an
  interrupted build never clobbers the readable copy). The `.sdr` sidecar is never
  deleted: reading position and highlights survive regeneration, which is the
  wallabag model and the opposite of the webbrowser plugin's delete-on-refetch.
  Position recovery across length changes is Phase 4 work (chapter-anchored jump).
- Every generated thread ends with a one-line end-of-thread marker (see Voice); it is
  a setting, and the default is on.
- Threads from forums with a distinct visual culture get a flavor variant at build
  time when the setting is on: a YOSPOS thread renders its post bodies in the
  monospace family (the one font-family declaration the typography rules permit,
  because generic `monospace` defers to the device's monospace). This is homage by
  typography, not by copying site art.

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
