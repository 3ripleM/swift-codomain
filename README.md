# swift-schema

Parse, don't validate: turn raw input into typed values, with the rules declared once
and mistakes caught by the compiler. Zod/io-ts-style, for Swift.

Status: prototype.

## Why (the need)

Validating with `if` checks scattered across call sites has these problems:

1. **Rules spread across modules:** one layer checks a trimmed value, another trims again
   with its own helper.
2. **Checked value ≠ stored value:** `" 42 "` is checked trimmed but sent untrimmed.
3. **Checks can be skipped:** nothing stops calling `send()` without `validate()`.
4. **Optionality via a runtime flag:** `requirement: .required/.optional` duplicates what
   `String` vs `String?` already expresses.
5. **No compile-time help:** a missing rule, a wrong field, or wrong optionality all
   compile and pass silently.

No maintained Swift package does this. GitHub searches for `zod swift`, `io-ts swift`,
and `swift refined types` returned none. The closest packages are `pointfreeco/swift-tagged`
(branded types, no rules) and `SvenTiigi/ValidatedPropertyKit` (property wrappers; the
value stays a `String`).

## Goals

1. **Rules in one place:** each field type owns both directions, typed once (`Email.codec`).
2. **Parsed types prove validity:** holding a `User` means every field passed its rule;
   field types have a `private init`, so the schema is the only way in.
3. **Errors as values, all at once:** `Result<User, Issues<Failure>>` lists every failure with its path
   (`email: notAnEmail, address.city: emptyString, phones[1].number: notAPhoneNumber`); within one field the chain stops at its first failure.
4. **Compiler errors, not runtime errors**, for developer mistakes (table below).
5. **Least boilerplate:** the developer writes one struct per model and one declaration
   per field type; input type, parsing, and encoding are generated.

Non-goals: a `@Codec` value that is itself a `@Schema` struct (nest `@Schema` structs directly instead).

## Usage

```swift
import Schema

// 1. A field type: `Codec<Input, Value, Failure>` holds `decode` (may fail) and `encode` (cannot fail).
//    `@Codec` generates `let value`, a `private init`, `schema`, `encoded`, and `Field`.
@Codec
struct Email: Hashable {
    static let codec: Codec<String, String, BasicFailure> = Codec(
        decode: .identity
            .trimmed()
            .map { $0.lowercased() }
            .matches(#"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, .notAnEmail),
        encode: { $0 }
    )
}

@Codec
struct DateFromString {
    static let codec: Codec<String, Date, BasicFailure> = Codec(
        decode: string.compactMap(.notADate) { try? Date($0, strategy: .iso8601) },
        encode: { $0.formatted(.iso8601) }
    )
}

// 2. A model: write the parsed struct only.
@Schema(failure: BasicFailure.self)
struct User {
    let email: Email                     // Input.email: String
    let birthday: DateFromString?        // Input.birthday: String? = nil
}

Email.mk(" Ada@Example.com ")                   // Result<Email, BasicFailure>
Email.unsafeMk("ada@example.com")               // Email; traps if the rule fails (literals, tests)

User.parse(.init(email: " Ada@Example.com "))   // decode: Result<User, Issues<BasicFailure>>
user.encode()                                   // encode: User.Input (normalized raw values)
```

`@Schema` generates `struct Input`, `init(parsing:) throws(Issues<Failure>)`,
`static func parse(_:) -> Result<Self, Issues<Failure>>` and `func encode() -> Input`. Every field is
parsed before `Self` is built, so one call reports every failure.

Properties can be `@Codec` fields, other `@Schema` structs, arrays of either, or optionals of those
(`let address: Address?`, `let phones: [Phone]`). Nested failures get a path:
`address.country: notACountryCode`, `phones[1].kind: unknownPhoneKind`.
Optional properties become optional inputs defaulting to `nil`.

For JSON, write `@JSONSchema(failure:)` instead: same expansion, plus `Input: Codable` and
`JSONParsable`:

```swift
switch TodoList.decode(json: data) {          // Result<TodoList, JSONFailure<TodoFailure>>
case .success(let list): let bytes = try list.json()  // sorted keys; throws(EncodingError)
case .failure(.malformed(let error)): ...     // DecodingError: wrong shape, missing key
case .failure(.invalid(let issues)): ...      // Issues<TodoFailure>: every rule failure
}
```

Every property's `Input` must be `Codable`, so a plain `@Schema` struct inside a `@JSONSchema`
struct is a compile error.

`@Codec` reads the `codec` annotation `Codec<I, V, F>`: `decode: Schema<I, V, F>` and `encode: (V) -> I`
are both checked against it, so the types are written once and `encode` cannot fail. Law: `decode(encode(v)) == v`; the reverse does not
hold for normalizing decoders (`" Ada@X.io "` encodes as `"ada@x.io"`). An optional `V`
(e.g. `Codec<String, String?, F>` with `nilIfEmpty()`) generates `OptionalField` instead of `Field`.
`.identity` only infers when both types match; otherwise start `decode` from a typed helper
(`let string = Schema<String, String, F>.identity`).

## Example: client and backend

`swift run Example` runs a small user registry (`Sources/Example/`):

- `Client.registerUser(...)`: raw input → `User.parse` → `user.encode()` → JSON → `Backend`.
- `Client.getUser(email:)`: `Backend` JSON → `User.Input` → `User.parse`. Stored data is
  untrusted too: a record that breaks a rule is refused.
- `Backend`: mocked database; stores JSON bodies in an array, unique by email.

## Building blocks

| File | Purpose |
|---|---|
| `Sources/Schema/Schema.swift` | `Schema<Input, Output, Failure>` chain and `Codec<Input, Value, Failure>`: `identity`, `map`, `compactMap`, `check`, `trimmed`, `nonEmpty`, `nilIfEmpty`, `max`, `matches` |
| `Sources/Schema/Field.swift` | `Parsable` (anything `@Schema` can hold; `[T]` is `Parsable` when `T` is), `Field` (schema always yields a value) and `OptionalField` (schema may yield absent), each with `mk`, `unsafeMk` and `encoded` |
| `Sources/Schema/SchemaMacro.swift` | `@Schema`, `@JSONSchema` and `@Codec` macro declarations |
| `Sources/Schema/JSON.swift` | `JSONParsable` (`decode(json:)`, `json()`) and `JSONFailure` (`.malformed` / `.invalid`) |
| `Sources/Schema/Issues.swift` | `Issues<Failure>`: every failure as `(path, failure)`, in declaration order; `IssueCollector` used by generated code |
| `Sources/SchemaMacros/SchemaMacro.swift` | `@Schema`/`@JSONSchema`: emits `Input` (`T.Input` / `T.Input?` per property; `Codable` for `@JSONSchema`), `init(parsing:)`, `parse`, `encode` |
| `Sources/SchemaMacros/CodecMacro.swift` | Emits `value`, `private init`, `schema` (from `codec.decode`), `encoded` (from `codec.encode`), and `Field`/`OptionalField` conformance |
| `Sources/Example/Basics.swift` | Field types: `Email`, `NonEmptyString`, `NonEmptyArray`, `PositiveNumber`, `NumberFromString`, `DateFromString` |
| `Tests/SchemaSmokeTests/` | Smoke tests on a `@JSONSchema` todo-list domain: JSON fixtures, normalization, full-tree round trip, deep issue paths |
| `Sources/Example/Client.swift`, `Contact.swift`, `Backend.swift`, `main.swift` | The client/backend example above; `Contact.swift` holds the nested `Address` and `Phone` |

## Compile-time guarantees (verified by mutation tests)

| Developer mistake | Result |
|---|---|
| Property type has no schema (`String?`, `Int`) | ❌ `'Input' is not a member type of …` |
| `nilIfEmpty` field declared required | ❌ `requires that 'Nickname' conform to 'Parsable'` |
| Array of a type without a schema (`[String]`) | ❌ `requires that 'String' conform to 'Parsable'` |
| Property without a type annotation | ❌ `@Schema needs an explicit type` |
| Plain `@Schema` struct inside a `@JSONSchema` struct | ❌ `'TodoList.Input' does not conform to protocol 'Decodable'` |
| Input/parsed name mismatch | Impossible with `@Schema` (one name list) |
| Constructing a field without its schema (`NonEmptyString("")`) | ❌ `initializer is inaccessible due to 'private' protection level` |
| `@Codec` without `codec` | ❌ `@Codec needs 'static let codec: …'` |
| `codec` without a type annotation | ❌ `'codec' needs an explicit type` |
| `encode` returning the wrong type | ❌ `cannot convert value of type …` |
| Hand-written `let value` next to `@Codec` | ❌ `invalid redeclaration of 'value'` |

## Costs and open risks

- **`public` structs need public field types:** a `public` `@Schema` struct whose field
  types are internal fails (`initializer cannot be declared public because its parameter
  uses an internal type`). Make the field types public; their `init` stays private.
- **Encode round-trips the normalized value:** `" Ada@Example.com "` encodes as
  `"ada@example.com"`, and `NumberFromString` `"36"` encodes as `"36.0"`.
- **Typed throws in closures aren't inferred** (Swift 6.3 without `FullTypedThrows`):
  write straight-line `throws(F)` bodies (`try result.get(or: F.wrap)`, see `Client.swift`) instead of
  `throws(F)` closures.
- Depends on `swift-syntax` (resolved 600.0.1); first clean build took 38 seconds.
- Xcode requires trusting the macro; CI likely needs `-skipMacroValidation` (unverified).
- Typed throws (`throws(Failure)`) at `iOS 17` deployment target: unverified.
- Building with `safe.bareRepository=explicit` in global git config breaks SwiftPM's
  cache; override per command: `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all swift build`.

## Run

```sh
swift run Example   # prints "schema: all checks passed"
swift test          # smoke tests: Tests/SchemaSmokeTests (todo list: 4 nested object levels, recursion, 11 issues in one parse)
```
