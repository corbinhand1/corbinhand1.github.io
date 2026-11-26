//
//  TimerServerTests.swift
//  Cue to CueTests
//
//  Countdown rounding, pause/resume precision, adjustments and clock
//  alignment, driven by an injected clock (no real waiting).
//

import XCTest
@testable import Cue_to_Cue

final class TimerServerTests: XCTestCase {

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000) // whole second
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private var clock: Clock!
    private var server: AuthoritativeTimerServer!

    override func setUp() {
        clock = Clock()
        let clock = self.clock!
        server = AuthoritativeTimerServer(now: { clock.now }, startTicking: false)
    }

    private func send(_ action: String, countdown: Int? = nil, adjust: Int? = nil) {
        server.executeCommand(TimerCommand(action: action, countdownTime: countdown, countUpTime: nil, adjustment: adjust, targetTimeString: nil))
    }

    private func tick(after seconds: TimeInterval) {
        clock.advance(seconds)
        server.updateTimers()
    }

    // MARK: Rounding

    func testSecondsRemainingRoundsUp() {
        let t = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(AuthoritativeTimerServer.secondsRemaining(until: t, from: t.addingTimeInterval(-10)), 10)
        XCTAssertEqual(AuthoritativeTimerServer.secondsRemaining(until: t, from: t.addingTimeInterval(-9.5)), 10)
        XCTAssertEqual(AuthoritativeTimerServer.secondsRemaining(until: t, from: t.addingTimeInterval(-0.1)), 1)
        XCTAssertEqual(AuthoritativeTimerServer.secondsRemaining(until: t, from: t), 0)
        XCTAssertEqual(AuthoritativeTimerServer.secondsRemaining(until: t, from: t.addingTimeInterval(5)), 0)
    }

    func testCountdownShowsFullValueThenReachesZeroExactlyAtTarget() {
        send("setCountdownTime", countdown: 10)
        send("start")
        tick(after: 0.4)
        XCTAssertEqual(server.countdownTime, 10, "the first second still shows 10")
        tick(after: 9.5)                       // 9.9 s elapsed
        XCTAssertEqual(server.countdownTime, 1, "must not show 0 before the target")
        XCTAssertTrue(server.countdownRunning)
        tick(after: 0.1)                       // exactly 10 s
        XCTAssertEqual(server.countdownTime, 0)
        XCTAssertFalse(server.countdownRunning)
    }

    // MARK: Pause / resume

    func testPauseResumeKeepsFractionalSeconds() {
        send("setCountdownTime", countdown: 10)
        send("start")
        clock.advance(0.9)                     // 9.1 s left
        send("pause")
        XCTAssertEqual(server.countdownTime, 10)
        XCTAssertFalse(server.countdownRunning)

        clock.advance(600)                     // paused for 10 minutes
        send("start")
        tick(after: 9.0)
        XCTAssertEqual(server.countdownTime, 1, "0.1 s still left")
        tick(after: 0.1)
        XCTAssertEqual(server.countdownTime, 0, "total running time is exactly 10 s")
    }

    func testRepeatedPauseResumeDoesNotLoseTime() {
        send("setCountdownTime", countdown: 60)
        send("start")
        for _ in 0..<10 {
            clock.advance(0.95)
            send("pause")
            clock.advance(5)
            send("start")
        }
        // 9.5 s of running time used; 50.5 s left.
        tick(after: 50.4)
        XCTAssertEqual(server.countdownTime, 1)
        tick(after: 0.1)
        XCTAssertEqual(server.countdownTime, 0)
    }

    func testResetClearsPausedRemainder() {
        send("setCountdownTime", countdown: 10)
        send("start")
        clock.advance(0.5)
        send("pause")
        send("reset")
        XCTAssertEqual(server.countdownTime, 0)
        send("setCountdownTime", countdown: 30)
        send("start")
        tick(after: 29.9)
        XCTAssertEqual(server.countdownTime, 1)
    }

    // MARK: Adjust

    func testAdjustWhileRunningAddsExactly() {
        send("setCountdownTime", countdown: 10)
        send("start")
        clock.advance(0.5)                     // 9.5 left
        send("adjust", adjust: 60)             // 69.5 left
        tick(after: 69.4)
        XCTAssertEqual(server.countdownTime, 1)
        tick(after: 0.1)
        XCTAssertEqual(server.countdownTime, 0)
    }

    func testAdjustBelowZeroStops() {
        send("setCountdownTime", countdown: 30)
        send("start")
        send("adjust", adjust: -60)
        XCTAssertEqual(server.countdownTime, 0)
        XCTAssertFalse(server.countdownRunning)
    }

    func testAdjustWhilePausedThenStart() {
        send("setCountdownTime", countdown: 10)
        send("adjust", adjust: 60)
        XCTAssertEqual(server.countdownTime, 70)
        send("start")
        tick(after: 69.9)
        XCTAssertEqual(server.countdownTime, 1)
    }

    // MARK: Cue-driven reset

    func testResetCountdownFromCueStartsRunning() {
        server.resetCountdown(with: 90)
        XCTAssertTrue(server.countdownRunning)
        tick(after: 30)
        XCTAssertEqual(server.countdownTime, 60)
    }

    // MARK: Time of day

    func testClockFlipsOnTheRealSecondBoundary() {
        clock.now = Date(timeIntervalSince1970: 1_800_000_000.95)
        server.updateTimers()
        let shown = server.currentTime
        tick(after: 0.04)                      // .99: same second
        XCTAssertEqual(server.currentTime, shown)
        tick(after: 0.03)                      // 1_800_000_001.02: new second
        XCTAssertEqual(Int(server.currentTime.timeIntervalSince1970), 1_800_000_001,
                       "the displayed second changes within one tick of the real one")
    }

    func testTimerStateUsesInjectedClock() {
        let state = server.getTimerState()
        XCTAssertEqual(state.timestamp, clock.now.timeIntervalSince1970 * 1000, accuracy: 0.001)
    }
}
