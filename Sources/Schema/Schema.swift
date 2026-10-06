import Foundation

/// Turns a raw `Input` into a typed `Output`. Never throws: the outcome is a `Result`.
public struct Schema<Input, Output, Failure: Error>: Sendable {
    public let run: @Sendable (Input) -> Result<Output, Failure>

    public init(run: @escaping @Sendable (Input) -> Result<Output, Failure>) { self.run = run }

    public func map<T>(_ transform: @escaping @Sendable (Output) -> T) -> Schema<Input, T, Failure> {
        Schema<Input, T, Failure> { run($0).map(transform) }
    }

    /// Converts and validates in one step: `nil` → `failure`. E.g. `.compactMap(.notANumber) { Double($0) }`.
    public func compactMap<T>(_ failure: Failure, _ transform: @escaping @Sendable (Output) -> T?) -> Schema<Input, T, Failure> {
        Schema<Input, T, Failure> { raw in run(raw).flatMap { transform($0).map { .success($0) } ?? .failure(failure) } }
    }

    /// Fails with `failure` when `isValid` returns false.
    public func check(_ failure: Failure, _ isValid: @escaping @Sendable (Output) -> Bool) -> Schema {
        Schema { raw in run(raw).flatMap { isValid($0) ? .success($0) : .failure(failure) } }
    }
}

/// Both directions of a field, typed once: `decode` may fail, `encode` cannot.
/// Law: `decode(encode(v)) == .success(v)`.
public struct Codec<Input, Value, Failure: Error>: Sendable {
    public let decode: Schema<Input, Value, Failure>
    public let encode: @Sendable (Value) -> Input

    public init(decode: Schema<Input, Value, Failure>, encode: @escaping @Sendable (Value) -> Input) {
        self.decode = decode
        self.encode = encode
    }
}

extension Schema where Input == Output {
    /// Start of every chain.
    public static var identity: Schema { Schema { .success($0) } }
}

// MARK: - String steps

extension Schema where Output == String {
    public func trimmed() -> Schema { map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }

    /// Empty → `failure`.
    public func nonEmpty(_ failure: Failure) -> Schema { check(failure) { !$0.isEmpty } }

    /// Empty → absent. Use for fields where blank means "not provided".
    public func nilIfEmpty() -> Schema<Input, String?, Failure> { map { $0.isEmpty ? nil : $0 } }
}

extension Schema where Output == String? {
    /// Wraps a present value; absent stays absent.
    public func map<T>(_ transform: @escaping @Sendable (String) -> T) -> Schema<Input, T?, Failure> {
        Schema<Input, T?, Failure> { run($0).map { $0.map(transform) } }
    }
}

// MARK: - Rules on a present string (absent passes through)

public protocol StringValue: SendableMetatype { var stringValue: String? { get } }
extension String: StringValue { public var stringValue: String? { self } }
extension Optional: StringValue where Wrapped == String { public var stringValue: String? { self } }

extension Schema where Output: StringValue {
    public func max(_ length: Int, _ failure: Failure) -> Schema {
        check(failure) { $0.stringValue.map { $0.count <= length } ?? true }
    }

    public func matches(_ pattern: String, _ failure: Failure) -> Schema {
        check(failure) { $0.stringValue.map { $0.range(of: pattern, options: .regularExpression) != nil } ?? true }
    }
}
