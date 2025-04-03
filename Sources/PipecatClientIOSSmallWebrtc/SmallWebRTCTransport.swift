import Foundation
import PipecatClientIOS
import OSLog
import WebRTC

/// An RTVI transport to connect with the SmallWebRTCTransport  backend.
public class SmallWebRTCTransport: Transport {
    
    public static let SERVICE_NAME = "small-webrtc-transport";
    
    private var iceServers: [String] = []
    private let options: RTVIClientOptions
    private var _state: TransportState = .disconnected
    private var smallWebRTCConnection: SmallWebRTCConnection?  = nil
    private let audioManager = AudioManager()
    private let videoManager = VideoManager()
    private var connectedBotParticipant = Participant(
        id: ParticipantId(id: UUID().uuidString),
        name: "Small WebRTC Bot",
        local: false
    )
    private var devicesInitialized: Bool = false
    private var _selectedMic: MediaDeviceInfo?
    
    // MARK: - Public
    
    /// Voice client delegate (used directly by user's code)
    public weak var delegate: PipecatClientIOS.RTVIClientDelegate?
    
    /// RTVI inbound message handler (for sending RTVI-style messages to voice client code to handle)
    public var onMessage: ((PipecatClientIOS.RTVIMessageInbound) -> Void)?
    
    public required convenience init(options: PipecatClientIOS.RTVIClientOptions) {
        self.init(options: options, iceServers: nil)
    }
    
    public init(options: PipecatClientIOS.RTVIClientOptions, iceServers: [String]?) {
        self.options = options
        self.audioManager.delegate = self
        if iceServers != nil {
            self.iceServers = iceServers!
        }
    }
    
    public func initDevices() async throws {
        if (self.devicesInitialized) {
            // There is nothing to do in this case
            return
        }
        
        self.setState(state: .initializing)
        
        // start managing audio device configuration
        self.audioManager.startManagingIfNecessary()
        
        // initialize devices state and report initial available & selected devices
        self._selectedMic = self.getSelectedMic()
        self.delegate?.onAvailableMicsUpdated(mics: self.getAllMics());
        self.delegate?.onMicUpdated(mic: self._selectedMic)
        
        self.setState(state: .initialized)
        self.devicesInitialized = true
    }
    
    public func release() {
        // stop managing audio device configuration
        self.audioManager.stopManaging()
        self._selectedMic = nil
        VideoTrackRegistry.clearRegistry()
    }
    
    private func sendOffer(connectUrl: String, sdp: RTCSessionDescription) async throws -> RTCSessionDescription {
        guard let url = URL(string: connectUrl) else {
            throw InvalidAuthBundleError()
        }
        
        Logger.shared.debug("connectUrl, \(connectUrl)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            /*var customBundle:Value = Value.object([
             "sdp": Value.string(sdp.sdp),
             "type": Value.number(Double(sdp.type.rawValue))
             ])*/
            request.httpBody = try JSONEncoder().encode( SessionDescription(from:sdp))
            
            Logger.shared.debug("Will send offer")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, ( httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299 ) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                let message = "Failed while authenticating: \(errorMessage)"
                throw HttpError(message: message)
            }
            
            let answer = try JSONDecoder().decode(SessionDescription.self, from: data)
            
            Logger.shared.debug("Received answer")
            
            return answer.rtcSessionDescription
        } catch {
            throw HttpError(message: "Failed while trying to receive answer.", underlyingError: error)
        }
    }
    
    public func connect(authBundle: PipecatClientIOS.AuthBundle?) async throws {
        self.setState(state: .connecting)
        
        let webrtcClient = SmallWebRTCConnection(iceServers: self.iceServers)
        self.smallWebRTCConnection = webrtcClient
        
        webrtcClient.delegate = self
        
        // TODO: we should consider the options to know if we should r not
        // create the audio and video track
        // right now we are always capturing both for testing
        webrtcClient.startCaptureLocalVideo()
        
        // start connecting
        do {
            let offer = try await webrtcClient.offer()
            
            guard let connectUrl = self.options.params.config.serverUrl else {
                Logger.shared.error("Missing Base URL")
                return
            }
            
            let answer = try await self.sendOffer(connectUrl: connectUrl, sdp: offer)
            webrtcClient.set(remoteSdp: answer, completion: { error in
                if let error = error {
                    Logger.shared.error("Failed to set remote SDP: \(error.localizedDescription)")
                }
            })
        } catch {
            Logger.shared.error("Received error while trying to connect \(error)")
            self.smallWebRTCConnection = nil
            self.setState(state: .error)
            throw error
        }
        
        // go to connected state
        // (unless we've already leaped ahead to the ready state - see connectionDidFinishModelSetup())
        if _state == .connecting {
            self.setState(state: .connected)
        }
    }
    
    public func disconnect() async throws {
        // stop websocket connection
        self.smallWebRTCConnection?.disconnect()
        self.smallWebRTCConnection = nil
        
        self.delegate?.onTracksUpdated(tracks: self.tracks()!)
        
        self.setState(state: .disconnected)
    }
    
    public func getAllMics() -> [PipecatClientIOS.MediaDeviceInfo] {
        audioManager.availableDevices.map { $0.toRtvi() }
    }
    
    public func getAllCams() -> [PipecatClientIOS.MediaDeviceInfo] {
        videoManager.availableDevices.map { $0.toRtvi() }
    }
    
    public func updateMic(micId: PipecatClientIOS.MediaDeviceId) async throws {
        audioManager.preferredAudioDevice = .init(deviceID: micId.id)
        
        // Refresh what we should report as the selected mic
        refreshSelectedMicIfNeeded()
    }
    
    public func updateCam(camId: PipecatClientIOS.MediaDeviceId) async throws {
        self.smallWebRTCConnection?.switchCamera(to: camId.id)
    }
    
    /// What we report as the selected mic.
    public func selectedMic() -> PipecatClientIOS.MediaDeviceInfo? {
        _selectedMic
    }
    
    public func selectedCam() -> PipecatClientIOS.MediaDeviceInfo? {
        return self.smallWebRTCConnection?.getCurrentCamera()?.toRtvi()
    }
    
    public func enableMic(enable: Bool) async throws {
        if enable {
            self.smallWebRTCConnection?.unmuteAudio()
        } else {
            self.smallWebRTCConnection?.muteAudio()
        }
    }
    
    public func enableCam(enable: Bool) async throws {
        if enable {
            self.smallWebRTCConnection?.showVideo()
        } else {
            self.smallWebRTCConnection?.hideVideo()
        }
    }
    
    public func isCamEnabled() -> Bool {
        return self.smallWebRTCConnection?.isVideoEnabled() ?? false
    }
    
    public func isMicEnabled() -> Bool {
        return self.smallWebRTCConnection?.isAudioEnabled() ?? true
    }
    
    public func sendMessage(message: PipecatClientIOS.RTVIMessageOutbound) throws {
        do {
            try self.smallWebRTCConnection?.sendMessage(message: message)
        } catch {
            Logger.shared.error("Error sending message: \(error.localizedDescription)")
        }
    }
    
    public func state() -> PipecatClientIOS.TransportState {
        self._state
    }
    
    public func setState(state: PipecatClientIOS.TransportState) {
        let previousState = self._state
        
        self._state = state
        
        // Fire delegate methods as needed
        if state != previousState {
            self.delegate?.onTransportStateChanged(state: self._state)
            
            if state == .connected {
                self.delegate?.onConnected()
                // New bot participant id each time we connect
                connectedBotParticipant = Participant(
                    id: ParticipantId(id: UUID().uuidString),
                    name: connectedBotParticipant.name,
                    local: connectedBotParticipant.local
                )
                self.delegate?.onParticipantJoined(participant: connectedBotParticipant)
                self.delegate?.onBotConnected(participant: connectedBotParticipant)
            }
            else if state == .disconnected {
                self.delegate?.onParticipantLeft(participant: connectedBotParticipant)
                self.delegate?.onBotDisconnected(participant: connectedBotParticipant)
                self.delegate?.onDisconnected()
            }
        }
    }
    
    public func isConnected() -> Bool {
        return [.connected, .ready].contains(self._state)
    }
    
    public func tracks() -> PipecatClientIOS.Tracks? {
        // removing any track since we are going to store it again
        VideoTrackRegistry.clearRegistry()
        
        let localVideoTrack = self.smallWebRTCConnection?.getLocalVideoTrack()
        // Registering the track so we can retrieve it later inside the VoiceClientVideoView
        if let localVideoTrack = localVideoTrack {
            VideoTrackRegistry.registerTrack(originalTrack: localVideoTrack, mediaTrackId: localVideoTrack.toRtvi())
        }
        
        let botVideoTrack = self.smallWebRTCConnection?.getRemoteVideoTrack()
        // Registering the track so we can retrieve it later inside the VoiceClientVideoView
        if let botVideoTrack = botVideoTrack {
            VideoTrackRegistry.registerTrack(originalTrack: botVideoTrack, mediaTrackId: botVideoTrack.toRtvi())
        }
        
        return Tracks(
            local: ParticipantTracks(
                audio: self.smallWebRTCConnection?.getLocalAudioTrack()?.toRtvi(),
                video: localVideoTrack?.toRtvi()
            ),
            bot: ParticipantTracks(
                audio: self.smallWebRTCConnection?.getRemoteAudioTrack()?.toRtvi(),
                video: botVideoTrack?.toRtvi()
            )
        )
    }
    
    public func expiry() -> Int? {
        return nil
    }
    
    public func setIceServers(iceServers: [String]) {
        self.iceServers = iceServers
    }
    
    // MARK: - Private
    
    /// Refresh what we should report as the selected mic.
    private func refreshSelectedMicIfNeeded() {
        let newSelectedMic = getSelectedMic()
        if newSelectedMic != _selectedMic {
            _selectedMic = newSelectedMic
            delegate?.onMicUpdated(mic: _selectedMic)
        }
    }
    
    /// Selected mic is a value derived from the preferredAudioDevice and the set of available devices, so it may change whenever either of those change.
    private func getSelectedMic() -> PipecatClientIOS.MediaDeviceInfo? {
        audioManager.availableDevices.first { $0.deviceID == audioManager.preferredAudioDeviceIfAvailable?.deviceID }?.toRtvi()
    }
}

// MARK: - SmallWebRTCConnectionDelegate

extension SmallWebRTCTransport: SmallWebRTCConnectionDelegate {
    
    func onConnectionStateChanged(state: RTCIceConnectionState) {
        if ( state == .failed || state == .closed ) && ( self._state != .disconnected && self._state != .disconnecting ){
            Task {
                try await self.disconnect()
            }
        }
    }
    
    func onMsgReceived(msg: PipecatClientIOS.Value) {
        self.handleMessage(msg)
    }
    
    func onTracksUpdated() {
        self.delegate?.onTracksUpdated(tracks: self.tracks()!)
    }
    
    private func handleMessage(_ msg: Value) {
        let dict = msg.asObject
        if let typeValue = dict["label"] {
            if typeValue?.asString == "rtvi-ai" {
                Logger.shared.debug("Received RTVI message: \(msg)")
                self.onMessage?(.init(
                    type: dict["type"]??.asString,
                    data: dict["data"]??.asString,
                    id: dict["id"]??.asString
                ))
            }
        }
        // TODO: implement the signalling message
    }
    
}

// MARK: - AudioManagerDelegate

extension SmallWebRTCTransport: AudioManagerDelegate {
    func audioManagerDidChangeAvailableDevices(_ audioManager: AudioManager) {
        // Report available mics changed
        delegate?.onAvailableMicsUpdated(mics: getAllMics())
        
        // Refresh what we should report as the selected mic
        refreshSelectedMicIfNeeded()
    }
    
    func audioManagerDidChangeAudioDevice(_ audioManager: AudioManager) {
        // nothing to do here
    }
}
