// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AgentBurn",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "AgentBurn", targets: ["AgentBurn"])],
  targets: [
    .executableTarget(
      name: "AgentBurn",
      resources: [.copy("Resources/AppIcon.icns"), .copy("Resources/Brands")]),
    .testTarget(name: "AgentBurnTests", dependencies: ["AgentBurn"]),
  ]
)
