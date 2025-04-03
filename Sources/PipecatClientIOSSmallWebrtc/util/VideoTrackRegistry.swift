import PipecatClientIOS
import WebRTC

final class VideoTrackRegistry {

    // Dictionary to store the original track and associated MediaTrackId
    private static var trackMap: [MediaTrackId: RTCVideoTrack] = [:]

    // Method to store the original track and MediaTrackId
    static func registerTrack(originalTrack: RTCVideoTrack, mediaTrackId: MediaTrackId) {
        trackMap[mediaTrackId] = originalTrack
    }

    // Retrieves the original track
    static func getTrack(mediaTrackId: MediaTrackId) -> RTCVideoTrack? {
        return trackMap[mediaTrackId]
    }

    // Method to clear all tracks from the registry
    static func clearRegistry() {
        trackMap.removeAll()
    }

}
