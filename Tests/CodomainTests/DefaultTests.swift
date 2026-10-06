import Codomain
import Foundation
import Testing

@Test func anAbsentDefaultedFieldTakesItsDefault() throws {
    #expect(try Defaults.parse(.init(x: 4)).get() == Defaults(size: .unsafeMk(2), x: .unsafeMk(4)))
    #expect(try Defaults.parse(.init(size: 6, x: 4)).get().size.value == 6)
    #expect(try Defaults.decode(json: Data(#"{"x":4}"#.utf8)).get().size.value == 2)
    #expect(try Defaults.decode(json: Data(#"{"size":null,"x":4}"#.utf8)).get().size.value == 2)
    #expect(try Defaults.decode(json: Data(#"{"size":6,"x":4}"#.utf8)).get().size.value == 6)
}

@Test func aDefaultedFieldIsAlwaysWritten() throws {
    let value = try Defaults.decode(json: Data(#"{"x":4}"#.utf8)).get()
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    #expect(
        String(decoding: try encoder.encode(value.encoded), as: UTF8.self) == #"{"size":2,"x":4}"#)
}

@Test func aDefaultIsCheckedLikeAnyValue() {
    guard case .failure(let issues) = BadDefault.parse(.init()) else {
        Issue.record("expected failure")
        return
    }
    #expect(issues == Issues("size", .odd))
    guard case .failure(.invalid(let problems)) = BadDefault.decode(json: Data("{}".utf8)) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(problems == Issues("size", .rule(.odd)))
}
