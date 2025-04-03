
import XCTest
@testable import DualCameraKit

@MainActor
final class DualCameraViewModelTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func test_init_withDefaultParams_setsDefaultValues() async {
        let mockController = MockDualCameraController()
        CurrentDualCameraEnvironment.dualCameraController = mockController
        
        let viewModel = DualCameraViewModel()
        
        XCTAssertEqual(viewModel.viewState, .loading)
        XCTAssertEqual(viewModel.configuration.layout, .piP(miniCamera: .front, miniCameraPosition: .bottomTrailing))
        XCTAssertEqual(viewModel.videoRecorderType, .cpuBased(.init(photoCaptureMode: .fullScreen)))
        XCTAssertIdentical(viewModel.controller as? MockDualCameraController, mockController)
    }
    
    func test_init_withCustomParams_setsCustomValues() {
        let mockController = MockDualCameraController()
        let customLayout: DualCameraLayout = .sideBySide
        let customRecorderMode: DualCameraVideoRecordingMode = .replayKit()
        
        let viewModel = DualCameraViewModel(
            dualCameraController: mockController,
            layout: customLayout,
            videoRecorderMode: customRecorderMode
        )
        
        // Then
        XCTAssertEqual(viewModel.configuration.layout, customLayout)
        XCTAssertEqual(viewModel.videoRecorderType, customRecorderMode)
    }
    
    // MARK: - Lifecycle Tests
    
    func test_onAppear_startsSession() async {
        let mockController = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: mockController)
        
        viewModel.onAppear(containerSize: CGSize(width: 390, height: 844))
        
        // Need to wait for the async Task to complete
        await Task.yield()
        
        // Then
        XCTAssertTrue(mockController.sessionStarted)
        XCTAssertEqual(viewModel.configuration.containerSize, CGSize(width: 390, height: 844))
        XCTAssertEqual(viewModel.viewState, .ready)
    }
    
    func test_onAppear_handlesError() async {
        let mockController = MockDualCameraController()
        mockController.shouldFailStartSession = true
        let viewModel = DualCameraViewModel(dualCameraController: mockController)
        
        viewModel.onAppear(containerSize: CGSize(width: 390, height: 844))
        
        // Need to wait for the async Task to complete
        await Task.yield()
        
        XCTAssertEqual(viewModel.viewState, .error(DualCameraError.unknownError))
        XCTAssertNotNil(viewModel.alert)
    }
    
    func test_onDisappear_stopsSession() async {
        let mockController = MockDualCameraController()
        let viewModel = DualCameraViewModel(dualCameraController: mockController)
        
        viewModel.onAppear(containerSize: CGSize(width: 390, height: 844))
        await Task.yield()
        
        viewModel.onDisappear()
        
        XCTAssertTrue(mockController.sessionStopped)
    }
   
}

// MARK: - Test Helpers

class MockDualCameraController: DualCameraControlling {
    var sessionStarted = false
    var sessionStopped = false
    var videoRecordingStarted = false
    var videoRecordingStopped = false
    var shouldFailStartSession = false
    var shouldFailCaptureScreen = false
    
    var mockCapturedImage = UIImage()
    var mockVideoOutputURL = URL(string: "file:///tmp/test.mp4")!
    
    var frontCameraStream: AsyncStream<PixelBufferWrapper> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    
    var backCameraStream: AsyncStream<PixelBufferWrapper> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    
    func getRenderer(for source: DualCameraSource) -> CameraRenderer {
        MockCameraRenderer()
    }
    
    func startSession() async throws {
        if shouldFailStartSession {
            throw DualCameraError.unknownError
        }
        sessionStarted = true
    }
    
    func stopSession() {
        sessionStopped = true
    }
    
    var photoCapturer: any DualCameraPhotoCapturing {
        MockPhotoCapturer(mockImage: mockCapturedImage, shouldFail: shouldFailCaptureScreen)
    }
    
    func captureRawPhotos() async throws -> (front: UIImage, back: UIImage) {
        if shouldFailCaptureScreen {
            throw DualCameraError.captureFailure(.noFrameAvailable)
        }
        return (front: mockCapturedImage, back: mockCapturedImage)
    }
    
    func captureCurrentScreen(mode: DualCameraPhotoCaptureMode) async throws -> UIImage {
        if shouldFailCaptureScreen {
            throw DualCameraError.captureFailure(.noFrameAvailable)
        }
        return mockCapturedImage
    }
    
    var videoRecorder: (any DualCameraVideoRecording)? = nil
    
    func setVideoRecorder(_ recorder: any DualCameraVideoRecording) async throws {
        videoRecorder = recorder
    }
    
    func startVideoRecording(mode: DualCameraVideoRecordingMode) async throws {
        videoRecordingStarted = true
    }
    
    func stopVideoRecording() async throws -> URL {
        videoRecordingStopped = true
        return mockVideoOutputURL
    }
}

class MockCameraRenderer: CameraRenderer {
    func update(with buffer: CVPixelBuffer) {
        // No-op for tests
    }
    
    func captureCurrentFrame() async throws -> UIImage {
        return UIImage()
    }
}

class MockPhotoCapturer: DualCameraPhotoCapturing {
    private let mockImage: UIImage
    private let shouldFail: Bool
    
    init(mockImage: UIImage, shouldFail: Bool = false) {
        self.mockImage = mockImage
        self.shouldFail = shouldFail
    }
    
    func captureRawPhotos(frontRenderer: CameraRenderer, backRenderer: CameraRenderer) async throws -> (front: UIImage, back: UIImage) {
        if shouldFail {
            throw DualCameraError.captureFailure(.noFrameAvailable)
        }
        return (front: mockImage, back: mockImage)
    }
    
    func captureCurrentScreen(mode: DualCameraPhotoCaptureMode) async throws -> UIImage {
        if shouldFail {
            throw DualCameraError.captureFailure(.noFrameAvailable)
        }
        return mockImage
    }
}
