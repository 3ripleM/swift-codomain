import Schema

// Minimal types shared by the unit tests.

enum F: Error, Equatable { case blank, tooLong, noMatch, notInt, odd, first, second }

typealias Text = Schema<String, String, F>

/// Even integers; `Field`.
@Codec
struct Even: Equatable {
    static let codec: Codec<Int, Int, F> = Codec(decode: .identity.check(.odd) { $0 % 2 == 0 }, encode: { $0 })
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

@JSONSchema(failure: F.self)
struct Point {
    let x: Even
    let label: Nick?
}

@JSONSchema(failure: F.self)
struct Reading {
    let value: Real
}

func failure<T>(_ result: Result<T, F>) -> F? {
    if case .failure(let failure) = result { failure } else { nil }
}
