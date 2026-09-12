import Foundation

/// Decides whether a finished session is worth persisting.
///
/// Rule: sessions that produced **no added words** are not recorded. For
/// applications that report a word count, this means a session whose manuscript
/// did not change (net word change of zero) is discarded. Applications without a
/// word count (time-only) are still recorded when they have meaningful activity,
/// because there is no word signal to apply the rule to.
public enum SessionRecordingPolicy {
    public static func hasWordCountData(_ session: Session) -> Bool {
        session.startingWordCount != nil
            || session.endingWordCount != nil
            || session.netWordChange != nil
            || session.wordsAdded != nil
            || session.wordsRemoved != nil
    }

    /// True when the session adds (or removes) words, or, for time-only sessions,
    /// when it contains real activity.
    public static func shouldRecord(_ session: Session) -> Bool {
        if hasWordCountData(session) {
            let net = session.netWordChange ?? 0
            let added = session.wordsAdded ?? 0
            let removed = session.wordsRemoved ?? 0
            return net != 0 || added > 0 || removed > 0
        }
        return session.activeSeconds >= 1 || session.focusSeconds >= 1
    }

    public static let zeroWordRejectionMessage =
        "A session must add or remove at least one word to be recorded."
}
