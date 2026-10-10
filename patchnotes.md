# patchnotes

## v0.4.0

Wave A of the parity program: the posts view reads like the reference
client, in grayscale.

- Design tokens retuned to the reference's posts-view palette: near-white
  page, white cards, hairline #ddd rules, 30%-black meta ink, and a seen
  tint flattened from the reference's blue to its luminance.
- Quotes longer than three lines collapse to three plus a "+N lines"
  control; tapping expands, tapping "less" collapses again.
- Spoilers render as inverted white-on-black cards, masked until tapped;
  a tap toggles every spoiler in that post.
- Hold a post for its action menu: copy the permalink (the reference
  client's format), copy the post's text or its BBcode (fetched from the
  site's own quote form), or mark read to here (the setseen POST, with the
  card list re-tinting in place).
- Author badges parsed from the post's class list: [admin], [mod], [PT],
  and [OP]; registration dates hidden in the forums whose tweaks hide them
  there (FYAD 26, 154, 196, BYOB 268).
- Your own username renders bold in post bodies, and quote headers citing
  you carry a "(you)" tag.
- Image blocks carry their URL: tap to fetch and view full-screen; a dead
  fetch answers "[dead image: name]".
- Tweet, bluesky, video, and linked-image bare links render as labeled
  placeholders; smilies collapse to their typed codes.
- The page selector's label is now the jump control: tap it, type a page.
- End-of-thread marker polished: centered, spaced, and still exactly one
  frog.
- Hardening: post HTML is sanitized before block parsing (raw HTML meant
  paragraph breaks vanished, images disappeared, spoilers stayed
  unmasked); card text widgets carry the card's background (TextBoxWidget
  fills its own buffer white by default, which ate the spoiler black and
  the seen tint); and the session cookie header is scoped to the site's
  own hosts so image fetches never carry credentials to third-party CDNs.

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
