import XCTest
@testable import WritingTrackerCore

final class AdapterTests: XCTestCase {
    func testWordDocumentLineParsing() {
        let line = "Naphtali.docx|||https://d.docs.live.net/abc/Naphtali.docx|||33799|||153277|||131|||true"
        let info = WordAdapter.parseDocumentLine(line)
        XCTAssertEqual(info?.displayName, "Naphtali.docx")
        XCTAssertEqual(info?.stableIdentifier, "https://d.docs.live.net/abc/Naphtali.docx")
        XCTAssertEqual(info?.wordCount, 33_799)
        XCTAssertEqual(info?.characterCount, 153_277)
        XCTAssertEqual(info?.pageCount, 131)
    }

    func testWordDocumentLineParsingWithoutStats() {
        let info = WordAdapter.parseDocumentLine("Notes.docx|||/Users/x/Notes.docx", includeStats: false)
        XCTAssertEqual(info?.displayName, "Notes.docx")
        XCTAssertEqual(info?.filePath, "/Users/x/Notes.docx")
        XCTAssertNil(info?.wordCount)
    }

    /// Regression: the adapter script no longer requests pages, so it returns a
    /// four-field line. The parser must still read words and characters.
    func testWordDocumentLineParsingWithoutPages() {
        let line = "Naphtali.docx|||/Users/x/Naphtali.docx|||34735|||157678"
        let info = WordAdapter.parseDocumentLine(line)
        XCTAssertEqual(info?.wordCount, 34_735)
        XCTAssertEqual(info?.characterCount, 157_678)
        XCTAssertNil(info?.pageCount)
    }

    func testWordParserRejectsEmptyOrMalformedLines() {
        XCTAssertNil(WordAdapter.parseDocumentLine(""))
        XCTAssertNil(WordAdapter.parseDocumentLine("|||"))
    }

    func testAdapterRegistryUsesCorrectAdapterTypes() {
        let registry = AdapterRegistry()
        XCTAssertEqual(registry.adapter(forBundleIdentifier: "com.microsoft.Word").adapterType, .word)
        XCTAssertEqual(registry.adapter(forBundleIdentifier: "com.apple.iWork.Pages").adapterType, .pages)
        XCTAssertEqual(registry.adapter(forBundleIdentifier: "md.obsidian").adapterType, .obsidian)
        XCTAssertEqual(registry.adapter(forBundleIdentifier: "com.apple.Safari").adapterType, .browser)
        XCTAssertEqual(registry.adapter(forBundleIdentifier: "com.unknown.app").adapterType, .generic)
    }

    func testWordAdapterCapabilitiesAreHonest() {
        let word = WordAdapter(executor: MockScriptExecutor(result: nil))
        XCTAssertTrue(word.capabilities.activeDocument)
        XCTAssertTrue(word.capabilities.wordCount)
        XCTAssertTrue(word.capabilities.documentPath)
        // The tracker never claims text access.
        XCTAssertFalse(word.capabilities.textAccess)
    }

    func testPagesDocumentLineParsing() {
        let line = "Novel.pages|||/Users/writer/Novel.pages|||48210|||260144"
        let info = PagesAdapter.parseDocumentLine(line)
        XCTAssertEqual(info?.displayName, "Novel.pages")
        XCTAssertEqual(info?.filePath, "/Users/writer/Novel.pages")
        XCTAssertEqual(info?.wordCount, 48_210)
        XCTAssertEqual(info?.characterCount, 260_144)
    }

    func testPagesAdapterReportsExactWordCount() {
        let pages = PagesAdapter(executor: MockScriptExecutor(result: nil))
        XCTAssertTrue(pages.capabilities.activeDocument)
        XCTAssertTrue(pages.capabilities.wordCount)
        XCTAssertFalse(pages.capabilities.textAccess)
    }

    func testOnlyWordAndPagesAreAdvertisedAsWordCountApps() {
        let countApps = AdapterRegistry.knownApplications.map(\.adapterType)
        XCTAssertEqual(Set(countApps), Set([.word, .pages]))
        // Time-only apps must never advertise a word count.
        for entry in AdapterRegistry.timeOnlyApplications {
            let adapter = AdapterRegistry().adapter(forBundleIdentifier: entry.bundleIdentifier, adapterType: entry.adapterType)
            XCTAssertFalse(adapter.capabilities.wordCount, "\(entry.displayName) should not claim a word count")
        }
    }

    func testGenericAdapterReportsFocusOnly() {
        let generic = GenericApplicationAdapter(bundleIdentifier: "com.example.app")
        XCTAssertEqual(generic.capabilities, .focusAndActivityOnly)
        XCTAssertNil(generic.activeDocument())
    }

    func testWordAdapterDegradesGracefullyOnPermissionDenied() {
        let executor = MockScriptExecutor(error: ScriptError.permissionDenied)
        let adapter = WordAdapter(executor: executor)
        // When Word is not running the adapter returns nil before scripting;
        // when it is running a permission error is swallowed into nil.
        let document = adapter.activeDocument()
        if ApplicationLocator.isRunning(bundleIdentifier: "com.microsoft.Word") {
            XCTAssertNil(document)
        }
    }
}

/// Test double for AppleScript execution.
final class MockScriptExecutor: ScriptExecuting {
    var result: String?
    var error: Error?

    init(result: String? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func execute(_ script: String) throws -> String? {
        if let error { throw error }
        return result
    }
}

final class PermissionDegradationTests: XCTestCase {
    func testWordAutomationDeniedStillAllowsManualAndFocusTracking() throws {
        let db = try TestSupport.makeDatabase()
        let permissions = MockPermissionManager(states: [.wordAutomation: .denied])
        XCTAssertEqual(permissions.status(for: .wordAutomation).state, .denied)

        // The engine can still be constructed and manual sessions never need a
        // permission; activity uses the system idle counter.
        let engine = TrackingEngine(
            database: db,
            permissionProvider: permissions,
            dateProvider: MutableDateProvider(TestSupport.date("2026-09-08T09:00:00-04:00")),
            calendarContext: TestSupport.calendar()
        )
        XCTAssertEqual(engine.snapshot().state, .idle)
        // No crash and no fabricated data.
        XCTAssertEqual(engine.snapshot().todayNetWords, 0)
    }

    func testOptionalPermissionStatesAreRepresentable() {
        let combinations: [(PermissionState, PermissionState)] = [
            (.granted, .granted), (.granted, .denied), (.denied, .granted), (.denied, .denied)
        ]
        for (automation, notifications) in combinations {
            let manager = MockPermissionManager(states: [.wordAutomation: automation, .notifications: notifications])
            XCTAssertEqual(manager.status(for: .wordAutomation).state, automation)
            XCTAssertEqual(manager.status(for: .notifications).state, notifications)
        }
    }

    func testPermissionRequestsUpdateState() {
        let manager = MockPermissionManager(states: [.notifications: .denied])
        manager.request(.notifications)
        XCTAssertEqual(manager.status(for: .notifications).state, .granted)
    }
}
