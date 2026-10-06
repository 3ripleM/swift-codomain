import Schema

// Nested models: each is a `@Schema` struct, so it can be a property of `User` (alone, optional, or in an array).

@Schema(failure: BasicFailure.self)
struct Address {
    let street: NonEmptyString
    let city: NonEmptyString
    let country: CountryCode
}

@Schema(failure: BasicFailure.self)
struct Phone {
    let kind: PhoneKind
    let number: PhoneNumber
}

// Must live in the file that declares the type for Codable synthesis.
extension Address.Input: Codable {}
extension Phone.Input: Codable {}
