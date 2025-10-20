import SwiftUI
import PipecatClientIOS

/// A wrapper for `SmallWebRTCVideoView` that exposes the video size via a `@Binding`.
public struct SmallWebRTCVideoViewSwiftUI: UIViewRepresentable {

    /// The current size of the video being rendered by this view.
    @Binding private(set) var videoSize: CGSize

    private let videoTrack: MediaTrackId?
    private let videoScaleMode: SmallWebRTCVideoView.VideoScaleMode

    public init(
        videoTrack: MediaTrackId? = nil,
        videoScaleMode: SmallWebRTCVideoView.VideoScaleMode = .fill,
        videoSize: Binding<CGSize> = .constant(.zero)
    ) {
        self.videoTrack = videoTrack
        self.videoScaleMode = videoScaleMode
        self._videoSize = videoSize
    }

    public func makeUIView(context: Context) -> SmallWebRTCVideoView {
        let videoView = SmallWebRTCVideoView()
        videoView.delegate = context.coordinator
        return videoView
    }

    public func updateUIView(_ videoView: SmallWebRTCVideoView, context: Context) {
        context.coordinator.smallWebRTCVideoView = self

        if videoView.videoTrack != videoTrack {
            videoView.videoTrack = videoTrack
        }

        if videoView.videoScaleMode != videoScaleMode {
            videoView.videoScaleMode = videoScaleMode
        }
    }
}

extension SmallWebRTCVideoViewSwiftUI {
    public final class Coordinator: VideoViewDelegate {
        fileprivate var smallWebRTCVideoView: SmallWebRTCVideoViewSwiftUI

        init(_ smallWebRTCVideoView: SmallWebRTCVideoViewSwiftUI) {
            self.smallWebRTCVideoView = smallWebRTCVideoView
        }

        public func videoView(_ videoView: VideoView, didChangeVideoSize size: CGSize) {
            // Update the `videoSize` binding with the current `size` value.
            DispatchQueue.main.async {
                self.smallWebRTCVideoView.videoSize = size
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

#Preview {
    SmallWebRTCVideoViewSwiftUI()
}
