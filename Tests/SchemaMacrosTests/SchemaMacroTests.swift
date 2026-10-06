import SchemaMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

private let specs: [String: MacroSpec] = [
    "Schema": MacroSpec(type: SchemaMacro.self, conformances: ["Parsable"]),
    "JSONSchema": MacroSpec(type: JSONSchemaMacro.self, conformances: ["Parsable", "JSONParsable"]),
    "Codec": MacroSpec(type: CodecMacro.self, conformances: ["Field", "OptionalField"]),
]

final class SchemaMacroTests: XCTestCase {
    func testSchemaExpansion() {
        assertMacroExpansion(
            """
            @Schema(failure: F.self)
            struct User {
                let email: Email
                let age: Age?
            }
            """,
            expandedSource: """
            struct User {
                let email: Email
                let age: Age?
            }

            extension User: Parsable {
                typealias Failure = F

                struct Input {
                    let email: Email.Input
                    let age: Age.Input?

                    init(email: Email.Input, age: Age.Input? = nil) {
                        self.email = email
                        self.age = age
                    }
                }

                init(parsing input: Input) throws(Issues<F>) {
                    var collector = IssueCollector<F>()
                    let email = collector.required("email", input.email, as: Email.self)
                    let age = collector.optional("age", input.age, as: Age.self)
                    guard collector.issues.isEmpty else {
                        throw Issues<F>(collector.issues)
                    }
                    self.email = email!
                    self.age = age!
                }

                static func parse(_ input: Input) -> Result<Self, Issues<F>> {
                    Result { () throws(Issues<F>) in
                        try Self(parsing: input)
                    }
                }

                func encode() -> Input {
                    Input(email: email.encoded, age: age?.encoded)
                }

                var encoded: Input {
                    encode()
                }
            }
            """,
            macroSpecs: specs
        )
    }

    func testJSONSchemaExpansion() {
        assertMacroExpansion(
            """
            @JSONSchema(failure: F.self)
            public struct Point {
                let x: Even
            }
            """,
            expandedSource: """
            public struct Point {
                let x: Even
            }

            extension Point: Parsable, JSONParsable {
                public typealias Failure = F

                public struct Input: Codable {
                    public let x: Even.Input

                    public init(x: Even.Input) {
                        self.x = x
                    }
                }

                public init(parsing input: Input) throws(Issues<F>) {
                    var collector = IssueCollector<F>()
                    let x = collector.required("x", input.x, as: Even.self)
                    guard collector.issues.isEmpty else {
                        throw Issues<F>(collector.issues)
                    }
                    self.x = x!
                }

                public static func parse(_ input: Input) -> Result<Self, Issues<F>> {
                    Result { () throws(Issues<F>) in
                        try Self(parsing: input)
                    }
                }

                public func encode() -> Input {
                    Input(x: x.encoded)
                }

                public var encoded: Input {
                    encode()
                }
            }
            """,
            macroSpecs: specs
        )
    }

    func testCodecExpansion() {
        assertMacroExpansion(
            """
            @Codec
            struct Even {
                static let codec: Codec<Int, Int, F> = Codec(decode: .identity, encode: { $0 })
            }
            """,
            expandedSource: """
            struct Even {
                static let codec: Codec<Int, Int, F> = Codec(decode: .identity, encode: { $0 })

                typealias Input = Int

                typealias Failure = F

                let value: Int

                private init(_ value: Int) {
                    self.value = value
                }

                static var schema: Schema<Int, Self, F> {
                    Schema {
                        codec.decode.run($0).map {
                            Self($0)
                        }
                    }
                }

                var encoded: Int {
                    Self.codec.encode(value)
                }
            }

            extension Even: Field {
            }
            """,
            macroSpecs: specs
        )
    }

    func testOptionalCodecExpansion() {
        assertMacroExpansion(
            """
            @Codec
            struct Nick {
                static let codec: Codec<String, String?, F> = Codec(decode: d, encode: { $0 ?? "" })
            }
            """,
            expandedSource: """
            struct Nick {
                static let codec: Codec<String, String?, F> = Codec(decode: d, encode: { $0 ?? "" })

                typealias Input = String

                typealias Failure = F

                let value: String

                private init(_ value: String) {
                    self.value = value
                }

                static var schema: Schema<String, Self?, F> {
                    Schema {
                        codec.decode.run($0).map {
                            $0.map {
                                Self($0)
                            }
                        }
                    }
                }

                var encoded: String {
                    Self.codec.encode(value)
                }
            }

            extension Nick: OptionalField {
            }
            """,
            macroSpecs: specs
        )
    }

    // MARK: - Diagnostics

    func testSchemaOnEnum() {
        assertMacroExpansion(
            "@Schema(failure: F.self) enum E {}",
            expandedSource: "enum E {}",
            diagnostics: [DiagnosticSpec(message: "@Schema applies to structs only", line: 1, column: 1)],
            macroSpecs: specs
        )
    }

    func testJSONSchemaWithoutFailure() {
        assertMacroExpansion(
            "@JSONSchema struct S {}",
            expandedSource: "struct S {}",
            diagnostics: [DiagnosticSpec(message: "usage: @JSONSchema(failure: Failure.self)", line: 1, column: 1)],
            macroSpecs: specs
        )
    }

    func testSchemaPropertyWithoutType() {
        assertMacroExpansion(
            """
            @Schema(failure: F.self)
            struct S {
                let a = 1
            }
            """,
            expandedSource: """
            struct S {
                let a = 1
            }
            """,
            diagnostics: [DiagnosticSpec(message: "@Schema needs an explicit type on 'a'", line: 3, column: 9)],
            macroSpecs: specs
        )
    }

    func testCodecOnClass() {
        assertMacroExpansion(
            "@Codec class C {}",
            expandedSource: "class C {}",
            diagnostics: [DiagnosticSpec(message: "@Codec applies to structs only", line: 1, column: 1)],
            macroSpecs: specs
        )
    }

    func testCodecWithoutCodec() {
        assertMacroExpansion(
            "@Codec struct S {}",
            expandedSource: "struct S {}",
            diagnostics: [DiagnosticSpec(message: "@Codec needs 'static let codec: Codec<Input, Value, Failure>'", line: 1, column: 1)],
            macroSpecs: specs
        )
    }

    func testCodecWithoutTypeAnnotation() {
        assertMacroExpansion(
            """
            @Codec
            struct S {
                static let codec = Codec(decode: d, encode: e)
            }
            """,
            expandedSource: """
            struct S {
                static let codec = Codec(decode: d, encode: e)
            }
            """,
            diagnostics: [DiagnosticSpec(message: "'codec' needs an explicit type: Codec<Input, Value, Failure>", line: 3, column: 16)],
            macroSpecs: specs
        )
    }
}
