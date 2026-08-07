// swift-tools-version: 6.0
import PackageDescription

// The engine, vended from the repository root.
//
// PaintKit's own manifest lives at `Packages/PaintKit/Package.swift`, because that
// is the directory the Xcode project consumes as a local package. But a manifest
// nested one level down is invisible to almost everything else: `swift build` in a
// fresh clone finds nothing, `.package(url:)` cannot resolve this repository, and
// the Swift Package Index reads only the root of the default branch, so it cannot
// see the package at all.
//
// So the root gets a manifest too. It adds no targets and copies no source: it
// points at the same directories the nested manifest does, which is why both can
// build the same code without a second copy of it existing anywhere. CI asserts
// the two stay in agreement — see `.github/workflows/ci.yml`.
//
// Tools version 6.0 matches the nested manifest, and for the same reason: it is
// the floor that still has `swiftLanguageMode`, and pinning higher means the
// package cannot build on the Xcode that ships with the current GitHub runners.
let package = Package(
    name: "PaintKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaintKit", targets: ["PaintKit"]),
        // Generates sample artwork by driving the real engine. Used for
        // screenshots, README assets and end-to-end verification; it is not
        // linked into the app, which depends only on the library product.
        .executable(name: "paint-demo", targets: ["PaintDemo"]),
    ],
    targets: [
        .target(
            name: "PaintKit",
            path: "Packages/PaintKit/Sources/PaintKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "PaintDemo",
            dependencies: ["PaintKit"],
            path: "Packages/PaintKit/Sources/PaintDemo",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PaintKitTests",
            dependencies: ["PaintKit"],
            path: "Packages/PaintKit/Tests/PaintKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PaintDemoTests",
            dependencies: ["PaintDemo"],
            path: "Packages/PaintKit/Tests/PaintDemoTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
