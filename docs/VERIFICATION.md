# Verification — 25–26 October 2026

## Environment

- Source: this repository.
- Xcode: `/Applications/Xcode-27.1.0-Release.Candidate.app/Contents/Developer`, version 27.1, build `27A9275`.
- Swift 6.4, strict Swift 6 language mode; XcodeGen 2.45.3.
- Deployment target: macOS 14.

## Completed checks

- Debug application build succeeded.
- Release application build succeeded for Apple Silicon (`arm64`) and Intel (`x86_64`).
- The universal Release app passes `codesign --verify --deep --strict`. Its entitlements enable App Sandbox and outbound networking; the Release app does not carry the debugger-attach entitlement. Signing is ad hoc for local use.
- Final Debug and optimized Release suites each pass 24 tests, including the response-size limit and a delayed startup-cache race.
- Live Swift client (not a curl-only probe) decoded the 2026 season and round-tripped its disk cache: 25 calendar events, including two cancellations; 17 published GP winners; 23 drivers; 11 constructors.
- The live selection was United States Grand Prix, using the actual clock. Championship snapshots were explicitly associated with Singapore Grand Prix. These are dated provider observations, not app constants.
- Tests cover before/during/after-weekend selection, sprint order, testing/cancelled-event exclusion, race-start/result-delay boundaries, missing times, Saturday races, DST repetition, season rollover, earlier-session metadata, decimal points/provider ranking, partial failures, malformed data, disappeared events, rate limits, corrupt cache, overlapping refreshes, late startup-cache reads, and stale cancelled results.
- Test products are isolated from the shipping build; no fixture or test-control path is included in app composition.
- The Release Swift client also passed the live API/cache check after introducing bounded streaming response reads.
- Shell syntax, entitlement plist syntax, project generation, and whitespace checks passed. The source scan found no embedded credentials; build products, caches, and coverage artifacts are ignored.

## Installation and startup fixes

- Installed the Release app in `~/Applications/F1 Menu Bar.app`.
- Initial installed launches exposed a hardened-runtime library-validation failure: the ad-hoc dynamic F1Core framework could not load despite passing code-signature verification. F1Core is now linked statically, with no embedded core framework. The corrected universal Release build and all 24 optimized core tests passed. The build now checks for signature failures, dynamic core linkage, and stale embedded frameworks.
- A subsequent process sample identified a continuous menu-bar status-button update loop at launch, while the custom label contained a TimelineView and lifecycle modifiers. Replaced it with a plain Label and moved startup, refresh timing, wake handling, and timezone notifications into AppLifecycle. The Release build passed; the hung process was stopped, and the corrected app was reinstalled and launched.

## Calendar availability fix

- The installed app's network log and a direct `meetings?year=2026` request returned HTTP 401 at 20:31 UTC. The response explicitly stated that a live session restricted global API access, including past sessions. The network sandbox entitlement was present; this was a provider restriction.
- Added Jolpica as an automatic backup for full schedules, GP winners, and standings. Provider snapshots, identities, and disk caches remain separate. Source attribution follows the active snapshot.
- The universal Release build passed its signature/static-link checks. All 32 optimized core tests passed, including first-launch 401 fallback, recovery to OpenF1 without merging identities, separate caches, both providers failing, partial standings failure, wrong-round responses, missing times/numbers, non-numeric classifications, decimal/deducted points, and pagination limits.
- The production Swift repository selected Jolpica and decoded 23 weekends, 17 published GP winners, 23 drivers, and 11 constructors, then round-tripped its cache. The featured weekend was United States Grand Prix and both points tables were scoped to the published Singapore GP. These are dated API observations, not constants or visual app verification.
- Replaced the installed bundle with the Release fallback build and issued its launch command. No UI inspection was performed, as requested by the user.

## Ongoing weekend heading

- The menu bar panel now shows **Ongoing Grand Prix** during the featured weekend's dates in the selected display timezone, including the time before its first practice on that date and gaps between sessions. It keeps the session schedule and countdown visible. This is a weekend date label, not a live-session signal.
- All 37 optimized core tests passed. New tests cover first-day midnight, the full race date, the next midnight across daylight-saving changes, Saturday races in different timezones, completed/cancelled/removed weekends, and unknown race dates.
- The universal Release build passed the signature and static-core packaging checks. The installed app was replaced and its launch command issued. Visual inspection remains with the user.

## Standings weekend notice

- Driver and constructor standings show **Waiting for this weekend’s results** during the GP weekend's dates in the selected timezone. Each message disappears when that table includes the GP, even if the other table is still pending. A published winner alone does not establish updated points.
- All 39 optimized core tests passed, covering separate championship updates and the notice's date boundaries. The universal Release build passed its signature and static-core packaging checks.
- Replaced the installed app and issued its launch command. No UI inspection was performed, as requested by the user.

## Experimental personal live timing

- Added a separate Live timing section with positions, gaps, laps, last/best/sector times, tyre compound and age, observed stint history, pit counts, recent race control, track status, and weather. Its single anonymous connection follows section/window visibility and sleep, with an explicit manual pause. No live data is written to disk or used to calculate standings or winners.
- All 53 optimized core tests passed. The 14 added tests cover subscription snapshots, sparse array/object updates, tyre age, null/deleted fields, missing metadata, old timestamps, session resets, fragmented UTF-8 SignalR frames, malformed/deep/oversized inputs, bounded message history, Retry-After, pre-snapshot deltas, protocol failures, cancellation generations, manual pause, and sleep/wake state.
- The universal Release build passed signature and static-core packaging checks. Project generation, shell syntax, and whitespace checks passed. No third-party dependency was introduced.
- Two headless connections using the production Swift client succeeded anonymously. The final 45-second check had no interruptions and returned United States Grand Prix / Race, with 22 drivers carrying lap times, tyre compounds, and pit counts, plus the latest 40 race-control messages. The initial check reported `Finalised`; the later one reported `Ends`. Neither observed fresh active-session timing. These are dated feed observations, not constants or evidence of live racing.
- The connection check verifies negotiation, subscription, snapshot decoding, keepalive, and cancellation. Actual updates during an active session, behavior across a live session change, and recovery from a real network outage remain unverified outside deterministic fixtures.
- Replaced `~/Applications/F1 Menu Bar.app` with the Release build and issued its launch command. No UI inspection was performed, as requested by the user.

## Live window and connection repair — 26 October 2026

- Following a report that Live timing made the sidebar and window disappear, the installed process was still running. A stack sample showed an idle event loop; no new app crash report was found. The disappearance itself was not visually reproduced.
- Source inspection found synchronous observable-state mutation in the live view’s native attachment/removal callbacks. Moved visibility observation to the stable detail-window container and added deferred, coalesced delivery with obsolete-notification guards. Section changes no longer replace the visibility observer. Window minimum size is constant across sections, and sidebar visibility is explicitly restored when navigating.
- The installed app’s network log recorded a WebSocket HTTP 101 upgrade followed by `NSURLErrorTimedOut` after about 30 seconds. The stream had shared the finite HTTP session’s 30-second resource timeout. It now has a separate long-lived URLSession; both sessions retain one cancellation owner. The protocol watchdog now also covers sending the initial handshake.
- All 56 optimized core tests passed, including three new deterministic regressions for deferred view-update callbacks, transient detach/reattach events, and a close superseding queued visibility. Release signature/static-core checks passed.
- The strengthened 75-second production-client smoke check passed: 74 seconds continuously connected, zero interruptions, and the final United States GP snapshot with 22 drivers. Fresh active-session timing was not observed. The script now requires at least 60 uninterrupted connected seconds to succeed.
- Replaced the installed Release app and confirmed a new running process. UI inspection remains with the user; compilation, process presence, and the headless connection check do not establish the sidebar/window rendering outcome.

## Blank live window layout repair — 26 October 2026

- The user's screenshot showed an intact window and toolbar with empty sidebar/detail regions. The running process remained responsive at its event loop; this was not evidence of process termination.
- Reproduced a layout failure with the production `ChampionshipWindow` and `LiveTimingView` in an isolated, offscreen AppKit window. On the first fixture timing snapshot, the split view grew to 2,324.5 points high and its origin moved to -786 inside a 752-point host. This placed sidebar labels and timing rows outside the visible region. The earlier transport/lifecycle repair did not constrain this layout.
- Wrapped the live content in a viewport-sized scroll container and gave the native timing table an explicit height based on the available viewport. The identical probe now keeps the split view at 752 points, origin zero, and the root fitting height at 720 points through the empty-to-populated transition.
- All 59 optimized tests passed: 56 existing core tests and three new offscreen window tests. The latter cover a 22-driver snapshot with 40 race-control messages, section changes, a new empty session, a long reconnect message, and window resizing. They use the actual production views, fixture dependencies, explicit layout passes, and continuation-based synchronization; they do not launch or operate the installed app.
- Added lifecycle diagnostics for window attachment/visibility/size, navigation, and connection phase. They do not log timing payloads or connection credentials.
- The repair is version 0.1.1, build 2. Settings now reads the version from the installed bundle instead of displaying a hardcoded version.
- The final universal Release build passed signature/static-core checks, project generation, and whitespace checks. Installed it in `~/Applications/F1 Menu Bar.app`, confirmed the installed executable matches the build, and launched a new process. The agent did not click through or visually inspect the installed app.

## Standings season wins and toolbar — 26 October 2026

- Separated the season label/selector from the refresh action, gave the label its intrinsic width, and kept the icon button explicitly sized. This addresses the cramped shared toolbar capsule in the user's screenshot.
- Driver standings now include qualifying/GP win counts and horizontally scrollable event badges with country flags; a double win becomes one **Quali & GP** badge. Constructor standings show GP win counts and flags for either driver's victories, with event names on hover. Both native tables are bounded by their available viewport.
- Statistics use published final P1 classifications, excluding sprint sessions and grid positions. Jolpica results retain stable driver/constructor IDs; OpenF1 metadata is resolved at the result session. Constructor wins stay with the team at that race. Optional cache fields preserve previously saved calendars and championship points.
- All 74 optimized tests passed: 69 core tests and five offscreen window tests. Added coverage includes combined wins, car-number changes, team changes, cancelled/removed events, old-cache decoding, qualifying before the first GP, result failures, malformed/duplicate/wrong-season qualifying responses, result-row pagination, flag aliases, and both populated tables with 24 event badges.
- The universal Release build passed signature/static-core checks; project generation and whitespace checks passed. Version is 0.2.0, build 3.
- Separate production Swift checks succeeded for both providers and round-tripped their disk caches. Each returned 18 qualifying winners and 18 GP winners; the standings aggregation accounted for all 18 of each in driver statistics and all 18 GP wins in constructor statistics. OpenF1 supplied 25 calendar events including two cancellations; Jolpica supplied 23. Both supplied 23 drivers, 11 constructors, and points after the United States GP. These are dated API observations, not app constants.
- Installed the Release bundle in `~/Applications/F1 Menu Bar.app`, verified its executable matches the build, and launched a new process. No installed-app UI automation or visual inspection was performed.

## Centered live timing loader — 26 October 2026

- Replaced the half-height empty block with a compact, centered status in the available viewport. The header, connection control, and attribution remain in place; long messages can still scroll.
- Connecting, reconnecting, and waiting for initial timing show three decorative timing-row placeholders with a gentle 1.8-second shimmer. Only the small skeleton redraws, capped at 30 fps. Reduce Motion and inactive scenes use static shapes; stopped/unavailable states show static explanatory text. Existing timing rows remain visible during reconnects.
- All 74 existing optimized tests passed, including the offscreen initial-empty, first-snapshot, session-reset, navigation, and resizing regressions. The universal Release build passed signature/static-core checks.
- Installed and launched version 0.2.1, build 4, in `~/Applications/F1 Menu Bar.app`; the installed executable matches the build. No installed-app UI automation or visual inspection was performed. Animation appearance and the visual centering remain for the user to review.

## Native verification pending

Visual inspection after the window repair, standings update, and loader polish is left to the user. Menu bar visibility, toolbar and panel/window rendering, loader appearance, win-badge scrolling, keyboard/VoiceOver behavior, light/dark appearance, close/reopen behavior, actual login registration, wake behavior, and idle energy use remain unverified by the agent. Offscreen layout assertions verify geometry through fixture updates; a successful launch command, compilation, unit tests, and the headless API check do not establish the complete visible app behavior.

Manual checks: open the installed app, inspect the menu panel and every sidebar section, confirm timezone/appearance changes, close and reopen the window, and quit from the panel.

## Distribution

The project uses ad-hoc signing for local development. No Developer ID certificate, notarization, installer, App Store submission, or reboot/login verification has been performed.


## Combined race timeline — 30 October 2026

- Reconciled PR #1 (recorded snapshots) and PR #2 (simulation demo) in one Race timeline section, with Recorded selected by default and an explicit Demo tab. Both use the same visibility-owned connection and connection controls/status/error presentation.
- Fixed simulated retirements masking captured positions, retirement flags, gap and lap values; prevented old-session or wrong-lap snapshots from supplying a row; retained absolute positions in one-driver snapshots; and marked drivers absent from a captured lap Unavailable. Known session changes clear the lap history before a new lap count or roster is required.
- All 89 optimized tests passed on macOS 27.0.1 and Xcode 27.1: 71 core tests and 18 window/model tests. Coverage includes session transitions, the three reproduced PR defects, row provenance, stale/finished/disconnected presentation, and both timeline layouts at 1000×720 and 1200×900. Light/dark demo fixture renders and a recorded-mode render are saved in `.build/screenshots/` and attached to the test result bundle. These are offscreen native fixture renders, not screenshots of a live race in the installed app.
- The new long-error layout test reproduced split-view inflation. Bounding the shared connection-error region to a scrollable 64-point area fixed the same probe. Generation, whitespace, universal Release build, signature and static-core packaging checks pass.
- Version 0.3.0, build 5, replaces the existing `~/Applications/F1 Menu Bar.app`. Its executable matches the verified build. The separate PR1/PR2 test installations were moved to Trash, leaving one F1 app installed. The previous normal app bundle is retained as a rollback under the ignored `.build/install-backup/` folder.
- Installed-app process launch is checked separately. Interactive visual inspection remains incomplete because native app inspection timed out during PR testing; no new claim is made about live-race capture, keyboard/VoiceOver, or animation feel on the installed app.


## Historical GP timeline and navigation — 30 October 2026

- Removed the demo/simulated race models, controls and replay views. Calendar now opens the selected GP's real history; Race timeline has a GP picker, Previous/Next lap buttons above a full-width lap progress slider, positions/gaps charts, and fully expanded sortable timing rows inside one page scroll. Historical HTTP/cache work is injected once at composition and is independent of the personal live WebSocket.
- Implemented OpenF1 lap/position/interval/driver/stint/pit/race-control history mapping. Position and fresh gap samples are scoped to the explicit Race session and each driver's approximate lap boundary; gaps older than ten seconds stay unknown. Ten-minute interval windows bound downloads. Optional endpoint failures stay visible without fabricating values. Replacing a GP cancels obsolete work and rejects late callbacks.
- Added Jolpica fallback lap pagination (counting Timings, including a split lap), same-race result metadata and reported pit stops. No provider IDs or rows are combined. Gaps, tyres and race-control remain unavailable in fallback mode. Separate atomic provider/year/schema/race caches retain the last good history after refresh failures or empty refreshes; each file is limited to 8 MB and the total cache to 128 MB.
- Live production checks for the United States GP (OpenF1 session 11396, meeting 1297, 25 October 2026) returned 22 drivers, 56 completed laps and 1,163 real timing rows. OpenF1 also supplied 173 race-control messages. Forced OpenF1 HTTP 401 correctly switched to Jolpica, with the same lap/timing counts and explicit unsupported-field notices. Both providers' normalized histories round-tripped through their disk cache. These are dated observations, not hardcoded app values. The live check caught and verified correction of the time-window URL key (`date>`; the equals sign is the URL separator).
- All 89 optimized tests passed (81 core and 8 window/model tests). Tests cover sampled gap freshness, unfinished laps, wrong-session and duplicate data, pagination, fallback, cache schema/retention, stale GP responses, calendar routing, and a single page scroll with all 22 driver rows. Native offscreen light/dark renders are saved in `.build/screenshots/history-*.png`, including the timing rows at the bottom and an upcoming-race empty state. These renders use test-only fixtures; the Release composition contains no fixtures or simulated history.
- Delivery version is 0.4.0, build 6, updating only `~/Applications/F1 Menu Bar.app`. Release build/signature/static-core checks, installed executable equality and process launch are checked separately. Interactive installed-app UI inspection remains unverified because the native inspection tool previously timed out.

## Exclude upcoming GPs from timeline selection — 30 October 2026

- The timeline picker includes only races whose GP start has passed; practice dates do not qualify a future GP. A published GP result can establish eligibility when its start time is unknown. Cancelled/removed events and cancelled Race sessions are excluded.
- Calendar disables ineligible timeline links, and the navigation coordinator rejects those requests as well. A season with no eligible race shows a disabled picker and a clear empty state.
- All 91 optimized tests passed (83 core and 8 window/model tests), including exact-start boundaries, practice-before-race, unknown times, published results, cancellation, and the Calendar navigation guard. Delivery version is 0.4.1, build 7.
