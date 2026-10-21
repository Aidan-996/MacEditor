// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacEditor",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacEditor", targets: ["MacEditor"])],
    targets: [
        .executableTarget(name: "MacEditor", path: "Sources/MacEditor")
    ]
)
