import Codomain
import Foundation
import Testing

private func plist(_ value: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
}

@Test func anyDataDecoderReadsAModel() throws {
    let data = try plist(["x": 2, "label": " ab "])
    let point = try Point.decode(data, using: PropertyListDecoder()).get()
    #expect(point.x.value == 2 && point.label?.value == "ab")
}

@Test func anyDataDecoderReportsEveryProblem() throws {
    guard
        case .failure(.invalid(let issues)) = Point.decode(
            try plist(["x": 3, "label": "toolong"]), using: PropertyListDecoder())
    else {
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

@Test func badBytesAreNotJSONWhateverTheDecoder() {
    guard
        case .failure(.unreadable) = Point.decode(
            Data("not a plist".utf8), using: PropertyListDecoder())
    else {
        Issue.record("expected .unreadable")
        return
    }
}

/// A decoder that throws something other than `DecodingError`.
private struct Broken: DataDecoder {
    struct Boom: Error {}
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T { throw Boom() }
}

@Test func aNonDecodingErrorIsWrappedNotCrashed() {
    guard
        case .failure(.unreadable(.dataCorrupted(let context))) = Point.decode(Data(), using: Broken())
    else {
        Issue.record("expected .unreadable(.dataCorrupted)")
        return
    }
    #expect(context.underlyingError is Broken.Boom)
}
