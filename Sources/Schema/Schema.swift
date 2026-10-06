import Foundation

/// Turns a raw `Input` into a typed `Output`. Never throws: the outcome is a `Result`.
public struct Schema<Input, Output, Failure: Error>: Sendable {
    /// Every failure, in order; never empty on failure. More than one only after `collect`.
    let runAll: @Sendable (Input) -> Result<Output, FailureList<Failure>>

    public init(run: @escaping @Sendable (Input) -> Result<Output, Failure>) {
        runAll = { run($0).mapError { FailureList(all: [$0]) } }
    }

    private init(
        all runAll: @escaping @Sendable (Input) -> Result<Output, FailureList<Failure>>, _: Void
    ) { self.runAll = runAll }

    static func all(_ runAll: @escaping @Sendable (Input) -> Result<Output, FailureList<Failure>>)
        -> Schema
    {
        Schema(all: runAll, ())
    }

    /// The first failure only; `parse` and `decode(json:)` report all of them.
    public func run(_ input: Input) -> Result<Output, Failure> {
        runAll(input).mapError { $0.all[0] }
    }

    public func map<T>(_ transform: @escaping @Sendable (Output) -> T) -> Schema<Input, T, Failure> {
        .all { runAll($0).map(transform) }
    }

    /// Converts and validates in one step: `nil` → `failure`. E.g. `.compactMap(.notANumber) { Double($0) }`.
    public func compactMap<T>(_ failure: Failure, _ transform: @escaping @Sendable (Output) -> T?)
        -> Schema<Input, T, Failure>
    {
        .all { raw in
            runAll(raw).flatMap {
                transform($0).map { .success($0) } ?? .failure(FailureList(all: [failure]))
            }
        }
    }

    /// Fails with `failure` when `isValid` returns false.
    public func refine(_ failure: Failure, _ isValid: @escaping @Sendable (Output) -> Bool) -> Schema {
        compactMap(failure) { isValid($0) ? $0 : nil }
    }

    /// Runs every check on the same value and keeps every failure. When all pass, the output is the
    /// last check's output, so put transforms before `collect` unless the last check makes them.
    /// E.g. `.collect({ $0.min(8, .tooShort) }, { $0.refine(.noDigit) { $0.contains(where: \.isNumber) } })`.
    public func collect(
        _ checks: (Schema<Output, Output, Failure>) -> Schema<Output, Output, Failure>...
    ) -> Schema where Output: Sendable {
        let built = checks.map { $0(.all { .success($0) }) }
        return .all { raw in
            runAll(raw).flatMap { value in
                var output = value
                var failures: [Failure] = []
                for check in built {
                    switch check.runAll(value) {
                    case .success(let checked): output = checked
                    case .failure(let failed): failures += failed.all
                    }
                }
                return failures.isEmpty ? .success(output) : .failure(FailureList(all: failures))
            }
        }
    }
}

/// Every failure of one run, in order; never empty.
struct FailureList<F: Error>: Error {
    let all: [F]
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
