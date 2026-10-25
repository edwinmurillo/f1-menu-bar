# Verification — 25 October 2026

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

## Native verification pending

The native computer-use tool reported that the Mac was locked and could not unlock it. App launch, menu bar visibility, panel/window rendering, keyboard/VoiceOver behavior, light/dark appearance, close/reopen behavior, actual login registration, wake behavior, and idle energy use have not been visually or physically verified. Compilation, unit tests, and the headless API check do not establish these behaviors.

Once the desktop is available, run `Scripts/run.sh Release`, inspect the menu panel and every sidebar section, confirm timezone/appearance changes, close and reopen the window, and quit from the panel. Capture native screenshots of the delivered build.

## Distribution

The project uses ad-hoc signing for local development. No Developer ID certificate, notarization, installer, App Store submission, or reboot/login verification has been performed.
