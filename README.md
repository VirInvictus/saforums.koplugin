# saforums.koplugin

Read the Something Awful Forums on your e-reader. A KOReader plugin for
lurkers: log in, browse forums and your bookmark shelf with unread counts,
continue bookmarked threads at the first unseen post, and read everything as
bordered post cards laid out for e-ink — no posting, no clutter in your
reading history.

Posting stays on your phone. This is a reading client by design.

## Status

v0.2.0: the working lurker loop (login, forum index, thread lists, bookmarks,
continue-at-unread, in-app reading view), device-verified on a Kindle Oasis
and running in the KOReader emulator. See `roadmap.md` for what is next and
`patchnotes.md` for what shipped.

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
  cards, seen tinting (white means new), avatars, and the end-of-thread frog
  are all part of that port.
- The site is screen-scraped by contract: endpoints and HTML structure are
  written down in `spec.md` and covered by tests against synthetic fixtures.
  No real forum content ever enters the repository.
- The plugin is read-only and polite: your session at human pace, threads
  marked read only when you explicitly continue reading, and an honest
  User-Agent.

## Related

The scraping contract was fact-checked against the open-source iOS client
Awful.app (unlicensed upstream: used as a reference for facts about the
site's HTML, not code). The visual design follows that app's posts-view
theme, translated for grayscale screens.

## License

AGPL-3.0. See `LICENSE`.
