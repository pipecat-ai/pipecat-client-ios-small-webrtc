import Foundation
import WebRTC
import PipecatClientIOS

protocol SmallWebRTCConnectionDelegate: AnyObject {
    func onConnectionStateChanged(state: RTCIceConnectionState)
    func onMsgReceived(msg: Value)
    func onTracksUpdated()
}

final class SmallWebRTCConnection: NSObject {
    
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    weak var delegate: SmallWebRTCConnectionDelegate?
    
    private let peerConnection: RTCPeerConnection
    private let mediaConstraints = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                    kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue]
    
    private var signallingDataChannel: RTCDataChannel?
    
    private var localAudioTrack: RTCAudioTrack?
    private var remoteAudioTrack: RTCAudioTrack?
    
    private var videoCapturer: RTCVideoCapturer?
    private var localVideoTrack: RTCVideoTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    
    private var iceGatheringCompleted = false
    
    @available(*, unavailable)
    override init() {
        fatalError("SmallWebRTCConnection:init is unavailable")
    }
    
    required init(iceServers: [String]) {
        let config = RTCConfiguration()
        if !iceServers.isEmpty {
            config.iceServers = [RTCIceServer(urlStrings: iceServers)]
        }
        
        // Unified plan is more superior than planB
        config.sdpSemantics = .unifiedPlan
        
        // gatherContinually will let WebRTC to listen to any network changes and send any new candidates to the other client
        config.continualGatheringPolicy = .gatherOnce
        
        // Define media constraints. DtlsSrtpKeyAgreement is required to be true to be able to connect with web browsers.
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: ["DtlsSrtpKeyAgreement":kRTCMediaConstraintsValueTrue])
        
        guard let peerConnection = SmallWebRTCConnection.factory.peerConnection(with: config, constraints: constraints, delegate: nil) else {
            fatalError("Could not create new RTCPeerConnection")
        }
        
        self.peerConnection = peerConnection
        
        super.init()
        self.createMediaSenders()
        self.peerConnection.delegate = self
    }
    
    // MARK: Signaling
    func offer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void) {
        // 1. Create the offer
        let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstraints, optionalConstraints: nil)
        
        self.peerConnection.offer(for: constrains) { (sdp, error) in
            guard let sdp = sdp else {
                Logger.shared.debug("Error creating offer: \(String(describing: error))")
                return
            }
            
            // 2. Set the local description to trigger ICE gathering
            self.peerConnection.setLocalDescription(sdp) { (error) in
                if let error = error {
                    Logger.shared.debug("Error setting local description: \(error)")
                    return
                }
                
                // Now ICE gathering will start, we need to wait for it to complete
                self.waitForIceGathering(completion: {
                    // Manipulating so we can choose the codec
                    var offer = SessionDescription.init(from: self.peerConnection.localDescription!)
                    // It seems aiortc it is working a lot better when receiving VP8 from iOS
                    offer.sdp = self.filterCodec(kind: "video", codec: "VP8", in: offer.sdp)
                    completion(offer.rtcSessionDescription)
                })
            }
        }
    }
    
    private func waitForIceGathering(completion: @escaping () -> Void) {
        // Wait until ICE gathering is complete
        DispatchQueue.global().async {
            while self.peerConnection.iceGatheringState != .complete {
                // Sleep to avoid blocking the main thread
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            // Once gathering is complete, proceed with the callback
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    func offer() async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation { continuation in
            self.offer { sdp in
                continuation.resume(returning: sdp)
            }
        }
    }
    
    func answer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void)  {
        let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstraints,
                                             optionalConstraints: nil)
        self.peerConnection.answer(for: constrains) { (sdp, error) in
            guard let sdp = sdp else {
                return
            }
            
            self.peerConnection.setLocalDescription(sdp, completionHandler: { (error) in
                completion(sdp)
            })
        }
    }
    
    func answer() async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation { continuation in
            self.answer { sdp in
                continuation.resume(returning: sdp)
            }
        }
    }
    
    func set(remoteSdp: RTCSessionDescription, completion: @escaping (Error?) -> ()) {
        self.peerConnection.setRemoteDescription(remoteSdp, completionHandler: completion)
    }
    
    func set(remoteCandidate: RTCIceCandidate, completion: @escaping (Error?) -> ()) {
        self.peerConnection.add(remoteCandidate, completionHandler: completion)
    }
    
    func getLocalAudioTrack() -> RTCAudioTrack? {
        return self.localAudioTrack
    }
    
    func getRemoteAudioTrack() -> RTCAudioTrack? {
        return self.remoteAudioTrack
    }
    
    func getLocalVideoTrack() -> RTCVideoTrack? {
        return self.localVideoTrack
    }
    
    func getRemoteVideoTrack() -> RTCVideoTrack? {
        return self.remoteVideoTrack
    }
    
    // MARK: Media
    func startCaptureLocalVideo() {
        guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer else {
            return
        }
        
        guard
            let frontCamera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == .front }),
            
                // choose highest res
            let format = (RTCCameraVideoCapturer.supportedFormats(for: frontCamera).sorted { (f1, f2) -> Bool in
                let width1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription).width
                let width2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription).width
                return width1 < width2
            }).last,
            
                // choose highest fps
            let fps = (format.videoSupportedFrameRateRanges.sorted { return $0.maxFrameRate < $1.maxFrameRate }.last) else {
            return
        }
        
        Logger.shared.info("FRAME RATE \(fps.maxFrameRate)")
        
        capturer.startCapture(with: frontCamera,
                              format: format,
                              fps: Int(fps.maxFrameRate))
    }
    
    func switchCamera(to deviceID: String) {
        guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer else {
            return
        }
        
        let captureDevices = RTCCameraVideoCapturer.captureDevices()
        guard let selectedDevice = captureDevices.first(where: { $0.uniqueID == deviceID }) else {
            Logger.shared.warn("Device with ID \(deviceID) not found")
            return
        }
        
        // Choose the highest resolution format
        guard let format = (RTCCameraVideoCapturer.supportedFormats(for: selectedDevice).sorted { (f1, f2) -> Bool in
            let width1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription).width
            let width2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription).width
            return width1 < width2
        }).last,
        
        // Choose the highest fps
        let fps = (format.videoSupportedFrameRateRanges.sorted { return $0.maxFrameRate < $1.maxFrameRate }.last) else {
            return
        }
        
        Logger.shared.info("Switching to camera: \(selectedDevice.localizedName)")
        
        capturer.startCapture(with: selectedDevice, format: format, fps: Int(fps.maxFrameRate))
    }
    
    func getCurrentCamera() -> Device? {
        guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer else {
            return nil
        }
        
        guard let currentDevice = capturer.captureSession.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first else {
            return nil
        }
        
        return Device(
            deviceID: currentDevice.uniqueID,
            groupID: "",
            kind: DeviceKind.videoInput,
            label: currentDevice.localizedName
        )
    }
    
    func renderRemoteVideo(to renderer: RTCVideoRenderer) {
        self.remoteVideoTrack?.add(renderer)
    }
    
    private func createMediaSenders() {
        let streamId = "stream"
        
        // Audio
        let audioTrack = self.createAudioTrack()
        self.localAudioTrack = audioTrack
        self.peerConnection.add(audioTrack, streamIds: [streamId])
        
        // Video
        let videoTrack = self.createVideoTrack()
        self.localVideoTrack = videoTrack
        self.peerConnection.add(videoTrack, streamIds: [streamId])
        // TODO: check if we need to do something different, like we do for audioTrack
        self.remoteVideoTrack = self.peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
        
        // Data
        if let dataChannel = self.createDataChannel(label: "rtvi-events") {
            dataChannel.delegate = self
            self.signallingDataChannel = dataChannel
        }
    }
    
    private func createAudioTrack() -> RTCAudioTrack {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = SmallWebRTCConnection.factory.audioSource(with: audioConstrains)
        let audioTrack = SmallWebRTCConnection.factory.audioTrack(with: audioSource, trackId: UUID().uuidString)
        return audioTrack
    }
    
    private func createVideoTrack() -> RTCVideoTrack {
        let videoSource = SmallWebRTCConnection.factory.videoSource()
        self.videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        let videoTrack = SmallWebRTCConnection.factory.videoTrack(with: videoSource, trackId: UUID().uuidString)
        return videoTrack
    }
    
    // MARK: Data Channels
    private func createDataChannel(label:String) -> RTCDataChannel? {
        let config = RTCDataChannelConfiguration()
        guard let dataChannel = self.peerConnection.dataChannel(forLabel: label, configuration: config) else {
            Logger.shared.debug("Warning: Couldn't create data channel.")
            return nil
        }
        return dataChannel
    }
    
    func sendMessage( message: Encodable) throws{
        let jsonData = try JSONEncoder().encode(message);
        Logger.shared.debug("Sending message: \(String(data: jsonData, encoding: .utf8) ?? "")")
        let buffer = RTCDataBuffer(data: jsonData, isBinary: true)
        self.signallingDataChannel?.sendData(buffer)
    }
    
    func disconnect() {
        self.signallingDataChannel?.close()
        self.peerConnection.close()
        
        self.signallingDataChannel = nil
        self.localAudioTrack = nil
        self.remoteAudioTrack = nil
        self.localVideoTrack = nil
        self.remoteVideoTrack = nil
    }
}

extension SmallWebRTCConnection: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Logger.shared.debug("peerConnection new signaling state: \(stateChanged)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Logger.shared.debug("peerConnection did add stream")
        if !stream.audioTracks.isEmpty {
            self.remoteAudioTrack = stream.audioTracks[0]
            self.delegate?.onTracksUpdated()
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Logger.shared.debug("peerConnection did remove stream")
        if !stream.audioTracks.isEmpty && self.remoteAudioTrack != nil && self.remoteAudioTrack?.trackId == stream.audioTracks[0].trackId {
            self.remoteAudioTrack = nil
            self.delegate?.onTracksUpdated()
        }
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Logger.shared.debug("peerConnection should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Logger.shared.debug("peerConnection new connection state: \(newState)")
        self.delegate?.onConnectionStateChanged(state: newState)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Logger.shared.debug("peerConnection new gathering state: \(newState)")
        if newState == .complete {
            self.iceGatheringCompleted = true
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Logger.shared.debug("peerConnection did discover new ice candidate \(candidate.sdp)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        Logger.shared.debug("peerConnection did remove candidate(s)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        Logger.shared.debug("peerConnection did receive new data channel")
    }
    
}
extension SmallWebRTCConnection {
    private func setTrackEnabled<T: RTCMediaStreamTrack>(_ type: T.Type, isEnabled: Bool) {
        peerConnection.transceivers
            .compactMap { return $0.sender.track as? T }
            .forEach { $0.isEnabled = isEnabled }
    }
}

// MARK:- Audio and Video control
extension SmallWebRTCConnection {
    func muteAudio() {
        self.setAudioEnabled(false)
    }
    
    func unmuteAudio() {
        self.setAudioEnabled(true)
    }
    
    func isAudioEnabled() -> Bool {
        return self.localAudioTrack?.isEnabled ?? true
    }
    
    private func setAudioEnabled(_ isEnabled: Bool) {
        setTrackEnabled(RTCAudioTrack.self, isEnabled: isEnabled)
    }
    
    func hideVideo() {
        self.setVideoEnabled(false)
    }
    
    func showVideo() {
        self.setVideoEnabled(true)
    }
    
    func isVideoEnabled() -> Bool {
        return self.localVideoTrack?.isEnabled ?? false
    }
    
    private func setVideoEnabled(_ isEnabled: Bool) {
        setTrackEnabled(RTCVideoTrack.self, isEnabled: isEnabled)
    }
}

extension SmallWebRTCConnection: RTCDataChannelDelegate {
    
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Logger.shared.debug("dataChannel did change state: \(dataChannel.readyState)")
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        do {
            let receivedValue = try JSONDecoder().decode(Value.self, from: buffer.data)
            self.delegate?.onMsgReceived(msg: receivedValue)
        } catch {
            Logger.shared.error("Error decoding JSON into Value: \(error.localizedDescription)")
        }
    }
    
}

// handle codecs manipulation
extension SmallWebRTCConnection {
    
    func filterCodec(kind: String, codec: String, in sdp: String) -> String {
        var allowedPayloadTypes: [String] = []
        let lines = sdp.components(separatedBy: "\n")
        var isMediaSection = false
        var modifiedLines: [String] = []

        let codecPattern = "a=rtpmap:(\\d+) \(NSRegularExpression.escapedPattern(for: codec))"
        let rtxPattern = "a=fmtp:(\\d+) apt=(\\d+)"
        let mediaPattern = "m=\(kind) \\d+ [A-Z/]+(?: (\\d+))*"

        guard let codecRegex = try? NSRegularExpression(pattern: codecPattern),
              let rtxRegex = try? NSRegularExpression(pattern: rtxPattern),
              let mediaRegex = try? NSRegularExpression(pattern: mediaPattern) else {
            return sdp
        }

        for line in lines {
            if line.starts(with: "m=\(kind) ") {
                isMediaSection = true
            } else if line.starts(with: "m=") {
                isMediaSection = false
            }

            if isMediaSection {
                if let match = codecRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let payloadRange = Range(match.range(at: 1), in: line) {
                    allowedPayloadTypes.append(String(line[payloadRange]))
                }

                if let match = rtxRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let payloadTypeRange = Range(match.range(at: 1), in: line),
                   let aptRange = Range(match.range(at: 2), in: line),
                   allowedPayloadTypes.contains(String(line[aptRange])) {
                    allowedPayloadTypes.append(String(line[payloadTypeRange]))
                }
            }
        }

        isMediaSection = false
        for line in lines {
            if line.starts(with: "m=\(kind) ") {
                isMediaSection = true
                if let match = mediaRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let mediaLineRange = Range(match.range(at: 0), in: line) {
                    let mediaLine = String(line[mediaLineRange])
                    let newMediaLine = mediaLine + " " + allowedPayloadTypes.joined(separator: " ")
                    modifiedLines.append(newMediaLine)
                    continue
                }
            } else if line.starts(with: "m=") {
                isMediaSection = false
            }

            if isMediaSection {
                let skipPatterns = ["a=rtpmap:", "a=fmtp:", "a=rtcp-fb:"]
                if skipPatterns.contains(where: { line.starts(with: $0) }),
                   let payloadType = line.split(separator: ":").last?.split(separator: " ").first,
                   !allowedPayloadTypes.contains(String(payloadType)) {
                    continue
                }
            }

            modifiedLines.append(line)
        }

        return modifiedLines.joined(separator: "\n")
    }
    
}
