// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "NestedKit",
  platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "NestedCore", targets: ["NestedCore"]),
    .library(name: "NestedData", targets: ["NestedData"]),
  ],
  dependencies: [
    // Pinned per the PRD's dependency-risk mitigation. Bump deliberately.
    .package(url: "https://github.com/pointfreeco/sqlite-data", exact: "1.12.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
  ],
  targets: [
    // Pure Foundation: units, predictions, flags, alarm rules, stats, CSV.
    // No Apple-only frameworks so it builds and tests on Linux too.
    .target(name: "NestedCore"),
    // Schema, migrations, EventStore, sync bootstrap.
    .target(
      name: "NestedData",
      dependencies: [
        "NestedCore",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "GRDB", package: "GRDB.swift"),
      ]
    ),
    .testTarget(name: "NestedCoreTests", dependencies: ["NestedCore"]),
    .testTarget(
      name: "NestedDataTests",
      dependencies: [
        "NestedData",
        .product(name: "SQLiteDataTestSupport", package: "sqlite-data"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
