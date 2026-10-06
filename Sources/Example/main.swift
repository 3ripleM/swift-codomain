import Foundation
import Schema

let backend = Backend()
let client = Client(backend: backend)

func show(_ label: String, _ run: @autoclosure () throws(ClientError) -> User) -> Result<
    User, ClientError
> {
    let result = Result(catching: run)
    switch result {
    case .success(let user): print("✔︎ \(label): \(user.name.value) <\(user.email.value)>")
    case .failure(let error): print("✘ \(label): \(error)")
    }
    return result
}

// Register: input is trimmed/lowercased on the way in, then encoded for the backend.
let ada = try show(
    "register",
    try client.registerUser(
        email: " Ada@Example.com ", name: "Ada", roles: ["admin"], age: " 36 ",
        birthday: "1815-12-10T00:00:00Z")
).get()
precondition(ada.email.value == "ada@example.com" && ada.age?.value == 36)

// Get: JSON from the backend is decoded and parsed again.
let fetched = try show("get", try client.getUser(email: "ADA@example.com")).get()
precondition(fetched.name.value == "Ada" && fetched.roles.first == "admin")
precondition(fetched.birthday?.value == ada.birthday?.value && fetched.age?.value == 36)

// Failures
func failure<T, F>(_ result: Result<T, F>) -> F? {
    if case .failure(let error) = result { error } else { nil }
}
precondition(
    failure(
        show(
            "duplicate",
            try client.registerUser(email: "ada@EXAMPLE.com", name: "Ada 2", roles: ["dev"])))
        == .rejected(.duplicateEmail))
precondition(
    failure(show("bad email", try client.registerUser(email: "ada", name: "Ada", roles: ["dev"])))
        == .invalid(Issues("email", .notAnEmail)))
precondition(
    failure(
        show(
            "blank name",
            try client.registerUser(email: "bob@example.com", name: "  ", roles: ["dev"])))
        == .invalid(Issues("name", .emptyString)))
precondition(
    failure(
        show("no roles", try client.registerUser(email: "bob@example.com", name: "Bob", roles: [])))
        == .invalid(Issues("roles", .emptyArray)))
precondition(
    failure(
        show("all at once", try client.registerUser(email: "x", name: " ", roles: [], age: "old")))
        == .invalid(
            Issues([
                .init(path: "email", failure: .notAnEmail),
                .init(path: "name", failure: .emptyString),
                .init(path: "roles", failure: .emptyArray),
                .init(path: "age", failure: .notANumber),
            ])))
// Nested: every failure carries its path.
let ben = try show(
    "nested",
    try client.registerUser(
        email: "ben@example.com", name: "Ben", roles: ["dev"],
        address: .init(street: "1 Main St", city: "Montreal", country: " ca "),
        phones: [.init(kind: "Mobile", number: "+1 (514) 555-0100")]
    )
).get()
precondition(ben.address?.country.value == "CA" && ben.phones.first?.number.value == "+15145550100")
let benAgain = try client.getUser(email: "ben@example.com")
precondition(benAgain.phones.first?.kind.value == .mobile)
precondition(
    failure(
        show(
            "nested failures",
            try client.registerUser(
                email: "cy@example.com", name: "Cy", roles: ["dev"],
                address: .init(street: " ", city: "Paris", country: "France"),
                phones: [
                    .init(kind: "home", number: "+33 1 23 45 67 89"),
                    .init(kind: "pager", number: "12"),
                ]
            )))
        == .invalid(
            Issues([
                .init(path: "address.street", failure: .emptyString),
                .init(path: "address.country", failure: .notACountryCode),
                .init(path: "phones[1].kind", failure: .unknownPhoneKind),
                .init(path: "phones[1].number", failure: .notAPhoneNumber),
            ])))
precondition(failure(show("unknown", try client.getUser(email: "bob@example.com"))) == .notFound)

// A record written by someone else breaks a rule: `get` refuses it instead of trusting it.
_ = backend.insert(Data(#"{"email":"eve@example.com","name":" ","roles":["x"],"phones":[]}"#.utf8))
precondition(
    failure(show("bad record", try client.getUser(email: "eve@example.com")))
        == .invalid(Issues("name", .emptyString)))
_ = backend.insert(Data(#"{"email":"mal@example.com"}"#.utf8))
precondition(
    failure(show("corrupt record", try client.getUser(email: "mal@example.com"))) == .corruptRecord)

precondition(Email.unsafeMk(" Ada@Example.com ").value == "ada@example.com")
precondition(failure(Email.mk("ada")) == .notAnEmail)
// Codec law: decode(encode(v)) == v.
precondition(Email.mk(ada.email.encoded) == .success(ada.email))
precondition(ada.birthday.map { DateFromString.unsafeMk($0.encoded).value == $0.value } ?? false)
print("schema: all checks passed")
