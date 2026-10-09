# patchnotes

## v0.2.0

The lurker client works end to end, on a Kindle Oasis and in the KOReader
emulator.

- Login with persisted session cookies, forum index, thread lists with
  unread counts, and bookmark shelf — tapping a bookmarked thread opens it
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
  native page selector bar; scroll positions persist per thread and page.
- The renderer is native widget composition (postblocks + threadview) —
  no HTML engine, no files, no reader history pollution. The design is a
  grayscale port of the Awful.app posts-view theme. The EPUB builder and
  the HTML renderer remain in the tree, tested but unwired.
- Thread-book shelf self-cleans by LRU cap (default 100).
- Marketplace-ready: _meta.lua carries the plain-string name and version
  the on-device plugin stores regex out; releases ship a zip asset.

## v0.1.0

Initial skeleton: spec (the scraping contract and semantics), four-phase roadmap, plugin
stub that loads in KOReader and registers a menu entry. No site functionality yet.
