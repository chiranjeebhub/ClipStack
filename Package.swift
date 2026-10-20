// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipstack",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clipstack", targets: ["Clipstack"]),
        // Used by the Xcode project (project.yml) for the signed build.
        .library(name: "ClipboardCore", targets: ["ClipboardCore"])
    ],
    targets: [
        .target(name: "ClipboardCore"),
        .executableTarget(
            name: "Clipstack",
            dependencies: ["ClipboardCore"],
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("CloudKit")]
        ),
        .executableTarget(name: "MakeIcon", dependencies: ["ClipboardCore"]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"])
    ]
)
