// swift-tools-version:4.0

import PackageDescription

let package = Package(name: "layout",
        dependencies: [
            .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.1.0"),
            .package(url: "https://github.com/onevcat/Rainbow", from: "3.0.0")
        ],
        targets: [
            .target(name: "layout", dependencies: ["Utility", "Rainbow"], path: "layout"),
        ])
