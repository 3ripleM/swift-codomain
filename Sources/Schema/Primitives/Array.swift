// Steps for a field whose value is an array, e.g. `Codec<[String], [String], F>`.
// A model's array property (`let items: [Todo]`) is not a chain: check its count in `refine`.
extension Schema {
    public func min<Element>(_ count: Int, _ failure: Failure) -> Schema where Output == [Element] {
        refine(failure) { $0.count >= count }
    }

    public func max<Element>(_ count: Int, _ failure: Failure) -> Schema where Output == [Element] {
        refine(failure) { $0.count <= count }
    }

    public func length<Element>(_ count: Int, _ failure: Failure) -> Schema
    where Output == [Element] {
        refine(failure) { $0.count == count }
    }

    public func nonEmpty<Element>(_ failure: Failure) -> Schema where Output == [Element] {
        refine(failure) { !$0.isEmpty }
    }
}
