/// Anything `@Schema` can hold: a `@Codec` field, a `@Schema` struct, or an array of either.
/// `parse` reports every failure with its path; `encoded` goes back to the raw input.
public protocol Parsable {
    associatedtype Input
    associatedtype Failure: Error
    static func parse(_ input: Input) -> Result<Self, Issues<Failure>>
    var encoded: Input { get }
}

/// Every element is parsed; failures are reported as `[index]`.
extension Array: Parsable where Element: Parsable {
    public static func parse(_ input: [Element.Input]) -> Result<[Element], Issues<Element.Failure>> {
        var collector = IssueCollector<Element.Failure>()
        let values = input.enumerated().map { collector.required("[\($0.offset)]", $0.element, as: Element.self) }
        guard collector.issues.isEmpty else { return .failure(Issues(collector.issues)) }
        return .success(values.map { $0! })
    }

    public var encoded: [Element.Input] { map(\.encoded) }
}

/// A field whose schema always produces a value. A codec: `schema` decodes, `encoded` encodes.
/// Law: decoding `encoded` gives back the same value.
public protocol Field: Parsable {
    static var schema: Schema<Input, Self, Failure> { get }
    var encoded: Input { get }
}

/// A field whose schema may decide "absent" (e.g. `nilIfEmpty()`).
public protocol OptionalField {
    associatedtype Input
    associatedtype Failure: Error
    static var schema: Schema<Input, Self?, Failure> { get }
    var encoded: Input { get }
}

extension Field {
    /// Smart constructor: runs the rule, failure as a value.
    public static func mk(_ raw: Input) -> Result<Self, Failure> { schema.run(raw) }

    /// For literals and tests: runs the rule and traps on failure, so the value is still valid.
    public static func unsafeMk(_ raw: Input, file: StaticString = #fileID, line: UInt = #line) -> Self {
        switch mk(raw) {
        case .success(let value): value
        case .failure(let failure): preconditionFailure("\(Self.self).unsafeMk: \(failure)", file: file, line: line)
        }
    }

    /// The field's own failure has an empty path; the enclosing `@Schema` adds the property name.
    public static func parse(_ raw: Input) -> Result<Self, Issues<Failure>> { mk(raw).mapError { Issues("", $0) } }
}

extension OptionalField {
    /// Smart constructor: runs the rule, failure as a value; `nil` means absent.
    public static func mk(_ raw: Input) -> Result<Self?, Failure> { schema.run(raw) }

    /// For literals and tests: runs the rule and traps on failure, so the value is still valid.
    public static func unsafeMk(_ raw: Input, file: StaticString = #fileID, line: UInt = #line) -> Self? {
        switch mk(raw) {
        case .success(let value): value
        case .failure(let failure): preconditionFailure("\(Self.self).unsafeMk: \(failure)", file: file, line: line)
        }
    }
}
