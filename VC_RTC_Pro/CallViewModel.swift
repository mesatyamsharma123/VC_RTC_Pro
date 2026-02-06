import SwiftUI
import WebRTC
import AVFoundation
import Combine

class CallViewModel: ObservableObject {
    private let signalClient: SignalingClient
    private let webRTCClient: WebRTCClient
    
    
    @Published var remoteVideoTrack: RTCVideoTrack?
    @Published var connectionState: String = "Disconnected"
    @Published var isMuted: Bool = false
    @Published var isSpeakerOn: Bool = false
    @Published var isConnected: Bool = false
    
    
//    var localRenderer: RTCVideoRenderer?
//    private var isLocalVideoStarted = false
    
    
      /*
       Initialization ensures that all dependencies, delegates, and system configurations are ready before any asynchronous events occur, preventing race conditions and lost callbacks.
       */
    
    init() {
        self.signalClient = SignalingClient()
        self.webRTCClient = WebRTCClient()
        
        self.signalClient.delegate = self
        self.webRTCClient.delegate = self
        configureAudioSession()
    }
    
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Failed to configure AudioSession: \(error)")
        }
    }
    
    func connect() {
        signalClient.connect()
        self.isConnected = true
    }
    
    func startLocalVideo(renderer: RTCVideoRenderer) {
//        self.localRenderer = renderer
        webRTCClient.startCaptureLocalVideo(renderer: renderer)
    }
    
    func startCall() {
        connectionState = "Calling..."
        webRTCClient.offer { [weak self] sdp in
            self?.signalClient.sendSdp(sdp: sdp, type: "offer")
        }
    }
    func endCall() {
        
        webRTCClient.stopCapture()
        signalClient.disconnect()
        DispatchQueue.main.async {
            self.remoteVideoTrack = nil
            self.connectionState = "Disconnected"
//            self.isLocalVideoStarted = false
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
        webRTCClient.muteAudio(isMuted)
    }
    
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
        } catch {
            print("Speaker toggle failed: \(error)")
        }
    }
    
    
    func checkPermissions() {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if videoStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { print("Camera access granted") }
            }
        }
        
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
                self?.signalClient.sendSdp(sdp: answerSdp, type: "answer")
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


extension CallViewModel: WebRTCClientDelegate {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
        let candidateDict: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": candidate.sdpMLineIndex
        ]
        signalClient.sendIceCandiadte(candidate: candidateDict)
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack track: RTCVideoTrack) {
        print("RECEIVED REMOTE VIDEO TRACK")
        
      
        DispatchQueue.main.async {
            self.remoteVideoTrack = track
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected: self.connectionState = "Connected"
            case .disconnected, .failed: self.connectionState = "Ended"
            default: break
            }
        }
    }
}
