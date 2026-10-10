# roadmap.md: saforums.koplugin

The execution ledger. `spec.md` is the contract; `PARITY.md` is the parity
program; this file says what is next and how to move. Every open item below
carries its own brief: goal, the mined facts (with citations into the
read-only Awful.app clone at `~/.gitrepos/Awful.app`), the files to touch,
the tests, and the done-when. A future agent should be able to take any item
and start without re-mining.

Rules of engagement, all items, all waves: contract-not-code from Awful.app
(facts only, cite file:line); `noseen=1` on every implicit fetch and only
explicit actions touch read state; no real SA content in the repo (fixtures
are synthetic, structure-true); Lua 5.1 subset; KOReader-bundled runtime
libraries only; cookies are credentials; every wave verifies as busted green,
then the kodev emulator (the only test surface per AGENTS.md), then Brandon's
own Kindle pass. Cited line numbers refer to the clone at its current HEAD
and should be re-verified if the clone moves.

## Current state (2026-10-09, late)

v0.5.0 is tagged and released (zip attached, CI green): Wave A reading
parity, Wave B lists and bookmarks parity. On main, committed but untagged:
the back-stack (menus stay beneath screens they open) and the gentler avatar
pass. Next release v0.5.1 batches those. The public e-reader-thread post is
drafted and waiting on Brandon. After that: Wave C (composition), Wave D
(gated surfaces), and the loose ends below.

## Loose ends (small, active)

### L1. Tick the mark-seen ledger box
The Phase 2 box "explicit mark-seen-to-index control" shipped in Wave A as
mark-read-to-here (`POST showthread.php action=setseen threadid index`,
index = the post's own `data-idx`; see `saforums/ui.lua` `mark_read_to_here`).
Tick it in the next paperwork commit.

### L2. Bookmark and star actions from inside the thread view
Goal: the Wave A post menu (hold a post) gains "Bookmark thread" /
"Remove bookmark" and "Set star…", reusing `SaforumsUI:set_bookmark` and
`show_star_menu` from Wave B. Files: `saforums/ui.lua` (`show_post_menu`).
The view already carries `thread_id`; nothing new is fetched. Done-when: the
menu shows the right action for the thread's bookmark state and the mutation
lands (star visible next list fetch). Tests: extend the post-menu smoke test.

### L3. Scroll-position persistence across page changes and restarts
Goal: when the view reopens (same thread, same page), restore the previous
scroll ratio. `SaforumsUI:get_position/save_position` already exist (dormant,
settings-backed). Wire: `ui.open_thread` reads the saved ratio after the view
builds and calls the scrollable's `setScrolledOffset` (clamped, the pattern
`ThreadView:refresh_preserving_scroll` uses); save on `handleBack` and before
page actions. Care: `ThreadView:build()` runs again on avatar refresh; only
restore on first build. Done-when: leave a thread mid-scroll, reopen, land
within a screen of where you were. Spec: Rendering, last paragraph.

### L4. Stale-while-revalidate deep-compare
The SWR swap in `render_thread_list` re-renders even when the refetched page
parsed identically, costing a pointless e-ink flash. Goal: serialize the
parsed page (a stable `tostring`-based hash of the threads table) and skip
the swap when unchanged. Files: `saforums/ui.lua` only. Done-when: sitting on
a stale list that refetches identically produces no repaint; a changed list
still swaps.

### L5. Voice sweep
A dedicated fresh-eyes pass over every user-facing string against the Voice
section of spec.md (deadpan, jokes only in permanent surfaces, error strings
blame the right party). `dragon-agents:slop-reader`-shaped review of the
gettext strings in `main.lua`, `saforums/ui.lua`, `saforums/threadview.lua`.
Done-when: Brandon reads every string without wincing.

### L6. v0.5.1
Cut when the batch feels right: back-stack + avatar pass (+ L1-L5 whatever
lands first). Same release procedure as v0.5.0 (release-auditor pre-flight,
verbatim tag, sweep).

## Dormant EPUB track (parked; moves only on a fresh decision)

The EPUB builder (`saforums/epubbuilder.lua`, `threadhtml.lua`) is dormant
but tested. The Phase 3/4 boxes below belong to that track and are parked
with it; they were superseded by the native widget renderer (the three
architecture verdicts recorded in Phase 3's history). Reviving any of them
is a new decision, not backlog:

- EPUB stylesheet to spec, two type themes behind one setting, build-time
  truncation budgets, `lang` attributes + balanced-HTML sanitizer upgrade,
  end-of-thread marker as an EPUB element, YOSPOS monospace flavor in EPUBs,
  the typography exit review.
- Refresh-in-place through `.tmp` + rename, skip-if-fresher last-post stamps,
  refresh summary InfoMessage.

## Wave C: composition parity (the gate is open)

Invariants that govern every C item (spec.md, Semantics > Composition):
submission is one-shot, never auto-retried; drafts persist before any
network call; the closed-thread check runs at compose open and at submit;
one in-flight submission ever; form fields are scraped and mirrored, never
hardcoded; per-forum quirks are honored; credentials never leave the device.
The verify ladder per item: busted, then kodev (compose against the real
site from the emulator is allowed; it is Brandon's account and he drives it),
then his Kindle pass. Composition bugs can double-post, so every C item also
gets a dry-run review from `dragon-agents:code-reviewer` before commit.

### C1. Draft files (build this first)

Goal: a draft per context, on disk before any network call, offered back.

- Shape: `drafts/reply-<threadid>.bbcode` and `drafts/edit-<postid>.bbcode`
  under the plugin data dir (`data_dir()` in ui.lua), plain text, one file
  per target. Written on every composer edit (or on close); deleted only on
  confirmed submit. On opening a composer for a target whose draft exists,
  offer resume (ConfirmBox) before a blank form.
- Files: new pure module `saforums/drafts.lua` (`path_for(target)`, `save`,
  `load`, `clear`, built on io + lfs like avatars.lua); ui wiring in the
  composer (C6) and the reply entry points.
- Tests: drafts_spec (save/load/clear round-trip, path shapes, resume
  detection with a fake data dir).
- Done-when: kill the process mid-compose; the next open offers the draft
  back verbatim.

### C2. The reply form as data (vbform mirror)

Goal: scrape `newreply.php`'s form and mirror it control-for-control; never
hardcode a field.

- Facts (mined, cite the clone): the form is `form[name='vbform']`, fetched
  `GET newreply.php?action=newreply&threadid=N`; discovery is generic: all
  `input`/`select`/`textarea` inside the form in document order
  (AwfulCore/Sources/AwfulCore/Scraping/Form.swift:191-193). Hidden inputs
  re-sent verbatim: `action` (value `postreply`), `threadid`, `formkey`,
  `form_cookie`, `MAX_FILE_SIZE` (newreply.html fixture:104-107). Visible
  controls: `textarea name="message"` (:144); checkboxes `parseurl`,
  `bookmark`, `disablesmilies`, `signature` (value `yes`, server-rendered
  checked state kept, :157-161); submit buttons `name="submit"` value
  "Submit Reply" and `name="preview"` value "Preview Reply" (:182-183).
  Correction to an earlier assumption: the reply form has NO post-icon field
  (`iconid` exists only on newthread). A missing vbform means the thread is
  closed (or the scrape failed; distinguish via the closed check, C3).
- Files: new pure module `saforums/formscraper.lua` (htmlparser-based:
  `parse_form(html)` returns ordered controls with name/type/value/checked;
  `compose_submit(form, message, submitter)` returns the field list to POST,
  mirroring everything except the edited `message`). Our session already
  POSTs multipart with cp1252 values and numeric-entity escaping for
  out-of-repertoire chars (saforums/session.lua + cp1252.lua): the dialect
  the site's forms speak, matching the reference client's behavior
  (Windows1252.swift:5-16).
- Spec: extend the HTML structure contract's reply-form paragraph with the
  control names and the no-iconid fact. Fixture: synthetic
  `spec/fixtures/newreply.html` with the real control set (fictional formkey).
- Tests: formscraper_spec (discovery order, hidden mirror, submitter
  selection, message substitution, checkbox state preservation).
- Done-when: a fixture form round-trips into an exact POST field list.

### C3. Submit with one-shot semantics and strict error classification

Goal: send exactly once; classify every outcome; never retry.

- Facts: POST to `newreply.php`, multipart, all values cp1252-escaped; only
  the chosen submitter rides the wire (`submit=Submit Reply`;
  SubmittableForm.swift:176-189). Success: the response contains
  `a[href*='goto=post']` (fallback `goto=lastpost`); the postid comes from
  that link's query (ForumsClient.swift:1458-1468). Leniency rule: NO goto
  link at all is still success ("probably posted"), reported as landing at
  the thread's last post (1470-1485). Error pages: `body.standarderror` with
  `#content div.standard h2` as title and `div.inner` text as message
  (StandardErrorScrapeResult.swift:11-31); a closed thread answers either a
  `body.standardredirect` page whose text contains "This thread is closed!"
  (newreply-closed.html:105-146) or the standarderror form of the same
  sentence (StandardErrorScrapeResult.swift:32-47). HTTP >= 400 without the
  site's `#content` maps to gateway/Cloudflare handling our session already
  performs.
- Behavior: the composer fires the POST once (UIManager callback), shows a
  progress toast, and on any transport failure stops with the error surfaced
  for a manual decision; there is no code path that resends. Success closes
  the composer, clears the draft (C1), and opens the thread at the new
  post's page (browse noseen; the site already marked it read).
- Files: `saforums/compose.lua` (new; `classify_reply_response(html)` pure:
  returns `{kind="posted", postid}` / `{kind="probably_posted"}` /
  `{kind="error", title, message}` / `{kind="closed"}`), ui wiring.
- Spec: the Composition section already carries the rules; add the error
  classification facts to the HTML contract.
- Tests: compose_spec over synthetic response fixtures (success redirect,
  goto=lastpost, no-goto leniency, standarderror, closed redirect, closed
  standarderror).
- Done-when: every synthetic outcome classifies correctly; a killed
  transport surfaces once and stops.

### C4. Quote prefill

Goal: "quote this post" prefills the composer with the site's own BBcode.

- Facts: `GET newreply.php?action=newreply&postid=M`; the vbform's
  `textarea name="message"` carries the prefilled BBcode, HTML-unescaped
  (ForumsClient.swift:1595-1603, 2607-2613). Attribution shape:
  `[quote="Name" post="ID"]...[/quote]` (newreply.html:144). The composer
  treats it as text to preserve (spec: Composition).
- Files: formscraper (C2) exposes `message_text(form)`; ui adds "Quote" to
  the Wave A post menu; the composer opens with existing draft (C1) + the
  quote appended below it (the reference client inserts at caret; at-end is
  fine for us, deadpan note not required).
- Tests: fixture round-trip; quote-onto-draft behavior in the composer spec.
- Done-when: hold a post, quote, the draft contains the attribution block.

### C5. Server-side preview

Goal: see the rendered post before sending, through the same reading
surface.

- Facts: re-GET the form (or reuse C2's), set `message`, POST
  `newreply.php` with the preview submitter (`preview=Preview Reply`),
  extract the first `.postbody` innerHTML from the response
  (ForumsClient.swift:1549-1580). NOTE: a preview POST still carries the
  form fields; it does not submit anything (that is what the `submit`
  submitter is for), but it IS a POST: exactly one per tap, same one-shot
  courtesy.
- Render: the extracted HTML goes through the native view as a one-post
  pseudo-thread (the announcement flow already does this in ui.lua), titled
  "Preview". Edited-by/quote/spoiler blocks render via the normal pipeline.
- Files: compose.lua (`preview_reply(form, message)`), ui wiring, a Close
  that returns to the composer with the draft intact.
- Tests: preview extraction from a fixture response; the pseudo-post render
  path is the announcement path (already covered).
- Done-when: a drafted BBcode with a quote and a spoiler previews correctly
  in the post-card view without any state change.

### C6. The composer shell

Goal: the editing surface. Minimal, deliberate, keyboard-friendly.

- KOReader facts: `ui/widget/inputtext.lua` provides the full editing widget
  (multiline text, virtual keyboard on e-ink, physical keyboard on devices
  with one, clipboard operations, undo); `ui/widget/buttondialog` for the
  action row; the login dialogs already prove InputDialog on this
  generation. A full-screen widget (FrameContainer + InputText + ButtonTable
  row Post/Preview/Close) is the shape; Post stays disabled until
  `message` is non-empty; one in-flight submission is a composer state
  (posting flag), not a queue.
- Voice: submit in progress states plainly ("Posting…"); success confirms
  with the new post's coordinates (thread, page, post id); the double-post
  guard failure is phrased for someone who has seen it before. YOSPOS
  quirk: the reference client carries `postButton = "YOSPOS BITHC"` for
  forum 219 as data and never consumes it (ForumTweaks.plist:56-61,
  ReplyWorkspace.swift:821-828); we will: forum 219's composer labels its
  Post button "YOSPOS BITHC" (spec: Composition).
- Files: `saforums/composer.lua` (new InputContainer screen), ui entry
  points: "Reply to thread" on the thread view (title bar or end-of-thread
  affordance) and "Quote" from the post menu (C4). Draft persistence (C1)
  hooks every edit.
- Tests: composer_spec under the widget stubs (state transitions: empty ->
  draft -> posting -> done/error; Post disabled when empty; draft written
  before the submit callback fires).
- Done-when: in kodev, compose a reply into a test thread on the real site
  (Brandon drives), draft persists across a restart, preview shows, submit
  lands once.

### C7. Edit flow (mechanically free after C2/C3)

Goal: edit your own posts.

- Facts: `GET editpost.php?action=editpost&postid=N`; the form is also
  `form[name='vbform']`; missing form with a `#content center div.standard`
  containing "permission" means forbidden (ForumsClient.swift:1695-1703).
  The client touches only `message` and, when present, the
  `attachmentaction` select (keep/delete/new) (1620-1645). No `reason`
  field exists. Submit: POST `editpost.php` (multipart, same mirror);
  success classification is absence of a standarderror page (1655).
- Files: compose.lua gains `classify_edit_response` (error/no-error);
  the composer opens from "Edit" on your own posts (the post menu gains it
  when `post.author_id` equals the account's user id, available from the
  index JSON user record stored at login); draft `edit-<postid>.bbcode`.
- Spec: Composition section note that edit is tier 2 of the same rules.
- Done-when: edit own post from kodev, text change visible in the thread.

### C8. Deferred behind C1-C7 (documented, not scheduled)

New threads (`newthread.php` has `iconid` radios and a `subject` field),
polls (a second transaction with "thread posted, poll wasn't" recovery),
attachments (Platinum-gated; `MAX_FILE_SIZE` input plus the
`dimensions:\s*(\d+)x(\d+)` cell regex discover limits,
ForumsClient.swift:1514-1547). Each needs its own decision + mining refresh
when scheduled.

## Wave D: gated surfaces (read-only; each brief is self-contained)

Common wiring: a settings flag per surface (`has_platinum` etc.) set by D1;
surfaces hidden (not broken) when the flag says no. All reads carry the
usual politeness (list cache TTLs where it makes sense).

### D1. Account-features probe

Goal: know what the account can do; fail loud.

- Facts: `GET member.php?action=accountfeatures`; the page must contain
  `dl.features` (its absence means session trouble: fail loud, do not
  guess); owned upgrades are `dt` elements with class `enabled` inside it;
  match by lowercased substring: `platinum`, `archives`, `no-ads` /
  `no ads` (AccountFeaturesScrapeResult.swift:30-41, accountfeatures.html
  fixture:41-63). Platinum implies PM sending and search (doc comment at
  AccountFeaturesScrapeResult.swift:16).
- Files: new pure `saforums/featuresparser.lua` (fixture-first), session
  GET, settings flags refreshed at login and via a menu action. Cache: one
  fetch per login is plenty (the reference client refreshes on demand).
- Tests: featuresparser_spec over a synthetic accountfeatures fixture.
- Done-when: flags land in settings and the Wave D surfaces gate on them.

### D2. PM folders (read-only inbox and sent)

- Facts: `GET private.php?folderid=N` (inbox `folderid=0`, sent `-1`,
  `pagenumber` only past page 1; ForumsClient.swift:2060-2074). Folder list
  from `select[name='folderid'] option[value]`, current = the
  `option[selected]` (PrivateMessageFolderScrapeResult.swift:33-42). List
  is `table.standard` with plain `tr` rows: `td.status img` (src containing
  `newpm` = unread), `td.icon img`, `td.title a` (href carries
  `privatemessageid`), `td.sender a`, `td.date` (fixture
  private-list.html:198-204). A `div.pmwarn a[href*='showall']` marks a
  truncated (last-50) folder.
- Render: a Menu list exactly like bookmarks (unread badge from the newpm
  marker). Folder switcher as leading menu entries.
- Spec: endpoints table gains private.php (reads only; send/move/delete
  stay forbidden). Fixture: synthetic private-list.html.
- Done-when: inbox lists with unread flags in kodev.

### D3. PM reading

- Facts: `GET private.php?action=show&privatemessageid=N`; the message page
  is post-shaped: `td.userinfo` sidebar (`dt.author`, `dd.registered`,
  `dd.title`), `td.postbody` body, `td.postdate` with the status icon and
  date (PrivateMessageScrapeResult.swift:33-65). Subject is the last
  component of `div.breadcrumbs b` text. Quoting would be
  `action=newmessage&privatemessageid=N` (we do not send).
- Render: the existing ThreadView with one pseudo-post (announcement
  pattern). Reuses postblocks/threadview unchanged.
- Done-when: a PM reads exactly like a post in kodev.

### D4. Profile view

- Facts: `GET member.php?action=getinfo&userid=N` (username alone also
  works; no id = own profile). Selectors (ProfileScrapeResult.swift:25-125):
  author sidebar as usual (`dt.author`, `ul.profilelinks` userid,
  `dd.registered`, `dd.title`); gender from `td.info p:first-of-type` after
  the literal phrase "claims to be a "; about text `td.info p:nth-of-type(2)`;
  `dl.contacts` (a PM link = can-receive; aim/icq/yahoo/homepage dds;
  `span.unset` = unset); profile picture `div.userpic img`;
  `dl.additional`: post count (2nd dd), post rate (3rd), last post (4th),
  then Location/Interests/Occupation from remaining dt/dd pairs.
- Render: a simple two-tier text view (reuse the post-card header stack);
  completes the "Author Profile" hold-menu item deferred from Wave B: the
  thread-list and post-menu hold menus gain "View profile" when
  `thread.author_id` / `post.author_id` is known.
- Done-when: hold a poster, view profile, the fields render in kodev.

### D5. Rap sheet (read-only)

- Facts: `GET banlist.php` always carrying the filter defaults
  `adminid=0&actfilt=-1&ban_month=0&ban_year=0` plus `pagenumber`, and
  `userid=N` for a single user's sheet (ForumsClient.swift:1994-2056).
  Table is `table.standard`, one `tr` per punishment, six columns: Type
  (PROBATION/AUTOBAN/PERMABAN/BAN substring; nested link carries
  `goto=post&postid=N` when the ban cites a post), Date ("MM/dd/yy hh:mma"),
  Horrible Jerk (user link), Punishment Reason (html), Requested By,
  Approved By (LepersColonyScrapeResult.swift:131-182, banlist.html:155).
  `actfilt` wire values: any=-1, probations=2, allBans=-2, regularBans=0,
  autobans=7, permabans=9 (68-75). Pagination via the usual div.pages
  attributes with an older select fallback.
- Render: a plain Menu list (date, jerk, reason excerpt). Entry point:
  the profile view (D4) and a Tools menu item.
- Done-when: your own rap sheet renders (or a clean sheet says so plainly).

### D6. Search (Platinum-gated; only after D1 flips the flag)

- Facts: form page `GET query.php` (`form[action='query.php']`; forum
  checkboxes `div.search_forum input.forumcheck`, value = forum id;
  hierarchy encoded as `depthN`/`parent<ID>` classes;
  SearchPageViewModel.swift:142-181). Submit: POST `query.php` with
  `application/x-www-form-urlencoded` body `q=...&action=query&forums[]=N&forums[]=M`
  (urlencoded, NOT multipart; `action=query`, not `dosearch`; omitting
  `forums[]` searches everywhere; `threadid:<N> ` prefix scopes to a
  thread) (ForumsClient.swift:369-400, SearchPageViewModel.swift:82-84,
  381-384). The response redirects to `query.php?action=results&qid=N`; the
  qid is the only handle on the results (366-368). Results pages:
  `GET query.php?action=results&qid=N&page=M`; hits are `div.search_result`
  blocks (`.threadtitle` with a postid link, `.blurb` excerpt with `<em>`
  highlights, `.hit_info` date), summary in `#search_info`; expired qids
  present as a non-results page (SearchPageViewModel.swift:239-257, 431-436).
- Render: a search dialog (InputDialog) -> results Menu (title + blurb
  lines) -> tap opens the post's thread page (browse noseen; showthread.php
  with `goto=post&postid=N` is a valid jump straight to the hit).
- Spec: endpoints table gains query.php (Platinum-gated).
- Done-when: a search from kodev returns results that open.

## Distribution (Phase 5, remaining)

- [ ] v0.5.1 release (back-stack, avatar pass, loose ends L1-L5 as they land).
- [ ] Brandon's Kindle pass on the release zip (his initiative, his policy).
- [ ] The e-reader-thread post (drafted; posted when he is satisfied).
- [ ] On-device App Store cold-install check; Storefront at its next catalog
      build.
- [ ] Voice polish on everything a stranger hits first (first-login copy,
      the Cloudflare error, an About screen with the "not endorsed by
      Something Awful" line).
- [ ] Stretch, only after everything above: one deliberately rare, harmless
      easter egg in the Magic Cake pattern (found, not sought; never
      documented in-app).

## Deferred (not scheduled; do not start without a fresh decision)

The dormant EPUB track's typography items (see the parked section). New
threads, polls, attachments (Wave C8). PM send/move/delete, folder
management, ignore list, SAclopedia reader, archives time machine, inline
custom-designed list widgets beyond KOReader's Menu, charts and
reading-stat tie-ins, LAN compose server.

## Phase history (met and closed)

- Phase 0 (skeleton): met. Plugin loads, menu entry, scaffold.
- Phase 1 (vertical slice): met on the Oasis 2026-10-08. Login -> forum ->
  thread on e-ink, noseen discipline intact, three device bugs fixed and
  test-pinned.
- Phase 2 (read state and bookmarks): met; the loop replaceable on the
  Oasis. Loose ends carried above (L1, L2).
- Phase 3 (typography pass): met by the native renderer pivot (three
  architecture verdicts recorded in the history below) and Wave A's token
  port; the EPUB-specific remainder is parked with the dormant track.
- Phase 4 (reading ergonomics): partially met and absorbed: retention
  shipped; SWR list rendering shipped in Wave B (deep-compare remainder is
  L4); the refresh-in-place items belonged to the EPUB route and are parked;
  scroll persistence is L3; settings surface and cookie-expiry warning move
  to the loose-ends backlog when composition lands.
- Phase 5 (distribution): the marketplace contract is met through v0.5.0;
  remaining boxes live in the Distribution section.
- Phase 6 (composition Tier 1): superseded by Wave C above (same rules, more
  research, draft-file first).
