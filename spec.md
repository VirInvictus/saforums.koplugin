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
deterministic path `saforums/thread-<threadid>.epub` under the plugin's data directory,
so KOReader's own progress, dictionary, highlights, and statistics attach to it and
survive refetches.

- One chapter per fetched site page (40 posts per page), so chapter boundaries align
  with SA pagination and regeneration is additive.
- Post layout: author, date, and index header per post, then the post body. Signature
  text included; avatars, images, and embeds become bracketed link placeholders in v1
  (`[image: host.tld/foo.png]`, `[video: youtube ...]`). Spoilers render as marked
  spans (`[spoiler: text]`), not hidden.
- Refresh rewrites the EPUB with the same path, then reopens and restores the last-read
  chapter before showing anything.

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
