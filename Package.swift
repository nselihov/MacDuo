// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacDuo",
    defaultLocalization: "ru",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "MacDuo", targets: ["MacDuo"]),
        .executable(name: "MacDuoChecks", targets: ["MacDuoChecks"]),
        .executable(name: "MacDuoSensorCheck", targets: ["MacDuoSensorCheck"]),
        .executable(name: "MacDuoDisplayCheck", targets: ["MacDuoDisplayCheck"]),
        .executable(name: "MacDuoLockScreenProbe", targets: ["MacDuoLockScreenProbe"]),
    ],
    targets: [
        .target(name: "MacDuoSkyLight", linkerSettings: [.linkedFramework("AppKit")]),
        .executableTarget(
            name: "MacDuoLockScreenProbe",
            dependencies: ["MacDuoSkyLight"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuartzCore")]
        ),
        .target(
            name: "MacDuoCore"
        ),
        .executableTarget(
            name: "MacDuo",
            dependencies: ["MacDuoCore", "MacDuoSkyLight"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "MacDuoChecks",
            dependencies: ["MacDuoCore"]
        ),
        .executableTarget(
            name: "MacDuoSensorCheck",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "MacDuoDisplayCheck",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
