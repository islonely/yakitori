import XCTest

@testable import WritingTrackerCore

final class EntitlementGatingTests: XCTestCase {
    func testRecordingIsGatedByTrackingAllowed() throws {
        let database = try TestSupport.makeDatabase()
        let engine = TrackingEngine(
            database: database,
            permissionProvider: MockPermissionManager(),
            dateProvider: MutableDateProvider(TestSupport.date("2026-09-08T09:00:00-04:00")),
            calendarContext: TestSupport.calendar()
        )

        engine.start()
        defer { engine.stop() }

        // Without an active license or trial, new sessions are refused.
        engine.setTrackingAllowed(false)
        XCTAssertFalse(engine.isTrackingAllowed)
        engine.startManualSession(projectID: nil, type: .drafting)
        XCTAssertFalse(engine.snapshot().isSessionOpen)

        // Once entitled, recording resumes.
        engine.setTrackingAllowed(true)
        engine.startManualSession(projectID: nil, type: .drafting)
        XCTAssertTrue(engine.snapshot().isSessionOpen)
    }

    /// The trial-expiry path: LicensingService reports the trial ended, the app
    /// sets tracking to disallowed, and the engine stops the running session.
    func testDisallowingTrackingEndsAnOpenSession() throws {
        let database = try TestSupport.makeDatabase()
        let engine = TrackingEngine(
            database: database,
            permissionProvider: MockPermissionManager(),
            dateProvider: MutableDateProvider(TestSupport.date("2026-09-08T09:00:00-04:00")),
            calendarContext: TestSupport.calendar()
        )

        engine.start()
        defer { engine.stop() }

        engine.setTrackingAllowed(true)
        engine.startManualSession(projectID: nil, type: .drafting)
        XCTAssertTrue(engine.snapshot().isSessionOpen)

        engine.setTrackingAllowed(false)
        XCTAssertFalse(engine.snapshot().isSessionOpen)
    }
}
