import XCTest
@testable import WritingTrackerCore

final class KeystrokeWordCounterTests: XCTestCase {
    private func counter() -> KeystrokeWordCounter { KeystrokeWordCounter() }

    func testTypingWordsCountsAdditions() {
        let c = counter()
        c.ingest(.characters("hello"))
        c.ingest(.characters(" "))
        c.ingest(.characters("world"))
        XCTAssertEqual(c.estimate.wordsAdded, 2)
        XCTAssertEqual(c.estimate.wordsRemoved, 0)
        XCTAssertEqual(c.estimate.netWordChange, 2)
        XCTAssertEqual(c.bufferedCharacterCount, 11)
    }

    func testPartialBackspaceDoesNotRemoveWord() {
        let c = counter()
        c.ingest(.characters("hello world"))
        c.ingest(.deleteBackward)
        c.ingest(.deleteBackward)
        XCTAssertEqual(c.estimate.wordsAdded, 2)
        XCTAssertEqual(c.estimate.wordsRemoved, 0)
        XCTAssertEqual(c.estimate.netWordChange, 2)
    }

    func testBackspaceRemovingWholeWordCountsRemoval() {
        let c = counter()
        c.ingest(.characters("hello world"))
        // Remove the five letters of "world".
        for _ in 0..<5 { c.ingest(.deleteBackward) }
        XCTAssertEqual(c.estimate.wordsAdded, 2)
        XCTAssertEqual(c.estimate.wordsRemoved, 1)
        XCTAssertEqual(c.estimate.netWordChange, 1)
    }

    func testBackspacingAWordThatWasNeverCommitted() {
        let c = counter()
        c.ingest(.characters("hello"))
        for _ in 0..<5 { c.ingest(.deleteBackward) }
        XCTAssertEqual(c.estimate.wordsAdded, 1)
        XCTAssertEqual(c.estimate.wordsRemoved, 1)
        XCTAssertEqual(c.estimate.netWordChange, 0)
        XCTAssertEqual(c.bufferedCharacterCount, 0)
    }

    func testOptionDeleteRemovesTrailingWord() {
        let c = counter()
        c.ingest(.characters("hello world"))
        c.ingest(.deleteWordBackward)
        XCTAssertEqual(c.estimate.wordsAdded, 2)
        XCTAssertEqual(c.estimate.wordsRemoved, 1)
        XCTAssertEqual(c.estimate.netWordChange, 1)
    }

    func testOptionDeleteIncludesTrailingSpaces() {
        let c = counter()
        c.ingest(.characters("hello world "))
        c.ingest(.deleteWordBackward)
        XCTAssertEqual(c.estimate.wordsRemoved, 1)
    }

    func testCmdDeleteRemovesToLineStart() {
        let c = counter()
        c.ingest(.characters("one two three"))
        c.ingest(.deleteToLineStart)
        XCTAssertEqual(c.estimate.wordsAdded, 3)
        XCTAssertEqual(c.estimate.wordsRemoved, 3)
        XCTAssertEqual(c.estimate.netWordChange, 0)
        XCTAssertEqual(c.bufferedCharacterCount, 0)
    }

    func testCmdDeleteOnlyAffectsCurrentLine() {
        let c = counter()
        c.ingest(.characters("keep me"))
        c.ingest(.newline)
        c.ingest(.characters("remove this line"))
        c.ingest(.deleteToLineStart)
        XCTAssertEqual(c.estimate.wordsRemoved, 3)
        // "keep me" (2) and "remove this line" (3) were added; 3 removed -> net 2.
        XCTAssertEqual(c.estimate.netWordChange, 2)
    }

    func testDeletingWithEmptyBufferIsSafe() {
        let c = counter()
        c.ingest(.deleteBackward)
        c.ingest(.deleteWordBackward)
        c.ingest(.deleteToLineStart)
        c.ingest(.deleteForward)
        XCTAssertTrue(c.estimate.isEmpty)
        XCTAssertEqual(c.bufferedCharacterCount, 0)
    }

    func testResetDestroysBufferAndCounters() {
        let c = counter()
        c.ingest(.characters("secret manuscript text"))
        XCTAssertGreaterThan(c.bufferedCharacterCount, 0)
        c.reset()
        XCTAssertEqual(c.bufferedCharacterCount, 0)
        XCTAssertTrue(c.estimate.isEmpty)
    }

    func testPunctuationIsTreatedAsPartOfWordBoundaries() {
        let c = counter()
        c.ingest(.characters("well-known"))
        XCTAssertEqual(c.estimate.wordsAdded, 1)
    }

    func testReTypingAfterFullDeletionCountsAgain() {
        let c = counter()
        c.ingest(.characters("draft"))
        for _ in 0..<5 { c.ingest(.deleteBackward) }
        c.ingest(.characters("final"))
        XCTAssertEqual(c.estimate.wordsAdded, 2)
        XCTAssertEqual(c.estimate.wordsRemoved, 1)
        XCTAssertEqual(c.estimate.netWordChange, 1)
    }
}

final class WordCountSourcePersistenceTests: XCTestCase {
    func testSessionWordCountSourceRoundTrips() throws {
        let db = try TestSupport.makeDatabase()
        let session = Session(
            startedAt: Date(),
            endedAt: Date(),
            netWordChange: 120,
            wordCountSource: .keystrokeEstimate
        )
        try SessionRepository(database: db).insert(session)
        let loaded = try SessionRepository(database: db).find(id: session.id)
        XCTAssertEqual(loaded?.wordCountSource, .keystrokeEstimate)
    }

    func testManualSessionIsMarkedManual() throws {
        let db = try TestSupport.makeDatabase()
        let statistics = StatisticsService(database: db, dateProvider: MutableDateProvider(), calendarContext: TestSupport.calendar())
        let service = SessionService(database: db, statistics: statistics)
        let session = try service.addManualSession(projectID: nil, date: Date(), words: 50, activeSeconds: 600)
        XCTAssertEqual(try service.session(id: session.id)?.wordCountSource, .manual)
    }

    func testEstimatedSessionUpdatesProjectTotal() throws {
        let db = try TestSupport.makeDatabase()
        let project = Project(title: "Estimated", targetWordCount: 1000, currentWordCount: 0)
        try ProjectRepository(database: db).insert(project)
        let session = Session(
            projectID: project.id,
            startedAt: Date(),
            endedAt: Date(),
            activeSeconds: 600,
            netWordChange: 100,
            wordCountSource: .keystrokeEstimate
        )
        try SessionRepository(database: db).insert(session)
        ProjectWordCountCalculator.recompute(projectID: project.id, database: db)
        XCTAssertEqual(try ProjectRepository(database: db).find(id: project.id)?.currentWordCount, 100)
    }

    func testNativeSnapshotTakesPrecedenceOverEstimate() throws {
        let db = try TestSupport.makeDatabase()
        let project = Project(title: "Native", targetWordCount: 1000, currentWordCount: 0)
        try ProjectRepository(database: db).insert(project)
        let session = Session(
            projectID: project.id, startedAt: Date(), endedAt: Date(),
            activeSeconds: 600, netWordChange: 100, wordCountSource: .keystrokeEstimate
        )
        try SessionRepository(database: db).insert(session)
        try WordCountSnapshotRepository(database: db).insert(
            WordCountSnapshot(timestamp: Date(), projectID: project.id, wordCount: 500, source: "word")
        )
        ProjectWordCountCalculator.recompute(projectID: project.id, database: db)
        XCTAssertEqual(try ProjectRepository(database: db).find(id: project.id)?.currentWordCount, 500)
    }
}
