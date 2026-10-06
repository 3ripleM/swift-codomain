/// Write the parsed type; the input type is generated from each field's `Input`.
///
///     @Schema(failure: BasicFailure.self)
///     struct User {
///         let email: Email                 // Input.email: String
///         let birthday: DateFromString?    // Input.birthday: String? (absent allowed)
///     }
///
/// On an enum, every case holds one `Parsable` value (`case circle(Circle)`); `Input` is the matching enum.
///
/// Generates `struct Input`, `init(parsing:) throws(Issues<Failure>)`,
/// `static func parse(_:) -> Result<Self, Issues<Failure>>`, `func encode() -> Input`, and `Parsable`
/// conformance, so a `@Schema` struct (or an array of them) can be a property of another `@Schema` struct.
@attached(
    extension, conformances: Parsable, names: named(Failure), named(Input), named(init(parsing:)),
    named(parse), named(encode), named(encoded))
public macro Schema<Failure: Error>(failure: Failure.Type) =
    #externalMacro(module: "SchemaMacros", type: "SchemaMacro")

/// `@Schema` whose `Input` is `Codable`, plus `JSONParsable`:
/// `static func decode(json:) -> Result<Self, DecodeFailure<Failure>>` and `func json() throws(EncodingError) -> Data`.
/// `decode(json:)` reports every problem — missing keys, wrong JSON types, broken rules — with its path.
/// Every property's `Input` must be `Codable`, so nesting a plain `@Schema` type is a compile error.
@attached(
    extension, conformances: Parsable, JSONParsable, names: named(Failure), named(Input),
    named(init(parsing:)), named(parse), named(encode), named(encoded), named(init(json:)),
    named(read))
public macro JSONSchema<Failure: Error>(
    failure: Failure.Type, keys: JSONKeys = .swift, strict: Bool = false
) =
    #externalMacro(module: "SchemaMacros", type: "JSONSchemaMacro")

/// How `@JSONSchema` names JSON keys. `@JSONKey("...")` on a property overrides either.
public enum JSONKeys: Sendable {
    /// The Swift property name: `dueDate`.
    case swift
    /// `dueDate` → `due_date`, `userID` → `user_id`.
    case snakeCase
}

/// `@JSONSchema` for an enum: a tagged union whose JSON is the payload's object plus the `tag` key.
///
///     @JSONSchema(failure: MyFailure.self, tag: "kind")
///     enum Shape { case circle(Circle), square(Square) }   // {"kind": "circle", "radius": 2}
///
/// Every case holds one `@JSONSchema` value. An unknown or non-string tag is `wrongType(expected: "circle | square")`.
@attached(
    extension, conformances: Parsable, JSONParsable, names: named(Failure), named(Input),
    named(init(parsing:)), named(parse), named(encode), named(encoded), named(init(json:)),
    named(read))
public macro JSONSchema<Failure: Error>(failure: Failure.Type, tag: String) =
    #externalMacro(module: "SchemaMacros", type: "JSONSchemaMacro")

/// Declare both directions once, typed once; the brand is generated.
///
///     @Codec
///     struct DateFromString {
///         static let codec: Codec<String, Date, MyFailure> = Codec(
///             decode: string.compactMap(.notADate) { try? Date($0, strategy: .iso8601) },
///             encode: { $0.formatted(.iso8601) }
///         )
///     }
///
/// Generates `let value: Date`, a `private init` (`codec.decode` is the only way in), `static var schema`,
/// `var encoded` (from `codec.encode`), and `Field` conformance. An optional value type
/// (`Codec<String, String?, F>`, e.g. from `nilIfEmpty()`) generates `OptionalField`.
@attached(
    member, names: named(Input), named(Failure), named(value), named(init(_:)), named(schema),
    named(encoded))
@attached(extension, conformances: Field, OptionalField)
public macro Codec() = #externalMacro(module: "SchemaMacros", type: "CodecMacro")

/// The JSON key for this property, instead of its Swift name (or the model's `keys:` conversion).
@attached(peer)
public macro JSONKey(_ key: String) = #externalMacro(module: "SchemaMacros", type: "MarkerMacro")

/// The JSON tag for this union case, instead of its Swift name. Used for decoding and encoding.
@attached(peer)
public macro JSONTag(_ tag: String) = #externalMacro(module: "SchemaMacros", type: "MarkerMacro")

/// On `case other(String)` of a tagged union: receives any tag no other case lists. The payload is dropped.
@attached(peer)
public macro UnknownTag() = #externalMacro(module: "SchemaMacros", type: "MarkerMacro")

/// Used when the value is absent (`nil` in `Input`, or absent or `null` in JSON).
@attached(peer)
public macro Default<T>(_ value: T) = #externalMacro(module: "SchemaMacros", type: "MarkerMacro")
