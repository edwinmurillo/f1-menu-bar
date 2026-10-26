# Data sources and freshness

[Back to the README](../README.md)

The independent [OpenF1 API](https://openf1.org/docs/) is the primary source for sessions, classifications, and beta championship tables. OpenF1 can block **all unauthenticated requests during a live session**, including the calendar. The app then uses [Jolpica](https://github.com/jolpica/jolpica-f1) for a complete calendar, GP winners, and championship snapshot. The active source is shown in the panel, calendar, standings, and Settings.

Provider snapshots and caches remain separate; race IDs, results, and points are never merged across providers. OpenF1 joins use the season and session; missing driver metadata is resolved from earlier sessions in the same season. Jolpica joins use season and round with event metadata checks. Standings use an explicit round with a published GP result, including fallback to an earlier completed round when necessary. Missing driver numbers, non-numeric classifications, decimal points, and deductions are preserved. Jolpica does not supply session end times or cancellation flags; the app does not invent them.

The current weekend stays selected through its race. A published GP classification advances it. If no result appears within six hours of the scheduled start, focus advances while the previous GP remains **Results pending**. Scheduled start/end times alone never establish a winner or confirmed completion.

The featured weekend is labeled **Ongoing Grand Prix** in the menu bar panel when today falls between its first scheduled session date and race date, inclusive, in the selected display timezone. This includes gaps between sessions and does not claim live timing. Completed, cancelled, removed, and unknown-date weekends do not receive this label.

After the season ends, the app checks the following calendar. The completed season stays available when the next one is unpublished. Each championship table identifies its season and the race associated with its snapshot.

During a GP weekend's dates in the selected display timezone, each standings table shows **Waiting for this weekend’s results** until its championship snapshot includes that GP. A published winner alone does not remove this message: driver and constructor standings can arrive separately. The message is hidden outside the weekend's dates and for cancelled, removed, or unknown-date events.

Season requests use an app User-Agent, a rate below 30 requests/minute per provider, bounded responses, and `Retry-After` handling. Jolpica requests use at most five pages of 100 rows per endpoint and reject incomplete pagination. Refreshes coalesce: normally six hours away from a weekend, 30 minutes near/during it, and five minutes while awaiting a race result. Countdown updates do not fetch data.

Versioned JSON snapshots are written atomically in the app’s sandboxed Application Support directory, under `F1MenuBar/openf1-v1` and `F1MenuBar/jolpica-v1`. The newest available provider cache can restore the app offline. Preferences use `UserDefaults`. Missing, corrupt, and unavailable data remain distinct. The smoke script uses `.build/live-smoke-cache`, separate from app data.

## Season wins

Driver statistics count published P1 classifications in Grand Prix qualifying and the Grand Prix itself. Sprint qualifying, sprint results, and grid positions after penalties do not contribute. One event can show **Quali**, **GP**, or **Quali & GP**, with its country flag. Constructors show only flags for GP wins by either driver, attributed to the team recorded for that race. Repeated flags can represent different events in the same country; hover text identifies the GP.

OpenF1 uses the existing season-wide [session result query](https://openf1.org/docs/#session-result), then matches each result to an exact `Race` or `Qualifying` session and its session-specific driver/team metadata. Jolpica adds its [qualifying results endpoint](https://github.com/jolpica/jolpica-f1/blob/main/docs/endpoints/qualifying.md), `{year}/qualifying/1.json`. That response can contain non-P1 final classifications: pagination counts individual `QualifyingResults` rows before filtering final `position == 1`. Jolpica driver and constructor IDs associate results with standings, including when a champion races under number 1 or a driver changes teams.

Qualifying can update before Sunday's GP and before championship points. Empty valid result responses differ from failures: unavailable statistics display a dash, while known zero wins display zero. Last good winners survive failed requests, with a visible warning. The added optional cache fields preserve existing saved calendars and points; an older cache shows qualifying as pending until refreshed. Country flags use the provider's country name, with aliases for UK/USA/UAE and a neutral globe when unknown.


## Experimental personal live timing

The Live timing view connects directly to `https://livetiming.formula1.com/signalrcore/negotiate` and the matching WSS endpoint. This is an unsupported F1 service used anonymously, not a supported public developer API. The integration uses [SignalR Core’s JSON protocol](https://github.com/dotnet/aspnetcore/blob/main/src/SignalR/docs/specs/HubProtocol.md); F1-specific negotiation, topic names, and sparse updates were researched in the [F1 Telemetry Dashboard client](https://github.com/mricero/F1-Telemetry-Dashboard/blob/main/src/f1dash/data/signalr_core.py). No third-party client library is bundled.

The subscribed topics are `SessionInfo`, `SessionStatus`, `TrackStatus`, `DriverList`, `TimingData`, `TimingAppData`, `LapCount`, `RaceControlMessages`, and `WeatherData`. Fields can be missing. The view follows the session actually published by the feed, including practice, qualifying, sprints, or a previously finished race; it does not associate old timing with the calendar’s next GP.

Positions, gaps, laps, best/last/sector times, compounds, tyre age, observed stint history, and pit counts remain provisional. Tyre `TotalLaps` includes previous use of the tyre set; `StartLaps` is retained separately. Future team strategy and exact stationary pit-stop durations are not inferred. Timing does not alter published winners or championship points.

Each subscription replaces the prior raw state, then merges sparse updates. A changed session identity clears old drivers and messages. Only a Started session with a TimingData delta timestamp no more than 30 seconds old (allowing five seconds of clock skew) receives **Live** status. Initial snapshots and connection pings never establish liveness. Finished, disconnected, and stale timing remain labeled; a wrong Mac clock can prevent the Live label.

The connection exists while the section and window are visible. Closing, minimizing/covering the window, switching sections, sleeping, or Disconnect cancels it. Automatic visibility/wake reconnection respects a manual pause. The transport owns ephemeral load-balancer cookies and connection IDs, uses an identifiable app User-Agent, rejects redirects, and sends no account credentials. It never requests paid car/position telemetry, radio, or a token bypass.

Transient failures receive at most three retries at 2, 5, and 15 seconds; a connection stable for a minute resets that budget. Access/rate refusals stop automatic retries and enforce at least a two-minute cooldown plus any longer Retry-After. Negotiation reads, WebSocket frames, JSON depth, stored timing, and early updates are bounded. Recent race control is capped at 40 messages; UI updates are coalesced to roughly one per second. Timing is kept in memory only: no disk recording or proxy server.

HTTP negotiation uses a separate URLSession with a 30-second resource deadline. The WebSocket retains Foundation’s long resource lifetime; the protocol watchdog covers its initial handshake/subscription and requires messages within 45 seconds. Cancelling a run invalidates both sessions. Window visibility is observed outside the live section and delivered asynchronously, coalescing temporary detach/attach notifications without mutating SwiftUI state during native view updates.

`Scripts/live-timing-smoke.sh Release` uses the production Swift client for a connection of up to 75 seconds. It prints session identity, field counts, interruptions, uninterrupted connection duration, and whether fresh timing was observed. Success requires at least 60 seconds connected with no interruption. It prints no cookies or connection IDs. Snapshot access alone does not verify active-session delivery or the app’s native UI.

## Provider terms

Both providers are independent of Formula 1 and the FIA. OpenF1 championship endpoints are in beta. Jolpica data is provided under [CC BY-NC-SA 4.0](https://github.com/jolpica/jolpica-f1/blob/main/TERMS.md); commercial use requires a separate arrangement with that provider. These data terms are separate from this repository’s source-code license, which has not been selected.

The personal timing experiment does not establish permission for redistribution or commercial use. F1’s [guidelines](https://www.formula1.com/en/information/guidelines.4EOKE9RRqevL4niTK9kWyt) and [legal notices](https://www.formula1.com/en/information/legal-notices.7egvZU48hzrypubGBNcQKt) apply independently of whether an endpoint accepts an anonymous connection. Access can change or be withdrawn.
