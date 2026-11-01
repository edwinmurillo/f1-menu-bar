# F1 Menu Bar — proposed project plan

Prepared on 25 October 2026. The name is provisional. Implementation was authorized later that day; this document preserves the original requirements and API research. See `README.md` and `docs/VERIFICATION.md` for current delivery status.

## 1. Product goal

Click a macOS status bar icon and immediately see the relevant Formula 1 weekend and its remaining sessions. Open a larger window to browse the season, see previous GP winners, and check driver and constructor points.

The initial scope is the current championship season, with automatic handling of the transition to the next published season. Browsing arbitrary historical seasons can be added later.

## 2. Proposed experience

| Surface | Content and behavior |
| --- | --- |
| Menu bar | Small monochrome racing icon. Optional short countdown to the next session. |
| Next GP panel | GP name, circuit, weekend dates, countdown, and all sessions in chronological order. The next session is emphasized; past scheduled starts are visually subdued. |
| Calendar window | Chronological season list, automatically positioned at the current/next GP. Each row shows country, GP, race date, sprint indicator, and status. Selecting a row opens its weekend schedule. |
| Previous races | Completed GP rows show the winning driver and constructor. A race awaiting published results displays that state instead of an invented winner. |
| Drivers | Table with championship position, driver, constructor(s), points, and season qualifying/GP win counts. Event badges combine **Quali & GP** when both were won, with country flags. |
| Constructors | Table with championship position, constructor, points, GP win count, and flags for races won by either driver. Hover a flag for the event name. |
| Session history in Live timing | Calendar deep link and GP picker; real historical laps, positions and available timing details; full-width GP lap progress with Previous/Next controls; one page scroll and complete timing rows. No simulation. |
| Live timing | Optional personal connection to F1’s current session feed: positions, gaps, laps, tyres, pit counts, selected-driver details, race control, and weather. |
| Settings | Launch at login, optional menu bar countdown, system-timezone or UTC display, and data-source information. |

The panel footer offers **Full calendar**, **Standings**, **Live timing**, **Refresh**, **Settings**, and **Quit**. The detail views share one reusable regular window. Closing that window leaves the menu bar app running and stops its live connection.

Aim for a roughly 360–400 point panel with native spacing and typography, a restrained racing accent, clear date grouping, system light/dark appearance, keyboard navigation, and VoiceOver labels. Status must remain understandable without color. The UI shows its timezone and last successful update.

### Weekend schedules

- Standard format: Practice 1, Practice 2, Practice 3, Qualifying, Grand Prix.
- Sprint format: Practice 1, Sprint Qualifying, Sprint, Qualifying, Grand Prix, using the actual chronological order returned by the provider.
- Read session presence and timestamps from the API. Never assume a particular venue is always a sprint weekend, that every race is on Sunday, or that every session has an announced time.
- Retain sessions already started within the displayed weekend so the whole schedule stays understandable. Label them by scheduled time; do not imply a confirmed finish from a start timestamp alone.
- In the menu bar panel, label the featured GP **Ongoing Grand Prix** when today falls between its first scheduled session date and race date, inclusive, in the selected display timezone. Use **Next Grand Prix** before that range. This describes the weekend, including gaps between sessions; it does not claim that a session is live. Published GP results still advance the panel to the next weekend under the selection policy below.

## 3. API decision and evidence

**Updated proposal after the OpenF1 comparison: use OpenF1 as the primary provider.** Live checks confirmed upcoming sessions, completed race results, and both championship tables. Its session end times and cancellation flags are useful additions to the original Jolpica-only proposal. The championship endpoints are beta, so validate them against known season snapshots during integration and keep the provider boundary replaceable. Following the installed app’s calendar failure on 25 October, Jolpica is an automatic backup when OpenF1 fails. Switch complete snapshots and keep provider-specific caches; do not mix conflicting provider records.

### OpenF1

OpenF1 is an independent community API, not an official Formula 1 service. It documents free unauthenticated historical access from 2023 and paid live access. Both championship endpoints are marked beta and are associated with race sessions. Sources: [OpenF1 documentation](https://openf1.org/docs/), [access and FAQ](https://openf1.org/).

| Need | OpenF1 endpoint |
| --- | --- |
| Season events | `/v1/meetings?year={year}` |
| Sessions, start/end times, cancellation flags | `/v1/sessions?year={year}` |
| GP or qualifying winning classification | `/v1/session_result?session_key={raceOrQualifyingSession}&position=1` |
| Driver names and team metadata | `/v1/drivers?session_key={raceSession}` |
| Driver points and position | `/v1/championship_drivers?session_key={completedRaceSession}` |
| Constructor points and position | `/v1/championship_teams?session_key={completedRaceSession}` |

**Observed on 25 October 2026 without authentication:** the sessions request returned 131 records including testing; 25 future sessions after 25 October; and sprint qualifying. Race-session filtering returned 25 races, of which two were explicitly cancelled, leaving 23 active races. Future dates extended through 6 December. For completed Singapore race session `11388`, results returned a position-1 classification, driver standings returned 23 rows, and team standings returned 11 rows. The session driver directory returned 22 rows and resolved the winner's number to Max Verstappen and Red Bull Racing. These are dated provider-response observations, not hardcoded app values.

Implementation must exclude testing and explicitly cancelled races from upcoming selection, join sessions through `meeting_key`, and keep driver-number identity scoped to the season and relevant session. Championship rows may include a driver absent from the latest race roster; resolve that driver's metadata from earlier season sessions rather than dropping the row. Select a completed **Race** session explicitly for standings; `latest` could instead identify practice or qualifying. Use provider `position_current` and `points_current`; names require metadata joins. Season win statistics were requested on 26 October: aggregate published P1 results for **Race** and **Qualifying**, excluding sprint sessions. Count qualifying classifications rather than grid positions after penalties. Attribute constructor wins using the team at that result, not a driver's later team.

A later live-session request on 25 October returned HTTP 401 with an explicit global restriction, including past-session data. Free OpenF1 access alone therefore cannot guarantee calendar availability during a race. Use the Jolpica backup for this failure; the separate live feature below does not depend on OpenF1. Respect the current free limits of 3 requests/second and 30/minute, cache requests, and distinguish a subscription-required response from a network failure. Treat scheduled session end times as schedule information, not proof of actual completion.

### Personal live timing — scope added 25 October 2026

Arturo authorized trying F1’s anonymous live feed locally for personal use after discussing its access and usage risks. Use the direct SignalR Core/WebSocket endpoint as an optional, experimental feature, separate from calendar, winners, and championship snapshots. This is not a supported public developer API or a promise of continued access.

- Show the feed’s actual meeting, session, status, positions, gaps, lap counts/times, sectors, tyre compound/age, observed stint history, pit counts, recent race-control messages, track status, and weather when supplied.
- Connect while Live timing is visible, including its session history browser. Historical requests retain an independent cache owner. Stop on close, hiding, leaving Live timing, sleep, or explicit Disconnect; preserve a manual pause until Connect is chosen.
- Merge sparse topic updates into the subscription snapshot. Reset on a new session or subscription, reject obsolete connections and older topic updates, and bound memory and publication frequency.
- Show **Live** only for a Started session with a recent timestamped timing update. A subscription snapshot, ping, scheduled timestamp, or last-known position does not establish liveness. Keep finished and stale data explicit.
- Use no account credentials, paid topics, backend, or telemetry sharing. Store bounded observed lap snapshots locally as requested. Respect access denials and Retry-After, with bounded reconnects and manual retry.
- Tyre history describes observed stints; future team strategy and exact stationary pit-stop durations are outside this scope. Provisional timing never updates GP winners or championship points.

Protocol references and dated connection evidence are in `docs/DATA_SOURCES.md` and `docs/VERIFICATION.md`.

### Formula 1's official calendar

The official [download/sync announcement](https://www.formula1.com/en/latest/article/download-or-sync-the-f1-race-calendar-to-your-device.7mpETY062kafAl55qVnemu) links to [calendar.formula1.com](https://calendar.formula1.com/) and states that it covers practice, qualifying, sprints, and Grands Prix. Browser inspection confirmed an ECAL subscription interface with Google, Apple, Outlook, and other calendar options. Inspecting its Other option led to a registration form; no registration or subscription was submitted.

An official calendar subscription exists. A general supported public developer API covering schedules, winners, and championship points was not established by this research. Do not equate these two claims, or claim that Formula 1 has no APIs internally. Arturo's existing subscription URL has not yet been inspected. Treat it as a candidate for schedule cross-checking or a future calendar adapter once its accessible format and coverage are verified; winners and championship points still need a results source.

### Jolpica, the automatic backup

Jolpica's established Ergast-compatible endpoints cover the requested data, including explicit sprint qualifying times. The provider documents its [race fields](https://github.com/jolpica/jolpica-f1/blob/main/docs/endpoints/races.md) and [sprint naming differences](https://github.com/jolpica/jolpica-f1/blob/main/docs/ergast_differences.md).

Base URL: `https://api.jolpi.ca/ergast/f1/`. Use an explicit season year consistently across requests.

| Need | Request path |
| --- | --- |
| Full calendar and session start times | `{year}.json?limit=100` |
| GP winners for the season | `{year}/results/1.json?limit=100` |
| Qualifying results filtered to final P1 | `{year}/qualifying/1.json?limit=100` |
| Driver championship | `{year}/{completedRound}/driverStandings.json?limit=100` |
| Constructor championship | `{year}/{completedRound}/constructorStandings.json?limit=100` |

Request `limit=100`, validate `total` and `offset`, and fetch additional pages when needed, bounded to five pages and 500 rows. Select an explicit completed GP round for standings; an unscoped latest table may already include the current weekend’s sprint. The winners query filters finishing position 1; it is not a request for round 1. Join winners to calendar events by season and round, with circuit identity checked during reconciliation.

**Verified during planning:** the calendar, GP winner, and two championship requests above succeeded for 2026 without authentication. The responses contained 23 scheduled races, six sprint weekends with six `SprintQualifying` entries, 17 GP winner records, 23 driver standings rows, and 11 constructor rows. Both standings responses identified round 17. These are observations of the provider response on the research date, not constants or independent confirmation of official race facts.

The qualifying results endpoint was added on 26 October. It can return additional classified drivers: filter the final `position` to `1` after counting all `QualifyingResults` rows for pagination. Match published driver and constructor IDs rather than assuming race car numbers equal permanent numbers. Cache qualifying winners independently from GP winners, so a qualifying failure does not block championship refreshes.

The initial Python HTTP probe encountered a local certificate-store error. Repeating the requests with macOS `curl` succeeded with certificate verification enabled. This establishes API reachability; the eventual Swift client still needs its own integration check.

The provider currently documents unauthenticated limits of 4 requests/second and 500/hour, and requires an app/version `User-Agent`. Use a lower internal budget, request coalescing, caching, and backoff. Limits can change. Sources: [request conventions](https://github.com/jolpica/jolpica-f1/blob/main/docs/README.md), [rate limits](https://github.com/jolpica/jolpica-f1/blob/main/docs/rate_limits.md).

Jolpica's [terms](https://github.com/jolpica/jolpica-f1/blob/main/TERMS.md) allow free non-commercial use under CC BY-NC-SA 4.0 and direct commercial users to contact the provider. Include source attribution in the app; resolve a commercial arrangement if commercial distribution becomes part of the product.


## 4. Selecting the next GP and representing status

Use a testable policy based on an injected clock, absolute session timestamps, and published GP results. Selecting the featured weekend and determining whether a race has finished are separate decisions.

1. Load the current year's schedule and results. Re-evaluate on app launch, panel opening, wake, relevant time boundaries, and system date/timezone changes.
2. Before a weekend starts, feature the earliest upcoming GP and highlight its first future session.
3. During its weekend, keep that GP featured even after practice or qualifying has started. Highlight the next session still in the future.
4. At the GP's scheduled start, keep the weekend featured and show “Race scheduled to have started · results pending.” Do not advance immediately or present an unverified live badge.
5. A published GP classification establishes **Raced** and its winner; then feature the next GP. Results remain refreshable because classifications can be revised.
6. To prevent an unavailable result from blocking the app indefinitely, use a proposed six-hour focus window after the scheduled GP start. If results are still absent after that window, feature the next scheduled GP and retain the previous one as **Results pending**. This is a navigation fallback, not a claim that the race has finished. Keep the policy configurable and visible to tests.
7. Once the season is over, check the following year's schedule. If it is not published, show “Season complete · next calendar not available” and retain the last season's calendar and standings with their year clearly labeled.

Calendar labels are **Raced**, **Current weekend**, **Next**, **Future**, **Cancelled**, and **Results pending**. Support **Time TBC** for missing times. OpenF1's explicit cancellation flag can establish **Cancelled**; neither scheduled end times nor missing rows establish completion or cancellation. On an explicit schedule change, reconcile dates and upcoming selection. Retain a cached removed event as “Schedule changed / unavailable” until reconciled. A Jolpica adapter must not invent cancellation information that its response does not provide.

Store UTC instants, format with the selected timezone, and compare full timestamps rather than day numbers. Use `Europe/Madrid` as one test timezone, not a hardcoded app default. A date without a time remains a date-only value and cannot drive a precise countdown.

## 5. Standings behavior

Preserve the championship order and points supplied by the API, including ties and decimal points. Do not sum race or sprint scores locally. Display the season, completed race/meeting used for the snapshot, and retrieval time so delayed standings remain understandable; use a round number only when the provider supplies one. Results and standings may update at different times; each section keeps its own freshness state. A GP snapshot does not prove that a more recent sprint is reflected in the table.

The season tables show every returned driver/team and scroll as needed. Driver rows can retain multiple constructor associations if a driver changes teams. No driver count, team count, team color, or championship leader is hardcoded.

During the current GP weekend's date range, show **Waiting for this weekend’s results** below each standings header until that table's snapshot includes the GP. Use the selected display timezone and the inclusive first-session/race dates. A GP winner and the two championship tables can update independently; hide the message separately for each updated table. Hide it outside the date range and for cancelled, removed, or unknown-date weekends.

## 6. Technical approach

- **Platform:** native Swift 6 and SwiftUI; proposed minimum macOS 14. Use `MenuBarExtra` with window style, a regular detail window, and `LSUIElement` for the menu bar app lifecycle. Apple's [MenuBarExtra documentation](https://developer.apple.com/documentation/swiftui/menubarextra) covers this presentation model. Verify focus, reopening, and settings behavior on the actual Mac.
- **Project:** XcodeGen configuration as the source of truth, an app target and XCTest target, and repository-owned scripts. Use Swift Package Manager only when a dependency is justified; no third-party client is required initially.
- **Layers:** app composition root → feature presentation models → schedule/standings repository → OpenF1/Jolpica clients and separate disk caches. Keep provider-specific DTOs and identities behind the repository boundary. Inject transport, clock, and cache so date rules and error behavior can be tested without the network.
- **Models:** race weekend, session, GP winner, driver standing, constructor standing, and data freshness. Normalize transport DTOs at the data boundary and keep UI formatting out of domain models.
- **Concurrency:** main-actor presentation state; one refresh coordinator; bounded HTTP work; explicit off-main cache/decoding ownership. Reject late responses from obsolete season selections or refresh generations.
- **Live connection:** separate injected actor-owned SignalR client and main-actor presentation store. Keep a single visible connection, cancel obsolete work, and coalesce timing publication to roughly once per second. Observe visibility at the stable window container and defer AppKit callbacks before publishing state. Keep the detail window size stable across sections; separate finite HTTP deadlines from the long-lived WebSocket.
- **Storage:** small versioned JSON snapshots in Application Support, keyed by provider/season/endpoint; serialized atomic writes and a conservative size limit. Use `UserDefaults` for preferences. A database is unnecessary for the initial dataset.
- **Backend:** direct HTTPS requests from the app. No account or server is required for the proposed initial feature set.

## 7. Refresh and failure behavior

Render cached data first, then refresh eligible sections. Proposed freshness intervals are six hours away from a race weekend, 30 minutes during it, and five minutes while awaiting results within the six-hour post-start focus window. Recalculate the local countdown without fetching data every second.

Use the same refresh owner for panel opening, manual refresh, timers, and wake events. Coalesce overlapping calls, respect `Retry-After`, and apply bounded exponential backoff. Timers must not prevent sleep. Refresh on wake instead of promising activity while the Mac sleeps or the app is quit.

If one request fails, retain valid data from other sections. Clearly distinguish loading, offline cached data, outdated standings, empty unpublished data, and an unrecoverable initial load. Keep the last good cache on transport or decoding failure and allow manual retry.

## 8. Implementation stages

| Stage | Deliverable | Completion check |
| --- | --- | --- |
| 1. Native shell | XcodeGen project, app composition, menu bar panel, detail window, basic settings, and scripts. | Reproducible build and visible launch on the Mac; close/reopen windows and Quit behave correctly. |
| 2. Data foundation | OpenF1 transport/DTO mapping, metadata joins, cache, refresh coordinator, date selection, and fixtures. | Standard and sprint fixtures decode; cancelled/testing events are excluded; missing driver metadata, beta standings, offline cache, and date boundaries behave correctly. |
| 3. Next GP | Polished panel with complete weekend schedule, local times, next-session emphasis, and countdown. | Before/during/after-weekend scenarios pass; panel remains responsive and uses no polling for countdown ticks. |
| 4. Calendar and winners | Full season list, status labels, selected-weekend detail, and winner integration. | Every returned event appears once; GP winners never come from sprint results; unavailable results remain explicit. |
| 5. Championship tables | Driver and constructor tables with provider ranking, points, wins, and freshness. | All returned rows render correctly, including ties, decimal points, and mismatched update rounds. |
| 6. Delivery polish | Launch at login, accessibility, appearance, sleep/wake behavior, Release verification, and local installation. | Actual screenshots of the menu panel/calendar/tables and a verified Release launch; packaging/signing details recorded. |

Keep each stage runnable when its app code exists. Do not mark the app finished solely because a build passed.

## 9. Acceptance and test scenarios

- Before FP1, between sessions, at the GP start, after a published GP result, and during a provider result delay.
- Standard and sprint weekends; explicitly verify sprint qualifying and the absence of nonexistent FP2/FP3 sessions on sprint fixtures.
- Midnight, daylight-saving changes, cross-timezone date differences, a Saturday race, sleep/wake, and a changed system timezone.
- An unpublished next season, a date-only session, a revised schedule, and a previously cached event disappearing from the returned schedule.
- Initial offline launch, offline launch with cache, malformed JSON, corrupt cache, rate limiting, incomplete pagination, and one endpoint failing while others succeed.
- Two overlapping refreshes with out-of-order completion; a late response must not overwrite newer data or a different season.
- Correct join of GP and qualifying winners to events; combined win badges, constructor attribution across driver transfers, and provider ranking/points preserved in both standings tables.
- SignalR framing, full snapshots and sparse deltas, tyre age, stale/finished status, session changes, protocol failures, bounded history, and old connection callbacks after cancellation.
- Visible panel/window checks in light/dark appearance, keyboard and VoiceOver checks, and low idle CPU/network activity measured on the Mac.

Use deterministic XCTest fixtures and controllable clocks, not sleep-based asynchronous tests. Keep remote smoke tests separate from the repeatable test suite.

## 10. Later additions

Optional follow-ups include session reminders, calendar export, favorite driver/team emphasis, a spoiler-hiding setting, previous-season browsing, full race classifications, and richer telemetry through a separately evaluated provider.

The implementation includes the native shell, OpenF1 with a Jolpica backup, next-GP panel, full calendar, both points tables with season wins, experimental personal live timing, settings, and verification scripts. Fixtures are confined to the test target; production uses the providers’ network services. Native visual verification and distribution checks are tracked in `docs/VERIFICATION.md`.

## 11. Design exploration

Two interactive concept directions were prepared for review. **Weekend** shows the full schedule immediately with a compact next-session countdown. **Session focus** gives the countdown more prominence and expands the weekend schedule on demand. Both lead to the same native-style calendar, race detail, driver/constructor tables, and settings window.

These are proposed designs with illustrative data, not implemented SwiftUI screens or a selected final visual direction. The working title remains provisional. The preview supports calendar selection, screen navigation, timezone changes, and appearance changes; its example championship points and winners are not a live data feed.

## 12. Historical GP timeline — 30 October 2026

Session selection update: The Grand Prix picker includes only weekends with a started session or a published GP result, including the current weekend once practice starts. The timeline initially chooses the latest started session and lists only the practice, sprint, qualifying, and Race sessions supplied by that weekend's calendar. Future sessions cannot be selected. OpenF1 history is keyed by the selected session; Jolpica remains a Race-only fallback. Non-Race sessions have independent cache keys; implicit and explicit Race selections keep the original GP key and existing saved histories.

Live recording update: Keep the one personal F1 SignalR connection running while either Live timing or Race timeline is visible. For a Started session, record observed lap snapshots under the stream's session identity, persist bounded JSON atomically in local Application Support, and restore the latest recording after relaunch. Use a local recording only when its meeting, session name and date match the selected calendar session. A complete historical snapshot takes precedence over a stale local recording. Never infer missing earlier laps; use the historical API for other sessions.

Practice/qualifying correction: Rank practice drivers by best lap time so far, including drivers not currently on track. Record improvements as chart steps. Qualifying captures changed rankings and reset/slower best times, using feed positions and gaps rather than comparing Q2/Q3 against earlier segments. Label updates by observed time and show last and best times in the timing table. Sprint and Grand Prix races retain lap-based history.

Live session clock and pit status: Subscribe to F1's ExtrapolatedClock topic and use its UTC anchor, remaining value, and extrapolating flag for a shared clock in Live timing and Race timeline. Hide the clock when the session is not active. In free practice, use red text below five minutes. Add a pit-status column to both tables from the stream's InPit and PitOut flags; leave historical values unknown when no live pit state was captured.

Tyre history: Add a compact stint sequence beside the existing current tyre/age column in both timing tables. Completed stints show laps driven on that tyre; the current stint has no final count. Use the live TimingAppData stint ages, subtracting known age before fitting used tyres, and OpenF1's historical stint start/end laps. Leave unknown durations blank.

The user requested removing all mock data after trying the combined PRs. Retain one installed app. Calendar links directly to the selected GP's Race timeline; a GP picker changes races without returning to Calendar. For the session timeline, only weekends with a started session are selectable. The Race itself stays unavailable until its start. A published GP result can qualify a Race with an unknown start time. Cancelled or removed events are excluded, and Calendar uses the same eligibility rule. Positions and Gaps share a full-width lap slider representing the entire available GP lap range. Clearly labelled Previous lap and Next lap buttons sit above it. The bottom timing rows expand to their full height inside the page's only vertical scroll.

Use OpenF1's historical laps, position, intervals, drivers, stints, pit and race_control endpoints with explicit race-session identity. Lap starts are approximate, so positions and fresh gaps are sampled at each driver's lap boundary and labelled accordingly. Only completed/observed laps are presented; missing values remain unknown. Read interval history in bounded time slices. Never generate race gaps by summing lap times or infer retirement/caution periods from missing samples.

Use Jolpica's paginated lap endpoint and same-race result directory/pit stops as a complete alternative if the OpenF1 snapshot is unavailable. Count Timing rows across pages, including a lap split at a page boundary. Keep identities and caches scoped by provider, calendar selection, year, race and schema. Do not mix provider rows. Unsupported gaps, tyres and race-control events remain unavailable in Jolpica mode. Missing, upcoming, cancelled and failed histories need clear empty/error states with retry and another GP selection.

One injected history store owns cancellation, coalescing, cache-first display, forced refresh and stale-request rejection. A slow response for a previous GP cannot replace the selected GP. Keep the last good history after refresh failures and do not overwrite it with an empty response. Historical requests remain separate from the shared personal live WebSocket; the window owns that connection while either timing section is visible.

### History loading and cache refinement

Retain completed GP histories across launches without hourly re-downloads; keep four recent races in memory and offer explicit Refresh for revisions. Publish essential real lap positions and times before the slower details requests finish. Repair sparse saved histories that cannot form any consecutive position trace, while preserving actual missing laps. Use visible neutral plot styling for unknown team colours and draw isolated samples without joining across unobserved laps.


### Live timing presentation refinement — 31 October 2026

Use one page scroll for the complete live timing screen, replacing the native Table, capped race-control/error scrolls and horizontal tyre strip with expanded rows. Retain viewport sizing and the split-view first-snapshot regression. Provide driver and team filters with a clear action, preserving source ranks and clearing incompatible choices after team/session/roster changes. Show the latest four tyre stints, explicit laps-on-set labels, and a See more modal containing every stint plus available new/used and fitting-age details. Missing counts stay unknown; current stints have no fabricated final count. Keep the shared connection and archive independent of filtering. Inventory additional useful feed fields in docs/LIVE_DATA_OPTIONS.md; implementing those additions requires separate product work.

Live timing uses its tyre-history summary instead of a separate current tyre/age column; the current compound remains identified by the final stint.

### Current-weekend session badges and live tyre column — 31 October 2026

During the featured GP's dates in the selected timezone, show Finished, Next and In progress badges beside the menu panel's session times. Mark timetable estimates with an asterisk and a visible explanation. Use supplied valid start/end bounds for the scheduled interval. Without an end time, show Started until the next scheduled session begins or the session falls on an earlier local day; never assume a fixed duration. Only published GP or GP qualifying results establish confirmed completion of those sessions. The GP remains Results pending after its scheduled end. Unknown times, cancelled sessions and cancelled/removed weekends cannot gain a running/finished estimate. Countdown and badges use the same lifecycle-owned clock.

Provider fields rechecked against [OpenF1 sessions](https://openf1.org/docs/#sessions) and [Jolpica race fields](https://github.com/jolpica/jolpica-f1/blob/main/docs/endpoints/races.md): OpenF1 supplies start/end times; Jolpica supplies optional session starts. Timetable status remains separate from live connection status, championship data and winners.

Move Live timing's four-stint tyre-history preview into a column immediately to the right of Driver. Keep the full-history modal, wrapping, filters, expanded rows and single page scroll.

Follow-up: Widen the live tyre-history column to keep all four preview stints on one line, redistributing spacing from the numeric columns while preserving the existing window minimum. Keep the preview's count/See more controls below the sequence. In both timing sections and the full-history modal, write completed tyre durations as N Laps, using 1 Lap for a single lap.

### Expanded driver standings and season-win details — 31 October 2026

Replace Driver standings' native Table and horizontal win strips with fully expanded rows in one viewport-sized page scroll. Preserve published ranks, decimal points, full driver/team names and qualifying/GP totals. Show the latest three winning weekends, newest first, retaining one combined Quali & GP pill for a double win. Keep unknown-date wins in the full history without displacing known recent results. Show more opens a bounded native modal with one scroll for all events, dates in the chosen timezone, circuit/location/country, separate qualifying and GP results, and each result's team at that event. Include season totals, championship context, source/update times and partial-result notices. Missing dates/teams remain explicit; sprint results stay excluded. Do not introduce fixture data into release composition.

### Responsive inline histories — 31 October 2026

Replace the fixed preview limits with one-line previews that fit the available width. Reserve readable driver and numeric columns, then let tyre history and season wins take the extra window space. Tyre history always follows Driver and includes at least three latest stints when available, keeping the current stint last. Driver wins show at least three newest winning weekends, expand as more whole pills fit, and move the flag to the end of each pill. Narrow win pills may shorten event names while preserving result type, full hover/accessibility labels and modal details. Show overflow buttons only while items remain hidden; clicking either preview still opens its modal. Both shrinking and widening must recalculate the visible count, without nested scrolling or resetting modal/filter state. These rules supersede the earlier fixed three-/four-item limits.

- Live timing: responsive timing/Race Control columns, hide/show control, unread message badges, and prominent lap/status flags. Preserve one page scroll and stack panels in narrow windows.

- Merge Race timeline into Live timing, first in the sidebar. Include recorded-lap scrubbing, explicit Go Live/follow mode, collapsible position history, and access to historical GP/session selection within the same destination.

- Live Pts* column includes compact padded values and a Simulate sheet for full-field driver/team totals, with explicit baseline context and session double-count protection.

- Calendar Ongoing status mirrors the menu. Add centered racing numbers to driver name cells and gold clinched-title trophies to published and projected standings, using conservative remaining GP/Sprint point capacity.

- Calendar: flags after day numbers, persistent circuit subtitles, and published gold/silver/bronze GP podiums in rows and details, supported independently by both providers.

- Remove the legacy RaceTimelineView/RaceHistoryTimingTable path. Historical sessions feed the shared Live Timing presentation, with separate cache ownership and Live disabled for previous sessions. Restrict Simulate to the current ongoing GP, show current tyre lap counts and fade retired rows without desaturating team colors.
