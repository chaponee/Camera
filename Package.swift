// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Camera",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(name: "Camera", targets: ["Camera"])
    ],
    targets: [
        .executableTarget(
            name: "Camera",
            path: "."
        )
    ]
)
