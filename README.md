# saforums.koplugin

Read the Something Awful Forums on your e-reader. A KOReader plugin for lurkers: forum
index, thread lists with unread counts, bookmarks, and thread pages rendered as EPUBs
with KOReader's own page turns, fonts, dictionary, and reading progress.

Posting stays on your phone. This is a reading client by design.

## Status

Pre-alpha skeleton (v0.1.0). Phase 0 of 4; see `roadmap.md`. Not yet usable for
anything.

## Requirements

- KOReader v2026.03 or newer (floor to be pinned in Phase 1).
- A Something Awful Forums account (the forums have no public or guest access).
- Wi-Fi on the reader.

## Install (when there is something to install)

Copy this repository as `koreader/plugins/saforums.koplugin/` on your device and restart
KOReader. An entry appears in the tools menu. Longer instructions arrive with the first
release; after Phase 4 the plugin may also be available through the on-device App Store
plugin manager.

## Design notes

- Threads render as EPUBs opened in KOReader's normal reader, so all reading machinery
  (pagination, progress sync, highlights, dictionary) works on forum threads unchanged.
- The site is screen-scraped by contract: the endpoints and HTML structures are written
  down in `spec.md` and covered by tests against synthetic fixtures. No real forum
  content ever enters the repository.
- The plugin is read-only and polite: it uses your session at human pace, marks
  threads read only when you explicitly continue reading, and never posts anything.

## Related

The scraping contract was fact-checked against the open-source iOS client Awful.app
(unlicensed upstream: used as a reference for facts about the site's HTML, not code).

## License

AGPL-3.0. See `LICENSE`.
