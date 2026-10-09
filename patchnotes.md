# patchnotes

## v0.3.0

The working lurker client: threads open, scroll, and render with avatars.
This is the first release where the full loop works on both the Kindle and
the desktop emulator.

- Native widget renderer: posts compose from KOReader's own widgets
  (TextBoxWidget, ImageWidget, FrameContainer) - no HTML engine, no
  generated files, nothing in the reader history.
- Scrolling works: ScrollableContainer with proper show_parent, page keys
  and touch gestures, per-thread and per-page scroll positions.
- Avatars fetch once per poster, cache on device, and appear beside author
  names after first paint.
- Bookmark shelf with unread counts; tapping a bookmarked thread continues
  at the first unseen post (goto=newpost).
- Forum browsing with thread lists showing unread counts, sticky and
  closed markers.
- Windows-1252 codec, JSON side-channel parser, and cookie jar for the
  site session; multipart POST with cookie persistence for login.
- Thread-book shelf self-cleans by LRU cap (default 100).
- Marketplace-ready: releases ship a zip asset; _meta.lua carries the
  plain-string name and version the on-device plugin stores regex out.

## v0.2.0

The lurker client works end to end, on a Kindle Oasis and in the KOReader
emulator.

- Login with persisted session cookies, forum index, thread lists with
  unread counts, and bookmark shelf; tapping a bookmarked thread opens it
  at the first unseen post (the goto=newpost continue action); holding one
  marks it unread.
- Threads render as bordered post cards in a full-screen native view:
  avatars, custom titles, post numbers, blockquotes with ruled headers,
  spoilers marked, and the 3em end-of-thread frog. Seen posts are tinted;
  new posts stay white.
- The site's read state is respected: every implicit fetch carries
  noseen=1, and only the explicit continue action ever marks anything
  read.
- Page navigation in the view (newer/older with a page indicator) and a
  native page selector bar. Scroll positions are not persisted across
  page changes yet (known limitation, recorded in the spec).
- Login from the device, or import a session's cookies from a desktop
  browser when a Cloudflare challenge blocks the login path.
- The renderer is native widget composition (postblocks + threadview):
  no HTML engine, no generated files, nothing in the reader history.
- Thread-book shelf self-cleans by LRU cap (default 100).
- Marketplace-ready: releases ship a zip asset; _meta.lua carries the
  plain-string name and version the on-device plugin stores regex out.

## v0.1.0

Initial skeleton: spec (the scraping contract and semantics), four-phase roadmap, plugin
stub that loads in KOReader and registers a menu entry. No site functionality yet.
