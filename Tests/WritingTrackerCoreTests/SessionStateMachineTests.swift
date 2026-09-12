import XCTest
@testable import WritingTrackerCore

final class SessionStateMachineTests: XCTestCase {
    private let t0 = TestSupport.date("2026-09-08T19:00:00Z")

    private func policy(_ mode: TrackingMode, inactivity: TimeInterval = 300) -> SessionPolicy {
        SessionPolicy(mode: mode, inactivityTimeout: inactivity, endOnAppUnfocus: mode == .automatic)
    }

    func testManualSessionPauseResumeAndStop() {
        let machine = SessionStateMachine(policy: policy(.manual))
        let start = t0
        let pauseAt = start.addingTimeInterval(600)
        let resumeAt = pauseAt.addingTimeInterval(300)
        let stopAt = resumeAt.addingTimeInterval(600)

        _ = machine.handle(.startManually(at: start, type: .drafting))
        XCTAssertEqual(machine.state, .active)
        _ = machine.handle(.activity(at: start.addingTimeInterval(10)))
        XCTAssertEqual(machine.state, .active)

        _ = machine.handle(.pauseManually(at: pauseAt))
        XCTAssertEqual(machine.state, .paused)
        _ = machine.handle(.resumeManually(at: resumeAt))
        XCTAssertEqual(machine.state, .active)
        _ = machine.handle(.stopManually(at: stopAt))
        XCTAssertEqual(machine.state, .ended)

        XCTAssertEqual(machine.session?.activeSeconds ?? 0, 1200, accuracy: 0.001)
        XCTAssertEqual(machine.session?.focusSeconds ?? 0, 1500, accuracy: 0.001)
        XCTAssertEqual(machine.session?.sessionType, .drafting)
    }

    func testAutomaticSessionEndsWhenWritingAppUnfocused() {
        let machine = SessionStateMachine(policy: policy(.automatic))
        let start = t0
        let firstActivity = start.addingTimeInterval(60)
        let unfocus = start.addingTimeInterval(300)

        _ = machine.handle(.frontmostChanged(at: start, applicationID: "app-1", isTrackedWritingApp: true))
        XCTAssertEqual(machine.state, .focused)
        _ = machine.handle(.activity(at: firstActivity))
        XCTAssertEqual(machine.state, .active)

        let transition = machine.handle(.frontmostChanged(at: unfocus, applicationID: "safari", isTrackedWritingApp: false))
        XCTAssertEqual(transition?.to, .ended)
        XCTAssertEqual(machine.session?.activeSeconds ?? 0, 240, accuracy: 0.001)
        XCTAssertEqual(machine.session?.focusSeconds ?? 0, 300, accuracy: 0.001)
    }

    func testFilteredSessionPausesOnUnfocusAndResumes() {
        let machine = SessionStateMachine(policy: policy(.automaticFiltered))
        let start = t0
        _ = machine.handle(.frontmostChanged(at: start, applicationID: "app-1", isTrackedWritingApp: true))
        _ = machine.handle(.activity(at: start.addingTimeInterval(30)))
        XCTAssertEqual(machine.state, .active)

        _ = machine.handle(.frontmostChanged(at: start.addingTimeInterval(120), applicationID: "mail", isTrackedWritingApp: false))
        XCTAssertEqual(machine.state, .paused)
        XCTAssertFalse(machine.isFocused)

        // Activity while unfocused must not resume the session.
        _ = machine.handle(.activity(at: start.addingTimeInterval(200)))
        XCTAssertEqual(machine.state, .paused)

        // Refocus + activity resumes.
        _ = machine.handle(.frontmostChanged(at: start.addingTimeInterval(300), applicationID: "app-1", isTrackedWritingApp: true))
        _ = machine.handle(.activity(at: start.addingTimeInterval(310)))
        XCTAssertEqual(machine.state, .active)
    }

    func testInactivityPausesAndActivityResumes() {
        let machine = SessionStateMachine(policy: policy(.manual, inactivity: 300))
        let start = t0
        _ = machine.handle(.startManually(at: start, type: .drafting))
        _ = machine.handle(.activity(at: start.addingTimeInterval(120)))

        let inactivityAt = start.addingTimeInterval(420)
        _ = machine.handle(.inactivityElapsed(at: inactivityAt))
        XCTAssertEqual(machine.state, .paused)

        _ = machine.handle(.activity(at: start.addingTimeInterval(500)))
        XCTAssertEqual(machine.state, .active)
        _ = machine.handle(.stopManually(at: start.addingTimeInterval(600)))

        // Active time covers 0→420s and 500→600s; the pause is excluded.
        XCTAssertEqual(machine.session?.activeSeconds ?? 0, 520, accuracy: 0.001)
        // Focus remains for the whole frontmost period.
        XCTAssertEqual(machine.session?.focusSeconds ?? 0, 600, accuracy: 0.001)
    }

    func testInactivityNeverDoesNotPause() {
        let machine = SessionStateMachine(policy: policy(.manual, inactivity: 0))
        let start = t0
        _ = machine.handle(.startManually(at: start, type: .drafting))
        _ = machine.handle(.inactivityElapsed(at: start.addingTimeInterval(10_000)))
        XCTAssertEqual(machine.state, .active)
    }

    func testSleepPausesAndWakeRemainsPausedUntilActivity() {
        let machine = SessionStateMachine(policy: policy(.manual))
        let start = t0
        _ = machine.handle(.startManually(at: start, type: .drafting))
        let sleepAt = start.addingTimeInterval(300)
        _ = machine.handle(.systemWillSleep(at: sleepAt))
        XCTAssertEqual(machine.state, .paused)
        XCTAssertFalse(machine.isFocused)

        let wakeAt = start.addingTimeInterval(3600)
        _ = machine.handle(.systemDidWake(at: wakeAt))
        XCTAssertEqual(machine.state, .paused)
        // No activity after wake: idle time is not counted.
        let resumed = start.addingTimeInterval(3700)
        _ = machine.handle(.frontmostChanged(at: wakeAt, applicationID: "app-1", isTrackedWritingApp: true))
        _ = machine.handle(.activity(at: resumed))
        XCTAssertEqual(machine.state, .active)
        _ = machine.handle(.stopManually(at: start.addingTimeInterval(3800)))

        XCTAssertEqual(machine.session?.activeSeconds ?? 0, 400, accuracy: 0.001)
        // Sleep time (300→3600) is excluded from focus.
        XCTAssertEqual(machine.session?.focusSeconds ?? 0, 500, accuracy: 0.001)
    }

    func testWordCountSamplingRecordsStartingAndEnding() {
        let machine = SessionStateMachine(policy: policy(.manual))
        let start = t0
        _ = machine.handle(.startManually(at: start, type: .drafting))
        _ = machine.handle(.wordCountSampled(starting: 1000, ending: 1000, at: start))
        _ = machine.handle(.wordCountSampled(starting: nil, ending: 1300, at: start.addingTimeInterval(600)))
        _ = machine.handle(.stopManually(at: start.addingTimeInterval(600)))

        XCTAssertEqual(machine.session?.startingWordCount, 1000)
        XCTAssertEqual(machine.session?.endingWordCount, 1300)
        XCTAssertEqual(machine.session?.netWordChange, 300)
        XCTAssertNil(machine.session?.wordsAdded)
        XCTAssertNil(machine.session?.wordsRemoved)
    }
}
