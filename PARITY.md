# PARITY.md: the Awful.app 1:1 program

Directive (Brandon, 2026-10-08): reach parity with the Awful.app iOS client on
KOReader, using its source as the reference. This document is the master plan;
`roadmap.md` remains the phase ledger for the core loop. Research source: four
mining passes over `~/.gitrepos/Awful.app` (posts-view pipeline, lists and
bookmarks, composition, rest-of-app inventory), consolidated here.

## Honesty section: what 1:1 can mean on a grayscale e-ink reader

Ported faithfully: all data features, read-state mechanics, list behaviors,
composition via draft-file workflow, PMs, profile, rap sheet, announcements,
search (Platinum-gated on the account, not by us).

Translated: haptics to refresh patterns; webview CSS to widget styling; colored
stars/mentions/role-stars to grayscale glyphs and text tags; tweet/video/bsky
embeds to labeled placeholders; GIF autoplay to first frame; 300ms animations to
instant toggles.

Not ported, deliberately: alternate app icons, tilt scroll, Handoff, URL scheme,
Imgur account flows, autocorrect flags, Liquid Glass anything, iOS share sheet,
WidgetKit (does not exist in Awful either).

## Wave A: reading parity (the posts view)

1. Seen-tint and token retune: page bg gray(0.96), cards white, rules #ddd
   (gray 0.13), meta ink #b3b3b3 (30% black), seen tint #e8e8e8-family; current
   tokens are darker than Awful's equivalents.
2. Quote collapse: quotes > 3 lines render 3 lines + "+N lines", tap expands
   (Awful QUOTE_COLLAPSED_LINES; collapse_long_quotes default).
3. Spoiler reveal: inverted (white-on-black) card per spoiler block, per-post
   toggle to reveal (tap-to-reveal needs hit-testing; per-post first).
4. Mark-read-to-here: local setseen write + live re-tint of the card list.
5. Post action menu: copy post URL, copy post text, mark-read-to-here.
6. Role and badge markers: parse dt.author role classes; render [mod]/[admin]/
   [PT] text tags; regdate suppression per forum (the reference client's
   ForumTweaks list: 26, 154, 196, 268; YOSPOS 219 keeps its regdate, the
   YOSPOS rule was folklore).
7. Mention + quoted-you highlighting: own username bold in bodies; quote
   headers marked when they cite you.
8. Image blocks carry URL; tap to fetch and view; dead fetch shows
   "[dead image: name]".
9. Jump-to-page input on the selector bar (Selectotron parity).
10. Linkified-image and video/tweet/bsky placeholders in meta gray.
11. End marker polish: centered, spaced, "End of the thread" + frog.

## Wave B: lists and bookmarks parity

1. Hold menu on every thread row (forum lists too): open first page / open at
   first unread (explicit continue) / mark unread / add-remove bookmark /
   copy link. Conditional by thread state (Awful's fixed menu order).
2. Row richness: secondary line with page estimate, replies, "Killed by"
   last-poster; rating text from td.rating; secondary tag text.
3. Bookmark star colors: parsed already; display as letter-coded tags
   ([R][Y][C][G][P][O]); filter sub-menu All/Unread/Read/per-star, persisted.
4. Add-bookmark from list hold menu (action=add with category_id, spec param
   addition); remove already exists.
5. Mark-thread-read from list for never-seen threads (goto=lastpost, no
   noseen; spec param addition).
6. Tag filter per forum (posticon param), filter memory per forum.
7. Announcements block on forum lists (a.announcement rows, unread tracking
   by title, body via announcement.php — spec decision noted).
8. Forums list parity: favorites section, expand/collapse state per forum,
   group separators, favorites reorder.
9. Refresh throttling + list caching (15 min forum lists, 10 min bookmarks,
   6 h index; stale-while-revalidate; manual refresh wins).
10. Jump-to-page on lists; skip "older page" when a page returns under 40 rows.

## Wave C: composition parity (the gate is open; draft-file workflow first)

1. Ordered full-form mirror for newreply.php: scrape vbform control-for-control
   (document order, disabled-aware, CRLF textarea, cp1252 entity escaping),
   submit with the scraped submit-button value. YOSPOS quirk falls out free.
2. One-shot submit with strict error classification: body.standarderror scrape
   (h2 + inner), closed-thread detection, Cloudflare passthrough, and the
   leniency rule: missing goto=post link is "probably posted", never a retry.
3. Draft files: drafts/reply-<threadid>.bbcode, written before any network
   call, deleted on confirmed post, offered back on next visit.
4. Quote prefill: GET newreply.php with postid, textarea value appended to the
   draft.
5. Server-side preview: POST with the preview submitter, render the returned
   .postbody through the native post view.
6. Minimal composer shell: TextBoxWidget draft view + Post/Preview/Close,
   Post disabled until non-empty, one in-flight submission.
7. Edit flow (mechanically free after 1): GET editpost.php, dump message to
   edit-<postid> draft, POST mirrored, success = no error thrown.
8. New threads + polls + attachments: deferred behind C1-C7 (poll is a second
   transaction with "thread posted, poll wasn't" recovery; attachments are
   Platinum-gated with form-discovered MAX_FILE_SIZE).

## Wave D: gated and misc surfaces (each gated by the accountfeatures probe)

1. Account-features probe: member.php?action=accountfeatures, dl.features
   dt.enabled markers, fail-loud; flips Platinum/Archives/No-Ads flags.
2. Announcements body reading (with Wave B item 7).
3. PM inbox + folders read-only (private.php folder scrape maps 1:1 to lists).
4. PM reading (action=show, same post renderer).
5. Profile view (member.php scrape; completes author-tap loops).
6. Rap sheet read-only (banlist.php table).
7. Search (query.php POST q/action/forums[], qid pagination) - Platinum-gated.
Deferred/skip: PM send/move/delete, folder management, ignore-list management,
SAclopedia reader, archives time machine, rap sheet filters, smilie picker.

## Verification

Every wave: busted green, then kodev emulator pass (the laptop is the design
review surface), then Kindle sign-off for e-ink truth. The parity spec sources
of record are the four mining reports (preserved in this repo's history) and
the Awful.app clone at ~/.gitrepos/Awful.app.
