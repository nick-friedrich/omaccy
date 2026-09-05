// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OmaccyHyperkey",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "omaccy-hyperkey", targets: ["hyperkey"])
    ],
    targets: [
        .executableTarget(
            name: "hyperkey",
            path: "Sources/hyperkey",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(name: "hyperkeyTests", dependencies: ["hyperkey"])
    ]
)
