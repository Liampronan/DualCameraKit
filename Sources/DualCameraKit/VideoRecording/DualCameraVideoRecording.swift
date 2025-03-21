import Foundation

public protocol DualCameraVideoRecording: Actor {
    func startVideoRecording() async throws
    func stopVideoRecording() async throws -> URL
    
    var isCurrentlyRecording: Bool { get }
}
