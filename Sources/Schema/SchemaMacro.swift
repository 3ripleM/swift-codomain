/// Write the parsed type; the input type is generated from each field's `Input`.
///
///     @Schema(failure: BasicFailure.self)
///     struct User {
///         let email: Email                 // Input.email: String
///         let birthday: DateFromString?    // Input.birthday: String? (absent allowed)
///     }
///
/// Generates `struct Input`, `init(parsing:) throws(Issues<Failure>)`,
/// `static func parse(_:) -> Result<Self, Issues<Failure>>`, `func encode() -> Input`, and `Parsable`
/// conformance, so a `@Schema` struct (or an array of them) can be a property of another `@Schema` struct.
@attached(extension, conformances: Parsable, names: named(Failure), named(Input), named(init(parsing:)), named(parse), named(encode), named(encoded))
public macro Schema<Failure: Error>(failure: Failure.Type) =
    #externalMacro(module: "SchemaMacros", type: "SchemaMacro")

/// `@Schema` whose `Input` is `Codable`, plus `JSONParsable`:
/// `static func decode(json:) -> Result<Self, JSONFailure<Failure>>` and `func json() throws(EncodingError) -> Data`.
/// Every property's `Input` must be `Codable`, so nesting a plain `@Schema` type is a compile error.
@attached(extension, conformances: Parsable, JSONParsable, names: named(Failure), named(Input), named(init(parsing:)), named(parse), named(encode), named(encoded))
public macro JSONSchema<Failure: Error>(failure: Failure.Type) =
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
@attached(member, names: named(Input), named(Failure), named(value), named(init(_:)), named(schema), named(encoded))
@attached(extension, conformances: Field, OptionalField)
public macro Codec() = #externalMacro(module: "SchemaMacros", type: "CodecMacro")
