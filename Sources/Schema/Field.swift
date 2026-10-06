/// Anything `@Schema` can hold: a `@Codec` field, a `@Schema` struct, or an array of either.
/// `parse` reports every failure with its path; `encoded` goes back to the raw input.
/// `Sendable`, so parsed values and raw inputs cross actors.
public protocol Parsable: Sendable {
    associatedtype Input: Sendable
    associatedtype Failure: Error
    static func parse(_ input: Input) -> Result<Self, Issues<Failure>>
    var encoded: Input { get }
}

/// Every element is parsed; failures are reported as `[index]`.
extension Array: Parsable where Element: Parsable {
    public static func parse(_ input: [Element.Input]) -> Result<[Element], Issues<Element.Failure>> {
        var collector = IssueCollector<Element.Failure>()
        let values = input.enumerated().map {
            collector.required("[\($0.offset)]", $0.element, as: Element.self, lift: { $0 })
        }
        guard collector.issues.isEmpty else { return .failure(Issues(collector.issues)) }
        return .success(values.map { $0! })
    }

    public var encoded: [Element.Input] { map(\.encoded) }
}

/// Every value is parsed; failures are reported as `["key"]`, in key order.
extension Dictionary: Parsable where Key == String, Value: Parsable {
    public static func parse(_ input: [String: Value.Input]) -> Result<
        [String: Value], Issues<Value.Failure>
    > {
        var collector = IssueCollector<Value.Failure>()
        let values = input.sorted { $0.key < $1.key }.map {
            ($0.key, collector.required(keyPath($0.key), $0.value, as: Value.self, lift: { $0 }))
        }
        guard collector.issues.isEmpty else { return .failure(Issues(collector.issues)) }
        return .success(Dictionary(uniqueKeysWithValues: values.map { ($0.0, $0.1!) }))
    }

    public var encoded: [String: Value.Input] { mapValues(\.encoded) }
}

/// `work` → `["work"]`, quotes and backslashes escaped.
func keyPath(_ key: String) -> String { "[\(String(reflecting: key))]" }

/// A field whose schema always produces a value. A codec: `schema` decodes, `encoded` encodes.
/// Law: decoding `encoded` gives back the same value.
public protocol Field: Parsable, JSONReadable {
    static var schema: Schema<Input, Self, Failure> { get }
    var encoded: Input { get }
}

/// A field whose schema may decide "absent" (e.g. `nilIfEmpty()`).
public protocol OptionalField: Sendable {
    associatedtype Input: Sendable
    associatedtype Failure: Error
    static var schema: Schema<Input, Self?, Failure> { get }
    var encoded: Input { get }
}

extension Field {
    /// Smart constructor: runs the rule, failure as a value.
    public static func mk(_ raw: Input) -> Result<Self, Failure> { schema.run(raw) }

    /// For literals and tests: runs the rule and traps on failure, so the value is still valid.
    public static func unsafeMk(_ raw: Input, file: StaticString = #fileID, line: UInt = #line)
        -> Self
    {
        switch mk(raw) {
        case .success(let value): value
        case .failure(let failure):
            preconditionFailure("\(Self.self).unsafeMk: \(failure)", file: file, line: line)
        }
    }

    /// The field's own failure has an empty path; the enclosing `@Schema` adds the property name.
    public static func parse(_ raw: Input) -> Result<Self, Issues<Failure>> {
        schema.runAll(raw).mapError { Issues($0.all.map { .init(path: "", failure: $0) }) }
    }
}

extension OptionalField {
    /// Smart constructor: runs the rule, failure as a value; `nil` means absent.
    public static func mk(_ raw: Input) -> Result<Self?, Failure> { schema.run(raw) }

    /// For literals and tests: runs the rule and traps on failure, so the value is still valid.
    public static func unsafeMk(_ raw: Input, file: StaticString = #fileID, line: UInt = #line)
        -> Self?
    {
        switch mk(raw) {
        case .success(let value): value
        case .failure(let failure):
            preconditionFailure("\(Self.self).unsafeMk: \(failure)", file: file, line: line)
        }
    }
}
