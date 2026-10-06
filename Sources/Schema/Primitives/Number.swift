extension Schema where Output: Comparable & Sendable {
    /// Any range: `1...10`, `1...`, `..<100`, `0.0..<1.0`. NaN is in no range.
    public func within<R: RangeExpression & Sendable>(_ range: R, _ failure: Failure) -> Schema
    where R.Bound == Output {
        refine(failure) { range.contains($0) }
    }
}

extension Schema where Output: Comparable & AdditiveArithmetic {
    /// `> 0`; `-0.0` is not positive.
    public func positive(_ failure: Failure) -> Schema { refine(failure) { $0 > .zero } }
    public func nonNegative(_ failure: Failure) -> Schema { refine(failure) { $0 >= .zero } }
    public func negative(_ failure: Failure) -> Schema { refine(failure) { $0 < .zero } }
    public func nonPositive(_ failure: Failure) -> Schema { refine(failure) { $0 <= .zero } }
}

extension Schema where Output: BinaryInteger & Sendable {
    /// `0` is a multiple of everything; only `0` is a multiple of `0`.
    public func multiple(of divisor: Output, _ failure: Failure) -> Schema {
        refine(failure) { $0.isMultiple(of: divisor) }
    }
}

extension Schema where Output: FloatingPoint {
    /// Not infinite, not NaN.
    public func finite(_ failure: Failure) -> Schema { refine(failure) { $0.isFinite } }
}
