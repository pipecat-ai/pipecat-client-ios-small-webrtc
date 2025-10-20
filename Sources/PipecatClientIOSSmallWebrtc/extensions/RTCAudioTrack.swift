import WebRTC
import PipecatClientIOS

extension RTCAudioTrack {
    func toRtvi() -> PipecatClientIOS.MediaStreamTrack {
        return MediaStreamTrack(
            id: MediaTrackId(id: trackId),
            kind: .audio
        )
    }
}
