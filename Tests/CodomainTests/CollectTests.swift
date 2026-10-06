import Codomain
import Foundation
import Testing

@Test func collectKeepsEveryFailingCheck() throws {
    #expect(
        Password.parse(" abc ")
            == .failure(
                Issues([.init(path: "", failure: .first), .init(path: "", failure: .second)])))
    #expect(Password.parse("abc1") == .failure(Issues("", .first)))
    #expect(Password.mk("abc") == .failure(.first))
    #expect(try Password.parse(" ABCDEFG1 ").get().value == "abcdefg1")
}

@Test func collectedFailuresReachTheModelAndJSON() {
    guard case .failure(let issues) = Account.parse(.init(password: "abc")) else {
        Issue.record("expected failure")
        return
    }
    #expect(issues.description == "password: first, password: second")
    guard
        case .failure(.invalid(let problems)) = Account.decode(
            json: Data(#"{"password":"abc"}"#.utf8))
    else {
        Issue.record("expected .invalid")
        return
    }
    #expect(problems.description == "password: first, password: second")
}

@Test func collectReturnsTheLastChecksOutputWhenAllPass() {
    let schema = Text.identity.collect({ $0.min(1, .first) }, { $0.trimmed().nonEmpty(.blank) })
    #expect(schema.run(" a ").map { $0 } == .success("a"))
    #expect(schema.run(" ").map { $0 } == .failure(.blank))
}
