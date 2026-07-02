# 1.2.0 — 2026-01-14

### Changed

- Updated the `PipecatClientIOS` dependency to [1.2.0](https://github.com/pipecat-ai/pipecat-client-ios/blob/main/CHANGELOG.md#120--2026-01-03).

# 1.1.1 — 2025-10-22

### Added

- Allowed `startBotAndConnect` to work with Pipecat Cloud and the Pipecat runner.
- Added trickle ICE support.

### Changed

- Updated the `PipecatClientIOS` dependency to [1.1.1](https://github.com/pipecat-ai/pipecat-client-ios/blob/main/CHANGELOG.md#111--2025-10-23).

# 0.0.1 — 2025-04-07

Initial release of `SmallWebRTCTransport`.

### Added

- Sending and receiving the SDP offer/answer.
- Support for sending and showing video tracks, enabling video, switching codecs (defaulting to VP8), and switching/selecting the camera device.
- Renegotiation support.
- Respecting the `enableCam`/`enableMic` flags via WebRTC transceivers.

### Changed

- Updated the `PipecatClientIOS` dependency to [0.3.5](https://github.com/pipecat-ai/pipecat-client-ios/blob/main/CHANGELOG.md#035---2025-04-02).
