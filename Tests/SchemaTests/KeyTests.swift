import Foundation
import Schema
import Testing

@Test func renamedKeysRoundTripThroughJSON() throws {
    let json = #"{"due_date":2,"url_path":"a","user_id":4,"x-y":6}"#
    let value = try Renamed.decode(json: Data(json.utf8)).get()
    #expect(
        value.dueDate.value == 2 && value.userID.value == 4 && value.custom.value == 6
            && value.urlPath?.value == "a")
    #expect(String(decoding: try value.json(), as: UTF8.self) == json)
}

@Test func jsonProblemsUseTheJSONKey() {
    let json = #"{"due_date":3,"userID":4,"x-y":"a"}"#
    guard case .failure(.invalid(let issues)) = Renamed.decode(json: Data(json.utf8)) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(
        issues
            == Issues([
                .init(path: "due_date", failure: .rule(.odd)),
                .init(path: "user_id", failure: .missing),
                .init(path: "x-y", failure: .wrongType(expected: "Int")),
            ]))
}

@Test func parseProblemsUseTheSwiftName() {
    guard case .failure(let issues) = Renamed.parse(.init(dueDate: 3, userID: 2, custom: 2)) else {
        Issue.record("expected failure")
        return
    }
    #expect(issues == Issues("dueDate", .odd))
}
