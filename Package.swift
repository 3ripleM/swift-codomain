// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-schema",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "Schema", targets: ["Schema"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
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
        .executableTarget(name: "Example", dependencies: ["Schema"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "SchemaSmokeTests", dependencies: ["Schema"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
