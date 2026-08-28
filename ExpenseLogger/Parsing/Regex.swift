import Foundation

/// Thin wrapper over `NSRegularExpression` with named-group access.
///
/// Patterns passed here are compile-time constants exercised by
/// `ExpenseParserTests`; an invalid one is a programmer error, so the
/// initialiser traps rather than propagating a failure into every call site.
struct Rx: @unchecked Sendable {
    private let regex: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("invalid regex \(pattern): \(error)")
        }
    }

    func firstMatch(in text: NSString, from location: Int = 0) -> RxMatch? {
        let range = NSRange(location: location, length: text.length - location)
        guard let result = regex.firstMatch(in: text as String, range: range) else { return nil }
        return RxMatch(result: result, source: text)
    }

    func matches(in text: NSString, from location: Int = 0) -> [RxMatch] {
        let range = NSRange(location: location, length: text.length - location)
        return regex.matches(in: text as String, range: range)
            .map { RxMatch(result: $0, source: text) }
    }

    func containsMatch(in text: NSString) -> Bool { firstMatch(in: text) != nil }
}

struct RxMatch {
    let result: NSTextCheckingResult
    let source: NSString

    var range: NSRange { result.range }
    var start: Int { result.range.location }
    var end: Int { result.range.location + result.range.length }

    func group(_ name: String) -> String? {
        let range = result.range(withName: name)
        guard range.location != NSNotFound else { return nil }
        return source.substring(with: range)
    }

    func group(_ index: Int) -> String? {
        guard index < result.numberOfRanges else { return nil }
        let range = result.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return source.substring(with: range)
    }
}
