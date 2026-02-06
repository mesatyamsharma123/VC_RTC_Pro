import Foundation
import WebRTC
import AVFoundation

protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate)
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState)
    func webRTCClient(_ client: WebRTCClient, didReceiveRemoteVideoTrack track: RTCVideoTrack)
}

class WebRTCClient: NSObject {
    weak var delegate: WebRTCClientDelegate?
    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection!
    private let mediaConstrains = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                   kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue]
    
    private var localVideoTrack: RTCVideoTrack?
   
    private var capturer: RTCCameraVideoCapturer?
    
    override init() {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
        super.init()
        setupPeerConnection()
    }
    
    private func setupPeerConnection() {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        self.peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
    }
    
   
    // MARK: - Media Setup
        func startCaptureLocalVideo(renderer: RTCVideoRenderer) {
            // 1. SAFETY CHECK: If we already have a capturer, just attach the new view and EXIT.
            if self.capturer != nil {
                print("⚠️ Camera is already running. Just updating the view.")
                self.localVideoTrack?.add(renderer)
                return
            }
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return }
            
            let videoSource = factory.videoSource()
            
            // 2. Initialize Capturer (Store in class property)
            self.capturer = RTCCameraVideoCapturer(delegate: videoSource)
            
            localVideoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
            localVideoTrack?.add(renderer)
            
            peerConnection.add(localVideoTrack!, streamIds: ["stream0"])
            
            // 3. Start capturing
            let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
            
            // Use a medium quality format (640x480) to be safe and save bandwidth
            // High 4K resolutions can sometimes cause the error -17281 too.
            let targetWidth = 640
            let targetHeight = 480
            
            var selectedFormat: AVCaptureDevice.Format? = nil
            var currentDiff = Int.max
            
            for format in formats {
                let dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let diff = abs(Int(dimension.width) - targetWidth) + abs(Int(dimension.height) - targetHeight)
                if diff < currentDiff {
                    selectedFormat = format
                    currentDiff = diff
                }
            }
            
            if let format = selectedFormat {
                let fps = 30 // Force 30 FPS
                print("✅ Starting Camera: \(CMVideoFormatDescriptionGetDimensions(format.formatDescription)) at \(fps)fps")
                self.capturer?.startCapture(with: device, format: format, fps: fps)
            } else {
                print("❌ Could not find a suitable camera format.")
            }

            // Add Audio
            let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
            let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
            peerConnection.add(audioTrack, streamIds: ["stream0"])
        }
    // MARK: - Signaling
    func offer(completion: @escaping (String) -> Void) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: mediaConstrains, optionalConstraints: nil)
        peerConnection.offer(for: constraints) { [weak self] (sdp, error) in
            guard let self = self, let sdp = sdp else { return }
            self.peerConnection.setLocalDescription(sdp) { _ in
                completion(sdp.sdp)
            }
        }
    }
    
    func answer(completion: @escaping (String) -> Void) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: mediaConstrains, optionalConstraints: nil)
        peerConnection.answer(for: constraints) { [weak self] (sdp, error) in
            guard let self = self, let sdp = sdp else { return }
            self.peerConnection.setLocalDescription(sdp) { _ in
                completion(sdp.sdp)
            }
        }
    }
    
    func set(remoteSdp: String, type: String) {
        let sdpType: RTCSdpType = type == "offer" ? .offer : .answer
        let sdp = RTCSessionDescription(type: sdpType, sdp: remoteSdp)
        
        peerConnection.setRemoteDescription(sdp) { error in
            if let error = error {
                print("Error setting remote description: \(error)")
            }
        }
    }
    
    func set(remoteCandidate: RTCIceCandidate) {
        peerConnection.add(remoteCandidate)
    }
    
    func muteAudio(_ isMuted: Bool) {
        if let sender = peerConnection.senders.first(where: { $0.track?.kind == "audio" }) {
            sender.track?.isEnabled = !isMuted
        }
    }
    
    func stopCapture() {
        self.capturer?.stopCapture()
        self.capturer = nil
        self.localVideoTrack = nil
        self.peerConnection.close()
    }
}


extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        delegate?.webRTCClient(self, didDiscoverLocalCandidate: candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let track = stream.videoTracks.first {
            delegate?.webRTCClient(self, didReceiveRemoteVideoTrack: track)
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if let track = transceiver.receiver.track as? RTCVideoTrack {
            print("✅ Found Remote Video Track via Transceiver!")
            delegate?.webRTCClient(self, didReceiveRemoteVideoTrack: track)
        }
    }
    

    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        delegate?.webRTCClient(self, didChangeConnectionState: newState)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
}
