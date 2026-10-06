import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SchemaMacros

private let specs: [String: MacroSpec] = [
    "Schema": MacroSpec(type: SchemaMacro.self, conformances: ["Parsable"]),
    "JSONSchema": MacroSpec(
        type: JSONSchemaMacro.self, conformances: ["Parsable", "JSONParsable"]),
    "Codec": MacroSpec(type: CodecMacro.self, conformances: ["Field", "OptionalField"]),
]

final class SchemaMacroTests: XCTestCase {
    func testRefineIsCalledAfterFieldsParse() {
        assertMacroExpansion(
            """
            @Schema(failure: F.self)
            struct Span {
                let low: Even
                static func refine(_ span: Span) -> [Issues<F>.Issue] { [] }
            }
            """,
            expandedSource: """
                struct Span {
                    let low: Even
                    static func refine(_ span: Span) -> [Issues<F>.Issue] { [] }
                }

                extension Span: Parsable {
                    typealias Failure = F

                    struct Input: Sendable {
                        let low: Even.Input

                        init(low: Even.Input) {
                            self.low = low
                        }
                    }

                    init(parsing input: Input) throws(Issues<F>) {
                        var collector = IssueCollector<F>()
                        let low = collector.required("low", input.low, as: Even.self, lift: F.lift)
                        guard collector.issues.isEmpty else {
                            throw Issues<F>(collector.issues)
                        }
                        self.low = low!
                        let refined = Self.refine(self)
                        guard refined.isEmpty else {
                            throw Issues<F>(refined)
                        }
                    }

                    static func parse(_ input: Input) -> Result<Self, Issues<F>> {
                        Result { () throws(Issues<F>) in
                            try Self(parsing: input)
                        }
                    }

                    func encode() -> Input {
                        Input(low: low.encoded)
                    }

                    var encoded: Input {
                        encode()
                    }
                }
                """,
            macroSpecs: specs
        )
    }

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

                    struct Input: Sendable {
                        let email: Email.Input
                        let age: Age.Input?

                        init(email: Email.Input, age: Age.Input? = nil) {
                            self.email = email
                            self.age = age
                        }
                    }

                    init(parsing input: Input) throws(Issues<F>) {
                        var collector = IssueCollector<F>()
                        let email = collector.required("email", input.email, as: Email.self, lift: F.lift)
                        let age = collector.optional("age", input.age, as: Age.self, lift: F.lift)
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

                    public struct Input: Codable, Sendable {
                        public let x: Even.Input

                        public init(x: Even.Input) {
                            self.x = x
                        }
                    }

                    public init(parsing input: Input) throws(Issues<F>) {
                        var collector = IssueCollector<F>()
                        let x = collector.required("x", input.x, as: Even.self, lift: F.lift)
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

                    public init(json decoder: any Decoder) throws(Issues<DecodeProblem<F>>) {
                        var reader = try JSONReader<F>(decoder)
                        let x = reader.required("x", as: Even.self, lift: F.lift)
                        guard reader.issues.isEmpty else {
                            throw Issues<DecodeProblem<F>>(reader.issues)
                        }
                        self.x = x!
                    }

                    public static func read(from decoder: any Decoder) -> Result<Self, Issues<DecodeProblem<F>>> {
                        Result { () throws(Issues<DecodeProblem<F>>) in
                            try Self(json: decoder)
                        }
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
                        codec.decode.map {
                            Self($0)
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
                        codec.decode.map {
                            $0.map {
                                Self($0)
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

    func testSnakeCase() {
        let cases = [
            "dueDate": "due_date", "userID": "user_id", "URLPath": "url_path",
            "line2Text": "line2_text", "id": "id", "isHTMLSafe": "is_html_safe",
        ]
        for (name, expected) in cases {
            XCTAssertEqual(SchemaMacro.snakeCased(name), expected, name)
        }
    }

    func testJSONKeyOnSchema() {
        assertMacroExpansion(
            """
            @Schema(failure: F.self)
            struct S {
                @JSONKey("k") let a: A
            }
            """,
            expandedSource: """
                struct S {
                    @JSONKey("k") let a: A
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@JSONKey applies to @JSONSchema properties only", line: 3, column: 5)
            ],
            macroSpecs: specs
        )
    }

    func testJSONTagOnSchemaEnum() {
        assertMacroExpansion(
            """
            @Schema(failure: F.self)
            enum E {
                @JSONTag("A") case a(A)
            }
            """,
            expandedSource: """
                enum E {
                    @JSONTag("A") case a(A)
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@JSONTag applies to @JSONSchema enum cases only", line: 3, column: 5)
            ],
            macroSpecs: specs
        )
    }

    func testUnknownTagNeedsAString() {
        assertMacroExpansion(
            """
            @JSONSchema(failure: F.self, tag: "kind")
            enum E {
                case a(A)
                @UnknownTag case other(Int)
            }
            """,
            expandedSource: """
                enum E {
                    case a(A)
                    @UnknownTag case other(Int)
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@UnknownTag marks one 'case other(String)' of a @JSONSchema enum",
                    line: 4, column: 5)
            ],
            macroSpecs: specs
        )
    }

    func testDefaultOnOptional() {
        assertMacroExpansion(
            """
            @Schema(failure: F.self)
            struct S {
                @Default(1) let a: A?
            }
            """,
            expandedSource: """
                struct S {
                    @Default(1) let a: A?
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Default applies to non-optional properties only", line: 3, column: 5)
            ],
            macroSpecs: specs
        )
    }

    func testNonLiteralOptions() {
        assertMacroExpansion(
            """
            @JSONSchema(failure: F.self, strict: isStrict)
            struct S {
                let a: A
            }
            """,
            expandedSource: """
                struct S {
                    let a: A
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "strict: must be true or false", line: 1, column: 38)
            ],
            macroSpecs: specs
        )
        assertMacroExpansion(
            """
            @JSONSchema(failure: F.self, keys: style)
            struct S {
                let a: A
            }
            """,
            expandedSource: """
                struct S {
                    let a: A
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "keys: must be .swift or .snakeCase", line: 1, column: 36)
            ],
            macroSpecs: specs
        )
    }

    func testDuplicateJSONKey() {
        assertMacroExpansion(
            """
            @JSONSchema(failure: F.self, keys: .snakeCase)
            struct S {
                let userID: A
                @JSONKey("user_id") let other: A
            }
            """,
            expandedSource: """
                struct S {
                    let userID: A
                    @JSONKey("user_id") let other: A
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "JSON key 'user_id' is already used by 'userID'", line: 4, column: 29)
            ],
            macroSpecs: specs
        )
    }

    func testDuplicateJSONTag() {
        assertMacroExpansion(
            """
            @JSONSchema(failure: F.self, tag: "kind")
            enum E {
                case a(A)
                @JSONTag("a") case b(B)
            }
            """,
            expandedSource: """
                enum E {
                    case a(A)
                    @JSONTag("a") case b(B)
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "tag 'a' is already used by 'a'", line: 4, column: 24)
            ],
            macroSpecs: specs
        )
    }

    // MARK: - Diagnostics

    func testJSONEnumWithoutTag() {
        assertMacroExpansion(
            """
            @JSONSchema(failure: F.self)
            enum E {
                case a(A)
            }
            """,
            expandedSource: """
                enum E {
                    case a(A)
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: #"usage: @JSONSchema(failure: Failure.self, tag: "kind") on an enum"#,
                    line: 1, column: 1)
            ],
            macroSpecs: specs
        )
    }

    func testTagOnStruct() {
        assertMacroExpansion(
            """
            @JSONSchema(failure: F.self, tag: "kind")
            struct S {
            }
            """,
            expandedSource: """
                struct S {
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "tag: applies to enums only", line: 1, column: 30)
            ],
            macroSpecs: specs
        )
    }

    func testSchemaOnClass() {
        assertMacroExpansion(
            "@Schema(failure: F.self) class C {}",
            expandedSource: "class C {}",
            diagnostics: [
                DiagnosticSpec(
                    message: "@Schema applies to structs and enums only", line: 1, column: 1)
            ],
            macroSpecs: specs
        )
    }

    func testEnumCaseWithoutOneValue() {
        assertMacroExpansion(
            """
            @Schema(failure: F.self)
            enum E {
                case a(A), b
            }
            """,
            expandedSource: """
                enum E {
                    case a(A), b
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Schema enum cases hold exactly one unlabeled value: 'case b(Model)'",
                    line: 3, column: 16)
            ],
            macroSpecs: specs
        )
    }

    func testJSONSchemaWithoutFailure() {
        assertMacroExpansion(
            "@JSONSchema struct S {}",
            expandedSource: "struct S {}",
            diagnostics: [
                DiagnosticSpec(
                    message: "usage: @JSONSchema(failure: Failure.self)", line: 1, column: 1)
            ],
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
            diagnostics: [
                DiagnosticSpec(message: "@Schema needs an explicit type on 'a'", line: 3, column: 9)
            ],
            macroSpecs: specs
        )
    }

    func testCodecOnClass() {
        assertMacroExpansion(
            "@Codec class C {}",
            expandedSource: "class C {}",
            diagnostics: [
                DiagnosticSpec(message: "@Codec applies to structs only", line: 1, column: 1)
            ],
            macroSpecs: specs
        )
    }

    func testCodecWithoutCodec() {
        assertMacroExpansion(
            "@Codec struct S {}",
            expandedSource: "struct S {}",
            diagnostics: [
                DiagnosticSpec(
                    message: "@Codec needs 'static let codec: Codec<Input, Value, Failure>'",
                    line: 1, column: 1)
            ],
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
            diagnostics: [
                DiagnosticSpec(
                    message: "'codec' needs an explicit type: Codec<Input, Value, Failure>",
                    line: 3, column: 16)
            ],
            macroSpecs: specs
        )
    }
}
