import Foundation
import Schema
import Testing

@Test func aUnionParsesTheCaseItIsGiven() throws {
    #expect(try Choice.parse(.even(2)).get() == .even(.unsafeMk(2)))
    #expect(try Choice.parse(.tag(" a ")).get() == .tag(.unsafeMk("a")))
    guard case .even(2) = Choice.even(.unsafeMk(2)).encoded else {
        Issue.record("expected .even(2)")
        return
    }
}

@Test func aUnionCaseFailureKeepsThePayloadPath() {
    guard case .failure(let odd) = Choice.parse(.even(3)),
        case .failure(let blank) = Choice.parse(.tag(" "))
    else {
        Issue.record("expected failures")
        return
    }
    #expect(odd == Issues("", .odd))
    #expect(blank == Issues("", .tag(.bad)))
}

@Test func aModelCaseFailureKeepsThePayloadPath() {
    guard case .failure(let issues) = Shape.parse(.circle(Circle.Input(radius: 3))) else {
        Issue.record("expected failure")
        return
    }
    #expect(issues == Issues("radius", .odd))
}

@Test func aTaggedUnionRoundTripsThroughJSON() throws {
    let json = #"{"kind":"circle","radius":2}"#
    let shape = try Shape.decode(json: Data(json.utf8)).get()
    #expect(shape == .circle(Circle(radius: .unsafeMk(2))))
    #expect(String(decoding: try shape.json(), as: UTF8.self) == json)
}

@Test(arguments: [
    (
        #"{"shapes":[{"kind":"square","side":2},{"kind":"circle","radius":3}]}"#,
        #"shapes[1].radius: odd"#
    ),
    (
        #"{"shapes":[{"kind":"hexagon"}]}"#,
        #"shapes[0].kind: wrongType(expected: "circle | square")"#
    ),
    (
        #"{"shapes":[{"kind":7,"side":2}]}"#,
        #"shapes[0].kind: wrongType(expected: "circle | square")"#
    ),
    (#"{"shapes":[{"side":2}]}"#, #"shapes[0].kind: missing"#),
    (#"{"shapes":[{"kind":null}]}"#, #"shapes[0].kind: missing"#),
    (#"{"shapes":["circle"]}"#, #"shapes[0]: wrongType(expected: "object")"#),
])
func aTaggedUnionReportsItsProblemsFromJSON(json: String, expected: String) {
    guard case .failure(.invalid(let issues)) = Drawing.decode(json: Data(json.utf8)) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues.description == expected)
}

@Test func aUnionsRefineRunsAfterItsCaseParses() {
    guard case .failure(let issues) = Small.parse(.circle(Circle.Input(radius: 12))) else {
        Issue.record("expected failure")
        return
    }
    #expect(issues == Issues("radius", .tooLong))
    guard
        case .failure(.invalid(let problems)) = Small.decode(
            json: Data(#"{"kind":"circle","radius":12}"#.utf8))
    else {
        Issue.record("expected .invalid")
        return
    }
    #expect(problems == Issues("radius", .rule(.tooLong)))
}

@Test func anOverriddenTagDecodesAndEncodesUnchanged() throws {
    let json = #"{"radius":2,"type":"CIRCLE"}"#
    let shape = try Tagged.decode(json: Data(json.utf8)).get()
    #expect(shape == .circle(Circle(radius: .unsafeMk(2))))
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    #expect(String(decoding: try encoder.encode(shape.encoded), as: UTF8.self) == json)
    #expect(String(decoding: try shape.json(), as: UTF8.self).contains(#""type":"CIRCLE""#))
    #expect(
        String(
            decoding: try encoder.encode(Tagged.square(Square(side: .unsafeMk(4))).encoded),
            as: UTF8.self) == #"{"side":4,"type":"SQUARE"}"#)
}

@Test func anOverriddenTagIsTheOnlyOneAccepted() {
    guard
        case .failure(.invalid(let issues)) = Tagged.decode(
            json: Data(#"{"type":"circle","radius":2}"#.utf8))
    else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues.description == #"type: wrongType(expected: "CIRCLE | SQUARE")"#)
}

@Test func anUnknownTagDecodesToTheMarkedCaseAndEncodesOnlyTheTag() throws {
    let open = try Open.decode(json: Data(#"{"kind":"triangle","sides":3}"#.utf8)).get()
    #expect(open == .other("triangle"))
    #expect(String(decoding: try open.json(), as: UTF8.self) == #"{"kind":"triangle"}"#)
    #expect(
        try Open.decode(json: Data(#"{"kind":"circle","radius":2}"#.utf8)).get()
            == .circle(Circle(radius: .unsafeMk(2))))
    #expect(try Open.parse(.other("triangle")).get() == .other("triangle"))
    let input = try JSONDecoder().decode(Open.Input.self, from: Data(#"{"kind":"triangle"}"#.utf8))
    guard case .other("triangle") = input else {
        Issue.record("expected .other")
        return
    }
}

@Test(arguments: [
    (#"{"radius":2}"#, "kind: missing"),
    (#"{"kind":null}"#, "kind: missing"),
    (#"{"kind":7}"#, #"kind: wrongType(expected: "string")"#),
])
func anUnknownTagStillNeedsAStringTag(json: String, expected: String) {
    guard case .failure(.invalid(let issues)) = Open.decode(json: Data(json.utf8)) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues.description == expected)
}
