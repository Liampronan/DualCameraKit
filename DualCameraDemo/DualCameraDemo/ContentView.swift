import DualCameraKit
import SwiftUI
import Photos

struct ContentView: View {
    @State private var layout = CameraLayout.fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
    @State private var containerSize: CGSize = .zero
    @State private var demoImage: UIImage?
    @State private var isCapturing = false
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var permissionDenied = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    private let dualCameraController = DualCameraController()
    
    var body: some View {
        GeometryReader { geoProxy in
            VStack {
                DualCameraScreen(
                    controller: dualCameraController,
                    layout: .fullScreenWithMini(miniCamera: .front, miniCameraPosition: .bottomTrailing)
                )
                .overlay(recordingIndicator(), alignment: .top)
                .overlay(controlButtons(), alignment: .bottom)
            }
            .onChange(of: geoProxy.size, initial: true) { _, newSize in
                containerSize = newSize
            }
            .onAppear {
                containerSize = geoProxy.size
                
                // Start camera session when view appears
                Task {
                    try? await dualCameraController.startSession()
                }
            }
            .onDisappear {
                // Stop recording if active
                if isRecording {
                    stopRecording()
                }
                
                // Stop camera session when view disappears
                dualCameraController.stopSession()
                
                // Clean up timer if needed
                recordingTimer?.invalidate()
                recordingTimer = nil
            }
            
            // Show the captured image if any
            .overlay {
                if let demoImage {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        Image(uiImage: demoImage)
                            .ignoresSafeArea(.all)
                        
                        VStack {
                            Spacer()
                            Button("Dismiss") {
                                self.demoImage = nil
                            }
                            .padding()
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                            .foregroundColor(.white)
                            .padding(.bottom, 20)
                        }
                    }
                    .ignoresSafeArea(.all)
                    .transition(.opacity)
                }
            }
            .overlay {
                if isCapturing {
                    // Flash effect for camera capture
                    Color.white
                        .ignoresSafeArea()
                        .opacity(0.3)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isCapturing)
            .animation(.easeInOut(duration: 0.3), value: demoImage != nil)
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("Video Recording"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    @ViewBuilder
    private func controlButtons() -> some View {
        HStack(spacing: 30) {
            // Photo capture button
            Button(action: takePhoto) {
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .padding()
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .disabled(isCapturing || isRecording)
            
            // Video recording button
            Button(action: isRecording ? stopRecording : startRecording) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .font(.largeTitle)
                    .foregroundColor(isRecording ? .red : .white)
                    .padding()
                    .background(
                        Circle()
                            .fill(isRecording ? Color.white.opacity(0.8) : Color.black.opacity(0.5))
                    )
            }
            .disabled(isCapturing)
        }
        .padding(.bottom, 30)
    }
    
    @ViewBuilder
    private func recordingIndicator() -> some View {
        if isRecording {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(0.8)
                
                Text(formatDuration(recordingDuration))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
            )
            .padding(.top, 40)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    @MainActor
    private func takePhoto() {
        Task {
            guard !isCapturing else { return }
            
            isCapturing = true
            defer { isCapturing = false }
            
            do {
                // Flash effect
                withAnimation {
                    isCapturing = true
                }
                
                // Capture screen
                demoImage = try await dualCameraController.captureCurrentScreen()
                print("Captured image: \(containerSize)")
                
                // End flash effect
                withAnimation {
                    isCapturing = false
                }
            } catch {
                print("Error capturing photo: \(error)")
                
                // End flash effect
                withAnimation {
                    isCapturing = false
                }
            }
        }
    }
    
    @MainActor
    private func startRecording() {
        // First check permissions
        checkPhotoLibraryPermission { hasPermission in
            guard hasPermission else {
                permissionDenied = true
                alertMessage = "Photo library access is required to save videos."
                showingAlert = true
                return
            }
            
            Task {
                do {
                    // Create a temporary file URL in the documents directory
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileName = "dualcamera_recording_\(Date().timeIntervalSince1970).mp4"
                    let fileURL = tempDir.appendingPathComponent(fileName)
                    
                    // Start recording
                    try await dualCameraController.startVideoRecording(
                        mode: .screenCapture(.fullScreen),
                        outputURL: fileURL
                    )
                    
                    // Update UI state
                    withAnimation {
                        isRecording = true
                        recordingDuration = 0
                    }
                    
                    // Start a timer to update recording duration
                    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        DispatchQueue.main.async {
                            recordingDuration += 1
                        }
                    }
                    
                } catch {
                    print("Error starting recording: \(error.localizedDescription)")
                    alertMessage = "Failed to start recording: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
    
    @MainActor
    private func stopRecording() {
        // Stop the timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Stop recording
        Task {
            do {
                // Stop recording and get output URL
                let outputURL = try await dualCameraController.stopVideoRecording()
                
                // Reset UI state
                withAnimation {
                    isRecording = false
                }
                
                // Save video to photo library
                saveVideoToPhotoLibrary(outputURL)
                
            } catch {
                print("Error stopping recording: \(error.localizedDescription)")
                alertMessage = "Failed to stop recording: \(error.localizedDescription)"
                showingAlert = true
                
                // Reset UI state even if there was an error
                withAnimation {
                    isRecording = false
                }
            }
        }
    }
    
    private func checkPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func saveVideoToPhotoLibrary(_ videoURL: URL) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    // Show success alert
                    alertMessage = "Video saved to photo library"
                    showingAlert = true
                    
                    // Clean up the temp file
                    try? FileManager.default.removeItem(at: videoURL)
                } else if let error = error {
                    // Show error alert
                    alertMessage = "Failed to save video: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
}
