import Codomain

// Minimal types shared by the unit tests.

enum F: Error, Equatable {
    case blank, tooLong, noMatch, notInt, odd, first, second, outOfOrder
    case tag(G)
    static func lift(_ g: G) -> F { .tag(g) }
}

/// A second failure type, as if from another module.
enum G: Error, Equatable { case bad }

/// Not blank, after trimming; fails with `G`.
@Codec
struct GName: Equatable {
    static let codec: Codec<String, String, G> = Codec(
        decode: .identity.trimmed().nonEmpty(.bad), encode: { $0 })
}

@JSONParsable(failure: G.self)
struct Tag {
    let name: GName
}

/// An `F` model holding `G` fields and models; `F.lift` converts.
@JSONParsable(failure: F.self)
struct Labeled {
    let x: Even
    let tag: Tag
    let tags: [Tag]
    let alias: GName?
}

typealias Text = Schema<String, String, F>

/// Even integers; `Field`.
@Codec
struct Even: Equatable {
    static let codec: Codec<Int, Int, F> = Codec(
        decode: .identity.refine(.odd) { $0 % 2 == 0 }, encode: { $0 })
}

/// Trimmed, at most 3 characters, blank → absent; `OptionalField`.
@Codec
struct Nick: Equatable {
    static let codec: Codec<String, String?, F> = Codec(
        decode: Text.identity.trimmed().nilIfEmpty().max(3, .tooLong),
        encode: { $0 ?? "" }
    )
}

/// Any `Double`, NaN included; used to make `JSONEncoder` fail.
@Codec
struct Real {
    static let codec: Codec<Double, Double, F> = Codec(decode: .identity, encode: { $0 })
}

@JSONParsable(failure: F.self)
struct Point {
    let x: Even
    let label: Nick?
}

@JSONParsable(failure: F.self)
struct Reading {
    let value: Real
}

@JSONParsable(failure: F.self)
struct Polyline {
    let points: [Point]
}

/// `low <= high`, checked by `refine` once both fields parse.
@JSONParsable(failure: F.self)
struct Bounds {
    let low: Even
    let high: Even

    static func refine(_ span: Bounds) -> [Issues<F>.Issue] {
        span.high.value < span.low.value ? [.init(path: "high", failure: .outOfOrder)] : []
    }
}

@JSONParsable(failure: F.self)
struct Schedule {
    let slots: [Bounds]
}

func failure<T>(_ result: Result<T, F>) -> F? {
    if case .failure(let failure) = result { failure } else { nil }
}

/// Declared here, next to `Even`, and used from another file: regression check for `[T].Input`
/// failing to resolve inside the macro expansion.
@JSONParsable(failure: F.self)
struct Board {
    let lanes: [String: Even]
    let pins: [String: Point]?
}

/// A union of a field and a model with another failure type.
@Parsable(failure: F.self)
enum Choice: Equatable {
    case even(Even)
    case tag(GName)
}

@JSONParsable(failure: F.self)
struct Circle: Equatable { let radius: Even }

@JSONParsable(failure: F.self)
struct Square: Equatable { let side: Even }

/// JSON: `{"kind": "circle", "radius": 2}`.
@JSONParsable(failure: F.self, tag: "kind")
enum Shape: Equatable {
    case circle(Circle)
    case square(Square)
}

@JSONParsable(failure: F.self)
struct Drawing { let shapes: [Shape] }

/// A union with `refine`: a circle's radius is at most 10.
@JSONParsable(failure: F.self, tag: "kind")
enum Small {
    case circle(Circle)

    static func refine(_ small: Small) -> [Issues<F>.Issue] {
        guard case .circle(let circle) = small, circle.radius.value > 10 else { return [] }
        return [.init(path: "radius", failure: .tooLong)]
    }
}

@JSONParsable(failure: F.self, keys: .snakeCase)
struct Renamed {
    let dueDate: Even
    let userID: Even
    @JSONKey("x-y") let custom: Even
    let urlPath: Nick?
}

/// Wire tags differ from case names: `{"type": "CIRCLE", "radius": 2}`.
@JSONParsable(failure: F.self, tag: "type")
enum Tagged: Equatable {
    @JSONTag("CIRCLE") case circle(Circle)
    @JSONTag("SQUARE") case square(Square)
}

/// Unlisted tags decode to `.other(tag)` instead of failing.
@JSONParsable(failure: F.self, tag: "kind")
enum Open: Equatable {
    case circle(Circle)
    @UnknownTag case other(String)
}

/// `size` is 2 when absent or `null`; `odd` defaults to a value that fails.
@JSONParsable(failure: F.self)
struct Defaults: Equatable {
    @Default(2) let size: Even
    let x: Even
}

@JSONParsable(failure: F.self)
struct BadDefault {
    @Default(3) let size: Even
}

/// Keys other than `x` are problems.
@JSONParsable(failure: F.self, strict: true)
struct Closed: Equatable { let x: Even }

@JSONParsable(failure: F.self, keys: .snakeCase, strict: true)
struct ClosedOuter: Equatable { let innerValue: Closed }

/// The tag key is not a problem for a strict payload, but is for objects nested in it.
@JSONParsable(failure: F.self, tag: "kind")
enum ClosedUnion: Equatable {
    case closed(Closed)
    case outer(ClosedOuter)
}

/// Both checks run; every failure is kept. Steps after `collect` keep the list.
@Codec
struct Password: Equatable {
    static let codec: Codec<String, String, F> = Codec(
        decode: Text.identity.trimmed().collect(
            { $0.min(8, .first) }, { $0.refine(.second) { $0.contains(where: \.isNumber) } }
        ).lowercased(),
        encode: { $0 }
    )
}

@JSONParsable(failure: F.self)
struct Account { let password: Password }

/// A union inside a union: a strict payload accepts both tag keys.
@JSONParsable(failure: F.self, tag: "inner")
enum InnerUnion: Equatable { case closed(Closed) }

@JSONParsable(failure: F.self, tag: "outer")
enum OuterUnion: Equatable { case inner(InnerUnion) }
