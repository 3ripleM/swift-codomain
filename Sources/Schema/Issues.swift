/// Every failure, in declaration order, each with its path (`email`, `address.city`, `phones[1].number`).
/// Within one field the chain stops at its first failure.
public struct Issues<Failure: Error>: Error {
    public struct Issue: Sendable {
        public let path: String
        public let failure: Failure

        public init(path: String, failure: Failure) {
            self.path = path
            self.failure = failure
        }
    }

    public let all: [Issue]

    public init(_ all: [Issue]) { self.all = all }
    public init(_ path: String, _ failure: Failure) { all = [Issue(path: path, failure: failure)] }

    /// `city` under `address` → `address.city`; `[1]` under `phones` → `phones[1]`.
    func prefixed(_ prefix: String) -> [Issue] {
        all.map { issue in
            let separator = issue.path.isEmpty || issue.path.hasPrefix("[") ? "" : "."
            return Issue(path: prefix + separator + issue.path, failure: issue.failure)
        }
    }
}

extension Issues.Issue: Equatable where Failure: Equatable {}
extension Issues: Equatable where Failure: Equatable {}

extension Issues: CustomStringConvertible {
    public var description: String { all.map { "\($0.path): \($0.failure)" }.joined(separator: ", ") }
}

/// Used by `@Schema`'s generated `init(parsing:)`: parses every field, keeps every failure.
public struct IssueCollector<Failure: Error> {
    public private(set) var issues: [Issues<Failure>.Issue] = []

    public init() {}

    /// `nil` when the field failed (its issues are recorded).
    public mutating func required<T: Parsable>(_ path: String, _ raw: T.Input, as: T.Type) -> T?
    where T.Failure == Failure {
        switch T.parse(raw) {
        case .success(let value): return value
        case .failure(let failed): issues += failed.prefixed(path); return nil
        }
    }

    /// Outer `nil` when the field failed; absent input → `.some(nil)`.
    public mutating func optional<T: Parsable>(_ path: String, _ raw: T.Input?, as: T.Type) -> T??
    where T.Failure == Failure {
        guard let raw else { return .some(nil) }
        return required(path, raw, as: T.self).map { $0 }
    }

    public mutating func optional<T: OptionalField>(_ path: String, _ raw: T.Input?, as: T.Type) -> T??
    where T.Failure == Failure {
        guard let raw else { return .some(nil) }
        switch T.mk(raw) {
        case .success(let value): return .some(value)
        case .failure(let failure): issues.append(.init(path: path, failure: failure)); return nil
        }
    }
}
