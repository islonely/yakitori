import Foundation

/// First-class Microsoft Word for Mac adapter.
///
/// Verified against Word for Mac 16.111 using AppleScript:
/// - `name of active document`
/// - `full name of active document` (POSIX path or OneDrive URL)
/// - `compute statistics active document statistic statistic words|characters|pages`
///
/// Word is never launched by the adapter: the running-application check happens
/// first, and automation errors (including permission denial -1743) degrade
/// gracefully rather than being reported as real word counts.
public final class WordAdapter: AppleScriptAdapter {
    public init(bundleIdentifier: String = "com.microsoft.Word", executor: ScriptExecuting = AppleScriptExecutor()) {
        super.init(
            bundleIdentifier: bundleIdentifier,
            adapterType: .word,
            capabilities: .documentAndWordCount,
            executor: executor
        )
    }

    private static let documentScript = """
    tell application "Microsoft Word"
        if (count of documents) is 0 then return "NO_DOC"
        set d to active document
        set dName to name of d
        set dPath to full name of d
        set isSaved to saved of d
        set wc to compute statistics d statistic statistic words
        set cc to compute statistics d statistic statistic characters
        set pc to compute statistics d statistic statistic pages
        return dName & "|||" & dPath & "|||" & (wc as string) & "|||" & (cc as string) & "|||" & (pc as string) & "|||" & (isSaved as string)
    end tell
    """

    private static let openDocumentsScript = """
    tell application "Microsoft Word"
        set output to ""
        repeat with d in documents
            set output to output & (name of d) & "|||" & (full name of d) & linefeed
        end repeat
        return output
    end tell
    """

    public override func activeDocument() -> ActiveDocumentInfo? {
        guard isApplicationRunning() else { return nil }
        do {
            guard let raw = try executor.execute(Self.documentScript), raw != "NO_DOC" else {
                return nil
            }
            return Self.parseDocumentLine(raw)
        } catch {
            Log.integrations.debug("Word active document unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public func openDocuments() -> [ActiveDocumentInfo] {
        guard isApplicationRunning() else { return [] }
        do {
            guard let raw = try executor.execute(Self.openDocumentsScript) else { return [] }
            return raw
                .split(separator: "\n")
                .compactMap { Self.parseDocumentLine(String($0), includeStats: false) }
        } catch {
            return []
        }
    }

    static func parseDocumentLine(_ line: String, includeStats: Bool = true) -> ActiveDocumentInfo? {
        let parts = line.components(separatedBy: "|||")
        guard parts.count >= 2, !parts[0].isEmpty else { return nil }
        let name = parts[0]
        let path = parts[1].isEmpty ? nil : parts[1]
        var words: Int?
        var characters: Int?
        var pages: Int?
        if includeStats, parts.count >= 5 {
            words = Int(parts[2].trimmingCharacters(in: .whitespaces))
            characters = Int(parts[3].trimmingCharacters(in: .whitespaces))
            pages = Int(parts[4].trimmingCharacters(in: .whitespaces))
        }
        return ActiveDocumentInfo(
            displayName: name,
            stableIdentifier: path,
            filePath: path,
            wordCount: words,
            characterCount: characters,
            pageCount: pages
        )
    }
}
