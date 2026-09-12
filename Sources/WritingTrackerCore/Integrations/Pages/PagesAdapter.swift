import Foundation

/// Apple Pages adapter. Pages exposes document identity via AppleScript but
/// does not provide a cheap, reliable word-count command, so the adapter
/// honestly reports document-only capabilities.
///
/// Script verified structure against the Pages AppleScript dictionary:
/// `front document`, `name of doc`, `file of doc`.
public final class PagesAdapter: AppleScriptAdapter {
    public init(bundleIdentifier: String = "com.apple.iWork.Pages", executor: ScriptExecuting = AppleScriptExecutor()) {
        super.init(
            bundleIdentifier: bundleIdentifier,
            adapterType: .pages,
            capabilities: .documentOnly,
            executor: executor
        )
    }

    private static let script = """
    tell application "Pages"
        if (count of documents) is 0 then return "NO_DOC"
        set d to front document
        set dName to name of d
        set dPath to ""
        try
            set dPath to POSIX path of (file of d as alias)
        end try
        return dName & "|||" & dPath
    end tell
    """

    public override func activeDocument() -> ActiveDocumentInfo? {
        guard isApplicationRunning() else { return nil }
        do {
            guard let raw = try executor.execute(Self.script), raw != "NO_DOC" else { return nil }
            let parts = raw.components(separatedBy: "|||")
            guard let name = parts.first, !name.isEmpty else { return nil }
            let path = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
            return ActiveDocumentInfo(displayName: name, stableIdentifier: path, filePath: path)
        } catch {
            return nil
        }
    }
}
