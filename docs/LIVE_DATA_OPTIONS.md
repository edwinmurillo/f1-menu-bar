# Useful data not yet displayed

Checked 31 October 2026 against the current app and a fresh anonymous F1 subscription snapshot for Mexico City / Practice 2 (`Ends`). Presence in an ended session establishes that a field is supplied, not its freshness during active racing. The inspection requested only the app's existing topics. No connection identifiers or cookies were saved. The feed is unsupported and availability can change.

## Confirmed in topics the app already receives

These need decoding/presentation work, not an additional subscription. Existing sectors, best lap, interval, pit/out status, tyre age, new/used sets and fitting age already have UI and are not counted as new data.

| Addition | Fields observed | Benefit |
| --- | --- | --- |
| Practice/qualifying gap to fastest and car above | `TimingData.Lines.*.TimeDiffToFastest`, `TimeDiffToPositionAhead` | Populate useful practice gaps; the current model reads race-style gap fields instead. |
| Lap when a driver's best was set | `BestLapTime.Lap` | Distinguish an old benchmark from a recent improvement. |
| Personal/session-fastest lap badges | `LastLapTime.PersonalFastest`, `OverallFastest` | Identify improvements without comparing rounded strings. |
| Personal/session-fastest sector badges | `Sectors.*.PersonalFastest`, `OverallFastest` | Show which sector produced an improvement. |
| Previous sector comparison | `Sectors.*.PreviousValue` | Compare successive sector readings; do not assume it is a complete previous lap. |
| Mini-sector progress | `Sectors.*.Segments.*.Status` | Follow progress between sector lines; validate status meanings before choosing colours. |
| Speed traps and intermediate speeds | `Speeds.I1`, `I2`, `FL`, `ST`, including fastest flags | Compare speed at timing points and highlight a personal/session benchmark. Empty readings remain unknown. |
| Stopped-car indication | Driver-level `Stopped`, sector-level `Stopped` | Distinguish a stopped car from a normal in-pit state after validating update semantics. |
| Structured race-control badges | `Category`, `Flag`, `Mode`, `Status`, `Scope`, `Sector`, `RacingNumber` | Group yellow/red/SC/VSC notices and associate them with a driver or sector instead of showing only text. |
| Rain indicator | `WeatherData.Rainfall` | Make a dry-to-wet change visible. |
| Wind | `WindSpeed`, `WindDirection` | Explain changing conditions and balance. |
| Humidity and pressure | `Humidity`, `Pressure` | Add weather context beyond the two temperatures already shown. |
| Extra stint context | `TimingAppData` stint `LapNumber`, `LapTime`, `TyresNotChanged`, `LapFlags` | Explain same-set reuse and the lap associated with a stint update. These are not automatically fitting lap numbers; validate flags and semantics before display. |
| Driver portraits and race numbers | `DriverList.HeadshotUrl`, `RacingNumber` | Improve identification; the race number already serves as model identity but is not shown beside every name. |
| Feed-withheld status | `TimingData.Withheld`, plus line `ShowPosition` | Explain unavailable/suppressed information rather than treating it as a blank measurement. |

Session metadata also supplies start/end, number, type, circuit/meeting information and archive status. The app already displays session identity/schedule; more of that metadata can support diagnostics rather than another dashboard card. Internal IDs, line ordering, raw status codes and transport metadata are not useful stand-alone user features.

The [FastF1 parser](https://github.com/theOehrly/Fast-F1/blob/master/fastf1/_api.py) independently documents timing-point speeds and weather units. Neither that project nor this snapshot establishes a supported public F1 API contract.

## Documented additions requiring more data work

These were checked in provider/project documentation, not confirmed as accessible new live topics in this run.

| Addition | Candidate source | Practical limit |
| --- | --- | --- |
| Qualifying-part progression and Q1/Q2/Q3 result comparison | Live `SessionData` / qualifying timing fields; [Jolpica qualifying](https://github.com/jolpica/jolpica-f1/blob/main/docs/endpoints/qualifying.md) for published results | Validate transitions and gaps to the elimination boundary in an active qualifying session. Published results are a separate snapshot. |
| Speed, RPM, gear, throttle, brake and DRS traces | F1 `CarData.z`; OpenF1 `car_data` | Compressed high-frequency payloads need separate bounded decoding/storage. No fuel, tyre wear or engine-temperature values are promised. |
| Circuit map with car positions | F1 `Position.z`; OpenF1 `location` | Approximate coordinates need a circuit transform; they do not establish a precise racing line. |
| Pit-lane duration and stationary stop time | F1 pit topics; OpenF1 `pit` | Historical OpenF1 documents separate `lane_duration` and `stop_duration`; do not derive a stationary time from the InPit flag. |
| Position-change feed | OpenF1 `overtakes`; candidate F1 `OvertakeSeries` | Provider events can include pit-stop/penalty changes and incomplete coverage, so they must not all be called on-track passes. |
| Team radio clips | F1 `TeamRadio`; OpenF1 `team_radio` | Selected clips only. OpenF1 documents substantially reduced availability in 2026. |
| Starting grid and positions gained | OpenF1 `starting_grid`; Jolpica results | Compare published grid and classifications; provisional timing is not a final result. |
| Full classification, finish status, race time, fastest-lap rank | [Jolpica results](https://github.com/jolpica/jolpica-f1/blob/main/docs/endpoints/results.md) | Extend race details beyond the winner; keep post-race results separate from live data. |
| Weather history | Existing WeatherData samples; `WeatherDataSeries` candidate | Needs bounded history capture and a chart rather than only the latest value. |
| Personal/session best-sector and speed leaderboards | `TimingStats` candidate or observed validated timing updates | Confirm coverage before claiming a complete session leaderboard. |
| Provisional championship projection | F1 `ChampionshipPrediction` candidate | Would require an explicitly provisional section, separate from official standings and caches. Access and fields were not tested here. |

[OpenF1 documentation](https://openf1.org/docs/) confirms its historical endpoints, paid real-time requirement, and data limitations. Pit stationary duration coverage starts at the 2024 US GP. The [LiveF1 topic catalogue](https://livef1.goktugocal.com/livetimingf1/data_topics.html) and FastF1 source identify candidate F1 topics; listing a topic does not confirm anonymous access or stable fields.

## Derived views we can build from observations

Lap-time trends, stint pace/consistency, driver-to-driver comparisons, gap trends, position-change summaries and weather trends can be calculated from bounded observations. Label them as calculated, exclude known out/pit/invalid laps where available, and retain missing intervals. A tyre-degradation or pit-window model would be an estimate, not provided team strategy.

The best first additions are practice gaps, fastest-sector colours, speed-trap readings, rain/wind and structured race-control tags: useful during a session, already present in the subscribed payload, and relatively small additions.
