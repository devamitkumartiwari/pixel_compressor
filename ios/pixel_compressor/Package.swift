// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pixel_compressor",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        // Flutter's SPM plugin tooling expects this product name hyphenated
        // (derived from the pub package name with underscores replaced by
        // hyphens), even though the target/module name below must stay
        // underscored to match Dart's generated `import pixel_compressor`.
        .library(name: "pixel-compressor", targets: ["pixel_compressor"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "pixel_compressor",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
