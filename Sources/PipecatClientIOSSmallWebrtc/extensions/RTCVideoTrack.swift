import WebRTC
import PipecatClientIOS

extension RTCVideoTrack {
    func toRtvi() -> PipecatClientIOS.MediaStreamTrack {
        return MediaStreamTrack(
            id: MediaTrackId(id: trackId),
            kind: .video
        )
    }
}
