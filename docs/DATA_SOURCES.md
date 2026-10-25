# Data sources and freshness

[Back to the README](../README.md)

The independent [OpenF1 API](https://openf1.org/docs/) is the primary source for sessions, classifications, and beta championship tables. OpenF1 can block **all unauthenticated requests during a live session**, including the calendar. The app then uses [Jolpica](https://github.com/jolpica/jolpica-f1) for a complete calendar, GP winners, and championship snapshot. The active source is shown in the panel, calendar, standings, and Settings.

Provider snapshots and caches remain separate; race IDs, results, and points are never merged across providers. OpenF1 joins use the season and session; missing driver metadata is resolved from earlier sessions in the same season. Jolpica joins use season and round with event metadata checks. Standings use an explicit round with a published GP result, including fallback to an earlier completed round when necessary. Missing driver numbers, non-numeric classifications, decimal points, and deductions are preserved. Jolpica does not supply session end times or cancellation flags; the app does not invent them.

The current weekend stays selected through its race. A published GP classification advances it. If no result appears within six hours of the scheduled start, focus advances while the previous GP remains **Results pending**. Scheduled start/end times alone never establish a winner or confirmed completion.

The featured weekend is labeled **Ongoing Grand Prix** in the menu bar panel when today falls between its first scheduled session date and race date, inclusive, in the selected display timezone. This includes gaps between sessions and does not claim live timing. Completed, cancelled, removed, and unknown-date weekends do not receive this label.

After the season ends, the app checks the following calendar. The completed season stays available when the next one is unpublished. Each championship table identifies its season and the race associated with its snapshot.

During a GP weekend's dates in the selected display timezone, each standings table shows **Waiting for this weekend’s results** until its championship snapshot includes that GP. A published winner alone does not remove this message: driver and constructor standings can arrive separately. The message is hidden outside the weekend's dates and for cancelled, removed, or unknown-date events.

Requests use an app User-Agent, a rate below 30 requests/minute per provider, bounded responses, and `Retry-After` handling. Jolpica requests use at most five pages of 100 rows per endpoint and reject incomplete pagination. Refreshes coalesce: normally six hours away from a weekend, 30 minutes near/during it, and five minutes while awaiting a race result. Countdown updates do not fetch data.

Versioned JSON snapshots are written atomically in the app’s sandboxed Application Support directory, under `F1MenuBar/openf1-v1` and `F1MenuBar/jolpica-v1`. The newest available provider cache can restore the app offline. Preferences use `UserDefaults`. Missing, corrupt, and unavailable data remain distinct. The smoke script uses `.build/live-smoke-cache`, separate from app data.


## Provider terms

Both providers are independent of Formula 1 and the FIA. OpenF1 championship endpoints are in beta. Jolpica data is provided under [CC BY-NC-SA 4.0](https://github.com/jolpica/jolpica-f1/blob/main/TERMS.md); commercial use requires a separate arrangement with that provider. These data terms are separate from this repository’s source-code license, which has not been selected.
