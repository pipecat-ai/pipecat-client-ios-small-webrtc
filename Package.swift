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
        .package(url: "https://github.com/pipecat-ai/pipecat-client-ios.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "PipecatClientIOSSmallWebrtc",
            dependencies: [
                .product(name: "PipecatClientIOS", package: "pipecat-client-ios"),
                "WebRTC"
            ]),
        // webrtc-sdk's WebRTC build (the one flutter-webrtc uses) in place of
        // stasel/WebRTC. Stock libwebrtc forces software echo cancellation
        // (AEC3) off on iOS and relies on the Voice-Processing I/O unit alone;
        // this build doesn't, and it exposes RTCDefaultAudioProcessingModule.
        // The module is still named WebRTC. Its zip is referenced directly
        // because webrtc-sdk/Specs' own manifest declares visionOS 26 under
        // swift-tools-version 5.9 and doesn't resolve.
        .binaryTarget(
            name: "WebRTC",
            url: "https://github.com/webrtc-sdk/Specs/releases/download/150.7871.04/WebRTC.xcframework.zip",
            checksum: "9532fe3ce47507c304f37a4355b907be1e89967971d614a04603005a546249be"
        ),
    ]
)
