import SwiftUI
import WebRTC
import AVFoundation
import Combine

class CallViewModel: ObservableObject {
    private let signalClient: SignalingClient
    private let webRTCClient: WebRTCClient
    
    // UI State
    @Published var remoteVideoTrack: RTCVideoTrack?
    @Published var connectionState: String = "Disconnected"
    @Published var isMuted: Bool = false
    @Published var isSpeakerOn: Bool = false
    
    // Local Video Renderer (kept to prevent deallocation)
    var localRenderer: RTCVideoRenderer?
    
    init() {
        self.signalClient = SignalingClient()
        self.webRTCClient = WebRTCClient()
        
        self.signalClient.delegate = self
        self.webRTCClient.delegate = self
        
        // CRITICAL FIX: Setup Audio Session for VoIP immediately
        configureAudioSession()
    }
    
    // MARK: - Audio Configuration
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Set category to PlayAndRecord (required for VoIP)
            // Options allow Bluetooth headsets and default to speaker if preferred
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Failed to configure AudioSession: \(error)")
        }
    }
    
    // MARK: - Connection
    func connect() {
        signalClient.connect()
    }
    
    func startLocalVideo(renderer: RTCVideoRenderer) {
        self.localRenderer = renderer
        webRTCClient.startCaptureLocalVideo(renderer: renderer)
    }
    
    // MARK: - User Actions
    func startCall() {
        connectionState = "Calling..."
        webRTCClient.offer { [weak self] sdp in
            self?.signalClient.send(sdp: sdp, type: "offer")
        }
    }
    func endCall() {
        connectionState = "Disconnected"
        self.signalClient.disconnect()
        self.signalClient.isConnected = false
    }
    
    func toggleMute() {
        isMuted.toggle()
        webRTCClient.muteAudio(isMuted)
    }
    
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        let session = AVAudioSession.sharedInstance()
        do {
            // Force output to Speaker or Receiver (Earpiece)
            try session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
        } catch {
            print("Speaker toggle failed: \(error)")
        }
    }
    
    // MARK: - Permissions
    func checkPermissions() {
        // 1. Check Camera
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if videoStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { print("Camera access granted") }
            }
        }
        
        // 2. Check Microphone
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted { print("Mic access granted") }
            }
        }
    }
}

// MARK: - Signaling Delegate (Socket -> WebRTC)
extension CallViewModel: SignalingClientDelegate {
    func signalingClient(_ client: SignalingClient, didReceiveRemoteSdp sdp: String, type: String) {
        webRTCClient.set(remoteSdp: sdp, type: type)
        
        if type == "offer" {
            // Automatically answer incoming calls
            DispatchQueue.main.async { self.connectionState = "Incoming Call..." }
            
            webRTCClient.answer { [weak self] answerSdp in
                self?.signalClient.send(sdp: answerSdp, type: "answer")
            }
        }
    }
    
    func signalingClient(_ client: SignalingClient, didReceiveCandidate candidate: [String : Any]) {
        guard let sdp = candidate["candidate"] as? String,
              let sdpMid = candidate["sdpMid"] as? String,
              let sdpMLineIndex = candidate["sdpMLineIndex"] as? Int32 else { return }
        
        let iceCandidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        webRTCClient.set(remoteCandidate: iceCandidate)
    }
}

// MARK: - WebRTC Delegate (WebRTC -> UI/Socket)
extension CallViewModel: WebRTCClientDelegate {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
        let candidateDict: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": candidate.sdpMLineIndex
        ]
        signalClient.send(candidate: candidateDict)
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack track: RTCVideoTrack) {
        print("✅ RECEIVED REMOTE VIDEO TRACK")
        
      
        DispatchQueue.main.async {
            self.remoteVideoTrack = track
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        // Update Connection Status Label
        DispatchQueue.main.async {
            switch state {
            case .connected: self.connectionState = "Connected"
            case .disconnected, .failed: self.connectionState = "Ended"
            default: break
            }
        }
    }
}
