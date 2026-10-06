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
- **Nesting:** structs inside structs, arrays, `String`-keyed dictionaries, optionals, recursive trees,
  and enums as tagged unions.
- **Common checks built in:** string (`email`, `url`, `uuid`, `datetime`, `ip`, lengths), number
  (`within`, `positive`, `multiple(of:)`), and array counts, in the style of Zod.
- **JSON in, JSON out:** `decode(json:)` and `json()` for `@JSONSchema` types, with snake_case keys,
  defaults, strict mode, and custom or unknown union tags.

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
    case blank, tooLong, tooShort, noDigit, notAnEmail, notADate, endsBeforeStart
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
        decode: .identity.trimmed().lowercased().email(.notAnEmail),
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

Write the struct you want to use. Properties can be field types, other models, arrays, `[String: T]`
dictionaries, and optionals:

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
case .failure(.unreadable(let error)):
    print(error)              // DecodingError: the bytes aren't JSON
case .failure(.invalid(let issues)):
    print(issues)             // every problem, see below
}
```

### 5. Read every error

Every key is read and every field is parsed before the result is built, so one call reports every
problem (a missing key, a wrong JSON type, a broken rule), each with its path:

```swift
let bad = """
{
  "title": " ",
  "owner": { "email": "ada-at-example.com", "name": "Ada" },
  "items": [
    { "title": "Groceries", "due": 42, "subtasks": [] },
    { "title": "Laundry", "due": "tomorrow", "subtasks": [] }
  ]
}
"""

if case .failure(.invalid(let issues)) = TodoList.decode(json: Data(bad.utf8)) {
    print(issues)
    // title: blank, owner.email: notAnEmail, items[0].due: wrongType(expected: "String"), items[1].due: notADate
    issues.all     // [Issue(path: "title", failure: .rule(.blank)), …]
    issues.byPath  // ["title": [.rule(.blank)], "owner.email": [.rule(.notAnEmail)], …]: one entry per form field
}
```

Within one field, the rule stops at its first failure. To report several, wrap the checks in `collect`:

```swift
@Codec
struct Password {
    static let codec: Codec<String, String, TodoFailure> = Codec(
        decode: .identity.collect(
            { $0.min(8, .tooShort) },
            { $0.refine(.noDigit) { $0.contains(where: \.isNumber) } }
        ),
        encode: { $0 }
    )
}
// "abc" → password: tooShort, password: noDigit
```

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

### 8. Rules across fields

A rule that compares fields goes in `static func refine`. It runs only after every field has parsed, so
it works with parsed values:

```swift
@JSONSchema(failure: TodoFailure.self)
struct Sprint {
    let starts: DueDate
    let ends: DueDate

    static func refine(_ sprint: Sprint) -> [Issues<TodoFailure>.Issue] {
        sprint.ends.value < sprint.starts.value ? [.init(path: "ends", failure: .endsBeforeStart)] : []
    }
}
```

The path you return is relative to the model; a `Sprint` at `sprints[2]` reports `sprints[2].ends`.

### 9. Mix failure types

A model or field with a different failure type (for example from another module) nests after you say once
how to convert its failure. Add a `lift` overload on the parent's failure type:

```swift
enum MemberFailure: Error, Equatable { case notAnEmail }

enum TodoFailure: Error, Equatable {
    case blank, tooLong, tooShort, noDigit, notAnEmail, notADate, endsBeforeStart, member(MemberFailure)
    static func lift(_ failure: MemberFailure) -> TodoFailure { .member(failure) }
}
```

Every `@Schema` and `@JSONSchema` property then converts with the `lift` whose parameter matches. A
`Member` with `MemberFailure` inside a `TodoList` reports
`Issue(path: "owner.email", failure: .member(.notAnEmail))`. With no matching `lift`, the build fails.

### 10. One of several shapes

An enum whose cases each hold one model is a tagged union. In JSON, the `tag` key names the case and the
model's keys sit next to it:

```swift
@JSONSchema(failure: TodoFailure.self)
struct AtTime { let due: DueDate }

@JSONSchema(failure: TodoFailure.self)
struct AtPlace { let place: Title }

@JSONSchema(failure: TodoFailure.self, tag: "kind")
enum Trigger {
    case time(AtTime)
    case place(AtPlace)
}

Trigger.decode(json: Data(#"{"kind": "place", "place": "Office"}"#.utf8))
// .success(.place(AtPlace(place: "Office")))
```

| JSON | Problem |
|---|---|
| `{"kind": "place", "place": " "}` | `place: blank`: the model's own path, no case name |
| `{"kind": "email"}` or `{"kind": 7}` | `kind: wrongType(expected: "time \| place")` |
| `{"place": "Office"}` | `kind: missing` |

To use a different tag in JSON than the case name, mark the case with `@JSONTag`. Decoding accepts only
that tag, and `json()` writes it. To accept tags you don't model (for example ones a server adds in a later
version), add one `@UnknownTag case other(String)`:

```swift
@JSONSchema(failure: TodoFailure.self, tag: "type")
enum Trigger {
    @JSONTag("TIME") case time(AtTime)
    @JSONTag("PLACE") case place(AtPlace)
    @UnknownTag case other(String)
}

// {"type": "WIFI", "ssid": "Home"} → .other("WIFI"). The rest of the object is dropped;
// json() writes {"type":"WIFI"}.
```

With `@UnknownTag`, an absent or `null` tag is still `missing`, and a tag that is not a string is
`wrongType(expected: "string")`.

Without JSON, `@Schema(failure:)` on an enum takes no `tag`, and its cases may also hold field types.
An enum can declare `static func refine` like a struct.

Dictionaries with `String` keys work like arrays: `let labels: [String: Title]` reads a JSON object and
reports `labels["work"]: blank`. Problems are listed in key order.

### 11. Match an existing API

```swift
@JSONSchema(failure: TodoFailure.self, keys: .snakeCase, strict: true)
struct Reminder {
    let dueDate: DueDate               // JSON key "due_date"
    @JSONKey("msg") let text: Title    // JSON key "msg"
    @Default("Inbox") let list: Title  // "Inbox" when the key is absent or null
}
```

- **`keys: .snakeCase`** names every JSON key in snake case: `dueDate` → `due_date`, `userID` → `user_id`.
  `@JSONKey("…")` sets one key and takes priority over `keys:`. Problems from `decode(json:)` use the JSON
  key (`due_date: notADate`); problems from `parse` use the Swift name (`dueDate: notADate`).
- **`@Default(raw)`** uses a raw value when the key is absent or `null` (or the `Input` property is `nil`).
  The default is parsed like any other value, so a default that breaks the rule is reported. `json()`
  always writes the key.
- **`strict: true`** reports every key the model doesn't declare as `unexpected`. When the model is a
  union's case, the union's tag key is allowed, and so is every enclosing union's tag key when unions nest.

### 12. Write your own steps

When no [built-in step](#steps) fits, add one to `Schema`. A step takes the failure to report, so it
works with any failure type.

A check, built from `refine`:

```swift
extension Schema where Output == String {
    /// Canadian postal code: `K1A 0B1`.
    func postalCode(_ failure: Failure) -> Schema {
        refine(failure) { $0.wholeMatch(of: #/[A-Z]\d[A-Z] ?\d[A-Z]\d/#) != nil }
    }
}
```

A conversion to another type, built from `compactMap` (`nil` means the value is invalid):

```swift
extension Schema where Output == String {
    /// `#FF8800` → `0xFF8800`.
    func hexColor(_ failure: Failure) -> Schema<Input, Int, Failure> {
        compactMap(failure) { text in
            guard text.count == 7, text.first == "#", text.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
            return Int(text.dropFirst(), radix: 16)
        }
    }
}
```

Then use them in a field type like any built-in step. When the value type differs from the input type,
start from a typed `identity`:

```swift
enum ShopFailure: Error { case notAPostalCode, notAColor, badPort }

@Codec
struct PostalCode {
    static let codec: Codec<String, String, ShopFailure> = Codec(
        decode: .identity.trimmed().uppercased().postalCode(.notAPostalCode),
        encode: { $0 }
    )
}

@Codec
struct Color {
    static let codec: Codec<String, Int, ShopFailure> = Codec(
        decode: Schema<String, String, ShopFailure>.identity.trimmed().uppercased().hexColor(.notAColor),
        encode: { String(format: "#%06X", $0) }
    )
}

PostalCode.mk(" k1a 0b1 ")  // .success, value "K1A 0B1"
Color.mk("#ff8800")         // .success, value 16746496
```

For a rule that doesn't fit a chain, write the `Schema` directly. It returns a `Result`:

```swift
let port = Schema<String, Int, ShopFailure> { raw in
    guard let number = Int(raw), (1...65535).contains(number) else { return .failure(.badPort) }
    return .success(number)
}
```

Check the law in a test: `mk(x.encoded)` gives back `x`.

### 13. Other formats

`decode(_:using:)` reads with any decoder that conforms to `DataDecoder`, and reports every problem with
its path, as `decode(json:)` does. `JSONDecoder` and `PropertyListDecoder` already conform. For another
library, add the conformance in one line:

```swift
import XMLCoder

extension XMLDecoder: DataDecoder {}

let result = Todo.decode(xmlData, using: XMLDecoder())  // Result<Todo, DecodeFailure<TodoFailure>>
let xml = try XMLEncoder().encode(result.get().encoded, withRootKey: "todo")
```

To encode, pass `encoded` (the `Codable` `Input`) to the format's encoder. When a decoder throws an error
that is not a `DecodingError`, the result is `.unreadable(.dataCorrupted(…))` with that error as
`underlyingError`. `DecodeFailure` and `DecodeProblem` are the same for every format.

With XMLCoder (tested in `Tests/SchemaXMLTests`):

| XML input | Result |
|---|---|
| Repeated `<item>` elements for an `[Item]` property | An array; problems are reported as `item[1].name` |
| One `<item>` element for an `[Item]` property | A one-item array |
| No `<item>` element | An empty array; XMLCoder writes `[]` as no element, so `[]` round-trips |
| `<item/>` | A one-item array whose fields are `missing` (`item[0].name: missing`) |
| An optional `[Item]?` set to `[]` | `nil` after a round trip: XML has no way to tell absent from empty |
| An empty element, e.g. `<id></id>` | The empty string `""` |
| An attribute, e.g. `<item id="7">` | Read like a child element named `id`; with `strict: true` an undeclared attribute is `id: unexpected` |

## API Reference

### `Schema`

A rule from `Input` to `Output` that returns a `Result` and never throws. Build one by chaining steps
from `identity`.

#### Signature

```swift
struct Schema<Input, Output, Failure: Error>: Sendable {
    func run(_ input: Input) -> Result<Output, Failure>  // the first failure only
}
```

#### Example

```swift
let title = Schema<String, String, TodoFailure>.identity.trimmed().nonEmpty(.blank)
title.run("  a ")  // .success("a")
title.run("   ")   // .failure(.blank)
```

### Steps

Every check takes the failure to report. The string checks let `nil` pass, so they also work after
`nilIfEmpty()`.

**Any value**

| Step | Signature | Does |
|---|---|---|
| `identity` | `static var identity: Schema` (when `Input == Output`) | Passes the input through. Start of every chain. |
| `map` | `map((Output) -> T)` | Transforms the value. Cannot fail. |
| `compactMap` | `compactMap(Failure, (Output) -> T?)` | Transforms; `nil` becomes `Failure`. |
| `refine` | `refine(Failure, (Output) -> Bool)` | Keeps the value when `true`, else `Failure`. |
| `collect` | `collect({ $0.min(8, .a) }, { $0.refine(.b) { … } })` | Runs every check on the same value and keeps every failure. When all pass, the output is the last check's output: put transforms such as `trimmed()` before `collect`. |

**Strings** (`Primitives/String.swift`)

| Step | Signature | Does |
|---|---|---|
| `trimmed` | `trimmed()` | Strips whitespace and newlines from both ends (includes Unicode spaces). |
| `lowercased`, `uppercased` | `lowercased()` | Changes case. |
| `nonEmpty` | `nonEmpty(Failure)` | Fails on `""`. Does not trim: put `trimmed()` first. |
| `nilIfEmpty` | `nilIfEmpty()` | `""` becomes `nil`. Output becomes `String?`. |
| `min`, `max`, `length` | `min(Int, Failure)` | At least, at most, exactly N characters, as people see them (`"👩‍👩‍👧"` is 1). |
| `startsWith`, `endsWith`, `includes` | `startsWith(String, Failure)` | Prefix, suffix, substring. |
| `email` | `email(Failure)` | `local@domain.tld`: one `@`, no whitespace, a dot in the domain. |
| `url` | `url(Failure)` | `http` or `https` with a host. |
| `uuid` | `uuid(Failure)` | `8-4-4-4-12` hex digits, any case. |
| `datetime` | `datetime(Failure)` | ISO 8601 with `Z` or an offset: `2026-10-05T12:00:00Z`. `2026-02-30` fails. |
| `ip` | `ip(Failure, version: IPVersion? = nil)` | IPv4 or IPv6; `version: .v4` or `.v6` allows one. |

**Numbers** (`Primitives/Number.swift`)

| Step | Signature | Does |
|---|---|---|
| `within` | `within(1...10, Failure)` | Any range: `1...`, `..<100`, `0.0..<1.0`. Works for any `Comparable`, such as `Date`. NaN fails. |
| `positive`, `nonNegative`, `negative`, `nonPositive` | `positive(Failure)` | Compared with zero. `-0.0` is not positive. |
| `multiple(of:)` | `multiple(of: 5, Failure)` | Integers only. |
| `finite` | `finite(Failure)` | Floating point only: not infinite, not NaN. |

**Arrays** (`Primitives/Array.swift`), for a field whose value is an array such as `Codec<[String], [String], F>`

| Step | Signature | Does |
|---|---|---|
| `min`, `max`, `length` | `min(Int, Failure)` | At least, at most, exactly N elements. |
| `nonEmpty` | `nonEmpty(Failure)` | Fails on `[]`. |

A model's array property (`let items: [Todo]`) is not a chain; check its count in the model's
[`refine`](#8-rules-across-fields).

**Regular expressions.** Write the regex inside `refine`. `Regex` is not `Sendable`, so a step can't hold
one, but a literal inside the closure works and is checked at compile time:

```swift
.refine(.notASlug) { $0.wholeMatch(of: #/[a-z0-9]+(-[a-z0-9]+)*/#) != nil }
```

The first failing step wins; later steps don't run. Inside `collect`, every check runs. `run` and `mk`
return the first failure; `parse` and `decode(json:)` report all of them.

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

Turns a struct into a model, or an enum into a union.

#### Signature

```swift
@Schema(failure: Failure.self)
struct Name { /* stored properties */ }

@Schema(failure: Failure.self)
enum Name { case a(A), b(B) /* each case holds one field type or model */ }
```

Every stored property needs a type annotation, and the type must be a field type, a model, an array or
`[String: T]` dictionary of those, or an optional of those.

#### Generates

- `struct Input`: one property per stored property, using its `Input` type. Optional properties
  become optional and default to `nil`.
- `static func parse(_: Input) -> Result<Name, Issues<Failure>>`
- `init(parsing: Input) throws(Issues<Failure>)`
- `func encode() -> Input` and `var encoded: Input`

On an enum, `Input` is an enum with the same cases holding each value's `Input`. A case's failure keeps
the value's own path.

`Input`, `Name`, and every field type are `Sendable`.

`@Default(raw) let p: T` makes `p` optional in `Input`; `nil` parses `raw` instead. Not allowed on an
optional property.

If the type declares `static func refine(_: Name) -> [Issues<Failure>.Issue]`, parsing calls it once
every field has parsed and fails with its issues. A wrong signature is a compile error.

Each property's failure is converted with `Failure.lift`. The library provides `lift(_: Self) -> Self` on
every `Error`; add overloads to nest other failure types (see [Mix failure types](#9-mix-failure-types)).

### `@JSONSchema`

`@Schema` plus JSON. Every property must be readable from JSON, so a plain `@Schema` model inside a
`@JSONSchema` model fails to compile.

#### Signature

```swift
@JSONSchema(failure: Failure.self, keys: JSONKeys = .swift, strict: Bool = false)
struct Name {
    @JSONKey("json_key") let a: A  // optional: overrides the key
    @Default(raw) let b: B         // optional: value when absent or null
}

@JSONSchema(failure: Failure.self, tag: "kind")
enum Name {
    case a(A)                  // each case holds one @JSONSchema model
    @JSONTag("B") case b(B)    // optional: overrides the tag
    @UnknownTag case other(String)  // optional: any other string tag
}
```

`JSONKeys` is `.swift` (the property name) or `.snakeCase`. See [Match an existing API](#11-match-an-existing-api).

#### Generates

Everything `@Schema` generates, with `Input: Codable`, plus:

- `static func decode(json: Data) -> Result<Name, DecodeFailure<Failure>>`: reads every key, reports every problem.
- `static func decode(_: Data, using: some DataDecoder) -> Result<Name, DecodeFailure<Failure>>`: the same,
  with any decoder (see [Other formats](#13-other-formats)).
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

Paths join property names with `.`, array positions with `[i]`, and dictionary keys with `["key"]`:
`items[0].subtasks[1].title`, `labels["work"]`.
`print(issues)` gives `path: failure, path: failure`. `Issues` is `Equatable` when `Failure` is.
`issues.byPath` groups failures by path: `[String: [Failure]]`.

### `DecodeFailure`

#### Signature

```swift
enum DecodeFailure<Failure: Error>: Error {
    case unreadable(DecodingError)                // the bytes aren't JSON, or nest deeper than 512 levels
    case invalid(Issues<DecodeProblem<Failure>>) // every problem, with its path
}

enum DecodeProblem<Failure: Error>: Error {
    case rule(Failure)                 // right type, rule failed
    case missing                       // required key absent or null
    case wrongType(expected: String)   // e.g. a number where a string is expected
    case unexpected                    // a key the model doesn't declare, with strict: true
}
```

An unknown key is ignored unless the model is `strict: true`. An absent or `null` optional is `nil`. A union's tag that is absent or `null`
is `missing`; any other value that names no case is `wrongType(expected: "a | b")`, listing the `@JSONTag` values.

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
| `refine` returning the wrong type (`Bool`) | `value of type 'Bool' has no member 'isEmpty'` |
| Enum case without exactly one unlabeled value | `@Schema enum cases hold exactly one unlabeled value: 'case b(Model)'` |
| `@JSONSchema` enum without `tag:` | `usage: @JSONSchema(failure: Failure.self, tag: "kind") on an enum` |
| `@JSONSchema` enum case holding a field type, not a model | `requires that 'Title' conform to 'JSONParsable'` |
| `@JSONKey` in a plain `@Schema` | `@JSONKey applies to @JSONSchema properties only` |
| `@JSONTag` in a plain `@Schema` enum | `@JSONTag applies to @JSONSchema enum cases only` |
| `@UnknownTag` on a case other than `case x(String)`, or twice | `@UnknownTag marks one 'case other(String)' of a @JSONSchema enum` |
| `@Default` on an optional property | `@Default applies to non-optional properties only` |
| `strict:` or `keys:` given a variable instead of a literal | `strict: must be true or false`, `keys: must be .swift or .snakeCase` |
| Two properties with the same JSON key | `JSON key 'user_id' is already used by 'userID'` |
| Two union cases with the same tag | `tag 'a' is already used by 'a'` |
| Property whose failure type has no `lift` into the model's | `cannot convert value of type '(G) -> F' to expected argument type '(H) -> F'` |

## Limitations

- **Nesting depth.** `JSONDecoder` rejects JSON nested deeper than 512 levels with `.unreadable`; a todo
  uses 2 levels (`{` and `[`), so about 255 todos deep is the most a JSON tree accepts. Reading and parsing
  call themselves once per level and are bounded by the thread's stack: a debug build on a 512 KB stack
  crashed between 90 and 100 todos deep in `parse(_:)` (`decode(json:)` not measured). Decode deep trees on
  a thread with a larger stack (the main thread has 8 MB), or keep models shallow.
- **`public` models need `public` field types**, otherwise: `initializer cannot be declared public because
  its parameter uses an internal type`.
- **Typed throws aren't inferred for closures** (Swift 6.3): write `throws(F)` functions with straight-line
  `try result.get()` instead of throwing closures.
- **Unverified:** typed throws at the iOS 17 deployment target; CI may need `-skipMacroValidation`.
- A field type cannot wrap a model; nest models directly instead.
- **A union's tag shares the object with the model's keys**, so a case's model must not have a property
  with the tag's name.
- **`keys:`, `strict:`, and `tag:` must be literals** (`.snakeCase`, `true`, `"kind"`): the macro reads
  them from the source. A variable for `keys:` or `strict:` is a compile error.

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
