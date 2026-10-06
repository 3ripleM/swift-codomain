import Codomain
import Foundation
import Testing

@Test func childFailuresAreLiftedIntoTheParentFailure() {
    let input = Labeled.Input(
        x: 3, tag: Tag.Input(name: " "), tags: [Tag.Input(name: "a"), Tag.Input(name: "")],
        alias: "\n")
    guard case .failure(let issues) = Labeled.parse(input) else {
        Issue.record("expected failure")
        return
    }
    #expect(
        issues
            == Issues([
                .init(path: "x", failure: .odd),
                .init(path: "tag.name", failure: .tag(.bad)),
                .init(path: "tags[1].name", failure: .tag(.bad)),
                .init(path: "alias", failure: .tag(.bad)),
            ]))
}

@Test func childFailuresAreLiftedFromJSON() {
    let json = #"{"x":3,"tag":{"name":" "},"tags":[{"name":"a"},{"name":7}],"alias":""}"#
    guard case .failure(.invalid(let issues)) = Labeled.decode(json: Data(json.utf8)) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(
        issues
            == Issues([
                .init(path: "x", failure: .rule(.odd)),
                .init(path: "tag.name", failure: .rule(.tag(.bad))),
                .init(path: "tags[1].name", failure: .wrongType(expected: "String")),
                .init(path: "alias", failure: .rule(.tag(.bad))),
            ]))
}
