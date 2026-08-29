import Foundation

/// Where the log file lives.
///
/// By default it is the app's own Documents folder. When the Mac bridge is doing
/// the capturing, the log is a file in iCloud Drive instead — the user points
/// the app at it once, and a security-scoped bookmark keeps that access across
/// launches.
enum LogLocation {
    private static let bookmarkKey = "externalLogBookmark"
    private static let nameKey = "externalLogName"

    static var isExternal: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Display name of the chosen file, for the settings screen.
    static var externalName: String? {
        UserDefaults.standard.string(forKey: nameKey)
    }

    static func remember(_ url: URL) throws {
        let data = try withAccess(url) { try url.bookmarkData() }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    /// The chosen file, or nil when the default location is in use.
    static func externalURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        // A moved or re-synced file invalidates the bookmark; refresh it in place.
        if isStale, let refreshed = try? withAccess(url, { try url.bookmarkData() }) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }

    /// Runs `body` inside the URL's security scope.
    static func withAccess<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    /// Asks iCloud for the file's contents if only a placeholder is present.
    static func requestDownloadIfNeeded(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
