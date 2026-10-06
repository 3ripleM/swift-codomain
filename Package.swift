// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-codomain",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "Codomain", targets: ["Codomain"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        // Tests only: checks `decode(_:using:)` with a non-JSON decoder.
        .package(url: "https://github.com/CoreOffice/XMLCoder.git", from: "0.17.0"),
    ],
    targets: [
        .macro(
            name: "CodomainMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "Codomain", dependencies: ["CodomainMacros"]),
        .testTarget(
            name: "CodomainSmokeTests", dependencies: ["Codomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "CodomainTests", dependencies: ["Codomain"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "CodomainReadmeTests", dependencies: ["Codomain", "XMLCoder"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "CodomainXMLTests", dependencies: ["Codomain", "XMLCoder"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "CodomainMacrosTests",
            dependencies: [
                "CodomainMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
