// The macro only writes code a developer would write by hand. All safety comes from
// the compiler type-checking the expansion: a property type without `.parse` or
// `.Input`, or a wrong optionality, is a compile error.

import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ParsableMacro: ExtensionMacro {
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
        let macro = json ? "@JSONParsable" : "@Parsable"
        guard declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: node, message: Message("\(macro) applies to structs and enums only")))
            return []
        }
        guard let arg = node.arguments?.as(LabeledExprListSyntax.self)?.first,
            let failure = metatypeBase(arg.expression)
        else {
            context.diagnose(
                Diagnostic(node: node, message: Message("usage: \(macro)(failure: Failure.self)")))
            return []
        }
        let tagArgument = node.arguments?.as(LabeledExprListSyntax.self)?.first {
            $0.label?.text == "tag"
        }
        let tag = tagArgument?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        if declaration.is(EnumDeclSyntax.self) {
            if json && tag == nil {
                context.diagnose(
                    Diagnostic(
                        node: node,
                        message: Message(
                            #"usage: @JSONParsable(failure: Failure.self, tag: "kind") on an enum"#)))
                return []
            }
            return expandEnum(
                node, declaration, type, context, failure: failure, access: access(declaration),
                tag: json ? tag : nil)
        }
        if let tagArgument {
            context.diagnose(
                Diagnostic(node: tagArgument, message: Message("tag: applies to enums only")))
            return []
        }

        let strictArgument = argument(node, "strict")
        let keysArgument = argument(node, "keys")
        let strictLiteral = strictArgument?.as(BooleanLiteralExprSyntax.self)
        if let strictArgument, strictLiteral == nil {
            context.diagnose(
                Diagnostic(node: strictArgument, message: Message("strict: must be true or false")))
            return []
        }
        let keysName = keysArgument?.as(MemberAccessExprSyntax.self).flatMap {
            $0.base == nil ? $0.declName.baseName.text : nil
        }
        if let keysArgument, !["swift", "snakeCase"].contains(keysName ?? "") {
            context.diagnose(
                Diagnostic(
                    node: keysArgument, message: Message("keys: must be .swift or .snakeCase")))
            return []
        }
        let strict = strictLiteral?.literal.tokenKind == .keyword(.true)
        let snakeCase = keysName == "snakeCase"
        var properties:
            [(
                name: String, type: String, input: String, isOptional: Bool, key: String,
                fallback: String?
            )] = []
        for (name, type, binding, variable) in storedProperties(declaration.memberBlock) {
            guard let type else {
                context.diagnose(
                    Diagnostic(
                        node: binding,
                        message: Message("\(macro) needs an explicit type on '\(name)'")))
                return []
            }
            let keyAttribute = attribute("JSONKey", variable.attributes)
            if !json, let keyAttribute {
                context.diagnose(
                    Diagnostic(
                        node: keyAttribute,
                        message: Message("@JSONKey applies to @JSONParsable properties only")))
                return []
            }
            let key = keyAttribute.flatMap(stringArgument) ?? (snakeCase ? snakeCased(name) : name)
            if json, let owner = properties.first(where: { $0.key == key }) {
                context.diagnose(
                    Diagnostic(
                        node: binding,
                        message: Message("JSON key '\(key)' is already used by '\(owner.name)'")))
                return []
            }
            let defaultAttribute = attribute("Default", variable.attributes)
            let fallback = defaultAttribute?.arguments?.as(LabeledExprListSyntax.self)?.first?
                .expression.trimmedDescription
            if let wrapped = ParsableMacro.optionalWrapped(type) {
                if let defaultAttribute {
                    context.diagnose(
                        Diagnostic(
                            node: defaultAttribute,
                            message: Message("@Default applies to non-optional properties only")))
                    return []
                }
                properties.append(
                    (name, wrapped.trimmedDescription, "\(inputType(wrapped))?", true, key, nil))
            } else {
                properties.append(
                    (
                        name, type.trimmedDescription,
                        inputType(type) + (fallback == nil ? "" : "?"), false, key, fallback
                    ))
            }
        }

        let access = access(declaration)
        let fields = properties.map { "\(access)let \($0.name): \($0.input)" }.joined(
            separator: "\n")
        let params = properties.map {
            "\($0.name): \($0.input)\($0.isOptional || $0.fallback != nil ? " = nil" : "")"
        }.joined(separator: ", ")
        let copies = properties.map { "self.\($0.name) = \($0.name)" }.joined(separator: "\n")
        // Parse every field first, collecting failures; build `Self` only when none failed.
        let issues = "Issues<\(failure)>"
        let parses = properties.map { p in
            "let \(p.name) = collector.\(p.isOptional ? "optional" : "required")(\"\(p.name)\", input.\(p.name)\(p.fallback.map { " ?? (\($0))" } ?? ""), as: \(p.type).self, lift: \(failure).lift)"
        }.joined(separator: "\n")
        let assigns = properties.map { "self.\($0.name) = \($0.name)!" }.joined(separator: "\n")
        let (refine, refineJSON) = refineCalls(declaration, failure: failure)
        let encodes = properties.map { "\($0.name): \($0.name)\($0.isOptional ? "?" : "").encoded" }
            .joined(separator: ", ")
        let problems = "Issues<DecodeProblem<\(failure)>>"
        let reads = properties.map { p in
            "let \(p.name) = reader.\(p.isOptional ? "optional" : p.fallback == nil ? "required" : "defaulted")(\(StringLiteralExprSyntax(content: p.key)), \(p.fallback.map { "(\($0)), " } ?? "")as: \(p.type).self, lift: \(failure).lift)"
        }.joined(separator: "\n")
        let codingKeys =
            !json || properties.allSatisfy({ $0.key == $0.name })
            ? ""
            : """


                    \(access)enum CodingKeys: String, CodingKey {
                        \(properties.map { "case \($0.name) = \(StringLiteralExprSyntax(content: $0.key))" }.joined(separator: "\n"))
                    }
            """
        let jsonMembers =
            !json
            ? ""
            : """


                \(access)init(json decoder: any Decoder) throws(\(problems)) {
                    var reader = try JSONReader<\(failure)>(decoder)
                    \(reads)\(strict ? "\nreader.rejectUndeclared([\(properties.map { "\(StringLiteralExprSyntax(content: $0.key))" }.joined(separator: ", "))])" : "")
                    guard reader.issues.isEmpty else { throw \(problems)(reader.issues) }
                    \(assigns)\(refineJSON)
                }

                \(access)static func read(from decoder: any Decoder) -> Result<Self, \(problems)> {
                    Result { () throws(\(problems)) in try Self(json: decoder) }
                }
            """

        let ext: DeclSyntax = """
            extension \(type.trimmed): \(raw: json ? "Parsable, JSONParsable" : "Parsable") {
                \(raw: access)typealias Failure = \(raw: failure)

                \(raw: access)struct Input: \(raw: json ? "Codable, " : "")Sendable {
                    \(raw: fields)

                    \(raw: access)init(\(raw: params)) {
                        \(raw: copies)
                    }\(raw: codingKeys)
                }

                \(raw: access)init(parsing input: Input) throws(\(raw: issues)) {
                    var collector = IssueCollector<\(raw: failure)>()
                    \(raw: parses)
                    guard collector.issues.isEmpty else { throw \(raw: issues)(collector.issues) }
                    \(raw: assigns)\(raw: refine)
                }

                \(raw: access)static func parse(_ input: Input) -> Result<Self, \(raw: issues)> {
                    Result { () throws(\(raw: issues)) in try Self(parsing: input) }
                }

                \(raw: access)func encode() -> Input {
                    Input(\(raw: encodes))
                }

                \(raw: access)var encoded: Input { encode() }\(raw: jsonMembers)
            }
            """
        return [ext.cast(ExtensionDeclSyntax.self)]
    }

    /// A tagged union: every case holds exactly one `Parsable` value; failures keep the payload's paths.
    private static func expandEnum(
        _ node: AttributeSyntax,
        _ declaration: some DeclGroupSyntax,
        _ type: some TypeSyntaxProtocol,
        _ context: some MacroExpansionContext,
        failure: String,
        access: String,
        tag: String?
    ) -> [ExtensionDeclSyntax] {
        var cases: [(name: String, type: TypeSyntax, wire: String)] = []
        var unknown: String?
        for caseDecl in declaration.memberBlock.members.compactMap({
            $0.decl.as(EnumCaseDeclSyntax.self)
        }) {
            let tagAttribute = attribute("JSONTag", caseDecl.attributes)
            if tag == nil, let tagAttribute {
                context.diagnose(
                    Diagnostic(
                        node: tagAttribute,
                        message: Message("@JSONTag applies to @JSONParsable enum cases only")))
                return []
            }
            if let unknownAttribute = attribute("UnknownTag", caseDecl.attributes) {
                guard tag != nil, unknown == nil, tagAttribute == nil, caseDecl.elements.count == 1,
                    let element = caseDecl.elements.first,
                    let parameter = element.parameterClause?.parameters.first,
                    element.parameterClause?.parameters.count == 1,
                    parameter.firstName == nil, parameter.type.trimmedDescription == "String"
                else {
                    context.diagnose(
                        Diagnostic(
                            node: unknownAttribute,
                            message: Message(
                                "@UnknownTag marks one 'case other(String)' of a @JSONParsable enum"))
                    )
                    return []
                }
                unknown = element.name.text
                continue
            }
            for element in caseDecl.elements {
                guard let parameters = element.parameterClause?.parameters, parameters.count == 1,
                    let parameter = parameters.first, parameter.firstName == nil
                else {
                    context.diagnose(
                        Diagnostic(
                            node: element,
                            message: Message(
                                "@Parsable enum cases hold exactly one unlabeled value: 'case \(element.name.text)(Model)'"
                            )))
                    return []
                }
                let wire = tagAttribute.flatMap(stringArgument) ?? element.name.text
                if tag != nil, let owner = cases.first(where: { $0.wire == wire }) {
                    context.diagnose(
                        Diagnostic(
                            node: element,
                            message: Message("tag '\(wire)' is already used by '\(owner.name)'")))
                    return []
                }
                cases.append((element.name.text, parameter.type, wire))
            }
        }
        let issues = "Issues<\(failure)>"
        let inputCases =
            (cases.map { "case \($0.name)(\(inputType($0.type)))" }
            + [unknown.map { "case \($0)(String)" }].compactMap { $0 }).joined(separator: "\n")
        let unknownParse = unknown.map { "\ncase .\($0)(let tag): self = .\($0)(tag)" } ?? ""
        let unknownEncode = unknown.map { "\ncase .\($0)(let tag): .\($0)(tag)" } ?? ""
        let parses =
            cases.map { c in
                """
                case .\(c.name)(let raw):
                    guard let value = collector.required("", raw, as: \(c.type.trimmedDescription).self, lift: \(failure).lift) else { throw \(issues)(collector.issues) }
                    self = .\(c.name)(value)
                """
            }.joined(separator: "\n") + unknownParse
        let encodes =
            cases.map { "case .\($0.name)(let value): .\($0.name)(value.encoded)" }.joined(
                separator: "\n") + unknownEncode
        let (refine, refineJSON) = refineCalls(declaration, failure: failure)
        let problems = "Issues<DecodeProblem<\(failure)>>"
        let names = cases.map { "\(StringLiteralExprSyntax(content: $0.wire))" }.joined(
            separator: ", ")
        let codable =
            tag.map { tag in
                """


                        private enum TagKey: String, CodingKey { case tag = \(StringLiteralExprSyntax(content: tag)) }

                        \(access)init(from decoder: any Decoder) throws {
                            let container = try decoder.container(keyedBy: TagKey.self)
                            let tag = try container.decode(String.self, forKey: .tag)
                            switch tag {
                            \(cases.map { "case \(StringLiteralExprSyntax(content: $0.wire)): self = .\($0.name)(try \(inputType($0.type))(from: decoder))" }.joined(separator: "\n"))
                            \(unknown.map { "default: self = .\($0)(tag)" } ?? "default: throw DecodingError.dataCorruptedError(forKey: .tag, in: container, debugDescription: \(StringLiteralExprSyntax(content: "expected " + cases.map(\.wire).joined(separator: " | "))))")
                            }
                        }

                        \(access)func encode(to encoder: any Encoder) throws {
                            var container = encoder.container(keyedBy: TagKey.self)
                            switch self {
                            \(cases.map { "case .\($0.name)(let value): try container.encode(\(StringLiteralExprSyntax(content: $0.wire)), forKey: .tag); try value.encode(to: encoder)" }.joined(separator: "\n"))\(unknown.map { "\ncase .\($0)(let tag): try container.encode(tag, forKey: .tag)" } ?? "")
                            }
                        }
                """
            } ?? ""
        let jsonMembers =
            tag.map { tag in
                """


                    \(access)init(json decoder: any Decoder) throws(\(problems)) {
                        let tag = try JSONUnion<\(failure)>.tag(decoder, key: \(StringLiteralExprSyntax(content: tag)), cases: [\(names)]\(unknown == nil ? "" : ", unknown: true"))
                        switch tag {
                        \(cases.map { "case \(StringLiteralExprSyntax(content: $0.wire)): self = .\($0.name)(try JSONUnion<\(failure)>.payload(\($0.type.trimmedDescription).self, decoder, key: \(StringLiteralExprSyntax(content: tag)), lift: \(failure).lift))" }.joined(separator: "\n"))
                        \(unknown.map { "default: self = .\($0)(tag)" } ?? #"default: preconditionFailure("JSONUnion.tag returns only the listed cases")"#)
                        }\(refineJSON)
                    }

                    \(access)static func read(from decoder: any Decoder) -> Result<Self, \(problems)> {
                        Result { () throws(\(problems)) in try Self(json: decoder) }
                    }
                """
            } ?? ""

        let ext: DeclSyntax = """
            extension \(type.trimmed): \(raw: tag == nil ? "Parsable" : "Parsable, JSONParsable") {
                \(raw: access)typealias Failure = \(raw: failure)

                \(raw: access)enum Input: \(raw: tag == nil ? "" : "Codable, ")Sendable {
                    \(raw: inputCases)\(raw: codable)
                }

                \(raw: access)init(parsing input: Input) throws(\(raw: issues)) {
                    var collector = IssueCollector<\(raw: failure)>()
                    switch input {
                    \(raw: parses)
                    }\(raw: refine)
                }

                \(raw: access)static func parse(_ input: Input) -> Result<Self, \(raw: issues)> {
                    Result { () throws(\(raw: issues)) in try Self(parsing: input) }
                }

                \(raw: access)func encode() -> Input {
                    switch self {
                    \(raw: encodes)
                    }
                }

                \(raw: access)var encoded: Input { encode() }\(raw: jsonMembers)
            }
            """
        return [ext.cast(ExtensionDeclSyntax.self)]
    }

    /// When the type declares `static func refine`: the calls for `init(parsing:)` and `init(json:)`.
    private static func refineCalls(_ declaration: some DeclGroupSyntax, failure: String) -> (
        String, String
    ) {
        guard hasStaticFunc("refine", declaration.memberBlock) else { return ("", "") }
        return (
            """

            let refined = Self.refine(self)
            guard refined.isEmpty else { throw Issues<\(failure)>(refined) }
            """,
            """

            let refined = Self.refine(self)
            guard refined.isEmpty else { throw Issues<DecodeProblem<\(failure)>>(refined.map { .init(path: $0.path, failure: .rule($0.failure)) }) }
            """
        )
    }

    private static func access(_ declaration: some DeclGroupSyntax) -> String {
        declaration.modifiers.first { ["public", "package"].contains($0.name.text) }.map {
            $0.name.text + " "
        } ?? ""
    }

    /// `Foo.Bar.self` → `Foo.Bar`
    private static func metatypeBase(_ expr: ExprSyntax) -> String? {
        guard let member = expr.as(MemberAccessExprSyntax.self),
            member.declName.baseName.text == "self",
            let base = member.base
        else { return nil }
        return base.trimmedDescription
    }

    /// `T` → `T.Input`, `[T]` → `[T.Input]`, `[String: T]` → `[String: T.Input]`.
    /// Spelling collections out avoids `[T].Input`, which the compiler can fail to resolve when `T`'s
    /// conformance comes from a macro in another file.
    private static func inputType(_ type: TypeSyntax) -> String {
        if let array = type.as(ArrayTypeSyntax.self) { return "[\(inputType(array.element))]" }
        if let dictionary = type.as(DictionaryTypeSyntax.self) {
            return "[\(dictionary.key.trimmedDescription): \(inputType(dictionary.value))]"
        }
        return "\(type.trimmedDescription).Input"
    }

    /// `T?` or `Optional<T>` → `T`
    static func optionalWrapped(_ type: TypeSyntax) -> TypeSyntax? {
        if let optional = type.as(OptionalTypeSyntax.self) { return optional.wrappedType }
        if let named = type.as(IdentifierTypeSyntax.self), named.name.text == "Optional",
            let arg = named.genericArgumentClause?.arguments.first
        {
            return TypeSyntax(arg.argument)
        }
        return nil
    }

    /// `static func <name>` declared in the struct body.
    private static func hasStaticFunc(_ name: String, _ members: MemberBlockSyntax) -> Bool {
        members.members.contains {
            guard let function = $0.decl.as(FunctionDeclSyntax.self) else { return false }
            return function.name.text == name
                && function.modifiers.contains { $0.name.text == "static" }
        }
    }

    /// Instance stored properties: `let`/`var` without accessors, not `static`.
    private static func storedProperties(_ members: MemberBlockSyntax) -> [(
        String, TypeSyntax?, PatternBindingSyntax, VariableDeclSyntax
    )] {
        members.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .filter { !$0.modifiers.contains { $0.name.text == "static" } }
            .flatMap { variable in
                variable.bindings.compactMap {
                    binding -> (String, TypeSyntax?, PatternBindingSyntax, VariableDeclSyntax)? in
                    guard binding.accessorBlock == nil,
                        let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                    else { return nil }
                    return (name, binding.typeAnnotation?.type, binding, variable)
                }
            }
    }

    /// The macro's argument labeled `label`.
    static func argument(_ node: AttributeSyntax, _ label: String) -> ExprSyntax? {
        node.arguments?.as(LabeledExprListSyntax.self)?.first { $0.label?.text == label }?
            .expression
    }

    /// `@name(...)` among `attributes`.
    static func attribute(_ name: String, _ attributes: AttributeListSyntax) -> AttributeSyntax? {
        attributes.compactMap { $0.as(AttributeSyntax.self) }.first {
            $0.attributeName.trimmedDescription == name
        }
    }

    /// `@JSONKey("x")` → `x`.
    static func stringArgument(_ attribute: AttributeSyntax) -> String? {
        attribute.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.as(
            StringLiteralExprSyntax.self)?.representedLiteralValue
    }

    /// `dueDate` → `due_date`, `userID` → `user_id`, `urlPath` → `url_path`: a word starts at an uppercase
    /// letter after a lowercase letter or digit, or at the last uppercase letter of a run followed by lowercase.
    static func snakeCased(_ name: String) -> String {
        let chars = Array(name)
        var out = ""
        for (i, c) in chars.enumerated() {
            if c.isUppercase, i > 0 {
                let previous = chars[i - 1]
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                if previous.isLowercase || previous.isNumber
                    || (previous.isUppercase && next?.isLowercase == true)
                {
                    out += "_"
                }
            }
            out += c.lowercased()
        }
        return out
    }
}

/// `@Parsable` plus `Codable` input and `JSONParsable` (`decode(json:)`, `json()`).
public struct JSONParsableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        ParsableMacro.expand(node, declaration, type, context, json: true)
    }
}

struct Message: DiagnosticMessage {
    let message: String
    init(_ message: String) { self.message = message }
    var diagnosticID: MessageID { MessageID(domain: "CodomainMacros", id: message) }
    var severity: DiagnosticSeverity { .error }
}

@main
struct Plugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ParsableMacro.self, JSONParsableMacro.self, CodecMacro.self, MarkerMacro.self,
    ]
}
