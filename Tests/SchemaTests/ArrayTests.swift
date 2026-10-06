import Schema
import Testing

private let list = Schema<[String], [String], F>.identity

@Test func arrayCounts() {
    #expect(list.min(2, .tooLong).run(["a"]) == .failure(.tooLong))
    #expect(list.min(2, .tooLong).run(["a", "b"]) == .success(["a", "b"]))
    #expect(list.max(1, .tooLong).run(["a", "b"]) == .failure(.tooLong))
    #expect(list.max(1, .tooLong).run([]) == .success([]))
    #expect(list.length(2, .tooLong).run(["a"]) == .failure(.tooLong))
    #expect(list.length(2, .tooLong).run(["a", "b"]) == .success(["a", "b"]))
    #expect(list.nonEmpty(.blank).run([]) == .failure(.blank))
    #expect(list.nonEmpty(.blank).run([""]) == .success([""]))
}
