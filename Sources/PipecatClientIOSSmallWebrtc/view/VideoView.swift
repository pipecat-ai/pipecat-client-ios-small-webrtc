import UIKit
import WebRTC

/// The view's delegate.
public protocol VideoViewDelegate: AnyObject {
    /// Provides an opportunity to respond when the view's video size changes.
    func videoView(_ videoView: VideoView, didChangeVideoSize size: CGSize)
}

/// A view for rendering a video track's stream.
open class VideoView: UIView {
    /// Modes that define how a view’s video content fills the available space.
    public enum VideoScaleMode: Equatable, Hashable, CaseIterable {
        /// Resizes the content so it’s all within the available space,
        /// both vertically and horizontally.
        ///
        /// This mode preserves the content’s aspect ratio. If the content doesn’t have
        /// the same aspect ratio as the available space, the content becomes the same
        /// size as the available space on one axis and leaves empty space on the other.
        case fit

        /// Resize the content so it occupies all available space,
        /// both vertically and horizontally.
        ///
        /// This mode preserves the content’s aspect ratio. If the content doesn’t have
        /// the same aspect ratio as the available space, the content becomes the same
        /// size as the available space on one axis, and larger on the other axis.
        case fill
    }

    // Private delegate helper type to avoid leaking conformance (and thus WebRTC types):
    private class Delegate: NSObject, RTCVideoViewDelegate {
        weak var view: VideoView?

        internal init(view: VideoView) {
            self.view = view
        }

        public func videoView(
            _ videoView: RTCVideoRenderer,
            didChangeVideoSize size: CGSize
        ) {
            self.view?.rtcVideoView(videoView, didChangeVideoSize: size)
        }
    }

    /// The view's video track.
    public var track: RTCVideoTrack? {
        didSet {
            if oldValue !== self.track {
                oldValue?.remove(self.rtcView)
            }
            if let track = self.track {
                track.add(self.rtcView)
            } else {
                oldValue?.remove(self.rtcView)
            }
        }
    }

    /// The view's video scale mode.
    ///
    /// The default value of this property is `.fill`.
    public var videoScaleMode: VideoScaleMode = .fill {
        didSet {
            self.setNeedsUpdateConstraints()
        }
    }

    /// The view's video scale mode.
    ///
    /// The default value of this property is `.zero`.
    public private(set) var videoSize: CGSize = .zero {
        didSet {
            self.setNeedsUpdateConstraints()
        }
    }

    /// The view's delegate.
    public weak var delegate: VideoViewDelegate? = nil

    internal let rtcView: RTCMTLVideoView = .init(frame: .zero)

    private var contentModeConstraints: [NSLayoutConstraint] = []
    private var rtcDelegate: Delegate? = nil

    public override init(frame: CGRect) {
        super.init(frame: frame)

        self.commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)

        self.commonInit()
    }

    private func commonInit() {
        self.rtcDelegate = Delegate(view: self)
        self.rtcView.delegate = self.rtcDelegate

        self.clipsToBounds = true

        self.rtcView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.rtcView)

        self.setNeedsUpdateConstraints()
    }

    deinit {
        self.track?.remove(self.rtcView)
    }

    public override func updateConstraints() {
        NSLayoutConstraint.deactivate(self.contentModeConstraints)
        self.contentModeConstraints = self.constraints(contentMode: self.contentMode)
        NSLayoutConstraint.activate(self.contentModeConstraints)

        super.updateConstraints()
    }

    private func constraints(contentMode: ContentMode) -> [NSLayoutConstraint] {
        let size = self.videoSize

        guard size != .zero else {
            return []
        }

        let aspectRatio = size.width / size.height

        switch self.videoScaleMode {
        case .fit:
            return NSLayoutConstraint.scaleAspectFit(
                self.rtcView,
                in: self,
                aspectRatio: aspectRatio
            )
        case .fill:
            return NSLayoutConstraint.scaleAspectFill(
                self.rtcView,
                in: self,
                aspectRatio: aspectRatio
            )
        }
    }

    private func rtcVideoView(
        _ videoView: RTCVideoRenderer,
        didChangeVideoSize size: CGSize
    ) {
        self.videoSize = size
        self.delegate?.videoView(self, didChangeVideoSize: size)
        self.setNeedsUpdateConstraints()
    }
}
