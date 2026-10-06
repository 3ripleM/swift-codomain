import Foundation
import Schema
import Testing

private func decode(_ json: String) -> Result<Point, JSONFailure<F>> { Point.decode(json: Data(json.utf8)) }

@Test func decodeJSONParsesAndNormalizes() throws {
    let point = try decode(#"{"x":2,"label":" ab "}"#).get()
    #expect(point.x.value == 2)
    #expect(point.label?.value == "ab")
    #expect(try decode(#"{"x":2}"#).get().label == nil)
}

@Test func wrongShapeIsMalformed() {
    guard case .failure(.malformed) = decode(#"{"x":"2"}"#) else { Issue.record("expected .malformed"); return }
}

@Test func ruleFailuresAreInvalidWithEveryIssue() {
    guard case .failure(.invalid(let issues)) = decode(#"{"x":3,"label":"abcd"}"#) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues == Issues([.init(path: "x", failure: .odd), .init(path: "label", failure: .tooLong)]))
}

@Test func jsonHasSortedKeysAndOmitsAbsentOptionals() throws {
    #expect(try String(decoding: decode(#"{"x":2,"label":"ab"}"#).get().json(), as: UTF8.self) == #"{"label":"ab","x":2}"#)
    #expect(try String(decoding: decode(#"{"x":2,"label":" "}"#).get().json(), as: UTF8.self) == #"{"x":2}"#)
}

@Test func nonFiniteNumbersThrowEncodingError() throws {
    let reading = try Reading.parse(Reading.Input(value: .nan)).get()
    #expect(throws: EncodingError.self) { try reading.json() }
}
