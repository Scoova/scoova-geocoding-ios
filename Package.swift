// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScoovaGeocoding",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "ScoovaGeocoding", targets: ["ScoovaGeocoding"]),
    ],
    targets: [
        .target(
            name: "ScoovaGeocoding",
            path: "Sources/ScoovaGeocoding"
        ),
        .testTarget(
            name: "ScoovaGeocodingTests",
            dependencies: ["ScoovaGeocoding"],
            path: "Tests/ScoovaGeocodingTests"
        ),
    ]
)
