import Codomain
import Testing

private let int = Schema<Int, Int, F>.identity
private let real = Schema<Double, Double, F>.identity

@Test func withinTakesAnyRange() {
    #expect(int.within(1...10, .odd).run(10) == .success(10))
    #expect(int.within(1...10, .odd).run(0) == .failure(.odd))
    #expect(int.within(1..., .odd).run(.max) == .success(.max))
    #expect(int.within(..<10, .odd).run(10) == .failure(.odd))
    #expect(real.within(0.0..<1.0, .odd).run(0.5) == .success(0.5))
    #expect(real.within(0.0..<1.0, .odd).run(.nan) == .failure(.odd))
}

@Test func signs() {
    #expect(int.positive(.odd).run(0) == .failure(.odd))
    #expect(int.positive(.odd).run(1) == .success(1))
    #expect(int.nonNegative(.odd).run(0) == .success(0))
    #expect(int.nonNegative(.odd).run(-1) == .failure(.odd))
    #expect(int.negative(.odd).run(0) == .failure(.odd))
    #expect(int.negative(.odd).run(-1) == .success(-1))
    #expect(int.nonPositive(.odd).run(0) == .success(0))
    #expect(int.nonPositive(.odd).run(1) == .failure(.odd))
    #expect(real.positive(.odd).run(0.1) == .success(0.1))
    #expect(real.positive(.odd).run(-0.0) == .failure(.odd))
}

@Test func multipleOf() {
    #expect(int.multiple(of: 5, .odd).run(-10) == .success(-10))
    #expect(int.multiple(of: 5, .odd).run(0) == .success(0))
    #expect(int.multiple(of: 5, .odd).run(11) == .failure(.odd))
}

@Test func finite() {
    #expect(real.finite(.odd).run(1) == .success(1))
    #expect(real.finite(.odd).run(.infinity) == .failure(.odd))
    #expect(real.finite(.odd).run(.nan) == .failure(.odd))
}
