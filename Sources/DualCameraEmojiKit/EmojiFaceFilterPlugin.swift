import CoreGraphics
import CoreMedia
import DualCameraKit
import Foundation
import Observation
import os
import QuartzCore

/// Thread-safe frame processor that detects faces and composites emoji or sticker overlays onto camera frames.
public final class EmojiFaceFilterProcessor: DualCameraFrameProcessing, Sendable {
    private struct State {
        var configuration: EmojiFaceFilterConfiguration
        var revision: UInt64 = 0
        var cachedFrames: [DualCameraSource: CachedProcessedFrame] = [:]
        var onFaceCountChange: (@Sendable (DualCameraSource, Int) -> Void)?
    }

    private struct CachedProcessedFrame {
        let inputBufferID: ObjectIdentifier
        let revision: UInt64
        let outputFrame: PixelBufferWrapper
        let faceCount: Int
    }

    private let stateLock: OSAllocatedUnfairLock<State>
    private let faceDetector: any FaceDetectionProviding
    private let tracker = FaceTrackerActor()
    private let compositor = EmojiBufferCompositor()
    private let clock: @Sendable () -> TimeInterval

    /// Creates an emoji face filter processor.
    public init(
        configuration: EmojiFaceFilterConfiguration = .init(),
        faceDetector: any FaceDetectionProviding = VisionFaceDetector(),
        clock: @escaping @Sendable () -> TimeInterval = { CACurrentMediaTime() },
        onFaceCountChange: (@Sendable (DualCameraSource, Int) -> Void)? = nil
    ) {
        self.stateLock = OSAllocatedUnfairLock(
            initialState: State(
                configuration: configuration,
                onFaceCountChange: onFaceCountChange
            )
        )
        self.faceDetector = faceDetector
        self.clock = clock
    }

    /// Sets or clears the callback invoked whenever the tracked face count for a camera source is evaluated.
    public func setFaceCountChangeHandler(_ handler: (@Sendable (DualCameraSource, Int) -> Void)?) {
        stateLock.withLock { $0.onFaceCountChange = handler }
    }

    /// Returns a snapshot of the active filter configuration.
    public var configuration: EmojiFaceFilterConfiguration {
        stateLock.withLock { $0.configuration }
    }

    /// Updates the active filter configuration and invalidates cached output frames.
    public func updateConfiguration(_ newConfiguration: EmojiFaceFilterConfiguration) {
        stateLock.withLock { state in
            guard state.configuration != newConfiguration else { return }
            state.configuration = newConfiguration
            state.revision &+= 1
            state.cachedFrames.removeAll()
        }
    }

    /// Cycles the emoji assigned to the face containing `point` (normalized `[0, 1]` top-left coordinates).
    @discardableResult
    public func cycleEmoji(
        for source: DualCameraSource,
        atNormalizedTopLeftPoint point: CGPoint
    ) async -> Bool {
        let scaleMultiplier = stateLock.withLock { $0.configuration.scaleMultiplier }
        let didCycle = await tracker.cycleEmoji(
            for: source,
            atNormalizedTopLeftPoint: point,
            scaleMultiplier: scaleMultiplier
        )
        if didCycle {
            stateLock.withLock { state in
                state.revision &+= 1
                state.cachedFrames.removeValue(forKey: source)
            }
        }
        return didCycle
    }

    /// Resets all tracked face states and frame caches.
    public func resetTracking() async {
        await tracker.reset()
        stateLock.withLock { state in
            state.revision &+= 1
            state.cachedFrames.removeAll()
        }
    }

    /// Processes a camera frame, applying face detection and emoji compositing when enabled for `context`.
    public func process(
        frame: PixelBufferWrapper,
        context: DualCameraFrameContext
    ) async -> PixelBufferWrapper {
        let (config, revision, cached, onFaceCountChange) = stateLock.withLock { state in
            (
                state.configuration,
                state.revision,
                state.cachedFrames[context.source],
                state.onFaceCountChange
            )
        }

        guard config.isEnabled, config.targetSources.contains(context.source) else {
            onFaceCountChange?(context.source, 0)
            return frame
        }

        if context.purpose == .photoCaptureRaw && !config.redactRawCaptures {
            return frame
        }

        let inputBufferID = ObjectIdentifier(frame.buffer)
        if let cached, cached.inputBufferID == inputBufferID, cached.revision == revision {
            return cached.outputFrame
        }

        let timestamp = Self.resolveTimestamp(from: frame, fallbackClock: clock)
        let detections = (try? faceDetector.detectFaces(in: frame.buffer)) ?? []
        let overlays = await tracker.updateTracks(
            for: context.source,
            detections: detections,
            timestamp: timestamp,
            configuration: config
        )

        onFaceCountChange?(context.source, overlays.count)

        guard let outputBuffer = compositor.composite(
            overlays: overlays,
            onto: frame.buffer,
            configuration: config
        ) else {
            return frame
        }

        let outputFrame: PixelBufferWrapper
        if outputBuffer === frame.buffer {
            outputFrame = frame
        } else {
            outputFrame = PixelBufferWrapper(
                buffer: outputBuffer,
                presentationTimestamp: frame.presentationTimestamp
            )
        }

        stateLock.withLock { state in
            guard state.revision == revision else { return }
            state.cachedFrames[context.source] = CachedProcessedFrame(
                inputBufferID: inputBufferID,
                revision: revision,
                outputFrame: outputFrame,
                faceCount: overlays.count
            )
        }

        return outputFrame
    }

    private static func resolveTimestamp(
        from frame: PixelBufferWrapper,
        fallbackClock: @Sendable () -> TimeInterval
    ) -> TimeInterval {
        if let presentationTimestamp = frame.presentationTimestamp,
           presentationTimestamp.isNumeric {
            return presentationTimestamp.seconds
        }
        return fallbackClock()
    }
}

/// Observable `@MainActor` controller for managing the Emoji Face Filter plugin in SwiftUI and UIKit apps.
@Observable
@MainActor
public final class EmojiFaceFilterPlugin {
    /// Active configuration for the emoji filter. Mutating this property immediately updates the frame processor.
    public var configuration: EmojiFaceFilterConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            processor.updateConfiguration(configuration)
            if !configuration.isEnabled {
                detectedFaceCounts = [.front: 0, .back: 0]
            }
        }
    }

    /// Number of currently tracked faces per camera source.
    public private(set) var detectedFaceCounts: [DualCameraSource: Int] = [
        .front: 0,
        .back: 0
    ]

    /// Convenience accessor for enabling or disabling the filter.
    public var isEnabled: Bool {
        get { configuration.isEnabled }
        set { configuration.isEnabled = newValue }
    }

    /// Underlying thread-safe frame processor to pass to `DualCameraController`.
    @ObservationIgnored
    public nonisolated let processor: EmojiFaceFilterProcessor

    /// Creates an observable emoji face filter plugin.
    public init(
        configuration: EmojiFaceFilterConfiguration = .init(),
        faceDetector: any FaceDetectionProviding = VisionFaceDetector(),
        clock: @escaping @Sendable () -> TimeInterval = { CACurrentMediaTime() }
    ) {
        self.configuration = configuration
        let processor = EmojiFaceFilterProcessor(
            configuration: configuration,
            faceDetector: faceDetector,
            clock: clock
        )
        self.processor = processor
        processor.setFaceCountChangeHandler { [weak self] source, count in
            Task { @MainActor in
                guard let self else { return }
                if self.detectedFaceCounts[source] != count {
                    self.detectedFaceCounts[source] = count
                }
            }
        }
    }

    /// Toggles `isEnabled` on or off.
    public func toggle() {
        configuration.isEnabled.toggle()
    }

    /// Sets the assignment strategy to `.single(emoji)` and enables the filter.
    public func selectEmoji(_ emoji: String) {
        configuration.assignment = .single(emoji)
        configuration.isEnabled = true
    }

    /// Sets the assignment strategy to `.palette(emojis)` and enables the filter.
    public func selectPalette(_ emojis: [String] = EmojiAssignmentStrategy.defaultPalette) {
        configuration.assignment = .palette(emojis)
        configuration.isEnabled = true
    }

    /// Cycles the emoji on a tracked face at `normalizedTopLeftPoint` (in `[0, 1]` coordinates).
    /// If the current assignment is `.single`, switches to `.palette(defaultPalette)` first.
    @discardableResult
    public func cycleEmojiOnFace(
        for source: DualCameraSource = .front,
        atNormalizedTopLeftPoint point: CGPoint,
        palette: [String] = EmojiAssignmentStrategy.defaultPalette
    ) async -> Bool {
        if case .single(let currentEmoji) = configuration.assignment {
            var orderedPalette = palette.filter { $0 != currentEmoji }
            orderedPalette.insert(currentEmoji, at: 0)
            configuration.assignment = .palette(orderedPalette)
        }
        return await processor.cycleEmoji(for: source, atNormalizedTopLeftPoint: point)
    }
}
