import Foundation
import Schema
import Testing

@Test func everyBadDictionaryValueIsReportedByKeyInKeyOrder() {
    let input = Board.Input(lanes: ["b": 3, "a": 2, "c": 5], pins: ["x\"y": Point.Input(x: 1)])
    guard case .failure(let issues) = Board.parse(input) else {
        Issue.record("expected failure")
        return
    }
    #expect(
        issues
            == Issues([
                .init(path: #"lanes["b"]"#, failure: .odd),
                .init(path: #"lanes["c"]"#, failure: .odd),
                .init(path: #"pins["x\"y"].x"#, failure: .odd),
            ]))
}

@Test func everyBadDictionaryValueIsReportedFromJSON() {
    let json = #"{"lanes":{"b":3,"a":2,"c":"x"},"pins":{"p":{"x":1}}}"#
    guard case .failure(.invalid(let issues)) = Board.decode(json: Data(json.utf8)) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(
        issues
            == Issues([
                .init(path: #"lanes["b"]"#, failure: .rule(.odd)),
                .init(path: #"lanes["c"]"#, failure: .wrongType(expected: "Int")),
                .init(path: #"pins["p"].x"#, failure: .rule(.odd)),
            ]))
}

@Test func aDictionaryRoundTripsThroughJSON() throws {
    let json = #"{"lanes":{"a":2,"b":4}}"#
    let board = try Board.decode(json: Data(json.utf8)).get()
    #expect(board.lanes == ["a": .unsafeMk(2), "b": .unsafeMk(4)])
    #expect(board.pins == nil)
    #expect(String(decoding: try board.json(), as: UTF8.self) == json)
}

@Test func aDictionaryThatIsNotAnObjectIsAWrongType() {
    guard case .failure(.invalid(let issues)) = Board.decode(json: Data(#"{"lanes":[2]}"#.utf8))
    else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues == Issues("lanes", .wrongType(expected: "object")))
}
