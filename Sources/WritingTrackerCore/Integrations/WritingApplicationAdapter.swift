import Foundation
import AppKit

/// A writing application integration. Adapters are intentionally small and
/// stateless; all behaviour that depends on a specific editor lives here so the
/// tracking engine stays editor-agnostic.
public protocol WritingApplicationAdapter: AnyObject {
    var adapterType: AdapterType { get }
    var bundleIdentifier: String { get }
    var capabilities: ApplicationCapabilities { get }

    func isApplicationRunning() -> Bool
    /// The document currently in focus, if the application exposes one.
    func activeDocument() -> ActiveDocumentInfo?
    /// All documents currently open in the application (empty when unsupported).
    func openDocuments() -> [ActiveDocumentInfo]
}

public extension WritingApplicationAdapter {
    func openDocuments() -> [ActiveDocumentInfo] { [] }

    func isApplicationRunning() -> Bool {
        ApplicationLocator.isRunning(bundleIdentifier: bundleIdentifier)
    }
}

/// A simple, safe, generic adapter used for any application the user selects.
/// It can detect focus/activity but never invents document or word-count data.
public class GenericApplicationAdapter: WritingApplicationAdapter {
    public let bundleIdentifier: String
    public let adapterType: AdapterType = .generic
    public let capabilities: ApplicationCapabilities = .focusAndActivityOnly

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    public func activeDocument() -> ActiveDocumentInfo? { nil }
}

/// Generic focus/activity-only adapter that still carries a specific adapter type.
public class FocusOnlyAdapter: WritingApplicationAdapter {
    public let bundleIdentifier: String
    public let adapterType: AdapterType
    public let capabilities: ApplicationCapabilities = .focusAndActivityOnly

    public init(bundleIdentifier: String, adapterType: AdapterType) {
        self.bundleIdentifier = bundleIdentifier
        self.adapterType = adapterType
    }

    public func activeDocument() -> ActiveDocumentInfo? { nil }
}

/// Base class for AppleScript-backed adapters that share the executor.
public class AppleScriptAdapter: WritingApplicationAdapter {
    public let bundleIdentifier: String
    public let adapterType: AdapterType
    public let capabilities: ApplicationCapabilities
    let executor: ScriptExecuting

    public init(
        bundleIdentifier: String,
        adapterType: AdapterType,
        capabilities: ApplicationCapabilities,
        executor: ScriptExecuting = AppleScriptExecutor()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.adapterType = adapterType
        self.capabilities = capabilities
        self.executor = executor
    }

    public func activeDocument() -> ActiveDocumentInfo? { nil }
}

// MARK: - Script execution

/// Abstraction over AppleScript execution so adapters can be unit tested
/// without the target application installed.
public protocol ScriptExecuting {
    /// Executes a script and returns its string result, or throws on failure.
    func execute(_ script: String) throws -> String?
}

public enum ScriptError: Error, Equatable {
    case notRunning
    case permissionDenied
    case executionFailed(Int)
    case emptyResult
}

public final class AppleScriptExecutor: ScriptExecuting {
    public init() {}

    public func execute(_ script: String) throws -> String? {
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw ScriptError.executionFailed(-1)
        }
        let result = appleScript.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? -1
            if code == -1743 { throw ScriptError.permissionDenied }
            throw ScriptError.executionFailed(code)
        }
        return result.stringValue
    }
}

/// Locates applications on disk without launching them.
public enum ApplicationLocator {
    public static func isRunning(bundleIdentifier: String) -> Bool {
        !NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleIdentifier
        }.isEmpty
    }

    public static func url(forBundleIdentifier bundleIdentifier: String) -> URL? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return url
    }

    public static func isInstalled(bundleIdentifier: String) -> Bool {
        url(forBundleIdentifier: bundleIdentifier) != nil
    }

    public static func displayName(forBundleIdentifier bundleIdentifier: String) -> String? {
        guard let url = url(forBundleIdentifier: bundleIdentifier) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.replacingOccurrences(of: ".app", with: "")
    }
}

// MARK: - Registry

/// Resolves the correct adapter for a bundle identifier.
public final class AdapterRegistry {
    public static let shared = AdapterRegistry()

    /// Known writing applications the tracker can offer during onboarding.
    public static let knownApplications: [(bundleIdentifier: String, displayName: String, adapterType: AdapterType)] = [
        ("com.microsoft.Word", "Microsoft Word", .word),
        ("com.literatureandlatte.scrivener3", "Scrivener", .scrivener),
        ("com.literatureandlatte.scrivener", "Scrivener", .scrivener),
        ("com.apple.iWork.Pages", "Pages", .pages),
        ("com.ulyssesapp.mac", "Ulysses", .ulysses),
        ("org.libreoffice.script", "LibreOffice", .libreOffice),
        ("md.obsidian", "Obsidian", .obsidian),
        ("com.apple.Safari", "Safari", .browser),
        ("com.google.Chrome", "Google Chrome", .browser),
        ("com.brave.Browser", "Brave Browser", .browser),
        ("com.microsoft.edgemac", "Microsoft Edge", .browser),
        ("org.mozilla.firefox", "Firefox", .browser)
    ]

    private let executor: ScriptExecuting

    public init(executor: ScriptExecuting = AppleScriptExecutor()) {
        self.executor = executor
    }

    public func adapter(forBundleIdentifier bundleIdentifier: String, adapterType: AdapterType? = nil) -> WritingApplicationAdapter {
        let type = adapterType ?? Self.defaultAdapterType(forBundleIdentifier: bundleIdentifier)
        switch type {
        case .word:
            return WordAdapter(bundleIdentifier: bundleIdentifier, executor: executor)
        case .pages:
            return PagesAdapter(bundleIdentifier: bundleIdentifier, executor: executor)
        case .scrivener:
            return ScrivenerAdapter(bundleIdentifier: bundleIdentifier)
        case .ulysses:
            return UlyssesAdapter(bundleIdentifier: bundleIdentifier)
        case .libreOffice:
            return LibreOfficeAdapter(bundleIdentifier: bundleIdentifier)
        case .obsidian:
            return ObsidianAdapter(bundleIdentifier: bundleIdentifier)
        case .browser:
            return BrowserDocumentAdapter(bundleIdentifier: bundleIdentifier)
        case .generic:
            return GenericApplicationAdapter(bundleIdentifier: bundleIdentifier)
        }
    }

    public static func defaultAdapterType(forBundleIdentifier bundleIdentifier: String) -> AdapterType {
        switch bundleIdentifier {
        case "com.microsoft.Word": return .word
        case "com.literatureandlatte.scrivener3", "com.literatureandlatte.scrivener": return .scrivener
        case "com.apple.iWork.Pages": return .pages
        case "com.ulyssesapp.mac": return .ulysses
        case "org.libreoffice.script": return .libreOffice
        case "md.obsidian": return .obsidian
        case "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "org.mozilla.firefox":
            return .browser
        default: return .generic
        }
    }

    /// Applications that are installed and known to be writing applications.
    public func detectedApplications() -> [(bundleIdentifier: String, displayName: String, adapterType: AdapterType)] {
        Self.knownApplications.filter { ApplicationLocator.isInstalled(bundleIdentifier: $0.bundleIdentifier) }
    }
}
