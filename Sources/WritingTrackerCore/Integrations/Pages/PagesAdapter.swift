import Foundation

/// Apple Pages adapter.
///
/// Verified against Pages on macOS 26: `count of words of body text` returns the
/// document's word count and `count of characters of body text` its character
/// count. Pages has no dedicated "compute statistics" command, so the counts are
/// derived from the body text (headers, footers and text boxes are not included).
///
/// Pages is never launched by the adapter: `isApplicationRunning()` is checked
/// first and scripting errors degrade to "unavailable".
public final class PagesAdapter: AppleScriptAdapter {
    public init(bundleIdentifier: String = "com.apple.iWork.Pages", executor: ScriptExecuting = AppleScriptExecutor()) {
        super.init(
            bundleIdentifier: bundleIdentifier,
            adapterType: .pages,
            capabilities: ApplicationCapabilities(
                activeDocument: true,
                documentPath: true,
                wordCount: true,
                textAccess: false,
                projectDetection: false,
                changeDetection: false
            ),
            executor: executor
        )
    }

    private static let documentScript = """
    tell application "Pages"
        if (count of documents) is 0 then return "NO_DOC"
        set d to front document
        set dName to name of d
        set dPath to ""
        try
            set dPath to POSIX path of (file of d as alias)
        end try
        set wc to count of words of body text of d
        set cc to count of characters of body text of d
        return dName & "|||" & dPath & "|||" & (wc as string) & "|||" & (cc as string)
    end tell
    """

    public override func activeDocument() -> ActiveDocumentInfo? {
        guard isApplicationRunning() else { return nil }
        do {
            guard let raw = try executor.execute(Self.documentScript), raw != "NO_DOC" else { return nil }
            return Self.parseDocumentLine(raw)
        } catch {
            Log.integrations.debug("Pages active document unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    static func parseDocumentLine(_ line: String) -> ActiveDocumentInfo? {
        let parts = line.components(separatedBy: "|||")
        guard parts.count >= 2, !parts[0].isEmpty else { return nil }
        let name = parts[0]
        let path = parts[1].isEmpty ? nil : parts[1]
        var words: Int?
        var characters: Int?
        if parts.count >= 4 {
            words = Int(parts[2].trimmingCharacters(in: .whitespaces))
            characters = Int(parts[3].trimmingCharacters(in: .whitespaces))
        }
        return ActiveDocumentInfo(
            displayName: name,
            stableIdentifier: path,
            filePath: path,
            wordCount: words,
            characterCount: characters
        )
    }
}
