import Codomain
import Testing

private let t = Text.identity

@Test func caseTransforms() {
    #expect(t.lowercased().run("AbC") == .success("abc"))
    #expect(t.uppercased().run("AbC") == .success("ABC"))
}

@Test func lengthsCountCharactersAsPeopleSeeThem() {
    #expect(t.min(2, .tooLong).run("👩‍👩‍👧") == .failure(.tooLong))
    #expect(t.min(2, .tooLong).run("ab") == .success("ab"))
    #expect(t.length(1, .tooLong).run("👩‍👩‍👧") == .success("👩‍👩‍👧"))
    #expect(t.length(2, .tooLong).run("abc") == .failure(.tooLong))
    #expect(t.nilIfEmpty().min(2, .tooLong).length(5, .tooLong).run("") == .success(nil))
}

@Test func affixes() {
    #expect(t.startsWith("ab", .noMatch).run("abc") == .success("abc"))
    #expect(t.startsWith("bc", .noMatch).run("abc") == .failure(.noMatch))
    #expect(t.endsWith("bc", .noMatch).run("abc") == .success("abc"))
    #expect(t.endsWith("ab", .noMatch).run("abc") == .failure(.noMatch))
    #expect(t.includes("b", .noMatch).run("abc") == .success("abc"))
    #expect(t.includes("x", .noMatch).run("abc") == .failure(.noMatch))
}

@Test(arguments: [
    ("a@b.co", true), ("a.b+c@d-e.io", true), ("a@b", false), ("a b@c.io", false),
    (" a@b.co", false), ("a@@b.co", false),
])
func email(_ raw: String, _ ok: Bool) {
    #expect(t.email(.noMatch).run(raw) == (ok ? .success(raw) : .failure(.noMatch)))
}

@Test(arguments: [
    ("https://x.io/p?q=1", true), ("http://localhost:8080", true), ("ftp://x.io", false),
    ("https://", false), ("x.io", false), ("", false),
])
func url(_ raw: String, _ ok: Bool) {
    #expect(t.url(.noMatch).run(raw) == (ok ? .success(raw) : .failure(.noMatch)))
}

@Test(arguments: [
    ("E621E1F8-C36C-495A-93FC-0C247A3E6E5F", true), ("e621e1f8-c36c-495a-93fc-0c247a3e6e5f", true),
    ("E621E1F8C36C495A93FC0C247A3E6E5F", false), ("x", false),
])
func uuid(_ raw: String, _ ok: Bool) {
    #expect(t.uuid(.noMatch).run(raw) == (ok ? .success(raw) : .failure(.noMatch)))
}

@Test(arguments: [
    ("2026-10-05T12:00:00Z", true), ("2026-10-05T12:00:00.123Z", true),
    ("2026-10-05T12:00:00+02:00", true),
    ("2026-10-05", false), ("2026-13-05T12:00:00Z", false), ("2026-02-30T12:00:00Z", false),
    ("2028-02-29T00:00:00Z", true),
    (" 2026-10-05T12:00:00Z", false),
])
func datetime(_ raw: String, _ ok: Bool) {
    #expect(t.datetime(.noMatch).run(raw) == (ok ? .success(raw) : .failure(.noMatch)))
}

@Test(arguments: [
    ("192.168.0.1", IPVersion?.none, true), ("256.1.1.1", nil, false), ("1.2.3", nil, false),
    ("::1", nil, true),
    ("2001:db8::8a2e:370:7334", nil, true), ("::1", .v4, false), ("10.0.0.1", .v6, false),
    ("10.0.0.1", .v4, true), ("::1", .v6, true),
])
func ip(_ raw: String, _ version: IPVersion?, _ ok: Bool) {
    #expect(t.ip(.noMatch, version: version).run(raw) == (ok ? .success(raw) : .failure(.noMatch)))
}

@Test func aRegexGoesInRefine() {
    let slug = t.refine(.noMatch) { $0.wholeMatch(of: #/[a-z0-9]+(-[a-z0-9]+)*/#) != nil }
    #expect(slug.run("ab-1") == .success("ab-1"))
    #expect(slug.run("x ab-1") == .failure(.noMatch))
}

@Test func checksLetAbsentPass() {
    let absent = t.nilIfEmpty()
    for rule in [
        absent.email(.noMatch), absent.url(.noMatch), absent.uuid(.noMatch),
        absent.datetime(.noMatch), absent.ip(.noMatch), absent.startsWith("a", .noMatch),
    ] {
        #expect(rule.run("") == .success(nil))
    }
}
