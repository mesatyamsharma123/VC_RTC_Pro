import SwiftUI
import WebRTC
import Combine


struct VideoView: UIViewRepresentable {
    let track: RTCVideoTrack?
    var onAppear: ((RTCVideoRenderer) -> Void)? = nil 
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        return view
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // Remote Video
        if let track = track {
            track.add(uiView)
        }
        
        //Local Video
        onAppear?(uiView)
    }
}


struct ContentView: View {
    @StateObject var viewModel = CallViewModel()
    @ObservedObject var signaling = SignalingClient.shared
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // 1. Remote Video
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
                
                
                HStack(spacing: 40) {
                    
                    Button(action:{
                        viewModel.toggleMute()
                    }) {
                        Image(systemName: viewModel.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 24))
                            .padding()
                            .background(viewModel.isMuted ? Color.red : Color.gray)
                            .clipShape(Circle())
                    }
                    
                    if viewModel.isConnected {
                        Button {
                            viewModel.startCall()
                            viewModel.isConnected = false
                        }label :{
                            Image(systemName: "phone.fill")
                                .font(.system(size: 30))
                                .padding()
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                        
                    }
                    else{
                        Button {
                            viewModel.endCall()
                            viewModel.isConnected = true
                        }label :{
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 30))
                                .padding()
                                .background(Color.red)
                                .clipShape(Circle())
                            
                        }
                        
                    }
                    
                    Button(action: {
                        viewModel.toggleSpeaker()
                    }) {
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
            viewModel.checkPermissions()
            viewModel.connect()
        }
    }
}
