import Schema
import Testing

// `public`, because the compiler infers `Sendable` only for non-public types.
public enum PF: Error { case odd }

@Codec
public struct PEven {
    public static let codec: Codec<Int, Int, PF> = Codec(decode: .identity, encode: { $0 })
}

@Codec
public struct PNick {
    public static let codec: Codec<String, String?, PF> = Codec(
        decode: Schema<String, String, PF>.identity.nilIfEmpty(), encode: { $0 ?? "" })
}

@JSONSchema(failure: PF.self)
public struct PModel {
    public let x: PEven
    public let nick: PNick?
}

@JSONSchema(failure: PF.self, tag: "kind")
public enum PUnion { case model(PModel) }

private func sendable<T: Sendable>(_: T.Type) {}

@Test func generatedTypesAreSendable() {
    sendable(PEven.self)
    sendable(PNick.self)
    sendable(PModel.self)
    sendable(PModel.Input.self)
    sendable(PUnion.self)
    sendable(PUnion.Input.self)
}
