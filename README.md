# swift-schema

**Parse, don't validate** for Swift. Declare each rule once, get typed values or every error at once,
and let the compiler catch the mistakes. In the spirit of Zod and io-ts.

```swift
import Schema

enum TodoFailure: Error { case blank, tooLong }

@Codec
struct Title {
    static let codec: Codec<String, String, TodoFailure> = Codec(
        decode: .identity.trimmed().nonEmpty(.blank).max(120, .tooLong),
        encode: { $0 }
    )
}

@JSONSchema(failure: TodoFailure.self)
struct Todo {
    let title: Title
}

let todo = try Todo.decode(json: Data(#"{ "title": "  Buy milk " }"#.utf8)).get()
todo.title.value  // "Buy milk"
```

## About

Most input handling checks a `String` with a few `if`s and passes the same `String` along. Nothing
records that the check happened, so the next layer checks again or forgets to.

swift-schema **parses** instead. A rule turns raw input into a new type, such as `Title`, and the
only way to get a `Title` is through its rule. If a function takes a `Title`, the check has already happened.

## Features

- **One place per rule:** a field type owns its decode and encode, typed once.
- **Every error, with its path:** one parse reports `title: blank, items[1].due: notADate`.
- **Compile-time safety:** a field without a rule, a wrong optionality, or a mistyped encoder fails to
  compile (see [Compile-time guarantees](#compile-time-guarantees)).
- **Little boilerplate:** write the parsed struct; the raw `Input` struct, parsing, and encoding are generated.
- **Nesting:** structs inside structs, arrays, optionals, and recursive trees.
- **JSON in, JSON out:** `decode(json:)` and `json()` for `@JSONSchema` types.

## What is "parse, don't validate"?

Validating keeps the raw type:

```swift
func save(title: String) {
    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }  // trimmed here…
    database.insert(title)                                                     // …stored untrimmed
}
```

Parsing returns a new type that can only hold valid values:

```swift
func save(title: Title) {          // a Title is always trimmed, non-empty, at most 120 characters
    database.insert(title.value)
}

switch Title.mk("  Buy milk ") {   // the only way to get a Title
case .success(let title): save(title: title)
case .failure(let failure): print(failure)  // .blank or .tooLong
}
```

## Installation

Swift 6.0 tools or later; macOS 15 / iOS 17.

```swift
// Package.swift
dependencies: [
    .package(url: "[REF NEEDED: repository URL]", branch: "main"),
],
targets: [
    .target(name: "App", dependencies: [.product(name: "Schema", package: "swift-schema")]),
]
```

`@Codec`, `@Schema` and `@JSONSchema` are Swift macros: Xcode asks you to trust the macro once.

# Documentation

- [Getting Started](#getting-started)
- [API Reference](#api-reference)
- [Compile-time guarantees](#compile-time-guarantees)
- [Limitations](#limitations)
- [Development](#development)

## Getting Started

We build a todo list that arrives as JSON.

### 1. Name your failures

One enum lists everything that can be wrong with a value:

```swift
import Foundation
import Schema

enum TodoFailure: Error, Equatable {
    case blank, tooLong, notAnEmail, notADate
}
```

### 2. Write field types

A field type is a struct with `@Codec` and one `codec`: how to read the raw value (`decode`, may fail)
and how to write it back (`encode`, cannot fail). The type `Codec<Input, Value, Failure>` is written once
and both directions are checked against it.

```swift
@Codec
struct Title {
    static let codec: Codec<String, String, TodoFailure> = Codec(
        decode: .identity.trimmed().nonEmpty(.blank).max(120, .tooLong),
        encode: { $0 }
    )
}

@Codec
struct Email {
    static let codec: Codec<String, String, TodoFailure> = Codec(
        decode: .identity.trimmed().map { $0.lowercased() }.matches(#"^[^@\s]+@[^@\s]+$"#, .notAnEmail),
        encode: { $0 }
    )
}
```

When input and value types differ (`String` → `Date`), start from a typed `identity`:

```swift
let text = Schema<String, String, TodoFailure>.identity

@Codec
struct DueDate {
    static let codec: Codec<String, Date, TodoFailure> = Codec(
        decode: text.trimmed().compactMap(.notADate) { try? Date($0, strategy: .iso8601) },
        encode: { $0.formatted(.iso8601) }
    )
}
```

A rule can also decide that a value is absent. Here a blank note counts as no note:

```swift
@Codec
struct Note {
    static let codec: Codec<String, String?, TodoFailure> = Codec(
        decode: text.trimmed().nilIfEmpty().max(500, .tooLong),
        encode: { $0 ?? "" }
    )
}
```

Each field type gets `let value`, a `private init`, `mk`, `unsafeMk`, and `encoded`.

### 3. Write models

Write the struct you want to use. Properties can be field types, other models, arrays, and optionals:

```swift
@JSONSchema(failure: TodoFailure.self)
struct Member {
    let email: Email
    let name: Title
}

@JSONSchema(failure: TodoFailure.self)
struct Todo {
    let title: Title
    let due: DueDate?     // key may be missing
    let note: Note?       // key may be missing, or blank
    let subtasks: [Todo]  // recursion works
}

@JSONSchema(failure: TodoFailure.self)
struct TodoList {
    let title: Title
    let owner: Member
    let items: [Todo]
}
```

The macro generates `TodoList.Input`, the raw shape (`title: String`, `owner: Member.Input`,
`items: [Todo.Input]`), plus parsing and encoding.

### 4. Decode

```swift
let json = """
{
  "title": "  Weekend ",
  "owner": { "email": " Ada@Example.com ", "name": "Ada" },
  "items": [
    { "title": "Groceries", "due": "2026-10-10T17:00:00Z", "note": "  ", "subtasks": [] }
  ]
}
"""

switch TodoList.decode(json: Data(json.utf8)) {
case .success(let list):
    list.title.value          // "Weekend"
    list.owner.email.value    // "ada@example.com"
    list.items[0].note        // nil: blank became absent
case .failure(.malformed(let error)):
    print(error)              // DecodingError: not JSON, wrong type, missing key
case .failure(.invalid(let issues)):
    print(issues)             // every rule failure, see below
}
```

### 5. Read every error

Every field is parsed before the result is built, so one call reports every failure, each with its path:

```swift
let bad = """
{
  "title": " ",
  "owner": { "email": "ada-at-example.com", "name": "Ada" },
  "items": [
    { "title": "Groceries", "subtasks": [] },
    { "title": "Laundry", "due": "tomorrow", "subtasks": [] }
  ]
}
"""

if case .failure(.invalid(let issues)) = TodoList.decode(json: Data(bad.utf8)) {
    print(issues)  // title: blank, owner.email: notAnEmail, items[1].due: notADate
    issues.all     // [Issue(path: "title", failure: .blank), …]
}
```

Within one field, the rule stops at its first failure.

### 6. Encode

`json()` writes the parsed values back, normalized, with sorted keys:

```swift
let list = try TodoList.decode(json: Data(json.utf8)).get()
let data = try list.json()  // {"items":[{"due":"2026-10-10T17:00:00Z","subtasks":[],"title":"Groceries"}],"owner":{"email":"ada@example.com","name":"Ada"},"title":"Weekend"}
```

Decoding what you encoded gives the same value back.

### 7. Without JSON

Use `@Schema` when input does not come from JSON (forms, other models). You build the `Input` yourself:

```swift
@Schema(failure: TodoFailure.self)
struct SignUp {
    let email: Email
    let name: Title
}

let result = SignUp.parse(SignUp.Input(email: " Ada@Example.com ", name: "Ada"))
// Result<SignUp, Issues<TodoFailure>>
```

Single fields work the same way:

```swift
Email.mk("ada@example.com")       // Result<Email, TodoFailure>
Email.unsafeMk("ada@example.com") // Email; crashes if the rule fails. For literals and tests.
```

## API Reference

### `Schema`

A rule from `Input` to `Output` that returns a `Result` and never throws. Build one by chaining steps
from `identity`.

#### Signature

```swift
struct Schema<Input, Output, Failure: Error> {
    let run: (Input) -> Result<Output, Failure>
}
```

#### Example

```swift
let title = Schema<String, String, TodoFailure>.identity.trimmed().nonEmpty(.blank)
title.run("  a ")  // .success("a")
title.run("   ")   // .failure(.blank)
```

### Steps

| Step | Signature | Does |
|---|---|---|
| `identity` | `static var identity: Schema` (when `Input == Output`) | Passes the input through. Start of every chain. |
| `map` | `map((Output) -> T)` | Transforms the value. Cannot fail. |
| `compactMap` | `compactMap(Failure, (Output) -> T?)` | Transforms; `nil` becomes `Failure`. |
| `check` | `check(Failure, (Output) -> Bool)` | Keeps the value when `true`, else `Failure`. |
| `trimmed` | `trimmed()` | Strips whitespace and newlines from both ends (includes Unicode spaces). |
| `nonEmpty` | `nonEmpty(Failure)` | Fails on `""`. Does not trim: put `trimmed()` first. |
| `nilIfEmpty` | `nilIfEmpty()` | `""` becomes `nil`. Output becomes `String?`. |
| `max` | `max(Int, Failure)` | At most N characters, as people see them (`"👩‍👩‍👧"` is 1). `nil` passes. |
| `matches` | `matches(String, Failure)` | Regular expression search. Anchor with `^…$` to match the whole string. `nil` passes. |

The first failing step wins; later steps don't run.

### `@Codec`

Turns a struct with a `codec` into a field type.

#### Signature

```swift
@Codec
struct Name {
    static let codec: Codec<Input, Value, Failure> = Codec(
        decode: Schema<Input, Value, Failure>,
        encode: (Value) -> Input
    )
}
```

#### Generates

- `let value: Value`
- `private init`: only `codec.decode` creates values.
- `static func mk(_: Input) -> Result<Name, Failure>`
- `static func unsafeMk(_: Input) -> Name`: crashes with file and line if the rule fails.
- `var encoded: Input`

If `Value` is optional (`Codec<String, String?, F>`), `mk` returns `Result<Name?, Failure>`:
the rule can decide the value is absent. Such a field can only be used as an optional property.

Law: `mk(x.encoded)` gives back `x`. The reverse does not hold for normalizing rules:
`" Ada@X.io "` encodes as `"ada@x.io"`.

### `@Schema`

Turns a struct into a model.

#### Signature

```swift
@Schema(failure: Failure.self)
struct Name { /* stored properties */ }
```

Every stored property needs a type annotation, and the type must be a field type, a model, an array of
those, or an optional of those.

#### Generates

- `struct Input`: one property per stored property, using its `Input` type. Optional properties
  become optional and default to `nil`.
- `static func parse(_: Input) -> Result<Name, Issues<Failure>>`
- `init(parsing: Input) throws(Issues<Failure>)`
- `func encode() -> Input` and `var encoded: Input`

### `@JSONSchema`

`@Schema` plus JSON. Every property must be readable from JSON, so a plain `@Schema` model inside a
`@JSONSchema` model fails to compile.

#### Signature

```swift
@JSONSchema(failure: Failure.self)
struct Name { /* stored properties */ }
```

#### Generates

Everything `@Schema` generates, with `Input: Codable`, plus:

- `static func decode(json: Data) -> Result<Name, JSONFailure<Failure>>`
- `func json() throws(EncodingError) -> Data`: sorted keys. Throws for values JSON can't hold, such as `Double.nan`.

### `Issues`

Every failure from one parse, in property order.

#### Signature

```swift
struct Issues<Failure: Error>: Error {
    struct Issue { let path: String; let failure: Failure }
    let all: [Issue]
}
```

Paths join property names with `.` and array positions with `[i]`: `items[0].subtasks[1].title`.
`print(issues)` gives `path: failure, path: failure`. `Issues` is `Equatable` when `Failure` is.

### `JSONFailure`

#### Signature

```swift
enum JSONFailure<Failure: Error>: Error {
    case malformed(DecodingError)  // not JSON, wrong type, missing key
    case invalid(Issues<Failure>)  // right shape, rules failed
}
```

## Compile-time guarantees

Each row was checked by introducing the mistake and building.

| Mistake | Compiler says |
|---|---|
| Property type has no rule (`String`, `Int`) | `'Input' is not a member type of …` |
| Field that can be absent, used as required | `requires that '…' conform to 'Parsable'` |
| Array of a type without a rule (`[String]`) | `requires that 'String' conform to 'Parsable'` |
| Property without a type annotation | `@Schema needs an explicit type on '…'` |
| `@Schema` model inside a `@JSONSchema` model | `'….Input' does not conform to protocol 'Decodable'` |
| Creating a field type without its rule (`Title("")`) | `initializer is inaccessible due to 'private' protection level` |
| `@Codec` without `codec` | `@Codec needs 'static let codec: Codec<Input, Value, Failure>'` |
| `codec` without a type annotation | `'codec' needs an explicit type: Codec<Input, Value, Failure>` |
| `encode` returning the wrong type | `cannot convert value of type …` |
| Hand-written `let value` next to `@Codec` | `invalid redeclaration of 'value'` |

## Limitations

- **Nesting depth.** `JSONDecoder` rejects JSON nested deeper than 512 levels with `.malformed`; a todo
  uses 2 levels (`{` and `[`), so about 255 todos deep is the most a JSON tree accepts. Parsing calls itself
  once per level and is bounded by the thread's stack: a debug build on a 512 KB stack crashed between 90
  and 100 todos deep. Decode deep trees on a thread with a larger stack (the main thread has 8 MB), or keep
  models shallow.
- **`public` models need `public` field types**, otherwise: `initializer cannot be declared public because
  its parameter uses an internal type`.
- **Typed throws aren't inferred for closures** (Swift 6.3): write `throws(F)` functions with straight-line
  `try result.get()` instead of throwing closures.
- **Unverified:** typed throws at the iOS 17 deployment target; CI may need `-skipMacroValidation`.
- A field type cannot wrap a model; nest models directly instead.

## Development

```sh
swift test
```

| Directory | Contents |
|---|---|
| `Sources/Schema/` | Library: `Schema.swift` (steps, `Codec`), `Field.swift`, `Issues.swift`, `JSON.swift`, `SchemaMacro.swift` (macro declarations) |
| `Sources/SchemaMacros/` | Macro implementations: `SchemaMacro.swift` (`@Schema`, `@JSONSchema`), `CodecMacro.swift` |
| `Tests/SchemaTests/` | Unit tests, one file per library file |
| `Tests/SchemaMacrosTests/` | Generated-code snapshots and every macro error message |
| `Tests/SchemaSmokeTests/` | A full todo-list domain: fixtures, round trips, 500 seeded random trees, 10,000 items, Unicode, hostile JSON, depth limits, 200 parallel decodes |
