import SwiftUI
import WebRTC

// Helper: Wrapper for WebRTC Video View
struct VideoView: UIViewRepresentable {
    let track: RTCVideoTrack?
    var onAppear: ((RTCVideoRenderer) -> Void)? = nil // ✅ Added this back
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        return view
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // Case 1: Remote Video (Track is passed in)
        if let track = track {
            track.add(uiView)
        }
        
        // Case 2: Local Video (We need to send the view back to the ViewModel)
        onAppear?(uiView)
    }
}


struct ContentView: View {
    @StateObject var viewModel = CallViewModel()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // 1. Remote Video (Full Screen)
            if let remoteTrack = viewModel.remoteVideoTrack {
                VideoView(track: remoteTrack)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text(viewModel.connectionState)
                    .foregroundColor(.white)
                    .font(.headline)
            }
            
            // 2. Local Video (Picture in Picture)
            VStack {
                HStack {
                    Spacer()
                    VideoView(track: nil, onAppear: { renderer in
                        viewModel.startLocalVideo(renderer: renderer)
                    })
                    .frame(width: 100, height: 150)
                    .cornerRadius(10)
                    .shadow(radius: 10)
                    .padding()
                }
                Spacer()
                
                // 3. Controls
                HStack(spacing: 40) {
                    
                    // Mute
                    Button(action: { viewModel.toggleMute() }) {
                        Image(systemName: viewModel.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 24))
                            .padding()
                            .background(viewModel.isMuted ? Color.red : Color.gray)
                            .clipShape(Circle())
                    }
                    
                    // Start Call
                    Button(action: { viewModel.startCall() }) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 30))
                            .padding()
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    
                    // Speaker
                    Button(action: { viewModel.toggleSpeaker() }) {
                        Image(systemName: viewModel.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill")
                            .font(.system(size: 24))
                            .padding()
                            .background(viewModel.isSpeakerOn ? Color.blue : Color.gray)
                            .clipShape(Circle())
                    }
                }
                .foregroundColor(.white)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // FIXED: Call function via viewModel
            viewModel.checkPermissions()
            viewModel.connect()
        }
    }
}
