// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ThreeMinCore", products: [.library(name: "ThreeMinCore", targets: ["ThreeMinCore"])],
    targets: [.target(name: "ThreeMinCore", path: "Shared"),
              .testTarget(name: "ThreeMinCoreTests", dependencies: ["ThreeMinCore"], path: "Tests/Swift")])
