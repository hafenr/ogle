// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ogle",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.9.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.99.1"),
    ],
    targets: [
        .executableTarget(
            name: "Ogle",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
    ]
)
