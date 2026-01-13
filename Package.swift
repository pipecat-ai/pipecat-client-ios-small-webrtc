// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PipecatClientIOSSmallWebrtc",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "PipecatClientIOSSmallWebrtc",
            targets: ["PipecatClientIOSSmallWebrtc"]),
    ],
    dependencies: [
        // Local dependency
        //.package(path: "../pipecat-client-ios"),
        .package(url: "https://github.com/pipecat-ai/pipecat-client-ios.git", from: "1.2.0"),
        .package(url: "https://github.com/stasel/WebRTC", from: "134.0.0"),
    ],
    targets: [
        .target(
            name: "PipecatClientIOSSmallWebrtc",
            dependencies: [
                .product(name: "PipecatClientIOS", package: "pipecat-client-ios"),
                .product(name: "WebRTC", package: "WebRTC")
            ]),
    ]
)
