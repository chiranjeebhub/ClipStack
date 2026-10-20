// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipboard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clipboard", targets: ["Clipboard"]),
        // Used by the Xcode project (project.yml) for the signed build.
        .library(name: "ClipboardCore", targets: ["ClipboardCore"])
    ],
    targets: [
        .target(name: "ClipboardCore"),
        .executableTarget(
            name: "Clipboard",
            dependencies: ["ClipboardCore"],
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("CloudKit")]
        ),
        .executableTarget(name: "MakeIcon", dependencies: ["ClipboardCore"]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"])
    ]
)
