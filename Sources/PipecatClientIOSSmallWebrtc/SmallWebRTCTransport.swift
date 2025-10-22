import Foundation
import PipecatClientIOS
import OSLog
import WebRTC

/// An RTVI transport to connect with the SmallWebRTCTransport  backend.
public class SmallWebRTCTransport: Transport {
    private var iceConfig: IceConfig?
    private var options: PipecatClientOptions?
    private var smallWebRTConnectionParams: SmallWebRTCTransportConnectionParams?
    private var _state: TransportState = .disconnected
    private var smallWebRTCConnection: SmallWebRTCConnection?
    private let audioManager = AudioManager()
    private let videoManager = VideoManager()
    var connectedBotParticipant = Participant(
        id: ParticipantId(id: UUID().uuidString),
        name: "Small WebRTC Bot",
        local: false
    )
    private var devicesInitialized: Bool = false
    private var _selectedMic: MediaDeviceInfo?
    private var pc_id: String?
    private var preferredCamId: PipecatClientIOS.MediaDeviceId?
    private var _tracks: Tracks?

    // Needed for trickle ice
    private var canSendIceCandidates: Bool = false
    private var candidateQueue: [RTCIceCandidate] = []
    private var flushTimeout: Timer?
    private let flushDelay: TimeInterval = 0.2  // 200ms
    private var waitForIceGathering = false

    // MARK: - Public
    /// Parameters used to start the bot
    public var startBotParams: PipecatClientIOS.APIRequest?

    /// Voice client delegate (used directly by user's code)
    public weak var delegate: PipecatClientIOS.PipecatClientDelegate?

    /// RTVI inbound message handler (for sending RTVI-style messages to voice client code to handle)
    public var onMessage: ((PipecatClientIOS.RTVIMessageInbound) -> Void)?

    public required convenience init() {
        self.init(iceConfig: nil)
    }

    public init(iceConfig: IceConfig?, waitForIceGathering: Bool=false) {
        self.audioManager.delegate = self
        self.iceConfig = iceConfig
        self.waitForIceGathering = waitForIceGathering
    }

    public func initialize(options: PipecatClientOptions) {
        self.options = options
    }

    func handleTracksUpdated() {
        guard let currentTracks = self.tracks() else {
            // Nothing to do here, no tracks available yet
            return
        }

        if let previousTracks = self._tracks {
            self.handleTrackChanges(previous: previousTracks, current: currentTracks)
        } else {
            // First time tracks are available, notify all starting tracks
            self.handleInitialTracks(tracks: currentTracks)
        }

        self._tracks = currentTracks
    }

    public func initDevices() async throws {
        if self.devicesInitialized {
            // There is nothing to do in this case
            return
        }

        self.setState(state: .initializing)

        // start managing audio device configuration
        self.audioManager.startManagingIfNecessary()

        // initialize devices state and report initial available & selected devices
        self._selectedMic = self.getSelectedMic()
        self.delegate?.onAvailableMicsUpdated(mics: self.getAllMics())
        self.delegate?.onMicUpdated(mic: self._selectedMic)
        self.delegate?.onAvailableCamsUpdated(cams: self.getAllCams())
        self.delegate?.onCamUpdated(cam: self.selectedCam())

        self.setState(state: .initialized)
        self.devicesInitialized = true
    }

    public func release() {
        // stop managing audio device configuration
        self.audioManager.stopManaging()
        self._selectedMic = nil
        VideoTrackRegistry.clearRegistry()
    }

    private func sendOffer(offerBotParams: APIRequest, offer: SmallWebRTCSessionDescription) async throws
        -> SmallWebRTCSessionDescription {
        var request = URLRequest(url: offerBotParams.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Adding the custom headers if they have been provided
        for header in offerBotParams.headers {
            for (key, value) in header {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        do {
            request.httpBody = try JSONEncoder().encode(offer)

            Logger.shared.debug("Will send offer")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299
            else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                let message = "Failed while authenticating: \(errorMessage)"
                throw HttpError(message: message)
            }

            let answer = try JSONDecoder().decode(SmallWebRTCSessionDescription.self, from: data)

            Logger.shared.debug("Received answer")

            return answer
        } catch {
            throw HttpError(message: "Failed while trying to receive answer.", underlyingError: error)
        }
    }

    private func negotiate() async throws {
        // start connecting
        guard let webrtcClient = self.smallWebRTCConnection else {
            Logger.shared.warn("Unable to negotiate, no peer connection available.")
            return
        }
        guard let smallWebRTConnectionParams = self.smallWebRTConnectionParams else {
            Logger.shared.warn("Unable to negotiate, no connection params available.")
            return
        }
        do {
            let sdp = try await webrtcClient.offer()
            var offer = SmallWebRTCSessionDescription(from: sdp)
            offer.pc_id = self.pc_id

            let answer = try await self.sendOffer(
                offerBotParams: smallWebRTConnectionParams.webrtcRequestParams,
                offer: offer
            )
            self.pc_id = answer.pc_id

            webrtcClient.set(
                remoteSdp: answer.rtcSessionDescription,
                completion: { error in
                    if let error = error {
                        Logger.shared.error("Failed to set remote SDP: \(error.localizedDescription)")
                    }
                }
            )
        } catch {
            Logger.shared.error("Received error while trying to connect \(error)")
            self.smallWebRTCConnection = nil
            self.setState(state: .error)
            throw error
        }
    }

    public func connect(transportParams: TransportConnectionParams?) async throws {
        self.setState(state: .connecting)

        guard let smallWebRTConnectionParams = transportParams as? SmallWebRTCTransportConnectionParams else {
            throw InvalidTransportParamsError()
        }
        self.smallWebRTConnectionParams = smallWebRTConnectionParams

        let webrtcClient = SmallWebRTCConnection(
            iceConfig: smallWebRTConnectionParams.iceConfig ?? self.iceConfig,
            enableCam: self.options?.enableCam ?? false,
            enableMic: self.options?.enableMic ?? true,
            waitForIceGathering: self.waitForIceGathering
        )
        webrtcClient.delegate = self
        webrtcClient.startOrSwitchLocalVideoCapturer(deviceID: self.preferredCamId?.id)
        self.smallWebRTCConnection = webrtcClient

        try await self.negotiate()

        self.canSendIceCandidates = true
        self.flushIceCandidates()

        // Wait for the data channel to be open before setting state to connected
        try await webrtcClient.waitForDataChannelOpen()

        self.setState(state: .connected)

        try self.sendMessage(message: RTVIMessageOutbound.clientReady())
        self.syncTrackStatus()
    }

    private func buildRequestParamsBasedOnStartBotParams(startBotParams: PipecatClientIOS.APIRequest, sessionId: String)
        -> APIRequest {
        let startEndpoint = startBotParams.endpoint.absoluteString

        let offerUrlString = startEndpoint.replacingOccurrences(
            of: "/start",
            with: "/sessions/\(sessionId)/api/offer"
        )

        guard let offerUrl = URL(string: offerUrlString) else {
            fatalError("Invalid URL: \(offerUrlString)")
        }

        return APIRequest(
            endpoint: offerUrl,
            headers: startBotParams.headers
        )
    }

    public func transformStartBotResultToConnectionParams(
        startBotParams: PipecatClientIOS.APIRequest,
        startBotResult: StartBotResult
    ) throws -> any PipecatClientIOS.TransportConnectionParams {
        // It's already a TransportConnectionParams
        if let existingParams = startBotResult as? SmallWebRTCTransportConnectionParams {
            return existingParams
        }

        guard let startBotResult = startBotResult as? SmallWebRTCStartBotResult else {
            throw InvalidTransportParamsError()
        }

        let offerRequestParams = self.buildRequestParamsBasedOnStartBotParams(
            startBotParams: startBotParams,
            sessionId: startBotResult.sessionId
        )
        return SmallWebRTCTransportConnectionParams.init(
            webrtcRequestParams: offerRequestParams,
            iceConfig: startBotResult.iceConfig
        )
    }

    private func syncTrackStatus() {
        guard let smallWebRTCConnection = self.smallWebRTCConnection else { return }
        self.sendSignallingMessage(
            message: TrackStatusMessage.init(
                receiverIndex: SmallWebRTCTransceiverIndex.audio.rawValue,
                enabled: smallWebRTCConnection.isAudioEnabled()
            )
        )
        self.sendSignallingMessage(
            message: TrackStatusMessage.init(
                receiverIndex: SmallWebRTCTransceiverIndex.video.rawValue,
                enabled: smallWebRTCConnection.isVideoEnabled()
            )
        )
    }

    public func disconnect() async throws {
        // stop websocket connection
        self.smallWebRTCConnection?.disconnect()
        self.smallWebRTCConnection = nil
        self.handleTracksUpdated()
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
        self.preferredCamId = camId
        self.smallWebRTCConnection?.startOrSwitchLocalVideoCapturer(deviceID: camId.id)
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
        self.sendSignallingMessage(
            message: TrackStatusMessage.init(receiverIndex: SmallWebRTCTransceiverIndex.audio.rawValue, enabled: enable)
        )
    }

    public func enableCam(enable: Bool) async throws {
        Logger.shared.debug("Requested to enable cam: \(enable)")
        if enable {
            self.smallWebRTCConnection?.showVideo()
            self.smallWebRTCConnection?.startOrSwitchLocalVideoCapturer(deviceID: self.preferredCamId?.id)
        } else {
            self.smallWebRTCConnection?.hideVideo()
            self.smallWebRTCConnection?.stopLocalVideoCapturer()
        }
        self.sendSignallingMessage(
            message: TrackStatusMessage.init(receiverIndex: SmallWebRTCTransceiverIndex.video.rawValue, enabled: enable)
        )
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

    private func sendSignallingMessage(message: OutboundSignallingMessageProtocol) {
        let signallingMessage = OutboundSignallingMessage.init(message: message)
        do {
            try self.smallWebRTCConnection?.sendMessage(message: signallingMessage)
        } catch {
            Logger.shared.error("Error sending signalling message: \(error.localizedDescription)")
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
                self.connectedBotParticipant = Participant(
                    id: ParticipantId(id: UUID().uuidString),
                    name: connectedBotParticipant.name,
                    local: connectedBotParticipant.local
                )
                self.delegate?.onParticipantJoined(participant: connectedBotParticipant)
                self.delegate?.onBotConnected(participant: connectedBotParticipant)
            } else if state == .disconnected {
                self.delegate?.onParticipantLeft(participant: connectedBotParticipant)
                self.delegate?.onBotDisconnected(participant: connectedBotParticipant)
                self.delegate?.onDisconnected()
                self.candidateQueue = []
                self.canSendIceCandidates = false
            }
        }
    }

    public func tracks() -> PipecatClientIOS.Tracks? {
        // removing any track since we are going to store it again
        VideoTrackRegistry.clearRegistry()

        let localVideoTrack = self.smallWebRTCConnection?.getLocalVideoTrack()
        // Registering the track so we can retrieve it later inside the VoiceClientVideoView
        if let localVideoTrack = localVideoTrack {
            VideoTrackRegistry.registerTrack(originalTrack: localVideoTrack, mediaTrackId: localVideoTrack.toRtvi().id)
        }

        let botVideoTrack = self.smallWebRTCConnection?.getRemoteVideoTrack()
        // Registering the track so we can retrieve it later inside the VoiceClientVideoView
        if let botVideoTrack = botVideoTrack {
            VideoTrackRegistry.registerTrack(originalTrack: botVideoTrack, mediaTrackId: botVideoTrack.toRtvi().id)
        }

        return Tracks(
            local: ParticipantTracks(
                audio: self.smallWebRTCConnection?.getLocalAudioTrack()?.toRtvi(),
                video: localVideoTrack?.toRtvi(),
                screenAudio: nil,
                screenVideo: nil
            ),
            bot: ParticipantTracks(
                audio: self.smallWebRTCConnection?.getRemoteAudioTrack()?.toRtvi(),
                video: botVideoTrack?.toRtvi(),
                screenAudio: nil,
                screenVideo: nil
            )
        )
    }

    public func setIceConfig(iceConfig: IceConfig?) {
        self.iceConfig = iceConfig
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
        audioManager.availableDevices.first { $0.deviceID == audioManager.preferredAudioDeviceIfAvailable?.deviceID }?
            .toRtvi()
    }
}

// MARK: - SmallWebRTCConnectionDelegate

extension SmallWebRTCTransport: SmallWebRTCConnectionDelegate {

    private func sendIceCandidate(_ iceCandidate: RTCIceCandidate) {
        self.candidateQueue.append(iceCandidate)
        // We are sending all the ice candidates each 200ms
        if self.flushTimeout == nil {
            self.flushTimeout = Timer.scheduledTimer(withTimeInterval: self.flushDelay, repeats: false) {
                [weak self] _ in
                self?.flushIceCandidates()
            }
        }
    }

    private func flushIceCandidates() {
        self.flushTimeout = nil

        guard let connectionParams = self.smallWebRTConnectionParams,
            !self.candidateQueue.isEmpty,
            self.canSendIceCandidates
        else {
            return
        }

        // Drain queue
        // Copying the candidates
        let candidates = candidateQueue
        // Removing the previous ones
        self.candidateQueue.removeAll()

        Logger.shared.info("Will Flush ice candidate \(candidates.count)")

        Task {
            do {
                var request = URLRequest(url: connectionParams.webrtcRequestParams.endpoint)
                request.httpMethod = "PATCH"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                // Adding the custom headers if they have been provided
                for header in connectionParams.webrtcRequestParams.headers {
                    for (key, value) in header {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                }

                let payload =
                    [
                        "pc_id": self.pc_id,
                        "candidates": candidates.map { candidate in
                            [
                                "candidate": candidate.sdp,
                                "sdp_mid": candidate.sdpMid,
                                "sdp_mline_index": candidate.sdpMLineIndex
                            ]
                        }
                    ] as [String: Any]

                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (_, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                    httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299
                else {
                    throw HttpError(message: "Failed to send ICE candidates")
                }

            } catch {
                Logger.shared.error("Failed to send ICE candidate: \(error)")
            }
        }
    }

    func onNewIceCandidate(iceCandidate: RTCIceCandidate) {
        self.sendIceCandidate(iceCandidate)
    }

    func onConnectionStateChanged(state: RTCIceConnectionState) {
        if (state == .failed || state == .closed) && (self._state != .disconnected && self._state != .disconnecting) {
            Task {
                try await self.disconnect()
            }
        }
    }

    func onMsgReceived(msg: PipecatClientIOS.Value) {
        Task {
            let dict = msg.asObject
            if dict["type"] != nil && dict["type"]!!.asString == SIGNALLING_TYPE {
                let jsonData = Data(dict["message"]!!.asString.utf8)
                if let message = try? JSONDecoder().decode(InboundSignallingMessage.self, from: jsonData) {
                    await self.handleSignallingMessage(message)
                }
            } else {
                self.handleMessage(msg)
            }
        }
    }

    func onTracksUpdated() {
        self.handleTracksUpdated()
    }

    private func handleMessage(_ msg: Value) {
        let dict = msg.asObject
        if let typeValue = dict["label"] {
            if typeValue?.asString == "rtvi-ai" {
                Logger.shared.debug("Received RTVI message: \(msg)")
                self.onMessage?(
                    .init(
                        type: dict["type"]??.asString,
                        data: dict["data"]??.asString,
                        id: dict["id"]??.asString
                    )
                )
            }
        }
    }

    private func handleSignallingMessage(_ msg: InboundSignallingMessage) async {
        Logger.shared.info("Handling signalling message: \(msg)")
        do {
            switch msg {
            case .renegotiate:
                try await self.negotiate()
            case .peerLeft:
                try await self.disconnect()
            }
        } catch {
            Logger.shared.error("Error while handling signalling message: \(error.localizedDescription)")
        }
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
