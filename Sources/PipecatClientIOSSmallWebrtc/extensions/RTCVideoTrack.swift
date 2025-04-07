import WebRTC
import PipecatClientIOS

extension RTCVideoTrack {
    func toRtvi() -> MediaTrackId {
        return MediaTrackId(id: trackId)
    }
}
