// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipboard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clipboard", targets: ["Clipboard"])
    ],
    targets: [
        .target(name: "ClipboardCore"),
        .executableTarget(
            name: "Clipboard",
            dependencies: ["ClipboardCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .executableTarget(name: "MakeIcon", dependencies: ["ClipboardCore"]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"])
    ]
)
