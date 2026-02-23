// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "MockServiceMacro",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        // The library that exposes the macro declaration and runtime support types.
        .library(
            name: "MockServiceMacro",
            targets: ["MockServiceMacro"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        // The compiler plugin that implements the macro.
        .macro(
            name: "MockServiceMacroPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),

        // The library that declares the macro and re-exports runtime types.
        .target(
            name: "MockServiceMacro",
            dependencies: ["MockServiceMacroPlugin"]
        ),

        // Tests for the macro implementation.
        .testTarget(
            name: "MockServiceMacroTests",
            dependencies: [
                "MockServiceMacroPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
