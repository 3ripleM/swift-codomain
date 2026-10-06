import Foundation
import Schema
import Testing

@Test(arguments: [
    (#"{"x":2,"y":1,"a":null}"#, "a: unexpected, y: unexpected"),
    (#"{"x":3,"y":1}"#, "x: odd, y: unexpected"),
    (#"{"inner_value":{"x":2},"innerValue":{"x":2}}"#, "innerValue: unexpected"),
    (#"{"inner_value":{"x":2,"z":0}}"#, "inner_value.z: unexpected"),
])
func aStrictModelReportsUndeclaredKeys(json: String, expected: String) {
    let result: String
    if json.contains("inner") {
        guard case .failure(.invalid(let issues)) = ClosedOuter.decode(json: Data(json.utf8)) else {
            Issue.record("expected .invalid")
            return
        }
        result = issues.description
    } else {
        guard case .failure(.invalid(let issues)) = Closed.decode(json: Data(json.utf8)) else {
            Issue.record("expected .invalid")
            return
        }
        result = issues.description
    }
    #expect(result == expected)
}

@Test func aStrictPayloadAcceptsItsUnionsTag() throws {
    #expect(
        try ClosedUnion.decode(json: Data(#"{"kind":"closed","x":2}"#.utf8)).get()
            == .closed(Closed(x: .unsafeMk(2))))
    guard
        case .failure(.invalid(let issues)) = ClosedUnion.decode(
            json: Data(#"{"kind":"outer","inner_value":{"x":2,"kind":"no"},"z":0}"#.utf8))
    else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues.description == "inner_value.kind: unexpected, z: unexpected")
}

@Test func aStrictPayloadAcceptsEveryEnclosingUnionsTag() throws {
    let json = #"{"outer":"inner","inner":"closed","x":2}"#
    #expect(
        try OuterUnion.decode(json: Data(json.utf8)).get()
            == .inner(.closed(Closed(x: .unsafeMk(2)))))
    guard
        case .failure(.invalid(let issues)) = OuterUnion.decode(
            json: Data(#"{"outer":"inner","inner":"closed","x":2,"y":0}"#.utf8))
    else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues.description == "y: unexpected")
}
