import XCTest
@testable import F1Core

@MainActor final class WindowVisibilityDeliveryTests: XCTestCase {
    @MainActor private final class Queue {
        var jobs: [@MainActor @Sendable () -> Void] = []
        func drain() {
            let pending = jobs
            jobs.removeAll()
            pending.forEach { $0() }
        }
    }

    func testAttachmentNeverPublishesInsideTheViewUpdate() {
        let queue = Queue()
        var values: [Bool] = []
        let subject = WindowVisibilityDelivery(enqueue: { queue.jobs.append($0) }, onChange: { values.append($0) })
        subject.submit(true)
        XCTAssertTrue(values.isEmpty, "View attachment must not synchronously change SwiftUI state")
        queue.drain()
        XCTAssertEqual(values, [true])
        subject.submit(false)
        XCTAssertEqual(values, [true], "View removal must also defer state changes")
        queue.drain()
        XCTAssertEqual(values, [true, false])
    }

    func testTemporaryDetachAndReattachDoesNotDisconnectTheFeed() {
        let queue = Queue()
        var values: [Bool] = []
        let subject = WindowVisibilityDelivery(enqueue: { queue.jobs.append($0) }, onChange: { values.append($0) })
        subject.submit(true)
        queue.drain()
        subject.submit(false)
        subject.submit(true)
        subject.submit(true)
        queue.drain()
        XCTAssertEqual(values, [true])
        subject.submit(false)
        queue.drain()
        XCTAssertEqual(values, [true, false])
    }

    func testCloseSupersedesPendingVisibleNotification() {
        let queue = Queue()
        var values: [Bool] = []
        let subject = WindowVisibilityDelivery(enqueue: { queue.jobs.append($0) }, onChange: { values.append($0) })
        subject.submit(true)
        subject.submit(false)
        queue.drain()
        XCTAssertEqual(values, [false])
        subject.submit(true)
        queue.drain()
        XCTAssertEqual(values, [false, true])
    }
}
