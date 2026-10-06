@testable import Schema
import Testing

private typealias Issue = Issues<F>.Issue

@Test func prefixedJoinsPropertiesWithADotAndIndexesWithout() {
    let issues = Issues<F>([Issue(path: "city", failure: .blank), Issue(path: "[1]", failure: .odd), Issue(path: "", failure: .tooLong)])
    #expect(issues.prefixed("address").map(\.path) == ["address.city", "address[1]", "address"])
}

@Test func descriptionListsPathAndFailure() {
    let issues = Issues<F>([Issue(path: "email", failure: .blank), Issue(path: "phones[1]", failure: .tooLong)])
    #expect(issues.description == "email: blank, phones[1]: tooLong")
}

@Test func equalityIsOrderSensitive() {
    let a = Issue(path: "a", failure: .blank), b = Issue(path: "b", failure: .odd)
    #expect(Issues<F>("a", .blank) == Issues([a]))
    #expect(Issues([a, b]) != Issues([b, a]))
}

@Test func arrayParseReportsEveryFailingIndex() {
    #expect([Even].parse([2, 3, 4, 5]) == .failure(Issues([Issue(path: "[1]", failure: .odd), Issue(path: "[3]", failure: .odd)])))
    #expect([Even].parse([2, 4]).map { $0.map(\.value) } == .success([2, 4]))
    #expect([Even].parse([]).map(\.count) == .success(0))
    #expect([Even.unsafeMk(2), Even.unsafeMk(8)].encoded == [2, 8])
}

@Test func nestedArraysChainIndexes() {
    #expect([[Even]].parse([[2], [3, 5]]) == .failure(Issues([Issue(path: "[1][0]", failure: .odd), Issue(path: "[1][1]", failure: .odd)])))
}

@Test func collectorRequiredRecordsFailuresUnderThePath() {
    var collector = IssueCollector<F>()
    #expect(collector.required("n", 2, as: Even.self) == Even.unsafeMk(2))
    #expect(collector.required("m", 3, as: Even.self) == nil)
    #expect(collector.issues == [Issue(path: "m", failure: .odd)])
}

@Test func collectorOptionalDistinguishesAbsentFromFailed() {
    var collector = IssueCollector<F>()
    #expect(collector.optional("a", nil, as: Even.self) == .some(nil))  // absent: fine
    #expect(collector.optional("b", 4, as: Even.self) == .some(Even.unsafeMk(4)))
    #expect(collector.optional("c", 5, as: Even.self) == .none)  // failed
    #expect(collector.issues == [Issue(path: "c", failure: .odd)])
}

@Test func collectorOptionalFieldLetsTheSchemaDecideAbsent() {
    var collector = IssueCollector<F>()
    #expect(collector.optional("a", nil, as: Nick.self) == .some(nil))
    #expect(collector.optional("b", "   ", as: Nick.self) == .some(nil))  // blank → absent
    #expect(collector.optional("c", "abcd", as: Nick.self) == .none)
    #expect(collector.issues == [Issue(path: "c", failure: .tooLong)])
}
