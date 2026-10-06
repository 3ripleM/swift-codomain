import Codomain
import Foundation
import Testing

@Test func refineReportsCrossFieldFailures() {
    guard case .failure(let issues) = Bounds.parse(Bounds.Input(low: 4, high: 2)) else {
        Issue.record("expected failure")
        return
    }
    #expect(issues == Issues("high", .outOfOrder))
    #expect((try? Bounds.parse(Bounds.Input(low: 2, high: 4)).get())?.high.value == 4)
}

@Test func nestedRefineFailureGetsItsPathFromJSON() {
    let json = #"{"slots":[{"low":2,"high":4},{"low":4,"high":2}]}"#
    guard case .failure(.invalid(let issues)) = Schedule.decode(json: Data(json.utf8)) else {
        Issue.record("expected .invalid")
        return
    }
    #expect(issues == Issues("slots[1].high", .rule(.outOfOrder)))
}

@Test func refineIsSkippedWhenAFieldFails() {
    guard case .failure(let issues) = Bounds.parse(Bounds.Input(low: 3, high: 2)) else {
        Issue.record("expected failure")
        return
    }
    #expect(issues == Issues("low", .odd))
}
