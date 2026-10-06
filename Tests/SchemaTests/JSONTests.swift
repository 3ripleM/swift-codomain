import Foundation
import Schema
import Testing

private func decode(_ json: String) -> Result<Point, DecodeFailure<F>> {
    Point.decode(json: Data(json.utf8))
}

@Test func decodeJSONParsesAndNormalizes() throws {
    let point = try decode(#"{"x":2,"label":" ab "}"#).get()
    #expect(point.x.value == 2)
    #expect(point.label?.value == "ab")
    #expect(try decode(#"{"x":2}"#).get().label == nil)
}

@Test func wrongTypeIsReportedAlongsideRuleFailures() {
    guard case .failure(.invalid(let issues)) = decode(#"{"x":"2","label":"abcd"}"#) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues.all.map(\.path) == ["x", "label"])
    guard case .wrongType = issues.all.first?.failure else {
        Issue.record("expected wrongType")
        return
    }
    #expect(issues.all.last?.failure == .rule(.tooLong))
    #expect("\(issues)" == #"x: wrongType(expected: "Int"), label: tooLong"#)
}

@Test func everyBadArrayElementIsReported() {
    let json = #"{"points":[{"x":"a"},{"x":2},{"label":"ab"},{"x":3,"label":null}]}"#
    guard case .failure(.invalid(let issues)) = Polyline.decode(json: Data(json.utf8)) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(
        issues
            == Issues([
                .init(path: "points[0].x", failure: .wrongType(expected: "Int")),
                .init(path: "points[2].x", failure: .missing),
                .init(path: "points[3].x", failure: .rule(.odd)),
            ]))
}

@Test func ruleFailuresAreInvalidWithEveryIssue() {
    guard case .failure(.invalid(let issues)) = decode(#"{"x":3,"label":"abcd"}"#) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(
        issues
            == Issues([
                .init(path: "x", failure: .rule(.odd)),
                .init(path: "label", failure: .rule(.tooLong)),
            ]))
}

@Test func jsonHasSortedKeysAndOmitsAbsentOptionals() throws {
    #expect(
        try String(decoding: decode(#"{"x":2,"label":"ab"}"#).get().json(), as: UTF8.self)
            == #"{"label":"ab","x":2}"#)
    #expect(
        try String(decoding: decode(#"{"x":2,"label":" "}"#).get().json(), as: UTF8.self)
            == #"{"x":2}"#)
}

@Test func nonFiniteNumbersThrowEncodingError() throws {
    let reading = try Reading.parse(Reading.Input(value: .nan)).get()
    #expect(throws: EncodingError.self) { try reading.json() }
}
