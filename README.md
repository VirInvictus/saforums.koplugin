# saforums.koplugin

Read the Something Awful Forums on your e-reader. A KOReader plugin for
lurkers: log in, browse forums and your bookmark shelf, and read threads as
post cards laid out for e-ink. Posting stays on your phone; this is a
reading client by design.

## Status

v0.5.0: the full lurker surface, feature list below. Developed and verified
in the KOReader emulator; see `patchnotes.md` for what shipped and
`PARITY.md` for the parity roadmap (composition and gated surfaces such as
posting, PMs, and search are future work).

## Features

- Forum index with a favorites section (pin and reorder) and collapsible
  forum groups.
- Thread lists with page counts, replies, ratings, "Killed by" last poster,
  sticky and closed markers, and unread counts.
- Hold any thread row: open the first or last page, continue at the first
  unread post, copy the link or title, mark read or unread, add or remove
  the bookmark, set its star color.
- Bookmark shelf with unread counts and a persisted filter (unread, read,
  or a single star color).
- Per-forum tag filters, remembered between visits.
- Site announcements on forum lists; bodies render in the same post view.
- The posts view: bordered cards with avatars, seen tinting (bright means
  new), quotes that collapse past three lines, tap-to-reveal spoilers,
  tap-to-view images, jump-to-page, and the end-of-thread frog.
- Polite list caching: lists open instantly while fresh (15 minutes for
  forum lists, 10 for bookmarks, 6 hours for the index) and refresh in the
  background when stale; an explicit refresh always wins.

## Requirements

- KOReader v2026.03 or newer (the tested floor; older versions untested).
- A Something Awful Forums account (the forums have no public or guest access).
- Wi-Fi on the reader.

## Install

Copy this repository as `koreader/plugins/saforums.koplugin/` on your device
and restart KOReader; an entry appears under Tools. Releases on GitHub also
carry a zip asset that the on-device App Store plugin can install.

First run: Tools > SA Forums > Log in and enter your forum credentials, or
import a session's `bbuserid`/`bbpassword` cookies from a desktop browser.
Credentials stay on the device.

## Design notes

- Posts render through KOReader's own widgets in the app: no HTML engine, no
  generated files, nothing in your reading history, nothing to clean up.
- The design is a grayscale port of the Awful.app posts-view theme; post
  cards, seen tinting, avatars, and the end-of-thread frog are all part of
  that port.
- The site is screen-scraped by contract: endpoints and HTML structure are
  written down in `spec.md` and covered by tests against synthetic fixtures.
  No real forum content ever enters the repository.
- The plugin is polite: your session at human pace, list caching before
  refetching, threads marked read only when you act on them, and an honest
  User-Agent.

## Related

The scraping contract was fact-checked against the open-source iOS client
Awful.app (unlicensed upstream: used as a reference for facts about the
site's HTML, not code). The visual design follows that app's posts-view
theme, translated for grayscale screens.

## License

AGPL-3.0. See `LICENSE`.
