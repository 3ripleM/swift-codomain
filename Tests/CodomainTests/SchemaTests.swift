import Codomain
import Testing

@Test func identityPassesInputUnchanged() {
    #expect(Text.identity.run(" a ") == .success(" a "))
}

@Test func mapTransformsTheOutput() {
    #expect(Text.identity.map { $0.count }.run("abc") == .success(3))
}

@Test func compactMapTurnsNilIntoTheFailure() {
    let int = Text.identity.compactMap(.notInt) { Int($0) }
    #expect(int.run("12") == .success(12))
    #expect(int.run("x") == .failure(.notInt))
}

@Test func checkKeepsValidAndRejectsInvalid() {
    let even = Text.identity.refine(.odd) { $0.count % 2 == 0 }
    #expect(even.run("ab") == .success("ab"))
    #expect(even.run("abc") == .failure(.odd))
}

@Test func chainStopsAtItsFirstFailure() {
    let chain = Text.identity.refine(.first) { _ in false }.refine(.second) { _ in false }
    #expect(chain.run("x") == .failure(.first))
}

@Test func trimmedRemovesUnicodeWhitespaceAndNewlinesAtBothEnds() {
    #expect(Text.identity.trimmed().run(" \n\u{00A0}a b\t") == .success("a b"))
}

@Test func nonEmptyDoesNotTrimByItself() {
    #expect(Text.identity.nonEmpty(.blank).run("") == .failure(.blank))
    #expect(Text.identity.nonEmpty(.blank).run(" ") == .success(" "))
    #expect(Text.identity.trimmed().nonEmpty(.blank).run(" ") == .failure(.blank))
}

@Test func nilIfEmptyMakesBlankAbsent() {
    #expect(Text.identity.nilIfEmpty().run("") == .success(nil))
    #expect(Text.identity.nilIfEmpty().run("a") == .success("a"))
}

@Test func mapOnAnOptionalStringSkipsAbsent() {
    let count = Text.identity.nilIfEmpty().map { $0.count }
    #expect(count.run("") == .success(nil))
    #expect(count.run("ab") == .success(2))
}

@Test func maxCountsCharactersAndLetsAbsentPass() {
    #expect(Text.identity.max(2, .tooLong).run("ab") == .success("ab"))
    #expect(Text.identity.max(2, .tooLong).run("abc") == .failure(.tooLong))
    #expect(Text.identity.max(1, .tooLong).run("👩‍👩‍👧") == .success("👩‍👩‍👧"))
    #expect(Text.identity.nilIfEmpty().max(1, .tooLong).run("") == .success(nil))
}
