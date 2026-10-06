import Foundation
import Schema

// General-purpose codecs. `@Codec` generates `value` and a `private init`:
// `codec.decode` is the only way to get a value, so holding a `NonEmptyArray` proves it's non-empty.

enum BasicFailure: Error, Equatable {
    case emptyString, emptyArray, notPositive, notANumber, notADate, notAnEmail
    case notACountryCode, notAPhoneNumber, unknownPhoneKind
}

private let string = Schema<String, String, BasicFailure>.identity

/// Trimmed and lowercased, so `A@x.io` and `a@x.io` are the same email.
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

/// Trimmed; never blank.
@Codec
struct NonEmptyString: Hashable {
    static let codec: Codec<String, String, BasicFailure> = Codec(
        decode: .identity.trimmed().nonEmpty(.emptyString),
        encode: { $0 }
    )
}

@Codec
struct NonEmptyArray<Element> {
    static var codec: Codec<[Element], [Element], BasicFailure> {
        Codec(decode: .identity.check(.emptyArray) { !$0.isEmpty }, encode: { $0 })
    }

    /// Not optional: `codec.decode` guarantees an element.
    var first: Element { value[0] }
}

/// > 0. Works for any signed or floating-point number (`Int`, `Int64`, `Double`, `Decimal`).
@Codec
struct PositiveNumber<Number: Numeric & Comparable & Sendable> {
    static var codec: Codec<Number, Number, BasicFailure> {
        Codec(decode: .identity.check(.notPositive) { $0 > .zero }, encode: { $0 })
    }
}

/// io-ts `NumberFromString`: input is text, output is a number.
@Codec
struct NumberFromString {
    static let codec: Codec<String, Double, BasicFailure> = Codec(
        decode: string.trimmed().compactMap(.notANumber) { Double($0) },
        encode: { String($0) }
    )
}

/// io-ts `DateFromString`: ISO 8601 text in, `Date` out.
@Codec
struct DateFromString {
    static let codec: Codec<String, Date, BasicFailure> = Codec(
        decode: string.trimmed().compactMap(.notADate) { try? Date($0, strategy: .iso8601) },
        encode: { $0.formatted(.iso8601) }
    )
}

/// ISO 3166-1 alpha-2, e.g. `CA`. Trimmed and uppercased.
@Codec
struct CountryCode: Hashable {
    static let codec: Codec<String, String, BasicFailure> = Codec(
        decode: .identity.trimmed().map { $0.uppercased() }.matches("^[A-Z]{2}$", .notACountryCode),
        encode: { $0 }
    )
}

/// E.164-style: optional `+`, then 7–15 digits. Spaces, dashes, dots and parentheses are removed.
@Codec
struct PhoneNumber: Hashable {
    static let codec: Codec<String, String, BasicFailure> = Codec(
        decode: .identity
            .map { $0.filter { !" -.()".contains($0) } }
            .matches(#"^\+?[0-9]{7,15}$"#, .notAPhoneNumber),
        encode: { $0 }
    )
}

@Codec
struct PhoneKind: Hashable {
    enum Kind: String { case mobile, home, work }

    static let codec: Codec<String, Kind, BasicFailure> = Codec(
        decode: string.trimmed().compactMap(.unknownPhoneKind) { Kind(rawValue: $0.lowercased()) },
        encode: { $0.rawValue }
    )
}
