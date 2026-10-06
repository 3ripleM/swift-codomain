import Codomain
import Testing

@Test func mkRunsTheCodecsDecode() throws {
    #expect(try Even.mk(4).get().value == 4)
    #expect(failure(Even.mk(3)) == .odd)
    #expect(Even.unsafeMk(2).value == 2)
}

@Test func encodedRunsTheCodecsEncode() {
    #expect(Even.unsafeMk(6).encoded == 6)
}

@Test func codecLawDecodeOfEncodeIsIdentity() {
    for raw in [-4, 0, 2, 100] {
        let value = Even.unsafeMk(raw)
        #expect(Even.mk(value.encoded) == .success(value))
    }
}

@Test func fieldParseWrapsItsFailureWithAnEmptyPath() {
    #expect(Even.parse(3) == .failure(Issues("", .odd)))
    #expect(Even.parse(2) == .success(Even.unsafeMk(2)))
}

@Test func optionalFieldCanDecideAbsent() throws {
    #expect(Nick.mk("  ") == .success(nil))
    #expect(try Nick.mk(" ab ").get()?.value == "ab")
    #expect(failure(Nick.mk("abcd")) == .tooLong)
    #expect(Nick.unsafeMk("") == nil)
    #expect(Nick.unsafeMk("ab")?.encoded == "ab")
}
