import PipecatClientIOS

/// Overrides the WebRTC [VideoView] to allow [MediaTrackId] tracks from the VoiceClient to be rendered.
public final class SmallWebRTCVideoView: VideoView {
    
    /// Displays the specified [MediaTrackId] in this view.
    public var videoTrack: MediaTrackId? {
        get {
            guard let track = self.track else { return nil }
            return track.toRtvi()
        }
        set {
            self.track = newValue.flatMap { VideoTrackRegistry.getTrack(mediaTrackId: $0) }
        }
    }
    
}
