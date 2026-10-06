// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-schema",
    platforms: [.macOS(.v13), .iOS(.v15)],
    products: [
        .library(name: "Schema", targets: ["Schema"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        // Tests only: checks `decode(_:using:)` with a non-JSON decoder.
        .package(url: "https://github.com/CoreOffice/XMLCoder.git", from: "0.17.0"),
    ],
    targets: [
        .macro(
            name: "SchemaMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "Schema", dependencies: ["SchemaMacros"]),
        .testTarget(
            name: "SchemaSmokeTests", dependencies: ["Schema"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "SchemaTests", dependencies: ["Schema"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "SchemaXMLTests", dependencies: ["Schema", "XMLCoder"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "SchemaMacrosTests",
            dependencies: [
                "SchemaMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
