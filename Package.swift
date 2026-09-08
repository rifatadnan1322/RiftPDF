// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RiftPDF",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RiftPDF",
            path: "Sources/RiftPDF",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
