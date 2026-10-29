// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AveoRalenti",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AveoRalenti", targets: ["AveoRalenti"]),
        .library(name: "AveoCore", targets: ["AveoCore"])
    ],
    targets: [
        .target(name: "AveoCore"),
        .target(name: "AveoRalenti", dependencies: ["AveoCore"]),
        .testTarget(name: "AveoCoreTests", dependencies: ["AveoCore"])
    ],
    swiftLanguageModes: [.v6]
)
