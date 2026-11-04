import Foundation

/// Validation error for a configuration value.
public struct ConfigError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Validation rules. Values passed as SSH arguments must never begin with `-`
/// (prevents option injection such as `-oProxyCommand=...`).
public enum Validation {
    public static func isValidHost(_ s: String) -> Bool {
        isSafeToken(s, extra: "._:[]%/-", maxLength: 253)
    }

    /// Simple hostname eligible for standard `ssh://` URLs.
    public static func isSimpleHostname(_ s: String) -> Bool {
        isSafeToken(s, extra: "._-", maxLength: 253)
    }

    public static func isValidUser(_ s: String) -> Bool {
        isSafeToken(s, extra: "._-", maxLength: 64)
    }

    /// `ssh -J` jump host format: `[user@]host[:port][,...]`.
    public static func isValidJumpHost(_ s: String) -> Bool {
        isSafeToken(s, extra: "._:@[]%,-", maxLength: 512)
    }

    public static func isValidPort(_ p: Int) -> Bool { (1...65535).contains(p) }

    public static func isValidPath(_ s: String) -> Bool {
        !s.isEmpty && !s.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func isSafeToken(_ s: String, extra: String, maxLength: Int) -> Bool {
        guard !s.isEmpty, s.count <= maxLength, !s.hasPrefix("-") else { return false }
        let extras = Set(extra.unicodeScalars)
        return s.unicodeScalars.allSatisfy { scalar in
            (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) || extras.contains(scalar)
        }
    }
}
