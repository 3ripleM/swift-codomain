// The macro only writes code a developer would write by hand. All safety comes from
// the compiler type-checking the expansion: a property type without `.parse` or
// `.Input`, or a wrong optionality, is a compile error.

import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct SchemaMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        expand(node, declaration, type, context, json: false)
    }

    static func expand(
        _ node: AttributeSyntax,
        _ declaration: some DeclGroupSyntax,
        _ type: some TypeSyntaxProtocol,
        _ context: some MacroExpansionContext,
        json: Bool
    ) -> [ExtensionDeclSyntax] {
        let macro = json ? "@JSONSchema" : "@Schema"
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: Message("\(macro) applies to structs only")))
            return []
        }
        guard let arg = node.arguments?.as(LabeledExprListSyntax.self)?.first,
              let failure = metatypeBase(arg.expression) else {
            context.diagnose(Diagnostic(node: node, message: Message("usage: \(macro)(failure: Failure.self)")))
            return []
        }

        var properties: [(name: String, type: String, input: String, isOptional: Bool)] = []
        for (name, type, binding) in storedProperties(declaration.memberBlock) {
            guard let type else {
                context.diagnose(Diagnostic(node: binding, message: Message("\(macro) needs an explicit type on '\(name)'")))
                return []
            }
            if let wrapped = SchemaMacro.optionalWrapped(type) {
                properties.append((name, wrapped.trimmedDescription, "\(wrapped.trimmedDescription).Input?", true))
            } else {
                properties.append((name, type.trimmedDescription, "\(type.trimmedDescription).Input", false))
            }
        }

        let access = declaration.modifiers.contains { ["public", "package"].contains($0.name.text) }
            ? declaration.modifiers.first { ["public", "package"].contains($0.name.text) }!.name.text + " "
            : ""
        let fields = properties.map { "\(access)let \($0.name): \($0.input)" }.joined(separator: "\n")
        let params = properties.map { "\($0.name): \($0.input)\($0.isOptional ? " = nil" : "")" }.joined(separator: ", ")
        let copies = properties.map { "self.\($0.name) = \($0.name)" }.joined(separator: "\n")
        // Parse every field first, collecting failures; build `Self` only when none failed.
        let issues = "Issues<\(failure)>"
        let parses = properties.map { p in
            "let \(p.name) = collector.\(p.isOptional ? "optional" : "required")(\"\(p.name)\", input.\(p.name), as: \(p.type).self)"
        }.joined(separator: "\n")
        let assigns = properties.map { "self.\($0.name) = \($0.name)!" }.joined(separator: "\n")
        let encodes = properties.map { "\($0.name): \($0.name)\($0.isOptional ? "?" : "").encoded" }.joined(separator: ", ")

        let ext: DeclSyntax = """
            extension \(type.trimmed): \(raw: json ? "Parsable, JSONParsable" : "Parsable") {
                \(raw: access)typealias Failure = \(raw: failure)

                \(raw: access)struct Input\(raw: json ? ": Codable" : "") {
                    \(raw: fields)

                    \(raw: access)init(\(raw: params)) {
                        \(raw: copies)
                    }
                }

                \(raw: access)init(parsing input: Input) throws(\(raw: issues)) {
                    var collector = IssueCollector<\(raw: failure)>()
                    \(raw: parses)
                    guard collector.issues.isEmpty else { throw \(raw: issues)(collector.issues) }
                    \(raw: assigns)
                }

                \(raw: access)static func parse(_ input: Input) -> Result<Self, \(raw: issues)> {
                    Result { () throws(\(raw: issues)) in try Self(parsing: input) }
                }

                \(raw: access)func encode() -> Input {
                    Input(\(raw: encodes))
                }

                \(raw: access)var encoded: Input { encode() }
            }
            """
        return [ext.cast(ExtensionDeclSyntax.self)]
    }

    /// `Foo.Bar.self` → `Foo.Bar`
    private static func metatypeBase(_ expr: ExprSyntax) -> String? {
        guard let member = expr.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "self",
              let base = member.base else { return nil }
        return base.trimmedDescription
    }

    /// `T?` or `Optional<T>` → `T`
    static func optionalWrapped(_ type: TypeSyntax) -> TypeSyntax? {
        if let optional = type.as(OptionalTypeSyntax.self) { return optional.wrappedType }
        if let named = type.as(IdentifierTypeSyntax.self), named.name.text == "Optional",
           let arg = named.genericArgumentClause?.arguments.first {
            return TypeSyntax(arg.argument)
        }
        return nil
    }

    /// Instance stored properties: `let`/`var` without accessors, not `static`.
    private static func storedProperties(_ members: MemberBlockSyntax) -> [(String, TypeSyntax?, PatternBindingSyntax)] {
        members.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .filter { !$0.modifiers.contains { $0.name.text == "static" } }
            .flatMap { $0.bindings.compactMap { binding -> (String, TypeSyntax?, PatternBindingSyntax)? in
                guard binding.accessorBlock == nil,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
                return (name, binding.typeAnnotation?.type, binding)
            } }
    }
}

/// `@Schema` plus `Codable` input and `JSONParsable` (`decode(json:)`, `json()`).
public struct JSONSchemaMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        SchemaMacro.expand(node, declaration, type, context, json: true)
    }
}

struct Message: DiagnosticMessage {
    let message: String
    init(_ message: String) { self.message = message }
    var diagnosticID: MessageID { MessageID(domain: "SchemaMacros", id: message) }
    var severity: DiagnosticSeverity { .error }
}

@main
struct Plugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [SchemaMacro.self, JSONSchemaMacro.self, CodecMacro.self]
}
