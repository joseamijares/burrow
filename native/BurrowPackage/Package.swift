// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "BurrowFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BurrowFeature", targets: ["BurrowFeature"]),
    ],
    dependencies: [
        // In-app updates (Updates.swift), the same pin as Daybook. The release workflow
        // signs each Burrow-<version>.dmg with the same version's sign_update.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "BurrowFeature",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            // Scripts: the prototype's scan scripts, run with /bin/bash (Scripts.swift).
            resources: [.copy("Fonts"), .copy("Scripts")]
        ),
        .testTarget(
            name: "BurrowFeatureTests",
            dependencies: ["BurrowFeature"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
