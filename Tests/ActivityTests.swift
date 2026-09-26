import XCTest
@testable import NotchAgent

final class ActivityTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testLongBurstThenSilenceIsReportedOnce() {
        var tracker = ActivityTracker()
        for s in stride(from: 0.0, through: 10, by: 0.5) { tracker.output(at: at(s)) } // agent streaming for 10s
        XCTAssertTrue(tracker.isWorking(now: at(11)))
        XCTAssertFalse(tracker.finishedWork(now: at(11)), "not quiet long enough yet")
        XCTAssertFalse(tracker.isWorking(now: at(13)))
        XCTAssertTrue(tracker.finishedWork(now: at(13)))
        XCTAssertFalse(tracker.finishedWork(now: at(20)), "reported only once")
    }
    func testShortBurstIsNotWork() {
        var tracker = ActivityTracker()
        tracker.output(at: at(0)); tracker.output(at: at(1)); tracker.output(at: at(2)) // startup banner
        XCTAssertFalse(tracker.finishedWork(now: at(10)))
    }
    func testGapStartsANewBurst() {
        var tracker = ActivityTracker()
        for s in stride(from: 0.0, through: 6, by: 1) { tracker.output(at: at(s)) }
        XCTAssertTrue(tracker.finishedWork(now: at(9)))
        tracker.output(at: at(30)) // a single redraw much later
        XCTAssertEqual(tracker.busySince, at(30))
        XCTAssertFalse(tracker.finishedWork(now: at(40)))
    }
    func testNoOutputIsIdle() {
        var tracker = ActivityTracker()
        XCTAssertFalse(tracker.isWorking(now: t0))
        XCTAssertFalse(tracker.finishedWork(now: t0))
    }
}
