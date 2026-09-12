import Foundation

/// Stores security-scoped bookmarks for user-selected files and folders.
///
/// The tracker never requests Full Disk Access; it only keeps access to
/// locations the user explicitly chose through `NSOpenPanel`.
public final class FileAccessBookmarkStore {
    public static let shared = FileAccessBookmarkStore()

    private let defaultsKey = "com.writingtracker.fileBookmarks"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public struct Entry: Codable, Hashable {
        public let id: String
        public let displayName: String
        public let path: String
        public let bookmark: Data
    }

    public var hasAnyBookmark: Bool {
        !load().isEmpty
    }

    public func all() -> [Entry] {
        load()
    }

    @discardableResult
    public func add(url: URL) -> Entry? {
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return nil
        }
        let entry = Entry(
            id: UUID().uuidString,
            displayName: url.lastPathComponent,
            path: url.path,
            bookmark: data
        )
        var entries = load()
        entries.removeAll { $0.path == entry.path }
        entries.append(entry)
        save(entries)
        return entry
    }

    public func remove(id: String) {
        var entries = load()
        entries.removeAll { $0.id == id }
        save(entries)
    }

    /// Resolves a bookmark and begins security-scoped access. The caller must
    /// balance this with `stopAccessing` when finished.
    public func resolve(_ entry: Entry) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: entry.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        if stale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var entries = load()
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = Entry(id: entry.id, displayName: entry.displayName, path: entry.path, bookmark: refreshed)
                save(entries)
            }
        }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    private func load() -> [Entry] {
        guard let data = userDefaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: defaultsKey)
    }
}
