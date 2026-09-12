import Foundation

/// A normalized keystroke, produced by `KeystrokeMonitor` and consumed only by
/// the in-memory `KeystrokeWordCounter`. It carries no persistent meaning.
public enum KeystrokeInput: Equatable, Sendable {
    case characters(String)
    case newline
    case deleteBackward
    case deleteWordBackward
    case deleteToLineStart
    case deleteForward
    case deleteWordForward
    case deleteToLineEnd
}

/// Estimated gross word activity for one session.
public struct WordCountEstimate: Equatable, Sendable {
    public var wordsAdded: Int
    public var wordsRemoved: Int

    public init(wordsAdded: Int = 0, wordsRemoved: Int = 0) {
        self.wordsAdded = wordsAdded
        self.wordsRemoved = wordsRemoved
    }

    public var netWordChange: Int { wordsAdded - wordsRemoved }
    public var isEmpty: Bool { wordsAdded == 0 && wordsRemoved == 0 }
}

/// Estimates words added and removed from a stream of keystrokes.
///
/// **Privacy:** this type is the only place typed content is held. The buffer and
/// counters are session-scoped and must be discarded via `reset()` when the
/// session ends. Nothing here is ever persisted.
///
/// The model is intentionally approximate: it assumes text is appended at the
/// end of the active document, so it cannot observe pasted text, cursor moves,
/// autocorrect, or forward deletions accurately. That is why its output is always
/// labelled an estimate and never overrides a native word count.
public final class KeystrokeWordCounter {
    private var buffer: [Character] = []
    private var wordsAdded = 0
    private var wordsRemoved = 0

    public init() {}

    /// Discards the buffered characters and counters. Call at session end,
    /// when tracking stops, or on termination.
    public func reset() {
        buffer.removeAll(keepingCapacity: false)
        wordsAdded = 0
        wordsRemoved = 0
    }

    public var estimate: WordCountEstimate {
        WordCountEstimate(wordsAdded: wordsAdded, wordsRemoved: wordsRemoved)
    }

    /// Number of characters currently held in memory (for diagnostics/tests).
    public var bufferedCharacterCount: Int { buffer.count }

    public func ingest(_ input: KeystrokeInput) {
        switch input {
        case .characters(let text):
            for character in text { ingest(character) }
        case .newline:
            buffer.append("\n")
        case .deleteBackward:
            deleteBackward()
        case .deleteWordBackward:
            deleteWordBackward()
        case .deleteToLineStart:
            deleteToLineStart()
        case .deleteForward, .deleteWordForward, .deleteToLineEnd:
            // Forward deletions need cursor context the buffer does not have.
            break
        }
    }

    // MARK: - Private

    private func ingest(_ character: Character) {
        if character.isWhitespace || character.isNewline {
            buffer.append(character)
            return
        }
        let startsNewWord = buffer.last.map { $0.isWhitespace } ?? true
        if startsNewWord { wordsAdded += 1 }
        buffer.append(character)
    }

    private func deleteBackward() {
        guard let removed = buffer.popLast() else { return }
        guard !removed.isWhitespace else { return }
        let atBoundary = buffer.last.map { $0.isWhitespace } ?? true
        if atBoundary { wordsRemoved += 1 }
    }

    private func deleteWordBackward() {
        while let last = buffer.last, last.isWhitespace { buffer.removeLast() }
        var removedWord = false
        while let last = buffer.last, !last.isWhitespace {
            buffer.removeLast()
            removedWord = true
        }
        if removedWord { wordsRemoved += 1 }
    }

    private func deleteToLineStart() {
        var removedTokens = 0
        var inWord = false
        while let last = buffer.last, last != "\n" {
            buffer.removeLast()
            if last.isWhitespace {
                inWord = false
            } else if !inWord {
                removedTokens += 1
                inWord = true
            }
        }
        wordsRemoved += removedTokens
    }
}
