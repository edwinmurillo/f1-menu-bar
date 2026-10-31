import XCTest
@testable import F1Core

final class LiveTimingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func json(_ text: String) throws -> LiveJSON { try .decode(Data(text.utf8)) }
    private var initial: String {
        #"{"SessionInfo":{"Key":123,"Name":"Race","Meeting":{"Name":"Fixture GP"}},"SessionStatus":{"Status":"Started"},"DriverList":{"4":{"FullName":"Fixture Driver","Tla":"FIX","TeamName":"Fixture Team","TeamColour":"FF8800"}},"TimingData":{"Lines":{"4":{"Position":"2","GapToLeader":"+4.1","IntervalToPositionAhead":{"Value":"+1.2"},"NumberOfLaps":12,"NumberOfPitStops":1,"InPit":false,"LastLapTime":{"Value":"1:30.123"},"Sectors":[{"Value":"28.1"},{"Value":"31.2"},{"Value":"30.8"}]}}},"TimingAppData":{"Lines":{"4":{"Stints":[{"Compound":"SOFT","TotalLaps":12,"StartLaps":5,"New":"false"}]}}},"LapCount":{"CurrentLap":13,"TotalLaps":56}}"#
    }

    func testSnapshotDoesNotClaimLiveAndTyreAgeIncludesPreviousUse() throws {
        var reducer = LiveTimingReducer()
        try reducer.seed(json(initial), receivedAt: now)
        let value = reducer.snapshot(), driver = try XCTUnwrap(value.drivers.first)
        XCTAssertEqual(value.sessionID, "123")
        XCTAssertEqual(value.meetingName, "Fixture GP")
        XCTAssertEqual(driver.position, 2)
        XCTAssertEqual(driver.currentTyre?.tyreAge, 12)
        XCTAssertEqual(driver.currentTyre?.initialAge, 5)
        XCTAssertEqual(driver.currentTyre?.isNew, false)
        XCTAssertEqual(driver.stops, 1)
        XCTAssertFalse(driver.inPit)
        XCTAssertFalse(value.hasFreshTiming(at: now))
    }

    func testSessionClockCountsDownPausesAndResetsOnNewSession() throws {
        var reducer = LiveTimingReducer()
        try reducer.seed(json(initial), receivedAt: now)
        let utc = "2027-01-15T08:00:00Z"
        try reducer.apply(topic: "ExtrapolatedClock", value: json("{\"Utc\":\"\(utc)\",\"Remaining\":\"00:06:00\",\"Extrapolating\":true}"),
            timestamp: now, receivedAt: now)
        XCTAssertEqual(reducer.snapshot().sessionClock?.remaining(at: now.addingTimeInterval(90)), 270)
        try reducer.apply(topic: "ExtrapolatedClock", value: json(#"{"Remaining":"00:04:30","Extrapolating":false}"#),
            timestamp: now.addingTimeInterval(90), receivedAt: now.addingTimeInterval(90))
        XCTAssertEqual(reducer.snapshot().sessionClock?.remaining(at: now.addingTimeInterval(300)), 270)
        try reducer.apply(topic: "SessionInfo", value: json(#"{"Key":124,"Name":"Qualifying"}"#),
            timestamp: now.addingTimeInterval(301), receivedAt: now.addingTimeInterval(301))
        XCTAssertNil(reducer.snapshot().sessionClock)
    }

    func testSparseUpdatesKeepUnchangedFieldsAndMergeIndexedArrays() throws {
        var reducer = LiveTimingReducer()
        try reducer.seed(json(initial), receivedAt: now)
        try reducer.apply(topic: "TimingData", value: json(#"{"Lines":{"4":{"Position":"1","InPit":"true","PitOut":false,"Sectors":{"1":{"Value":"30.4"}}}}}"#), timestamp: now, receivedAt: now)
        try reducer.apply(topic: "TimingAppData", value: json(#"{"Lines":{"4":{"Stints":{"0":{"TotalLaps":13},"1":{"Compound":"HARD","TotalLaps":1,"New":true}}}}}"#), timestamp: now, receivedAt: now)
        let value = reducer.snapshot(), driver = try XCTUnwrap(value.drivers.first)
        XCTAssertEqual(driver.position, 1)
        XCTAssertEqual(driver.lastLap, "1:30.123")
        XCTAssertEqual(driver.sectors, ["28.1", "30.4", "30.8"])
        XCTAssertTrue(driver.inPit)
        XCTAssertEqual(driver.pitOut, false)
        XCTAssertEqual(driver.stints.map(\.compound), ["SOFT", "HARD"])
        XCTAssertEqual(driver.stints.first?.tyreAge, 13)
        XCTAssertTrue(value.hasFreshTiming(at: now.addingTimeInterval(30)))
        XCTAssertFalse(value.hasFreshTiming(at: now.addingTimeInterval(31)))
    }

    func testPitOutFlagAppearsAndClearsOnSparseTimingUpdates() throws {
        var reducer = LiveTimingReducer()
        try reducer.seed(json(initial), receivedAt: now)
        try reducer.apply(topic: "TimingData", value: json(#"{"Lines":{"4":{"InPit":false,"PitOut":true}}}"#),
            timestamp: now, receivedAt: now)
        XCTAssertEqual(reducer.snapshot().drivers.first?.pitOut, true)
        try reducer.apply(topic: "TimingData", value: json(#"{"Lines":{"4":{"PitOut":false}}}"#),
            timestamp: now.addingTimeInterval(1), receivedAt: now.addingTimeInterval(1))
        XCTAssertEqual(reducer.snapshot().drivers.first?.pitOut, false)
    }

    func testTyreHistorySubtractsUsedTyreAgeAndLeavesCurrentStintOpen() throws {
        var reducer = LiveTimingReducer()
        try reducer.seed(json(initial), receivedAt: now)
        try reducer.apply(topic: "TimingAppData", value: json(#"{"Lines":{"4":{"Stints":{"0":{"Compound":"SOFT","TotalLaps":10,"StartLaps":0},"1":{"Compound":"HARD","TotalLaps":25,"StartLaps":5},"2":{"Compound":"MEDIUM","TotalLaps":3,"StartLaps":0}}}}}"#),
            timestamp: now, receivedAt: now)
        let history = try XCTUnwrap(reducer.snapshot().drivers.first).tyreHistory
        XCTAssertEqual(history.map(\.compound), ["SOFT", "HARD", "MEDIUM"])
        XCTAssertEqual(history.map(\.completedLaps), [10, 20, nil])
    }

    func testOldTimingAndOtherTopicsCannotMakeDataFresh() throws {
        var reducer = LiveTimingReducer()
        try reducer.seed(json(initial), receivedAt: now)
        try reducer.apply(topic: "TimingData", value: json(#"{"Lines":{"4":{"Position":1}}}"#), timestamp: now.addingTimeInterval(-60), receivedAt: now)
        try reducer.apply(topic: "WeatherData", value: json(#"{"AirTemp":"24"}"#), timestamp: now, receivedAt: now)
        XCTAssertFalse(reducer.snapshot().hasFreshTiming(at: now))
        try reducer.apply(topic: "TimingData", value: json(#"{"Lines":{"4":{"Position":2}}}"#), timestamp: now.addingTimeInterval(-90), receivedAt: now)
        XCTAssertEqual(reducer.snapshot().drivers.first?.position, 1)
        try reducer.apply(topic: "TimingData", value: json(#"{"Lines":{"4":{"Position":3}}}"#), timestamp: now, receivedAt: now)
        XCTAssertTrue(reducer.snapshot().hasFreshTiming(at: now))
        try reducer.apply(topic: "SessionStatus", value: json(#"{"Status":"Finished"}"#), timestamp: now, receivedAt: now)
        XCTAssertFalse(reducer.snapshot().hasFreshTiming(at: now))
        XCTAssertTrue(reducer.snapshot().hasFinished)
    }

    func testReconnectSnapshotReplacesMissingFieldsAndNewSessionClearsOldDrivers() throws {
        var reducer = LiveTimingReducer()
        try reducer.seed(json(initial), receivedAt: now)
        try reducer.apply(topic: "TimingData", value: json(#"{"Lines":{"4":{"KnockedOut":true}}}"#), timestamp: now, receivedAt: now)
        try reducer.seed(json(initial), receivedAt: now)
        XCTAssertFalse(try XCTUnwrap(reducer.snapshot().drivers.first).knockedOut)
        XCTAssertNil(reducer.snapshot().lastTimingUpdate)
        try reducer.apply(topic: "SessionInfo", value: json(#"{"ArchiveStatus":{"Status":"Generating"}}"#), timestamp: now, receivedAt: now)
        XCTAssertEqual(reducer.snapshot().drivers.count, 1)
        try reducer.apply(topic: "SessionInfo", value: json(#"{"Key":124,"Name":"Sprint"}"#), timestamp: now, receivedAt: now)
        XCTAssertEqual(reducer.snapshot().sessionID, "124")
        XCTAssertTrue(reducer.snapshot().drivers.isEmpty)
        XCTAssertNil(reducer.snapshot().sessionStatus)
        XCTAssertNil(reducer.snapshot().meetingName)
    }

    func testExplicitNullAndDeletedFieldsClearRatherThanKeepStaleValues() throws {
        var reducer = LiveTimingReducer()
        try reducer.seed(json(initial), receivedAt: now)
        try reducer.apply(topic: "TimingData", value: json(#"{"Lines":{"4":{"GapToLeader":null,"_deleted":["LastLapTime"]},"77":{"Position":"3"}}}"#), timestamp: now, receivedAt: now)
        let value = reducer.snapshot()
        XCTAssertEqual(value.drivers.count, 2)
        XCTAssertNil(value.drivers.first?.gap)
        XCTAssertNil(value.drivers.first?.lastLap)
        XCTAssertEqual(value.drivers.last?.name, "Driver 77")
        try reducer.apply(topic: "TimingData", value: json(#"{"Lines":{"_deleted":["77"]}}"#), timestamp: now, receivedAt: now)
        XCTAssertEqual(reducer.snapshot().drivers.count, 1)
    }

    func testRaceControlKeepsFortyMessagesAndSparseIndicesDoNotAllocateGaps() throws {
        var reducer = LiveTimingReducer()
        for index in 0..<45 {
            let message = "{\"Messages\":{\"\(index)\":{\"Message\":\"Message \(index)\",\"Utc\":\"2026-10-25T20:00:00Z\"}}}"
            try reducer.apply(topic: "RaceControlMessages", value: json(message), timestamp: now, receivedAt: now)
        }
        XCTAssertEqual(reducer.snapshot().messages.count, 40)
        XCTAssertEqual(reducer.snapshot().messages.first?.id, "44")
        XCTAssertEqual(reducer.snapshot().messages.last?.id, "5")
        let sparse = try json(#"{"1000000000":{"Value":"1"}}"#)
        XCTAssertEqual(sparse.ordered.count, 1)
    }

    func testSignalRFramesHandlePartialUTF8AndMultipleMessages() throws {
        var parser = SignalRFrames()
        let data = Data((#"{"type":1,"arguments":["DriverList",{"Name":"Pérez"}]}"# + "\u{1e}" + #"{"type":6}"# + "\u{1e}").utf8)
        let split = try XCTUnwrap(data.firstIndex(of: 0xc3)) + 1
        XCTAssertTrue(try parser.append(Data(data[..<split])).isEmpty)
        let messages = try parser.append(Data(data[split...]))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["arguments"].array[1]["Name"].text, "Pérez")
        XCTAssertEqual(messages[1]["type"].int, 6)
    }

    func testMalformedDeepAndOversizedInputFailsWithinLimits() throws {
        var parser = SignalRFrames()
        XCTAssertThrowsError(try parser.append(Data("not-json\u{1e}".utf8)))
        var oversized = SignalRFrames()
        XCTAssertThrowsError(try oversized.append(Data(repeating: 32, count: SignalRFrames.maximumBytes + 1)))
        let deep = String(repeating: "{\"x\":", count: 26) + "0" + String(repeating: "}", count: 26)
        XCTAssertThrowsError(try json(deep))
    }

    func testRetryAfterSupportsBothSecondsAndHTTPDate() throws {
        XCTAssertEqual(LiveRetryPolicy.retryAfter("120", now: now), now.addingTimeInterval(120))
        XCTAssertEqual(LiveRetryPolicy.retryAfter("Sun, 25 Oct 2026 20:00:00 GMT", now: now), liveDate("2026-10-25T20:00:00Z"))
        XCTAssertNil(LiveRetryPolicy.retryAfter("invalid", now: now))
        XCTAssertNil(LiveRetryPolicy.retryAfter("-3", now: now))
    }

    func testUpdatesBeforeSubscriptionSnapshotAreBufferedAndPingsNeverEstablishLiveTiming() throws {
        var hub = LiveTimingHub()
        _ = try hub.consume(json("{}"), receivedAt: now)
        _ = try hub.consume(json(#"{"type":1,"target":"feed","arguments":["TimingData",{"Lines":{"4":{"Position":1}}},"2026-10-25T20:00:00Z"]}"#), receivedAt: now)
        XCTAssertFalse(hub.subscribed)
        _ = try hub.consume(json("{\"type\":3,\"invocationId\":\"1\",\"result\":\(initial)}"), receivedAt: now)
        XCTAssertTrue(hub.subscribed)
        XCTAssertEqual(hub.reducer.snapshot().drivers.first?.position, 1)
        let lastTiming = hub.reducer.snapshot().lastTimingUpdate
        _ = try hub.consume(json(#"{"type":6}"#), receivedAt: now.addingTimeInterval(60))
        XCTAssertEqual(hub.reducer.snapshot().lastTimingUpdate, lastTiming)
        _ = try hub.consume(json("{\"type\":3,\"invocationId\":\"1\",\"result\":\(initial)}"), receivedAt: now)
        XCTAssertEqual(hub.reducer.snapshot().drivers.first?.position, 1)
    }

    func testHandshakeSubscriptionAndServerCloseFailuresAreExplicit() throws {
        var refused = LiveTimingHub()
        XCTAssertThrowsError(try refused.consume(json(#"{"error":"Unsupported protocol"}"#), receivedAt: now))
        var hub = LiveTimingHub()
        _ = try hub.consume(json("{}"), receivedAt: now)
        XCTAssertThrowsError(try hub.consume(json(#"{"type":3,"invocationId":"1","error":"Unavailable"}"#), receivedAt: now))
        XCTAssertThrowsError(try hub.consume(json(#"{"type":7}"#), receivedAt: now))
    }
}
