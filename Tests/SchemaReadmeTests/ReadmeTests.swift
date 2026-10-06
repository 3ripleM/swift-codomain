// Every declaration and documented output in README.md, in README order. Keep both in sync:
// when this file fails to compile or a check fails, the README is wrong too.
import Foundation
import Schema
import Testing
import XMLCoder

// MARK: - 1. Name your failures (with the `member` case and `lift` from step 9)

enum MemberFailure: Error, Equatable { case notAnEmail }

enum TodoFailure: Error, Equatable {
    case blank, tooLong, tooShort, noDigit, notAnEmail, notADate, endsBeforeStart
    case member(MemberFailure)
    static func lift(_ failure: MemberFailure) -> TodoFailure { .member(failure) }
}

// MARK: - 2. Write field types

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

let text = Schema<String, String, TodoFailure>.identity

@Codec
struct DueDate {
    static let codec: Codec<String, Date, TodoFailure> = Codec(
        decode: text.trimmed().compactMap(.notADate) { try? Date($0, strategy: .iso8601) },
        encode: { $0.formatted(.iso8601) }
    )
}

@Codec
struct Note {
    static let codec: Codec<String, String?, TodoFailure> = Codec(
        decode: text.trimmed().nilIfEmpty().max(500, .tooLong),
        encode: { $0 ?? "" }
    )
}

// MARK: - 3. Write models

@JSONSchema(failure: TodoFailure.self)
struct Member {
    let email: Email
    let name: Title
}

@JSONSchema(failure: TodoFailure.self)
struct Todo {
    let title: Title
    let due: DueDate?  // key may be missing
    let note: Note?  // key may be missing, or blank
    let subtasks: [Todo]  // recursion works
}

@JSONSchema(failure: TodoFailure.self)
struct TodoList {
    let title: Title
    let owner: Member
    let items: [Todo]
}

// MARK: - 4. Decode

let json = """
    {
      "title": "  Weekend ",
      "owner": { "email": " Ada@Example.com ", "name": "Ada" },
      "items": [
        { "title": "Groceries", "due": "2026-10-10T17:00:00Z", "note": "  ", "subtasks": [] }
      ]
    }
    """

@Test func step4Decode() throws {
    let list = try TodoList.decode(json: Data(json.utf8)).get()
    #expect(list.title.value == "Weekend")
    #expect(list.owner.email.value == "ada@example.com")
    #expect(list.items[0].note == nil)
}

@Test func step4UnreadableBytes() {
    guard case .failure(.unreadable) = TodoList.decode(json: Data("not json".utf8)) else {
        Issue.record("expected .unreadable")
        return
    }
}

// MARK: - 5. Read every error

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

@Test func step5EveryError() throws {
    guard case .failure(.invalid(let issues)) = TodoList.decode(json: Data(bad.utf8)) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(
        issues.description
            == #"title: blank, owner.email: notAnEmail, items[0].due: wrongType(expected: "String"), items[1].due: notADate"#
    )
    #expect(issues.all.first?.path == "title")
    #expect(issues.byPath.keys.contains("owner.email"))
}

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

@Schema(failure: TodoFailure.self)
struct PasswordForm { let password: Password }

@Test func step5Collect() {
    guard case .failure(let issues) = PasswordForm.parse(.init(password: "abc")) else {
        Issue.record("expected failures")
        return
    }
    #expect(issues.description == "password: tooShort, password: noDigit")
}

// MARK: - 6. Encode

@Test func step6Encode() throws {
    let list = try TodoList.decode(json: Data(json.utf8)).get()
    let data = try list.json()
    #expect(
        String(decoding: data, as: UTF8.self)
            == #"{"items":[{"due":"2026-10-10T17:00:00Z","subtasks":[],"title":"Groceries"}],"owner":{"email":"ada@example.com","name":"Ada"},"title":"Weekend"}"#
    )
    #expect(try TodoList.decode(json: data).get().json() == data)
}

// MARK: - 7. Without JSON

@Schema(failure: TodoFailure.self)
struct SignUp {
    let email: Email
    let name: Title
}

@Test func step7WithoutJSON() throws {
    let result = SignUp.parse(SignUp.Input(email: " Ada@Example.com ", name: "Ada"))
    #expect(try result.get().email.value == "ada@example.com")
    #expect(try Email.mk("ada@example.com").get().value == "ada@example.com")
    #expect(Email.unsafeMk("ada@example.com").value == "ada@example.com")
}

// MARK: - 8. Rules across fields

@JSONSchema(failure: TodoFailure.self)
struct Sprint {
    let starts: DueDate
    let ends: DueDate

    static func refine(_ sprint: Sprint) -> [Issues<TodoFailure>.Issue] {
        sprint.ends.value < sprint.starts.value ? [.init(path: "ends", failure: .endsBeforeStart)] : []
    }
}

@Test func step8RulesAcrossFields() {
    let result = Sprint.parse(.init(starts: "2026-10-10T00:00:00Z", ends: "2026-10-01T00:00:00Z"))
    guard case .failure(let issues) = result else {
        Issue.record("expected endsBeforeStart")
        return
    }
    #expect(issues.description == "ends: endsBeforeStart")
}

// MARK: - 10. One of several shapes

@JSONSchema(failure: TodoFailure.self)
struct AtTime { let due: DueDate }

@JSONSchema(failure: TodoFailure.self)
struct AtPlace { let place: Title }

@JSONSchema(failure: TodoFailure.self, tag: "kind")
enum Trigger {
    case time(AtTime)
    case place(AtPlace)
}

private func problems(_ text: String) -> String {
    guard case .failure(.invalid(let issues)) = Trigger.decode(json: Data(text.utf8)) else { return "no problems" }
    return issues.description
}

@Test func step10Union() throws {
    guard case .place(let atPlace) = try Trigger.decode(json: Data(#"{"kind": "place", "place": "Office"}"#.utf8)).get()
    else {
        Issue.record("expected .place")
        return
    }
    #expect(atPlace.place.value == "Office")
    #expect(problems(#"{"kind": "place", "place": " "}"#) == "place: blank")
    #expect(problems(#"{"kind": "email"}"#) == #"kind: wrongType(expected: "time | place")"#)
    #expect(problems(#"{"kind": 7}"#) == #"kind: wrongType(expected: "time | place")"#)
    #expect(problems(#"{"place": "Office"}"#) == "kind: missing")
}

enum Step10Tags {
    @JSONSchema(failure: TodoFailure.self, tag: "type")
    enum Trigger {
        @JSONTag("TIME") case time(AtTime)
        @JSONTag("PLACE") case place(AtPlace)
        @UnknownTag case other(String)
    }
}

@Test func step10UnknownTag() throws {
    let trigger = try Step10Tags.Trigger.decode(json: Data(#"{"type": "WIFI", "ssid": "Home"}"#.utf8)).get()
    guard case .other(let tag) = trigger else {
        Issue.record("expected .other")
        return
    }
    #expect(tag == "WIFI")
    #expect(String(decoding: try trigger.json(), as: UTF8.self) == #"{"type":"WIFI"}"#)
}

@JSONSchema(failure: TodoFailure.self)
struct Labels { let labels: [String: Title] }

@Test func step10Dictionaries() {
    guard
        case .failure(.invalid(let issues)) = Labels.decode(
            json: Data(#"{"labels": {"work": " ", "home": "Home"}}"#.utf8))
    else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues.description == #"labels["work"]: blank"#)
}

// MARK: - 11. Match an existing API

@JSONSchema(failure: TodoFailure.self, keys: .snakeCase, strict: true)
struct Reminder {
    let dueDate: DueDate  // JSON key "due_date"
    @JSONKey("msg") let text: Title  // JSON key "msg"
    @Default("Inbox") let list: Title  // "Inbox" when the key is absent or null
}

@Test func step11MatchAnAPI() throws {
    let reminder = try Reminder.decode(json: Data(#"{"due_date": "2026-10-10T17:00:00Z", "msg": "Call"}"#.utf8)).get()
    #expect(reminder.text.value == "Call" && reminder.list.value == "Inbox")
    guard
        case .failure(.invalid(let issues)) = Reminder.decode(
            json: Data(#"{"due_date": "soon", "msg": "Call", "extra": 1}"#.utf8))
    else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues.description == "due_date: notADate, extra: unexpected")
    guard case .failure(let parsed) = Reminder.parse(.init(dueDate: "soon", text: "Call")) else {
        Issue.record("expected failure")
        return
    }
    #expect(parsed.description == "dueDate: notADate")
}

// MARK: - 12. Write your own steps

extension Schema where Output == String {
    /// Canadian postal code: `K1A 0B1`.
    func postalCode(_ failure: Failure) -> Schema {
        refine(failure) { $0.wholeMatch(of: #/[A-Z]\d[A-Z] ?\d[A-Z]\d/#) != nil }
    }
}

extension Schema where Output == String {
    /// `#FF8800` → `0xFF8800`.
    func hexColor(_ failure: Failure) -> Schema<Input, Int, Failure> {
        compactMap(failure) { text in
            guard text.count == 7, text.first == "#", text.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
            return Int(text.dropFirst(), radix: 16)
        }
    }
}

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

let port = Schema<String, Int, ShopFailure> { raw in
    guard let number = Int(raw), (1...65535).contains(number) else { return .failure(.badPort) }
    return .success(number)
}

@Test func step12OwnSteps() throws {
    #expect(try PostalCode.mk(" k1a 0b1 ").get().value == "K1A 0B1")
    #expect(try Color.mk("#ff8800").get().value == 16_746_496)
    #expect(try port.run("8080").get() == 8080)
    let color = Color.unsafeMk("#ff8800")
    #expect(try Color.mk(color.encoded).get().value == color.value)
}

// MARK: - 13. Other formats

extension XMLDecoder: DataDecoder {}

@Test func step13OtherFormats() throws {
    let xmlData = Data("<todo><title>Buy milk</title></todo>".utf8)
    let result = Todo.decode(xmlData, using: XMLDecoder())
    let xml = try XMLEncoder().encode(result.get().encoded, withRootKey: "todo")
    #expect(try Todo.decode(xml, using: XMLDecoder()).get().title.value == "Buy milk")
}
