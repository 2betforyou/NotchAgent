// swift-tools-version: 5.9
import PackageDescription

// SwiftTerm v1.13.0, 8e7a1e154f470e19c709a00a8768df348ba5fc43.
// See THIRD-PARTY-NOTICES.md for the clipboard hook patch.
// Standalone tools and benchmark dependencies omitted.
let package = Package(
    name: "SwiftTerm",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SwiftTerm", targets: ["SwiftTerm"])],
    targets: [.target(name: "SwiftTerm", path: "Sources/SwiftTerm",
                      exclude: ["Mac/README.md"],
                      resources: [.copy("Apple/Metal/Shaders.metal")])],
    swiftLanguageVersions: [.v5]
)
