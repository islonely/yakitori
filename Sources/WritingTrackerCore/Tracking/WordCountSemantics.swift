import Foundation

/// Word-count change calculations.
///
/// The tracker distinguishes three fundamentally different measurements:
///
/// - **Net manuscript change** — the only value reliably derivable from
///   periodically sampled word counts.
/// - **Words added / removed** — only derivable from edit-level information and
///   therefore returned as `nil` when unavailable.
/// - **Active writing time** — independent of any word count.
///
/// It must never report net change as "words written".
public enum WordCountSemantics {
    public struct Change: Equatable, Sendable {
        public var startingWordCount: Int?
        public var endingWordCount: Int?
        public var netChange: Int?
        public var wordsAdded: Int?
        public var wordsRemoved: Int?

        public init(
            startingWordCount: Int? = nil,
            endingWordCount: Int? = nil,
            netChange: Int? = nil,
            wordsAdded: Int? = nil,
            wordsRemoved: Int? = nil
        ) {
            self.startingWordCount = startingWordCount
            self.endingWordCount = endingWordCount
            self.netChange = netChange
            self.wordsAdded = wordsAdded
            self.wordsRemoved = wordsRemoved
        }

        /// A human label that never overstates precision.
        public var changeLabel: String {
            netChange == nil ? "Unavailable" : "Net manuscript change"
        }

        public var hasEditLevelDetail: Bool {
            wordsAdded != nil || wordsRemoved != nil
        }
    }

    /// Computes net change from two samples.
    public static func netChange(from starting: Int?, to ending: Int?) -> Int? {
        guard let starting, let ending else { return nil }
        return ending - starting
    }

    /// Computes net change across an ordered list of word-count samples.
    public static func netChange(across samples: [Int]) -> Int? {
        guard let first = samples.first, let last = samples.last else { return nil }
        return last - first
    }

    /// Computes gross additions/deletions from consecutive samples.
    ///
    /// This is still an approximation of editing activity: a decrease is not
    /// necessarily "words removed" and an increase is not necessarily "words
    /// added" (paste, undo, redo are indistinguishable). It is only exposed when
    /// the caller explicitly requests the estimated breakdown.
    public static func estimatedGrossChange(across samples: [Int]) -> (added: Int, removed: Int)? {
        guard samples.count >= 2 else { return nil }
        var added = 0
        var removed = 0
        for index in 1..<samples.count {
            let delta = samples[index] - samples[index - 1]
            if delta > 0 { added += delta } else { removed += -delta }
        }
        return (added, removed)
    }

    public static func change(from samples: [Int]) -> Change {
        guard let first = samples.first, let last = samples.last else {
            return Change()
        }
        return Change(
            startingWordCount: first,
            endingWordCount: last,
            netChange: last - first,
            wordsAdded: nil,
            wordsRemoved: nil
        )
    }
}
