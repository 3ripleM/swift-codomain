import Foundation

// MARK: - Transforms

extension Schema where Output == String {
    public func trimmed() -> Schema { map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
    public func lowercased() -> Schema { map { $0.lowercased() } }
    public func uppercased() -> Schema { map { $0.uppercased() } }

    /// Empty → `failure`.
    public func nonEmpty(_ failure: Failure) -> Schema { refine(failure) { !$0.isEmpty } }

    /// Empty → absent. Use for fields where blank means "not provided".
    public func nilIfEmpty() -> Schema<Input, String?, Failure> { map { $0.isEmpty ? nil : $0 } }
}

extension Schema where Output == String? {
    /// Wraps a present value; absent stays absent.
    public func map<T>(_ transform: @escaping @Sendable (String) -> T) -> Schema<Input, T?, Failure> {
        map { $0.map(transform) }
    }
}

// MARK: - Checks on a present string (absent passes through)

public protocol StringValue: SendableMetatype { var stringValue: String? { get } }
extension String: StringValue { public var stringValue: String? { self } }
extension Optional: StringValue where Wrapped == String { public var stringValue: String? { self } }

public enum IPVersion: Sendable { case v4, v6 }

extension Schema where Output: StringValue {
    /// Lengths count characters as people see them: `"👩‍👩‍👧"` is 1.
    public func min(_ length: Int, _ failure: Failure) -> Schema {
        present(failure) { $0.count >= length }
    }
    public func max(_ length: Int, _ failure: Failure) -> Schema {
        present(failure) { $0.count <= length }
    }
    public func length(_ length: Int, _ failure: Failure) -> Schema {
        present(failure) { $0.count == length }
    }

    public func startsWith(_ prefix: String, _ failure: Failure) -> Schema {
        present(failure) { $0.hasPrefix(prefix) }
    }
    public func endsWith(_ suffix: String, _ failure: Failure) -> Schema {
        present(failure) { $0.hasSuffix(suffix) }
    }
    public func includes(_ part: String, _ failure: Failure) -> Schema {
        present(failure) { $0.contains(part) }
    }

    /// `local@domain.tld`, no whitespace, one `@`. A shape check: deliverability needs an email.
    public func email(_ failure: Failure) -> Schema {
        present(failure) { $0.wholeMatch(of: #/[^@\s]+@[^@\s.]+(\.[^@\s.]+)+/#) != nil }
    }

    /// `http` or `https` with a host.
    public func url(_ failure: Failure) -> Schema {
        present(failure) {
            guard let url = URL(string: $0), let scheme = url.scheme?.lowercased() else { return false }
            return ["http", "https"].contains(scheme) && url.host?.isEmpty == false
        }
    }

    /// `8-4-4-4-12` hex digits, any case.
    public func uuid(_ failure: Failure) -> Schema {
        present(failure) { UUID(uuidString: $0) != nil }
    }

    /// ISO 8601 date and time with `Z` or an offset, optional fractional seconds: `2026-10-05T12:00:00Z`.
    /// Impossible dates such as `2026-02-30` fail.
    public func datetime(_ failure: Failure) -> Schema {
        present(failure) { raw in
            guard (try? Date.ISO8601FormatStyle().parse(raw)) != nil,
                let day = raw.prefixMatch(of: #/(\d{4})-(\d{2})-(\d{2})T/#)
            else { return false }
            return DateComponents(
                calendar: Calendar(identifier: .gregorian), year: Int(day.1), month: Int(day.2),
                day: Int(day.3)
            ).isValidDate
        }
    }

    /// IPv4 (`192.168.0.1`) or IPv6 (`::1`); `version` limits it to one.
    public func ip(_ failure: Failure, version: IPVersion? = nil) -> Schema {
        present(failure) { raw in
            var address = [UInt8](repeating: 0, count: 16)
            func parses(_ family: Int32) -> Bool {
                raw.withCString { inet_pton(family, $0, &address) } == 1
            }
            switch version {
            case .v4: return parses(AF_INET)
            case .v6: return parses(AF_INET6)
            case nil: return parses(AF_INET) || parses(AF_INET6)
            }
        }
    }

    private func present(_ failure: Failure, _ isValid: @escaping @Sendable (String) -> Bool)
        -> Schema
    {
        refine(failure) { $0.stringValue.map(isValid) ?? true }
    }
}
