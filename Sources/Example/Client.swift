import Foundation
import Schema

// The only model you write. `User.Input`, `User.parse` and `user.encode()` are generated.
@Schema(failure: BasicFailure.self)
struct User {
    let email: Email
    let name: NonEmptyString
    let roles: NonEmptyArray<String>
    let age: NumberFromString?
    let birthday: DateFromString?
    let address: Address?  // nested object
    let phones: [Phone]  // array of nested objects
}

// Wire format. Must live in the file that declares `User` for Codable synthesis.
extension User.Input: Codable {}

enum ClientError: Error, Equatable {
    case invalid(Issues<BasicFailure>)  // input (or a stored record) broke rules; every failing field
    case rejected(Backend.Failure)  // backend refused the request
    case notFound
    case corruptRecord  // stored JSON doesn't match `User.Input`
}

struct Client {
    let backend: Backend

    /// Raw input → decode → `User` → encode → JSON → backend.
    func registerUser(
        email: String, name: String, roles: [String], age: String? = nil, birthday: String? = nil,
        address: Address.Input? = nil, phones: [Phone.Input] = []
    ) throws(ClientError) -> User {
        let input = User.Input(
            email: email, name: name, roles: roles, age: age, birthday: birthday, address: address, phones: phones
        )
        let user = try User.parse(input).get(or: ClientError.invalid)
        try backend.insert(user.encode().json).get(or: ClientError.rejected)
        return user
    }

    /// Backend → JSON → `User.Input` → decode → `User`. Stored data is untrusted too.
    func getUser(email: String) throws(ClientError) -> User {
        let key = try Email.mk(email).get(or: { ClientError.invalid(Issues("email", $0)) })
        guard let body = backend.find(email: key.value) else { throw .notFound }
        guard let input = try? JSONDecoder().decode(User.Input.self, from: body) else { throw .corruptRecord }
        return try User.parse(input).get(or: ClientError.invalid)
    }
}

extension User.Input {
    // Encoding plain strings and arrays can't fail.
    var json: Data { try! JSONEncoder().encode(self) }
}

extension Result {
    /// `get()` with the failure wrapped, e.g. `Issues<BasicFailure>` → `ClientError.invalid`.
    func get<E: Error>(or wrap: (Failure) -> E) throws(E) -> Success { try mapError(wrap).get() }
}
