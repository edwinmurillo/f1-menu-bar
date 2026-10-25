# F1 Menu Bar

A native macOS menu bar app for the next Formula 1 weekend, the season calendar, GP winners, and championship points. Swift 6 and SwiftUI; no account, API key, backend, or third-party package dependency.

**Status:** initial implementation. The working title is provisional. See [verification notes](docs/VERIFICATION.md) for build, test, integration, and native UI verification status.

## Features

- Next GP with practice, qualifying, race, and sprint sessions when published.
- Optional menu bar countdown; system timezone or UTC.
- Full calendar with current, next, future, raced, cancelled, changed-schedule, and results-pending states.
- Published GP winners and teams; sprint results never become GP winners.
- Every returned driver and constructor, preserving provider positions and decimal points.
- System/light/dark appearance, optional launch at login, manual refresh, and wake/year-boundary handling.
- Cached data and independent section updates; a failed standings request does not erase a working calendar.

The first version provides schedules and published results, not live timing. The optional wins column from the concept is omitted; points come directly from OpenF1 rather than locally reconstructed scoring.

## Requirements

- macOS 14 or later.
- Full Xcode with Swift 6. Verified with Xcode 27.1 RC (`27A9275`) and Swift 6.4.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.45 or later; verified with 2.45.3.

```sh
brew install xcodegen
cd ~/Developer/f1-menu-bar
Scripts/bootstrap.sh
Scripts/run.sh
```

Click the checkered flag in the menu bar. **Full calendar** and **Standings** open the regular window. Closing that window keeps the app running; use the panel’s power button to quit.

## Development commands

```sh
Scripts/build.sh Release    # Build the locally signed app
Scripts/run.sh Release      # Build and launch
Scripts/test.sh             # Deterministic core tests
Scripts/test.sh Release     # Optimized tests
Scripts/check.sh            # Whitespace and project generation
Scripts/check-app.sh        # Release signature and static-link packaging
Scripts/live-smoke.sh       # Opt-in live API and disk-cache check
```

Products: `.build/DerivedData/Build/Products/<configuration>/F1 Menu Bar.app`. Tests use separate `.build/TestProducts` output; test-only module visibility is enabled by the test command, not the shipping build. Logs are in `.build/`.

Scripts honor `DEVELOPER_DIR` and locate full Xcode if the system selects Command Line Tools. They do not change the global developer-directory setting. To choose an installation:

```sh
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
Scripts/build.sh
```

`project.yml` is the source of truth. Build/test scripts regenerate automatically. Generated projects are not committed. There are no additional formatter/linter dependencies.

## Data and behavior

The independent [OpenF1 API](https://openf1.org/docs/) supplies sessions, classifications, and both beta championship tables. Data joins are scoped to the season and session. A driver missing from the latest race roster is resolved from earlier sessions in that same season.

The current weekend stays selected through its race. A published GP classification advances it. If no result appears within six hours of the scheduled start, focus advances while the previous GP remains **Results pending**. Scheduled start/end times alone never establish a winner or confirmed completion.

After the season ends, the app checks the following calendar. The completed season stays available when the next one is unpublished. Each championship table identifies its season and the race associated with its snapshot.

Requests use an app User-Agent, a rate below 30 requests/minute, bounded responses, and `Retry-After` handling. Refreshes coalesce: normally six hours away from a weekend, 30 minutes near/during it, and five minutes while awaiting a race result. Countdown updates do not fetch data.

Versioned JSON snapshots are written atomically in the app’s sandboxed Application Support directory, under `F1MenuBar/openf1-v1`. Preferences use `UserDefaults`. Missing, corrupt, and unavailable data remain distinct. The smoke script uses `.build/live-smoke-cache`, separate from app data.

## Project structure

```text
App/          Composition, routing, preferences, login items, assets
Features/     Next weekend, calendar, standings, settings, shared views
State/        Main-actor state and refresh ownership
Domain/       Models and time/status policies
Data/         OpenF1 transport, mapping, disk cache
Tests/        Fixtures, failures, date boundaries, async interleavings
Scripts/      Generate, build, test, run, live verification
docs/         Verification evidence and remaining manual checks
project.yml   XcodeGen source of truth
PLAN.md       Product plan and data-source research
AGENTS.md     Contributor/agent guidance; also linked as Claude.md
```

## Distribution

Local builds use ad-hoc signing and the App Sandbox with outbound network access. The core module is linked statically into the app, avoiding an embedded framework that ad-hoc hardened-runtime builds cannot load. Every build checks the signature and packaging. This is not a notarized download or App Store release. Developer ID signing, notarization, packaging, and commercial provider terms require a separate distribution pass.

This independent app is not affiliated with Formula 1, the FIA, or any team. OpenF1 is also independent; availability and beta championship data can change.
