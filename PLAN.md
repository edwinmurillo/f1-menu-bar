# F1 Menu Bar — proposed project plan

Prepared on 25 October 2026. Working folder: `/Users/arturo/Developer/f1-menu-bar`. The name is provisional. This document records a plan; application implementation has not started.

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
| Drivers | Table with championship position, driver, constructor(s), points, and wins. |
| Constructors | Table with championship position, constructor, points, and wins. |
| Settings | Launch at login, optional menu bar countdown, system-timezone or UTC display, and data-source information. |

The panel footer offers **Full calendar**, **Standings**, **Refresh**, **Settings**, and **Quit**. Calendar and standings use one reusable regular window with Calendar, Drivers, and Constructors navigation, keeping the small panel quick to scan. Closing that window leaves the menu bar app running.

Aim for a roughly 360–400 point panel with native spacing and typography, a restrained racing accent, clear date grouping, system light/dark appearance, keyboard navigation, and VoiceOver labels. Status must remain understandable without color. The UI shows its timezone and last successful update.

### Weekend schedules

- Standard format: Practice 1, Practice 2, Practice 3, Qualifying, Grand Prix.
- Sprint format: Practice 1, Sprint Qualifying, Sprint, Qualifying, Grand Prix, using the actual chronological order returned by the provider.
- Read session presence and timestamps from the API. Never assume a particular venue is always a sprint weekend, that every race is on Sunday, or that every session has an announced time.
- Retain sessions already started within the displayed weekend so the whole schedule stays understandable. Label them by scheduled time; do not imply a confirmed finish from a start timestamp alone.

## 3. API decision and evidence

**Recommend Jolpica F1 as the sole initial provider.** Its established Ergast-compatible endpoints cover the requested data, including explicit sprint qualifying times. The provider documents its [race fields](https://github.com/jolpica/jolpica-f1/blob/main/docs/endpoints/races.md) and [sprint naming differences](https://github.com/jolpica/jolpica-f1/blob/main/docs/ergast_differences.md).

Base URL: `https://api.jolpi.ca/ergast/f1/`. Use an explicit season year consistently across requests.

| Need | Request path |
| --- | --- |
| Full calendar and session start times | `{year}.json?limit=100` |
| GP winners for the season | `{year}/results/1.json?limit=100` |
| Driver championship | `{year}/driverstandings.json?limit=100` |
| Constructor championship | `{year}/constructorstandings.json?limit=100` |

Read `total`, `limit`, and `offset` and fetch additional pages when needed. The winners query filters finishing position 1; it is not a request for round 1. Join winners to calendar events by season and round, with circuit identity checked during reconciliation.

**Verified during planning:** all four requests above succeeded for 2026 without authentication. The responses contained 23 scheduled races, six sprint weekends with six `SprintQualifying` entries, 17 GP winner records, 23 driver standings rows, and 11 constructor rows. Both standings responses identified round 17. These are observations of the provider response on the research date, not constants or independent confirmation of official race facts.

The initial Python HTTP probe encountered a local certificate-store error. Repeating the requests with macOS `curl` succeeded with certificate verification enabled. This establishes API reachability; the eventual Swift client still needs its own integration check.

The provider currently documents unauthenticated limits of 4 requests/second and 500/hour, and requires an app/version `User-Agent`. Use a lower internal budget, request coalescing, caching, and backoff. Limits can change. Sources: [request conventions](https://github.com/jolpica/jolpica-f1/blob/main/docs/README.md), [rate limits](https://github.com/jolpica/jolpica-f1/blob/main/docs/rate_limits.md).

Jolpica's [terms](https://github.com/jolpica/jolpica-f1/blob/main/TERMS.md) allow free non-commercial use under CC BY-NC-SA 4.0 and direct commercial users to contact the provider. Include source attribution in the app; resolve a commercial arrangement if commercial distribution becomes part of the product.

**Alternative considered: OpenF1.** It exposes session information and results, plus championship endpoints currently marked beta. Its documentation distinguishes free historical access from paid live access. It is a possible later addition for richer timing features; the initial schedule-and-standings scope does not need it. Sources: [OpenF1 documentation](https://openf1.org/docs/), [access options](https://openf1.org/).

## 4. Selecting the next GP and representing status

Use a testable policy based on an injected clock, absolute session timestamps, and published GP results. Selecting the featured weekend and determining whether a race has finished are separate decisions.

1. Load the current year's schedule and results. Re-evaluate on app launch, panel opening, wake, relevant time boundaries, and system date/timezone changes.
2. Before a weekend starts, feature the earliest upcoming GP and highlight its first future session.
3. During its weekend, keep that GP featured even after practice or qualifying has started. Highlight the next session still in the future.
4. At the GP's scheduled start, keep the weekend featured and show “Race scheduled to have started · results pending.” Do not advance immediately or present an unverified live badge.
5. A published GP classification establishes **Raced** and its winner; then feature the next GP. Results remain refreshable because classifications can be revised.
6. To prevent an unavailable result from blocking the app indefinitely, use a proposed six-hour focus window after the scheduled GP start. If results are still absent after that window, feature the next scheduled GP and retain the previous one as **Results pending**. This is a navigation fallback, not a claim that the race has finished. Keep the policy configurable and visible to tests.
7. Once the season is over, check the following year's schedule. If it is not published, show “Season complete · next calendar not available” and retain the last season's calendar and standings with their year clearly labeled.

Calendar labels are **Raced**, **Current weekend**, **Next**, **Future**, and **Results pending**. Support **Time TBC** for missing times. The current provider's schedule must not be assumed to expose authoritative cancellation or live-status fields. On an explicit provider schedule change, reconcile dates and remove the event from upcoming selection as appropriate; never classify a missing row or a network error as a confirmed cancellation. Retain a cached removed event as “Schedule changed / unavailable” until reconciled.

Store UTC instants, format with the selected timezone, and compare full timestamps rather than day numbers. Use `Europe/Madrid` as one test timezone, not a hardcoded app default. A date without a time remains a date-only value and cannot drive a precise countdown.

## 5. Standings behavior

Preserve the championship order and points supplied by the API, including ties and decimal points. Do not sum race or sprint scores locally. Display the season, provider round, and retrieval time so delayed standings remain understandable. Results and standings may update at different times; each section keeps its own freshness state. A round number alone does not prove that a recently run sprint is reflected in the table.

The season tables show every returned driver/team and scroll as needed. Driver rows can retain multiple constructor associations if a driver changes teams. No driver count, team count, team color, or championship leader is hardcoded.

## 6. Technical approach

- **Platform:** native Swift 6 and SwiftUI; proposed minimum macOS 14. Use `MenuBarExtra` with window style, a regular detail window, and `LSUIElement` for the menu bar app lifecycle. Apple's [MenuBarExtra documentation](https://developer.apple.com/documentation/swiftui/menubarextra) covers this presentation model. Verify focus, reopening, and settings behavior on the actual Mac.
- **Project:** XcodeGen configuration as the source of truth, an app target and XCTest target, and repository-owned scripts. Use Swift Package Manager only when a dependency is justified; no third-party client is required initially.
- **Layers:** app composition root → feature presentation models → schedule/standings repository → Jolpica client and disk cache. Inject transport, clock, and cache so date rules and error behavior can be tested without the network.
- **Models:** race weekend, session, GP winner, driver standing, constructor standing, and data freshness. Normalize transport DTOs at the data boundary and keep UI formatting out of domain models.
- **Concurrency:** main-actor presentation state; one refresh coordinator; bounded HTTP work; explicit off-main cache/decoding ownership. Reject late responses from obsolete season selections or refresh generations.
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
| 2. Data foundation | Jolpica transport/DTO mapping, cache, refresh coordinator, date selection, and fixtures. | Standard and sprint fixtures decode; unknown times, pagination, offline cache, and date boundaries behave correctly. |
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
- Correct join of GP winner to its event; provider ranking/points preserved in both standings tables.
- Visible panel/window checks in light/dark appearance, keyboard and VoiceOver checks, and low idle CPU/network activity measured on the Mac.

Use deterministic XCTest fixtures and controllable clocks, not sleep-based asynchronous tests. Keep remote smoke tests separate from the repeatable test suite.

## 10. Later additions

Optional follow-ups include session reminders, calendar export, favorite driver/team emphasis, a spoiler-hiding setting, previous-season browsing, full race classifications, and richer live timing through a separately evaluated provider.

The first implementation step, once requested, is Stage 1 plus a small fixture-backed next-GP panel to validate the native interaction before expanding the screens.
