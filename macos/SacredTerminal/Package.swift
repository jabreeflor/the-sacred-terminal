// swift-tools-version:5.9
import PackageDescription

// The Sacred Terminal — a native macOS terminal workspace modeled on cmux,
// built on top of Ghostty by embedding libghostty (GhosttyKit.xcframework),
// exactly the way cmux does: each terminal is a Ghostty *surface* that owns its
// own PTY and GPU (Metal) rendering. We build the projects/agents workspace on
// top in Swift + AppKit.
//
// Prerequisite: vendor/GhosttyKit.xcframework must exist. Build it once from the
// pinned Ghostty submodule with `scripts/build-ghostty.sh` (see README). This
// mirrors cmux, which vendors Ghostty as a submodule built into GhosttyKit.
let package = Package(
    name: "SacredTerminal",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SacredTerminal", targets: ["SacredTerminal"]),
        .executable(name: "sacred", targets: ["sacred-cli"]),
    ],
    targets: [
        // libghostty, packaged as an xcframework (built from the Ghostty submodule).
        // Exposes the C embedding API (ghostty.h) as the `GhosttyKit` module.
        .binaryTarget(
            name: "GhosttyKit",
            path: "vendor/GhosttyKit.xcframework"
        ),
        .executableTarget(
            name: "SacredTerminal",
            dependencies: ["GhosttyKit"],
            path: "Sources/SacredTerminal",
            resources: [.copy("Resources/Icons"), .copy("Resources/AppIcon.png")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("QuartzCore"),
                // libghostty is a static archive of Zig + C++ (spirv-cross, glslang,
                // imgui) and uses Carbon's Text Input Services. Pull in the C++
                // runtime and Carbon so its symbols resolve at link time; the rest
                // (CoreText/CoreVideo/IOSurface/…) come transitively via AppKit.
                .linkedFramework("Carbon"),
                .linkedLibrary("c++"),
            ]
        ),
        .executableTarget(
            name: "sacred-cli",
            path: "Sources/sacred-cli"
        ),
    ]
)
