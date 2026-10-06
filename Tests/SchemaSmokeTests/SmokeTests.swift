import Foundation
import Schema
import Testing

private func decode(_ json: String) -> Result<TodoList, DecodeFailure<TodoFailure>> {
    TodoList.decode(json: Data(json.utf8))
}

@Test func validFixtureParsesAndNormalizes() throws {
    let list = try decode(Fixture.valid).get()

    #expect(list.title.value == "Weekend")
    #expect(list.slug.value == "weekend-plans")
    #expect(list.owner.email.value == "ada@example.com")
    #expect(list.settings.sort.value == .due)
    #expect(list.settings.timezone.value.identifier == "America/Toronto")

    let groceries = list.items[0]
    #expect(groceries.priority.value == .high)
    #expect(groceries.note == nil)  // blank → absent
    #expect(groceries.tags.map(\.value) == ["home", "errands"])
    #expect(groceries.reminder?.repeats.value == .weekly)
    #expect(groceries.subtasks[1].note?.value == "sourdough")
    #expect(groceries.subtasks[1].subtasks[0].title.value == "Check bakery hours")  // 3 levels deep
    #expect(list.items[1].due == nil && list.items[1].reminder == nil)  // absent keys
}

/// decode → encode → JSON → decode → encode gives the same JSON: the codec law over the whole tree.
@Test func encodeRoundTripsThroughJSON() throws {
    let first = try decode(Fixture.valid).get()
    let wire = try first.json()
    let second = try TodoList.decode(json: wire).get()

    #expect(try second.json() == wire)
    #expect(second.items[0].due?.value == first.items[0].due?.value)
}

@Test func invalidFixtureReportsEveryFailureWithItsPath() throws {
    guard case .failure(.invalid(let issues)) = decode(Fixture.invalid) else {
        Issue.record("expected .invalid")
        return
    }

    let expected: [(String, TodoFailure)] = [
        ("title", .blank),
        ("slug", .notASlug),
        ("owner.email", .notAnEmail),
        ("sharedWith[1].name", .blank),
        ("settings.reminderDefault", .notPositive),
        ("settings.timezone", .notATimeZone),
        ("items[0].priority", .unknownPriority),
        ("items[0].reminder.at", .notADate),
        ("items[0].subtasks[1].title", .tooLong),
        ("items[0].subtasks[1].subtasks[0].due", .notADate),
        ("items[1].tags[0]", .notASlug),
    ]
    #expect(issues.all.map(\.path) == expected.map(\.0))
    #expect(issues == Issues(expected.map { .init(path: $0.0, failure: .rule($0.1)) }))
}

@Test func bytesThatAreNotJSONNeverReachTheSchema() {
    guard case .failure(.unreadable) = decode(#"{ "title": "#) else {
        Issue.record("expected .unreadable")
        return
    }
}
