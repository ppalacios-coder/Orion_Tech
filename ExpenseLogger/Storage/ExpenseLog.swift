import Foundation

/// Owns the log file: appends parsed notifications, drops duplicates, and reads
/// entries back for the UI. Serialised as an actor because App Intents can fire
/// concurrently with the app being open.
actor ExpenseLog {
    static let shared = ExpenseLog()

    /// What happened to a notification handed to `append`.
    enum Outcome: Sendable {
        case logged(line: String)
        case duplicate
        case lowConfidence(Double)
        case ignored(reason: String)
        case unparsed(reason: String)

        var wasLogged: Bool { if case .logged = self { return true } else { return false } }

        var summary: String {
            switch self {
            case .logged(let line): "Logged: \(line)"
            case .duplicate: "Duplicate — already logged"
            case .lowConfidence(let value): "Low confidence (\(String(format: "%.2f", value))) — sent to review"
            case .ignored(let reason): "Ignored (\(reason))"
            case .unparsed(let reason): "Could not read an amount (\(reason))"
            }
        }
    }

    enum LogError: LocalizedError {
        case cannotWrite(String)
        var errorDescription: String? {
            switch self {
            case .cannotWrite(let path): "Could not write to \(path)"
            }
        }
    }

    // MARK: - Locations

    /// Documents, so the file shows up in Files ▸ On My iPhone ▸ Expense Logger.
    nonisolated var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// The file the Mac bridge writes, when one has been chosen; otherwise the
    /// app's own file in Documents.
    nonisolated var fileURL: URL {
        LogLocation.externalURL() ?? documentsDirectory.appendingPathComponent(AppSettings.fileName)
    }

    /// Anything rejected lands here rather than disappearing.
    /// Always local: rejected notifications are the app's own bookkeeping.
    nonisolated var reviewFileURL: URL {
        let name = AppSettings.fileName
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return documentsDirectory.appendingPathComponent("\(base).review.\(ext.isEmpty ? "txt" : ext)")
    }

    private var dedupeStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("recent-keys.json")
    }

    // MARK: - Appending

    @discardableResult
    func append(_ expense: ParsedExpense) throws -> Outcome {
        let format = AppSettings.format

        switch expense.kind {
        case .ignored:
            try appendToReview(expense, format: format)
            return .ignored(reason: expense.reason ?? "rule")
        case .unparsed:
            try appendToReview(expense, format: format)
            return .unparsed(reason: expense.reason ?? "unknown")
        case .expense, .credit:
            break
        }

        guard expense.confidence >= AppSettings.minimumConfidence else {
            try appendToReview(expense, format: format)
            return .lowConfidence(expense.confidence)
        }

        if isDuplicate(expense) { return .duplicate }

        let line = LogLine.render(expense, format: format)
        try appendLine(line, to: fileURL, header: format.header)
        remember(expense)
        return .logged(line: line)
    }

    private func appendToReview(_ expense: ParsedExpense, format: LogFormat) throws {
        guard AppSettings.keepRejected else { return }
        let url = reviewFileURL
        let reason = expense.reason ?? expense.kind.rawValue
        let line = "\(LogLine.timestamp(expense.receivedAt))\t[\(expense.kind.rawValue):\(reason)]\t" +
            expense.raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        try Self.rawAppend(line, to: url, header: nil)
    }

    /// Wraps file work in a security scope and NSFileCoordinator when the file
    /// is outside the sandbox. Plain file access is used for our own Documents.
    private func coordinated<T>(_ url: URL, writing: Bool, _ body: (URL) throws -> T) throws -> T {
        guard LogLocation.isExternal else { return try body(url) }

        return try LogLocation.withAccess(url) {
            var result: T?
            var thrown: Error?
            var coordinationError: NSError?
            let coordinator = NSFileCoordinator()
            let handler: (URL) -> Void = { actual in
                do { result = try body(actual) } catch { thrown = error }
            }
            if writing {
                coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError, byAccessor: handler)
            } else {
                coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError, byAccessor: handler)
            }
            if let thrown { throw thrown }
            if let coordinationError { throw coordinationError }
            guard let result else { throw LogError.cannotWrite(url.lastPathComponent) }
            return result
        }
    }

    private func appendLine(_ line: String, to url: URL, header: String?) throws {
        try coordinated(url, writing: true) { target in
            try Self.rawAppend(line, to: target, header: header)
        }
    }

    private static func rawAppend(_ line: String, to url: URL, header: String?) throws {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: url.path) {
            var contents = ""
            if let header { contents += header + "\n" }
            contents += line + "\n"
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw LogError.cannotWrite(url.lastPathComponent)
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        guard let data = (line + "\n").data(using: .utf8) else {
            throw LogError.cannotWrite(url.lastPathComponent)
        }
        try handle.write(contentsOf: data)
    }

    // MARK: - Duplicate suppression

    private func recentKeys() -> [String: TimeInterval] {
        guard let data = try? Data(contentsOf: dedupeStoreURL),
              let stored = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
        else { return [:] }
        return stored
    }

    private func isDuplicate(_ expense: ParsedExpense) -> Bool {
        guard let seenAt = recentKeys()[expense.dedupeKey] else { return false }
        return expense.receivedAt.timeIntervalSince1970 - seenAt < AppSettings.dedupeWindow
    }

    private func remember(_ expense: ParsedExpense) {
        var keys = recentKeys()
        let now = expense.receivedAt.timeIntervalSince1970
        keys[expense.dedupeKey] = now
        // Keep the store small: drop anything well outside the window.
        let cutoff = now - max(AppSettings.dedupeWindow * 10, 3600)
        keys = keys.filter { $0.value >= cutoff }
        if let data = try? JSONEncoder().encode(keys) {
            try? data.write(to: dedupeStoreURL, options: .atomic)
        }
    }

    // MARK: - Reading

    func rawContents() -> String {
        let url = fileURL
        if LogLocation.isExternal { LogLocation.requestDownloadIfNeeded(url) }
        let read = try? coordinated(url, writing: false) { target in
            (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        }
        return read ?? ""
    }

    func entries(limit: Int = 500) -> [LoggedEntry] {
        let format = AppSettings.format
        let parsed = rawContents()
            .components(separatedBy: .newlines)
            .compactMap { LogLine.parse($0, format: format) }
        return Array(parsed.suffix(limit).reversed())
    }

    func reviewContents() -> String {
        (try? String(contentsOf: reviewFileURL, encoding: .utf8)) ?? ""
    }

    func fileSize() -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? Int) ?? 0
    }

    // MARK: - Maintenance

    /// Only ever deletes files the app owns — an external log chosen by the
    /// user is left alone, since the Mac bridge is still writing to it.
    func clear() throws {
        var owned = [reviewFileURL]
        if !LogLocation.isExternal { owned.append(fileURL) }
        for url in owned where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: dedupeStoreURL)
    }
}
