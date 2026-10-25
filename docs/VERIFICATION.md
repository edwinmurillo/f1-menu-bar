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

## Native verification pending

Visual inspection after the latest startup fix is left to the user. Menu bar visibility, panel/window rendering, keyboard/VoiceOver behavior, light/dark appearance, close/reopen behavior, actual login registration, wake behavior, and idle energy use remain unverified. A successful launch command, compilation, unit tests, and the headless API check do not establish those behaviors.

Manual checks: open the installed app, inspect the menu panel and every sidebar section, confirm timezone/appearance changes, close and reopen the window, and quit from the panel.

## Distribution

The project uses ad-hoc signing for local development. No Developer ID certificate, notarization, installer, App Store submission, or reboot/login verification has been performed.
