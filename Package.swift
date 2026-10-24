// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PocketCrew",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "PocketCrew", targets: ["PocketCrew"])],
  dependencies: [
    .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.2")
  ],
  targets: [
    .executableTarget(
      name: "PocketCrew",
      dependencies: [.product(name: "Supabase", package: "supabase-swift")],
      path: "Sources/PocketCrew",
      resources: [.process("Resources")]
    )
  ]
)
