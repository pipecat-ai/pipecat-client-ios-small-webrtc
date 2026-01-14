# Pipecat iOS SDK with Small WebRTC transport

The SmallWebRTCTransport class provides a WebRTC transport layer establishing a PeerConnection with Pipecat SmallWebRTCTransport. 
It handles audio/video device management, WebRTC connections, and real-time communication between client and bot.

## Install

To depend on the client package, you can add this package via Xcode's package manager using the URL of this git repository directly, or you can declare your dependency in your `Package.swift`:

```swift
.package(url: "https://github.com/pipecat-ai/pipecat-client-ios-small-webrtc.git", from: "1.2.0"),
```

and add `"PipecatClientIOSSmallWebrtc"` to your application/library target, `dependencies`, e.g. like this:

```swift
.target(name: "YourApp", dependencies: [
    .product(name: "PipecatClientIOSSmallWebrtc", package: "pipecat-client-ios-small-webrtc")
],
```

## Quick Start

Instantiate a `RTVIClient` instance, wire up the bot's audio, and start the conversation:

```swift
let pipecatClientOptions = PipecatClientOptions.init(
    transport: SmallWebRTCTransport.init(),
    enableMic: true,
    enableCam: false,
)
let pipecatClientIOS = PipecatClient.init(
    options: pipecatClientOptions
)
let startBotParams = APIRequest.init(endpoint: URL(string: baseUrl)!)
pipecatClientIOS?.startBotAndConnect(startBotParams: startBotParams) { (result: Result<SmallWebRTCTransportConnectionParams, AsyncExecutionError>) in
    switch result {
    case .failure(let error):
        // Handle error
    case .success(_):
        // handle success
    }
}
```

## Contributing

We are welcoming contributions to this project in form of issues and pull request. For questions about Pipecat head over to the [Pipecat discord server](https://discord.gg/pipecat).
