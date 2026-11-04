import Foundation

/// Non-fatal warning encountered while parsing configuration.
public struct ConfigIssue: Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// Collects decoding issues safely across threads.
public final class IssueCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ConfigIssue] = []

    public init() {}

    public var issues: [ConfigIssue] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func add(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(ConfigIssue(message))
    }
}

extension CodingUserInfoKey {
    static let issueCollector = CodingUserInfoKey(rawValue: "openshuttler.issueCollector")!
}

/// Dummy consumer to skip invalid entries without aborting.
private struct Discard: Decodable {}

extension UnkeyedDecodingContainer {
    /// Decodes elements lossily: invalid entries become warnings instead of failing the whole list.
    mutating func decodeLossy<T: Decodable>(
        _ type: T.Type,
        label: String,
        collector: IssueCollector?
    ) -> [T] {
        var result: [T] = []
        while !isAtEnd {
            let index = currentIndex
            do {
                result.append(try decode(T.self))
            } catch {
                collector?.add("\(label), item \(index + 1): \(ErrorDescriber.describe(error))")
                if (try? decode(Discard.self)) == nil || currentIndex == index { break }
            }
        }
        return result
    }
}

enum ErrorDescriber {
    static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .dataCorrupted(let ctx):
            if let ns = ctx.underlyingError as NSError?,
               let detail = ns.userInfo["NSDebugDescription"] as? String {
                return detail
            }
            return ctx.debugDescription
        case .keyNotFound(let key, _):
            return "missing required key: '\(key.stringValue)'"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "invalid value (\(ctx.debugDescription))"
        @unknown default:
            return "\(decoding)"
        }
    }
}
