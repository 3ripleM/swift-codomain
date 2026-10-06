import SwiftSyntax
import SwiftSyntaxMacros

/// `@JSONKey`, `@JSONTag`, `@UnknownTag`, `@Default`: generate nothing; `@Schema`/`@JSONSchema` read them.
public struct MarkerMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}
