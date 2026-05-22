// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFConverterCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PDFConverterCore",
            targets: ["PDFConverterCore"]
        )
    ],
    targets: [
        .target(
            name: "PDFConverterCore",
            path: "Sources/PDFConverterCore"
        ),
        .testTarget(
            name: "PDFConverterCoreTests",
            dependencies: ["PDFConverterCore"],
            path: "Tests/PDFConverterCoreTests"
        )
    ]
)
