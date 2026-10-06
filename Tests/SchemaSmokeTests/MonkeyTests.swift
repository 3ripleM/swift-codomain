import Foundation
import Schema
import Testing

// Monkey tests: random trees, extreme sizes, Unicode traps, hostile JSON, and parallel decoding.
// Every random input comes from a fixed seed, so a failure message's seed reproduces it.

// MARK: - Seeded generator

/// SplitMix64: tiny, fast, and identical on every platform, so seeds are reproducible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Builds a random todo list. With `errorRate > 0` it swaps some values for invalid ones and records
/// each swap as `(path, failure)`, in the order the library must report them (declaration order).
struct Monkey {
    var rng: SplitMix64
    let errorRate: Double
    var injected: [Issues<TodoFailure>.Issue] = []

    init(seed: UInt64, errorRate: Double) {
        rng = SplitMix64(state: seed)
        self.errorRate = errorRate
    }

    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }
    mutating func pick<T>(_ options: [T]) -> T { options.randomElement(using: &rng)! }
    mutating func upTo(_ n: Int) -> Int { Int.random(in: 0...n, using: &rng) }

    /// `good`, or with probability `errorRate` one of `bad`, recorded at `path`.
    mutating func value<T>(_ path: String, _ good: T, _ bad: [(T, TodoFailure)]) -> T {
        guard chance(errorRate) else { return good }
        let (value, failure) = pick(bad)
        injected.append(.init(path: path, failure: failure))
        return value
    }

    /// Whitespace that `trimmed()` must strip: space, newline, tab, no-break space, ideographic space.
    mutating func padded(_ s: String) -> String {
        pick(["", " ", "\n", "\u{00A0}", "\u{3000}"]) + s + pick(["", "  ", "\t"])
    }

    mutating func title(_ path: String) -> String {
        let word = pick(["Milk", "Café", "日本語のタスク", "👩‍👩‍👧 family", "שלום", "e\u{301}clair", "🏳️‍🌈"])
        return value(path, padded(word), [("   ", .blank), ("\u{00A0}\n", .blank), (String(repeating: "x", count: 121), .tooLong)])
    }

    mutating func slug(_ path: String) -> String {
        value(path, pick(["a", " Weekend-Plans ", "x-1-y", "TODO-2026"]),
              [("has space", .notASlug), ("week\u{200B}end", .notASlug), ("-lead", .notASlug), ("İstanbul", .notASlug)])
    }

    mutating func instant(_ path: String) -> String {
        let date = Date(timeIntervalSince1970: Double(Int.random(in: 0...4_000_000_000, using: &rng)))
        return value(path, date.formatted(.iso8601), [("tomorrow", .notADate), ("2026-13-45", .notADate)])
    }

    mutating func member(_ path: String) -> Member.Input {
        Member.Input(
            email: value("\(path).email", pick([" Ada@Example.com ", "bob@x.io"]), [("nope", .notAnEmail), ("a@b", .notAnEmail)]),
            name: title("\(path).name")
        )
    }

    mutating func todo(_ path: String, depth: Int) -> Todo.Input {
        Todo.Input(
            title: title("\(path).title"),
            done: chance(0.5),
            priority: value("\(path).priority", pick(["low", "MEDIUM", " High "]), [("urgent", .unknownPriority)]),
            due: chance(0.5) ? instant("\(path).due") : nil,
            note: chance(0.5) ? value("\(path).note", pick(["  ", "sourdough", "📝"]), [(String(repeating: "n", count: 501), .tooLong)]) : nil,
            tags: (0..<upTo(3)).map { slug("\(path).tags[\($0)]") },
            reminder: chance(0.3)
                ? Reminder.Input(
                    at: instant("\(path).reminder.at"),
                    repeats: value("\(path).reminder.repeats", pick(["never", "Daily", "WEEKLY"]), [("hourly", .unknownRepeat)]))
                : nil,
            subtasks: depth < 3 ? (0..<upTo(3)).map { todo("\(path).subtasks[\($0)]", depth: depth + 1) } : []
        )
    }

    mutating func list() -> TodoList.Input {
        TodoList.Input(
            title: title("title"),
            slug: slug("slug"),
            owner: member("owner"),
            sharedWith: (0..<upTo(3)).map { member("sharedWith[\($0)]") },
            settings: Settings.Input(
                sort: value("settings.sort", pick(["manual", "Due", "PRIORITY"]), [("random", .unknownSort)]),
                reminderDefault: chance(0.5)
                    ? value("settings.reminderDefault", Int.random(in: 1...10_000, using: &rng), [(0, .notPositive), (-5, .notPositive)])
                    : nil,
                timezone: value("settings.timezone", pick(TimeZone.knownTimeZoneIdentifiers), [("Mars/Olympus", .notATimeZone)])
            ),
            items: (0..<upTo(6)).map { todo("items[\($0)]", depth: 0) }
        )
    }
}

// MARK: - Helpers

private func bytes(_ input: TodoList.Input) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(input)
}

private func issues(_ result: Result<TodoList, JSONFailure<TodoFailure>>) -> Issues<TodoFailure>? {
    if case .failure(.invalid(let issues)) = result { issues } else { nil }
}

private func failure<T>(_ result: Result<T, TodoFailure>) -> TodoFailure? {
    if case .failure(let failure) = result { failure } else { nil }
}

private func task(_ title: String = "t", due: String? = nil, subtasks: [Todo.Input] = []) -> Todo.Input {
    Todo.Input(title: title, done: false, priority: "low", due: due, tags: [], subtasks: subtasks)
}

private func list(_ items: [Todo.Input]) -> TodoList.Input {
    TodoList.Input(
        title: "L", slug: "l", owner: .init(email: "a@b.co", name: "A"), sharedWith: [],
        settings: .init(sort: "manual", timezone: "UTC"), items: items
    )
}

// MARK: - 1. Seeded fuzzing

@Test func fiveHundredRandomTreesRoundTripAndReportExactlyTheInjectedIssues() throws {
    var totalInjected = 0
    for seed in UInt64(0)..<500 {
        var clean = Monkey(seed: seed, errorRate: 0)
        let first = try TodoList.decode(json: bytes(clean.list())).get()
        let wire = try first.json()
        #expect(try TodoList.decode(json: wire).get().json() == wire, "seed \(seed)")

        var dirty = Monkey(seed: seed, errorRate: 0.1)
        let result = TodoList.decode(json: try bytes(dirty.list()))
        totalInjected += dirty.injected.count
        if dirty.injected.isEmpty {
            #expect((try? result.get()) != nil, "seed \(seed)")
        } else {
            #expect(issues(result) == Issues(dirty.injected), "seed \(seed)")
        }
    }
    #expect(totalInjected > 1_000)  // the fuzzer actually breaks things
}

// MARK: - 2. Extreme sizes

@Test func threeHundredLevelsOfSubtasksReportTheBottomPath() throws {
    var node = task(due: "never")
    for _ in 1..<300 { node = task(subtasks: [node]) }
    let path = "items[0]" + String(repeating: ".subtasks[0]", count: 299) + ".due"

    #expect(issues(TodoList.decode(json: try bytes(list([node])))) == Issues([.init(path: path, failure: .notADate)]))
}

@Test func tenThousandBrokenItemsGiveTenThousandOrderedIssues() throws {
    let result = TodoList.decode(json: try bytes(list((0..<10_000).map { _ in task("  ") })))

    #expect(issues(result) == Issues((0..<10_000).map { .init(path: "items[\($0)].title", failure: .blank) }))
}

// MARK: - 3. Unicode

@Test func lengthCountsVisibleCharactersNotBytes() {
    let family = "👩‍👩‍👧"  // 1 Character, 5 Unicode scalars, 18 UTF-8 bytes
    #expect(failure(Title.mk(String(repeating: family, count: 120))) == nil)
    #expect(failure(Title.mk(String(repeating: family, count: 121))) == .tooLong)

    let decomposed = "e\u{301}"  // é as e + combining accent: 1 Character
    #expect(failure(Title.mk(String(repeating: decomposed, count: 120))) == nil)
    #expect(failure(Title.mk(String(repeating: decomposed, count: 121))) == .tooLong)
}

@Test func unicodeWhitespaceIsTrimmedAndTextSurvives() throws {
    #expect(try Title.mk("\u{00A0}\u{3000}Milk\u{2003}\n").get().value == "Milk")
    #expect(failure(Title.mk("\u{00A0}\u{2003}\u{3000}")) == .blank)
    #expect(try Title.mk("שלום עולם").get().value == "שלום עולם")
    #expect(try Title.mk("e\u{301}clair").get().value == "e\u{301}clair")  // not silently normalized to é
}

@Test func slugRejectsLookalikes() throws {
    #expect(failure(Slug.mk("week\u{200B}end")) == .notASlug)  // zero-width space
    #expect(failure(Slug.mk("İstanbul")) == .notASlug)  // lowercases to i + combining dot
    #expect(failure(Slug.mk("wеekend")) == .notASlug)  // Cyrillic е
    #expect(try Slug.mk(" WEEKEND-Plans ").get().value == "weekend-plans")
}

// MARK: - 4. Hostile JSON

private let validItem = #"{"title":"t","done":false,"priority":"low","tags":[],"subtasks":[]}"#
private func doc(items: String = "[]", settings: String = #"{"sort":"manual","timezone":"UTC"}"#, title: String = #""L""#) -> String {
    #"{"title":\#(title),"slug":"l","owner":{"email":"a@b.co","name":"A"},"sharedWith":[],"settings":\#(settings),"items":\#(items)}"#
}

@Test(arguments: [
    "",
    "null",
    "[]",
    #"{"title":"#,
    doc(title: "42"),
    doc(title: "null"),
    doc(items: "{}"),
    doc(items: #"[{"title":"t","done":"true","priority":"low","tags":[],"subtasks":[]}]"#),
    doc(settings: #"{"sort":"manual","reminderDefault":1e30,"timezone":"UTC"}"#),
    doc(settings: #"{"sort":"manual","reminderDefault":9223372036854775808,"timezone":"UTC"}"#),
    doc(settings: #"{"sort":"manual","reminderDefault":1.5,"timezone":"UTC"}"#),
    #"{"title":"L"}"#,
])
func wrongShapeIsMalformedNeverACrash(json: String) {
    guard case .failure(.malformed) = TodoList.decode(json: Data(json.utf8)) else {
        Issue.record("expected .malformed")
        return
    }
}

@Test func harmlessOddJSONStillParses() throws {
    let extra = doc(items: #"[{"title":"t","done":false,"priority":"low","tags":[],"subtasks":[],"$where":{"admin":true}}]"#)
    #expect(try TodoList.decode(json: Data(extra.utf8)).get().items.count == 1)  // unknown keys ignored

    let explicitNull = doc(items: #"[{"title":"t","done":false,"priority":"low","due":null,"tags":[],"subtasks":[]}]"#)
    #expect(try TodoList.decode(json: Data(explicitNull.utf8)).get().items[0].due == nil)

    let huge = doc(title: "\"" + String(repeating: "x", count: 1_000_000) + "\"")
    #expect(issues(TodoList.decode(json: Data(huge.utf8))) == Issues([.init(path: "title", failure: .tooLong)]))
}

/// Foundation's JSONDecoder keeps the first value of a duplicated key. Pinned so a Foundation change is noticed.
@Test func duplicateKeysKeepTheFirstValue() throws {
    let json = #"{"title":"Kept","title":"   ","slug":"l","owner":{"email":"a@b.co","name":"A"},"sharedWith":[],"settings":{"sort":"manual","timezone":"UTC"},"items":[]}"#
    #expect(try TodoList.decode(json: Data(json.utf8)).get().title.value == "Kept")
}

// MARK: - 5. Concurrency and stability

@Test func twoHundredParallelDecodesAgree() async {
    let input = Data(Fixture.valid.utf8)
    let outputs = await withTaskGroup(of: Data?.self) { group in
        for _ in 0..<200 { group.addTask { try? TodoList.decode(json: input).get().json() } }
        return await group.reduce(into: [Data?]()) { $0.append($1) }
    }
    #expect(outputs.count == 200)
    #expect(outputs.allSatisfy { $0 != nil && $0 == outputs[0] })
}

@Test func issueOrderAndGeneratorAreDeterministic() throws {
    let input = Data(Fixture.invalid.utf8)
    let first = issues(TodoList.decode(json: input))
    #expect(first?.all.count == 11)
    for _ in 0..<50 { #expect(issues(TodoList.decode(json: input)) == first) }

    var a = Monkey(seed: 42, errorRate: 0.2)
    var b = Monkey(seed: 42, errorRate: 0.2)
    let bytesA = try bytes(a.list()), bytesB = try bytes(b.list())
    #expect(bytesA == bytesB)
    #expect(a.injected.map(\.path) == b.injected.map(\.path))
}
