import Foundation
import Combine

protocol SignalingClientDelegate: AnyObject {
    func signalingClient(_ client: SignalingClient, didReceiveRemoteSdp sdp: String, type: String)
    func signalingClient(_ client: SignalingClient, didReceiveCandidate candidate: [String: Any])
}

class SignalingClient: NSObject ,ObservableObject {
    static let shared = SignalingClient()
    weak var delegate: SignalingClientDelegate?
    private var webSocket: URLSessionWebSocketTask?

    private let serverUrl = URL(string: "ws://c8e62401610c.ngrok-free.app")!
    @Published var isConnected: Bool = false

    func connect() {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocket = session.webSocketTask(with: serverUrl)
        webSocket?.resume()
        print("Connecting to WebSocket...")
        listen()
    }
    
    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
    }

    func send(sdp: String, type: String) {
 
        let message = ["type": type, "sdp": sdp]
        sendData(message)
    }
    
    func send(candidate: [String: Any]) {
        // FIXED: Explicitly tell Swift this is [String: Any]
        let message: [String: Any] = ["type": "candidate", "candidate": candidate]
        sendData(message)
    }
    
    private func sendData(_ data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        
        webSocket?.send(.string(jsonString)) { error in
            if let error = error { print("WebSocket Send Error: \(error)") }
        }
    }
    

    private func listen() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleIncomingMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self?.handleIncomingMessage(text) }
                @unknown default: break
                }
                self?.listen() // Keep listening
            case .failure(let error):
                print("WebSocket Receive Error: \(error)")
            }
        }
    }
    
    private func handleIncomingMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        if type == "offer" || type == "answer" {
            if let sdp = json["sdp"] as? String {
                delegate?.signalingClient(self, didReceiveRemoteSdp: sdp, type: type)
            }
        } else if type == "candidate" {
            if let candidateData = json["candidate"] as? [String: Any] {
                delegate?.signalingClient(self, didReceiveCandidate: candidateData)
            }
        }
    }
}

extension SignalingClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket Connected")
        isConnected = true
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { print("WebSocket Error: \(error)") }
        isConnected = false
    }
}
