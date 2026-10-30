# F1 Menu Bar development guide

## Purpose and current stage

Build a native macOS menu bar utility for the next F1 weekend, season calendar and winners, and championship standings. Implementation was authorized on 25 October 2026. `PLAN.md` records the product requirements; `README.md` describes the delivered app and verified commands.

## Organization

- `App/`: composition root, menu bar scene, window routing, and app lifecycle.
- `Features/`: NextWeekend, Calendar, Standings, LiveTiming, RaceTimeline, and Settings SwiftUI views and presentation models.
- `State/`: main-actor season refresh and live connection ownership, shared with core tests.
- `Domain/`: normalized models, event selection, and time/status rules.
- `Data/`: OpenF1/Jolpica DTOs and mapping, HTTP transport, provider repositories, automatic fallback, and separate disk caches.
- `Tests/`: domain and repository tests plus small JSON fixtures.
- `Scripts/`: reproducible generation/build/test/run commands.
- `project.yml`: XcodeGen source of truth.

## Architecture and data rules

- Use SwiftUI with `MenuBarExtra` and a regular detail window. Use AppKit only where platform lifecycle or window behavior needs it.
- Construct services once at the app composition root; inject dependencies through initializers. Avoid global service locators and view-owned network requests.
- Keep presentation state on `@MainActor`. Give networking, decoding, and cache I/O explicit ownership outside UI work.
- Use one refresh coordinator to coalesce overlapping refreshes. Cancel obsolete tasks and reject results for superseded season/request identities.
- Keep domain models independent of SwiftUI, formatted labels, icons, and colors. Inject time and timezone for selection and formatting tests.
- Scope persistent data by provider, season, endpoint, and schema version. Serialize atomic cache writes and preserve the last good snapshot when refresh or decoding fails.
- Distinguish an empty valid response from transport, decoding, or cache errors. Load each screen section independently.
- Compare absolute timestamps; present them in the current system timezone by default. A missing time stays unknown.
- Keep GP and sprint results separate. Only a published GP result establishes its winner. Elapsed time alone does not establish a completed race or a live session.
- OpenF1 includes testing and cancelled sessions; exclude these from upcoming GP selection. Resolve championship snapshots using an explicit completed Race session. Scope driver-number joins to season/session and resolve roster changes within the season without dropping standings rows. Beta endpoint data and scheduled end times require explicit validation.
- Preserve provider championship positions and points, including ties, deductions, and decimal points. Do not recreate the scoring rules locally.
- Set an identifiable application/version `User-Agent`, honor `Retry-After`, bound retries and pagination, and cache responses.
- OpenF1 can return a global HTTP 401 during live sessions, even for historical/calendar requests. Use the Jolpica fallback without combining provider snapshots or IDs. Keep source attribution visible and use an explicitly completed round for Jolpica standings. Missing times and cancellation flags must not be invented.
- Live timing is a separate experimental personal connection. Keep its actor-owned SignalR transport and in-memory snapshot outside the season repository; never turn provisional timing into winners or points. Connect only while its view is visible, honor manual disconnect and sleep, and reject obsolete connection callbacks.
- Merge sparse timing updates, reset on a new subscription/session, bound frames/state, and coalesce publication. A Started status plus a recent timestamped TimingData delta establishes freshness; snapshots and pings do not. Use anonymous topics only, with no account tokens or backend redistribution. Race timeline may retain bounded, session-scoped lap snapshots in memory and on local disk, as requested by the user.
- Never embed secrets. The planned API calls require no credentials. Verify current provider documentation before changing API assumptions.

## Build and verification

Use `Scripts/bootstrap.sh` to generate the Xcode project, `Scripts/build.sh` to build, `Scripts/test.sh` for deterministic core tests, and `Scripts/run.sh` to build and launch. `Scripts/check.sh` checks whitespace and project generation. Set `DEVELOPER_DIR` to a full Xcode installation; scripts discover an installed Xcode when the system selection is Command Line Tools. `project.yml` is the source of truth; generated projects and build products are ignored. There are no third-party packages, formatter, or linter dependencies.

Keep F1Core a static framework and do not embed it in the app. A dynamic ad-hoc framework can pass signature verification yet fail hardened-runtime library validation at launch. `Scripts/check-app.sh` runs after every app build to catch dynamic-link or stale-embedding regressions; actual launch remains a separate check.

Keep the MenuBarExtra label a plain Label/Image/Text. Own refresh timers and system notifications in AppLifecycle, not inside the label. A TimelineView with lifecycle modifiers in that label triggered a continuous native status-button update loop during launch on macOS 27.

Constrain the live timing Table to the window viewport and scroll its surrounding content. A minimum-height-only Table inflated the NavigationSplitView's fitting height on the first snapshot, moving both columns out of view. `Tests/WindowRendering` exercises the real views in offscreen windows with fixture data; keep this target separate from F1CoreTests and release composition.

Observe window visibility from the stable ChampionshipWindow container, outside section-specific content. Defer and coalesce AppKit attachment/removal callbacks before changing observable SwiftUI state. Keep window size constraints independent of the selected section and explicitly own sidebar visibility. Use separate URLSessions for bounded HTTP negotiation and the long-lived WebSocket; a 30-second HTTP resource deadline must not be applied to the stream.

Use XCTest with a fixed clock, fixture transport, and temporary cache directories. Synchronize concurrent tests with continuations, gates, or expectations; never synchronize with `Task.sleep()` or `Task.yield()`. Test meaningful date boundaries, failure paths, and stale-response interleavings.

For UI delivery, build and launch on macOS, inspect the actual panel and windows, and capture visual evidence. Distinguish build success from visible behavior. Keep diagnostic fixtures and test controls out of release composition. Race timeline uses real historical API data or locally recorded live timing; no demo or simulated race data is included. It has one page scroll with fully expanded timing rows, a full-width lap slider, Previous/Next controls and GP/session pickers. Keep historical requests/caches separate from live connection ownership and championship snapshots.

## Working conventions

- Check Git status before editing; preserve unrelated changes and keep commits scoped.
- Update the plan and README when agreed scope or verified commands change.
- Prefer small, feature-oriented types and platform controls; avoid abstractions without a concrete need.
- Use semantic styling, accessible text labels, keyboard navigation, and both system appearances.
- Do not hardcode the current season, race count, team count, sprint venues, winners, or session order.
