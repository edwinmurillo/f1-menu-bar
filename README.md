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
| **Next race weekend** | The full session schedule, including sprint qualifying and sprints when scheduled, plus an optional menu bar countdown. |
| **Season calendar** | Past, current, next, and future weekends, with published GP winners and clear states for pending results, cancellations, or schedule changes when reported. |
| **Championship standings** | Driver and constructor tables with provider-supplied positions and points, including ties, deductions, and decimal scores. |
| **Your local time** | Session times in the Mac’s system timezone, with an option to use UTC. |
| **Mac preferences** | System, light, or dark appearance; optional launch at login; and manual refresh. |
| **Saved data and a backup source** | Cached calendars remain available offline. Jolpica takes over when OpenF1 is unavailable, including during its live-session access restrictions. |

This app shows schedules and published results. A scheduled start time does not mean a session is confirmed live or finished, and a winner appears only after a GP result is published.

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
3. Choose **Standings** to open driver and constructor points.
4. Open **Settings** to change the timezone, appearance, countdown, or launch-at-login preference.

Closing the detail window keeps the menu bar app running. Use the panel’s power button to quit.

## Data sources

[OpenF1](https://openf1.org/docs/) is the primary source. [Jolpica](https://github.com/jolpica/jolpica-f1) supplies a complete backup snapshot when OpenF1 is unavailable. The active provider is shown in the app; records and caches from different providers are kept separate.

The current weekend stays in view through its race. Published results and standings can arrive at different times, so each points table identifies the GP associated with its snapshot. Cached data stays available when a refresh fails.

See [data sources and freshness](docs/DATA_SOURCES.md) for selection rules, refresh intervals, caching, provider limitations, and attribution.

## Development

The project uses **Swift 6**, **SwiftUI**, **MenuBarExtra**, and **XCTest**, with no third-party packages. `project.yml` is the XcodeGen source of truth; generated Xcode projects and build products are ignored.

```sh
Scripts/bootstrap.sh        # Generate the Xcode project
Scripts/build.sh Release    # Build the locally signed app
Scripts/run.sh Release      # Build and launch
Scripts/test.sh             # Deterministic core tests
Scripts/test.sh Release     # Optimized core tests
Scripts/check.sh            # Whitespace and project generation
Scripts/check-app.sh        # Release signature and static-link packaging
Scripts/live-smoke.sh       # Opt-in live API and disk-cache check
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
Features/     Next weekend, calendar, standings, settings, shared views
State/        Main-actor state and refresh ownership
Domain/       Models and time/status policies
Data/         OpenF1/Jolpica adapters, fallback, HTTP transport, disk cache
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
