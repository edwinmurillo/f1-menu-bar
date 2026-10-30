![F1 Menu Bar — Race schedules and standings for macOS](docs/images/banner.png)

# F1 Menu Bar

**Your next Formula 1 weekend, right in the Mac menu bar.**

See practice, qualifying, sprint, and race times in your timezone. Browse the season calendar, check who won each Grand Prix, and follow driver and constructor points—all from the checkered flag in your menu bar.

![macOS 14 or later](https://img.shields.io/badge/macOS-14%2B-202328?style=flat-square)
![Swift 6](https://img.shields.io/badge/Swift-6-DE4033?style=flat-square)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-202328?style=flat-square)

Built natively with Swift and SwiftUI. No account, API key, or backend setup required.

[Get started](#get-started) · [Features](#features) · [Data sources](#data-sources) · [Development](#development)

## Features

| At a glance | What you get |
| --- | --- |
| **Next race weekend** | The full session schedule, including sprint qualifying and sprints when scheduled, plus an optional menu bar countdown. The panel shows **Ongoing Grand Prix** during the featured weekend’s dates. |
| **Season calendar** | Past, current, next, and future weekends, with published GP winners and clear states for pending results, cancellations, or schedule changes when reported. |
| **Championship standings** | Driver and constructor tables with provider-supplied positions and points, including ties, deductions, and decimal scores. During a GP weekend, each table shows “Waiting for this weekend’s results” until its points include that GP. |
| **Season wins** | Driver qualifying and GP win counts, with event names and country flags. A double win shares one **Quali & GP** badge. Constructors show GP win counts and flags for wins by either driver. |
| **Personal live timing** | An experimental session table with positions, gaps, lap times, tyre compounds and age, stint history, pit counts, race control, and weather. Connects directly to F1 while the view is visible. |
| **Race timeline** | Open a weekend from Calendar or choose one in the timeline, then choose a scheduled session. Real positions, lap times and available gaps, tyres, pits and race control come from OpenF1. Jolpica lap history is a Race-only fallback. A full-width lap slider and Previous/Next lap buttons control the graph. All timing rows expand in the page. |
| **Your local time** | Session times in the Mac’s system timezone, with an option to use UTC. |
| **Mac preferences** | System, light, or dark appearance; optional launch at login; and manual refresh. |
| **Saved data and a backup source** | Cached calendars remain available offline. Jolpica takes over when OpenF1 is unavailable, including during its live-session access restrictions. |

Schedules and published results stay separate from provisional timing. A scheduled start time does not mean a session is confirmed live or finished, and a winner appears only after a GP result is published. Live timing displays the session actually supplied by the feed, which can be a previous, finished session.

## Get started

**Current stage:** early release, built from source. There is no notarized download or App Store release yet. Build and data checks are recorded in the [verification notes](docs/VERIFICATION.md), alongside the remaining manual UI checks.

You’ll need:

- **macOS 14 or later.**
- **Full Xcode with Swift 6**, rather than Command Line Tools alone.
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.45 or later.**

```sh
brew install xcodegen
mkdir -p ~/Developer
git clone https://github.com/murilloarturo/f1-menu-bar.git ~/Developer/f1-menu-bar
cd ~/Developer/f1-menu-bar
Scripts/run.sh Release
```

The run script generates the Xcode project, builds the app, and launches it. Look for the **checkered flag in the menu bar**.

To keep it in Applications, quit the app and copy this bundle into your Applications folder, then open that copy:

```text
.build/DerivedData/Build/Products/Release/F1 Menu Bar.app
```

### Using the app

1. Click the checkered flag to see the next GP weekend and its session times.
2. Choose **Full calendar** to browse weekends and published winners.
3. Choose **Standings** to open driver and constructor points and season wins. Scroll the driver win badges horizontally to see every event; hover a constructor flag for the GP name.
4. Choose **Live timing** to connect to the current feed. Select a driver for sectors, best lap, and tyre history. Use **Disconnect** to pause; **Connect** resumes. The same personal connection stays active while either Live timing or Race timeline is visible. Closing or hiding the window, leaving both sections, or sleeping the Mac stops it. Race timeline stores observed lap snapshots locally for the active session and uses the historical API independently for other sessions.

When the live stream supplies its extrapolated session clock, both timing sections show the remaining time. The clock pauses when the feed stops extrapolating; in free practice it turns red below five minutes. Both timing tables mark a driver as **PIT** when the feed reports `InPit`, or **OUT** when it reports `PitOut`; historical laps without either state show an unknown value.

Both timing tables also show tyre history beside the current tyre and age: completed stints include laps driven on that set, such as `(S) 10 – (H) 20 – (M)` for a current medium stint. Used-tyre age before fitting is excluded when the feed supplies it. Missing stint duration remains unknown.
5. From Calendar, select a weekend and choose **View race timeline** after its first session starts, or open **Race timeline** and choose a Grand Prix and session in the two pickers. The current scheduled weekend is selected by default, with its latest started session. Upcoming sessions remain listed but show an empty state until they start. Use **Previous lap**, **Next lap**, or the full-width progress slider to inspect available laps. Switch between Positions and Gaps, highlight a driver, and sort the timing rows by their column headings. The page has one vertical scroll; every driver row and the selected lap's race-control messages are shown without an inner timing-table scroll.
6. Open **Settings** to change the timezone, appearance, countdown, or launch-at-login preference.

The timeline downloads actual race history and caches it separately from season standings and the personal live connection. OpenF1 supplies lap timing, sampled positions/gaps, tyre stints, pit stops and race-control messages when available. Jolpica supplies real lap times and positions if OpenF1 is unavailable; gaps, tyres and race-control fields remain unknown with that fallback. Completed GPs reopen from their saved history without an automatic hourly download; **Refresh** explicitly checks for updates. The four most recently viewed races also stay in memory for quick switching. First-time OpenF1 loads show lap positions and times before slower gaps, tyres and race-control details finish. Incomplete saved position histories are repaired automatically. No demo data, simulated laps, gaps, retirements or race events are included. Upcoming GPs, unpublished history, unavailable fields and connection failures have explicit empty or error states. Historical lap counts show available data, not an invented planned race length.

During an active session, the timeline uses the same F1 SignalR stream as Live timing and saves observed lap snapshots in Application Support on this Mac. The recording resumes after an app relaunch when its session still matches the selected calendar session. Laps that occurred before the app connected are not invented. Live recording is separate from OpenF1's historical API and its cache.

For live practice and qualifying, each chart step is a newly observed best-lap improvement, with a timestamp on the horizontal axis. Driver positions and gaps are calculated from each driver's best time so far, including drivers currently off track. The table shows their last and best times. Races and sprints remain lap based.

Closing the detail window keeps the menu bar app running. The detail window keeps the same minimum size across sections and restores the sidebar when navigating. Live timing keeps its table within the window; scroll to read additional driver and race-control details. Use the panel’s power button to quit. The installed version is shown in Settings.

While Live timing connects or waits for its first data, a centered status and subtle shimmer show where timing will appear. Reduce Motion and inactive windows use static placeholders. Existing timing stays visible during reconnects, and errors have a separate static state.

**Quali** means P1 in the published Grand Prix qualifying classification, excluding sprint qualifying. It is independent of the starting grid after penalties. GP wins belong to the constructor the winning driver represented at that event. Qualifying and GP results can update before the championship points; missing results stay pending and saved wins remain available after a refresh failure. The season control and refresh button are separate in the window toolbar.

## Data sources

[OpenF1](https://openf1.org/docs/) is the primary source. [Jolpica](https://github.com/jolpica/jolpica-f1) supplies a complete backup snapshot when OpenF1 is unavailable. The active provider is shown in the app; records and caches from different providers are kept separate.

The current weekend stays in view through its race. Published results and standings can arrive at different times, so each points table identifies the GP associated with its snapshot. Cached data stays available when a refresh fails.

The optional live view uses F1’s anonymous SignalR/WebSocket feed with no account token. It is an experimental personal-use integration with an unsupported endpoint: availability and fields can change. It keeps timing in memory and labels disconnected, stale, and finished data. Exact stationary pit-stop durations, future team strategy, and paid telemetry are outside this feature.

See [data sources and freshness](docs/DATA_SOURCES.md) for selection rules, refresh intervals, caching, provider limitations, and attribution.

## Development

The project uses **Swift 6**, **SwiftUI**, **MenuBarExtra**, and **XCTest**, with no third-party packages. `project.yml` is the XcodeGen source of truth; generated Xcode projects and build products are ignored.

```sh
Scripts/bootstrap.sh        # Generate the Xcode project
Scripts/build.sh Release    # Build the locally signed app
Scripts/run.sh Release      # Build and launch
Scripts/test.sh             # Core and offscreen window-layout tests
Scripts/test.sh Release     # Optimized core and window-layout tests
Scripts/check.sh            # Whitespace and project generation
Scripts/check-app.sh        # Release signature and static-link packaging
Scripts/live-smoke.sh       # Opt-in live API and disk-cache check
Scripts/live-timing-smoke.sh # Opt-in 75-second connection stability check
Scripts/race-history-smoke.sh YEAR MEETING_ID RACE_SESSION_ID START_ISO8601 # Real history and fallback/cache check
```

Scripts honor `DEVELOPER_DIR` and find full Xcode when the system selects Command Line Tools. They do not change the global developer-directory setting. To choose an installation:

```sh
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
Scripts/build.sh
```

Builds are written to `.build/DerivedData/Build/Products/<configuration>/F1 Menu Bar.app`. Tests use separate `.build/TestProducts` output; test-only module visibility is enabled by the test command. Logs are in `.build/`. There are no additional formatter or linter dependencies.

<details>
<summary>Project structure and local packaging</summary>

```text
App/          Composition, routing, preferences, login items, assets
Features/     Next weekend, calendar, standings, live timing, race timeline, settings
State/        Main-actor season refresh and live connection ownership
Domain/       Models and time/status policies
Data/         Season adapters, fallback/cache, bounded SignalR client
Tests/        Fixtures, failures, date boundaries, async interleavings
Scripts/      Generate, build, test, run, live verification
docs/         Data notes, verification evidence, banner, and artwork prompt
project.yml   XcodeGen source of truth
PLAN.md       Product plan and data-source research
AGENTS.md     Development guide; also linked as Claude.md
```

Local builds use ad-hoc signing and the App Sandbox with outbound network access. F1Core is linked statically to avoid an embedded framework that ad-hoc hardened-runtime builds cannot load. Every build checks the signature and packaging. Developer ID signing, notarization, and release packaging remain separate distribution work.

</details>

## Contributing

Bug reports and focused improvements are welcome. For a data issue, include the season, affected GP or standings table, and the provider shown in the app. Read [AGENTS.md](AGENTS.md) before changing code; the [product plan](PLAN.md) and [verification notes](docs/VERIFICATION.md) document scope and current limitations.

The banner’s reusable image-generation prompt is in [docs/BANNER_PROMPT.md](docs/BANNER_PROMPT.md).

## License and attribution

A source-code license has not been selected yet; this repository currently has no `LICENSE` file. Data-provider terms are documented separately in the [data notes](docs/DATA_SOURCES.md#provider-terms).

F1 Menu Bar is an independent project, not affiliated with Formula 1, the FIA, or any team.
