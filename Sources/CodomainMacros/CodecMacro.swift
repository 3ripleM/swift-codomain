// `@Codec` reads `static let codec: Codec<I, V, F>` and generates
// the brand: `let value: V`, a `private init`, `schema`, and `encoded`. The init stays private because only
// code inside the type (including this expansion) can call it.

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct CodecMacro: MemberMacro, ExtensionMacro {
    struct Signature {
        let input: String, value: String, failure: String
        let isOptional: Bool
        let access: String
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let s = signature(node, declaration, context) else { return [] }
        let output = s.isOptional ? "Self?" : "Self"
        let wrap = s.isOptional ? "$0.map { Self($0) }" : "Self($0)"
        return [
            "\(raw: s.access)typealias Input = \(raw: s.input)",
            "\(raw: s.access)typealias Failure = \(raw: s.failure)",
            "\(raw: s.access)let value: \(raw: s.value)",
            "private init(_ value: \(raw: s.value)) { self.value = value }",
            """
            \(raw: s.access)static var schema: Schema<\(raw: s.input), \(raw: output), \(raw: s.failure)> {
                codec.decode.map { \(raw: wrap) }
            }
            """,
            "\(raw: s.access)var encoded: \(raw: s.input) { Self.codec.encode(value) }",
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Diagnostics are reported once, by the member role.
        guard let s = signature(node, declaration, nil), !protocols.isEmpty else { return [] }
        let conformance = s.isOptional ? "OptionalField" : "Field"
        return [try ExtensionDeclSyntax("extension \(type.trimmed): \(raw: conformance) {}")]
    }

    private static func signature(
        _ node: AttributeSyntax, _ declaration: some DeclGroupSyntax,
        _ context: (any MacroExpansionContext)?
    ) -> Signature? {
        func fail(_ at: some SyntaxProtocol, _ message: String) -> Signature? {
            context?.diagnose(Diagnostic(node: at, message: Message(message)))
            return nil
        }
        guard declaration.is(StructDeclSyntax.self) else {
            return fail(node, "@Codec applies to structs only")
        }

        let statics = declaration.memberBlock.members
            .compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .filter { $0.modifiers.contains { $0.name.text == "static" } }
            .flatMap(\.bindings)
        func binding(_ name: String) -> PatternBindingSyntax? {
            statics.first { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name }
        }
        guard let codec = binding("codec") else {
            return fail(node, "@Codec needs 'static let codec: Codec<Input, Value, Failure>'")
        }
        guard let type = codec.typeAnnotation?.type.as(IdentifierTypeSyntax.self),
            type.name.text == "Codec",
            let args = type.genericArgumentClause?.arguments.map({ TypeSyntax($0.argument) }),
            args.count == 3
        else {
            return fail(codec, "'codec' needs an explicit type: Codec<Input, Value, Failure>")
        }

        let value = ParsableMacro.optionalWrapped(args[1])
        let access =
            declaration.modifiers.first { ["public", "package"].contains($0.name.text) }
            .map { $0.name.text + " " } ?? ""
        return Signature(
            input: args[0].trimmedDescription,
            value: (value ?? args[1]).trimmedDescription,
            failure: args[2].trimmedDescription,
            isOptional: value != nil,
            access: access
        )
    }
}
