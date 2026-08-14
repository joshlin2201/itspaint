// swift-tools-version: 6.0
import PackageDescription

// Tools version 6.0, not the newest: it is the floor that still has
// `swiftLanguageMode`, and pinning higher means the package cannot build on the
// Xcode that ships with the current GitHub runners — which is exactly where CI
// found this.
//
// PaintKit is the paint engine: pixels, tools, undo, document model, codecs.
// It has no UI and no third-party dependencies so it stays fast to test and
// trivial to reason about. The app shell (ItsPaint.xcodeproj) is a thin consumer.
//
// macOS 12, not the app's 14. The engine had the app's floor by inheritance rather
// than by need — it uses no API newer than Monterey, which is why it compiles at
// this deployment target and why the full suite passes there. The floor was not
// free: SwiftPM refuses to resolve at all for a consumer whose own target is
// older than the dependency's, so every app on 12 or 13 got a hard error rather
// than a warning. Raise this only for an API that genuinely needs it; the
// consumer job in ci.yml declares .v12 and fails if it moves.
let package = Package(
    name: "PaintKit",
    platforms: [.macOS(.v12)],
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
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "PaintDemo",
            dependencies: ["PaintKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PaintKitTests",
            dependencies: ["PaintKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PaintDemoTests",
            dependencies: ["PaintDemo"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
