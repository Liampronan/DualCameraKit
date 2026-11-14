import CoreGraphics
import DualCameraKit
import Foundation

/// A smoothed, identity-tracked face overlay ready for compositing.
public struct TrackedFaceOverlay: Sendable, Equatable, Identifiable {
    /// Stable identifier assigned while a face remains tracked across frames.
    public let trackID: Int
    /// Smoothed normalized bounding box (`[0, 1]`, origin at bottom-left).
    public let normalizedBoundingBox: CGRect
    /// Smoothed head roll angle in radians.
    public let rollAngleRadians: CGFloat
    /// Per-track offset incremented when the user taps a face to cycle its assigned emoji.
    public let paletteOffset: Int

    public var id: Int { trackID }

    /// Creates a tracked face overlay.
    public init(
        trackID: Int,
        normalizedBoundingBox: CGRect,
        rollAngleRadians: CGFloat,
        paletteOffset: Int = 0
    ) {
        self.trackID = trackID
        self.normalizedBoundingBox = normalizedBoundingBox
        self.rollAngleRadians = rollAngleRadians
        self.paletteOffset = paletteOffset
    }
}

/// Maintains temporally smoothed face tracks per camera source across consecutive video frames.
actor FaceTrackerActor {
    private struct ActiveTrack {
        let trackID: Int
        var boundingBox: CGRect
        var rollAngleRadians: CGFloat
        var lastSeenTimestamp: TimeInterval
        var paletteOffset: Int
    }

    private var tracksBySource: [DualCameraSource: [ActiveTrack]] = [:]
    private var nextTrackID: Int = 0

    /// Updates active tracks for `source` with `detections` observed at `timestamp`.
    func updateTracks(
        for source: DualCameraSource,
        detections: [DetectedFace],
        timestamp: TimeInterval,
        configuration: EmojiFaceFilterConfiguration
    ) -> [TrackedFaceOverlay] {
        let currentTracks = tracksBySource[source] ?? []
        let latestSeenTimestamp = currentTracks.map(\.lastSeenTimestamp).max() ?? timestamp
        let referenceTimestamp = max(timestamp, latestSeenTimestamp)
        let existingTracks = currentTracks.filter { track in
            let age = referenceTimestamp - track.lastSeenTimestamp
            return age >= 0 && age <= configuration.trackGracePeriod
        }
        var matchedTrackIndices = Set<Int>()
        var updatedTracks: [ActiveTrack] = []

        // Sort detections largest-first so primary subjects claim tracks deterministically.
        let sortedDetections = detections.sorted {
            ($0.boundingBox.width * $0.boundingBox.height) > ($1.boundingBox.width * $1.boundingBox.height)
        }
        let limitedDetections: ArraySlice<DetectedFace>
        if let maxFaces = configuration.maxFaces, maxFaces >= 0 {
            limitedDetections = sortedDetections.prefix(maxFaces)
        } else {
            limitedDetections = sortedDetections[...]
        }

        let alpha = configuration.smoothingFactor

        for detection in limitedDetections {
            if let matchIndex = bestMatchIndex(
                for: detection.boundingBox,
                in: existingTracks,
                excluding: matchedTrackIndices
            ) {
                matchedTrackIndices.insert(matchIndex)
                var track = existingTracks[matchIndex]
                track.boundingBox = Self.interpolateRect(
                    from: track.boundingBox,
                    to: detection.boundingBox,
                    alpha: alpha
                )
                if let detectedRoll = detection.rollAngleRadians {
                    track.rollAngleRadians = Self.interpolateAngle(
                        from: track.rollAngleRadians,
                        to: detectedRoll,
                        alpha: alpha
                    )
                }
                track.lastSeenTimestamp = timestamp
                updatedTracks.append(track)
            } else {
                let assignedID = nextTrackID
                nextTrackID += 1
                let newTrack = ActiveTrack(
                    trackID: assignedID,
                    boundingBox: detection.boundingBox,
                    rollAngleRadians: detection.rollAngleRadians ?? 0,
                    lastSeenTimestamp: timestamp,
                    paletteOffset: 0
                )
                updatedTracks.append(newTrack)
            }
        }

        // Retain unmatched tracks that are still within the dropout grace window.
        for (index, track) in existingTracks.enumerated() where !matchedTrackIndices.contains(index) {
            let age = timestamp - track.lastSeenTimestamp
            if age >= 0 && age <= configuration.trackGracePeriod {
                updatedTracks.append(track)
            }
        }

        if let maxFaces = configuration.maxFaces, maxFaces >= 0, updatedTracks.count > maxFaces {
            updatedTracks = Array(updatedTracks.prefix(maxFaces))
        }

        if timestamp >= latestSeenTimestamp {
            tracksBySource[source] = updatedTracks
        } else {
            tracksBySource[source] = existingTracks
        }

        return updatedTracks.map { track in
            TrackedFaceOverlay(
                trackID: track.trackID,
                normalizedBoundingBox: track.boundingBox,
                rollAngleRadians: configuration.tracksHeadRoll ? track.rollAngleRadians : 0,
                paletteOffset: track.paletteOffset
            )
        }
    }

    /// Increments the palette offset of the tracked face containing `normalizedTopLeftPoint` (in `[0, 1]` UI space),
    /// optionally rebasing the track's offset so its rendered palette index is `0` before advancing.
    func cycleEmoji(
        for source: DualCameraSource,
        atNormalizedTopLeftPoint point: CGPoint,
        scaleMultiplier: CGFloat,
        rebaseToPaletteCount paletteCount: Int? = nil
    ) -> Bool {
        guard var tracks = tracksBySource[source], !tracks.isEmpty else {
            return false
        }

        // Convert UI top-left normalized coordinates to Vision bottom-left normalized coordinates.
        let visionPoint = CGPoint(x: point.x, y: 1.0 - point.y)

        if let hitIndex = tracks.firstIndex(where: { track in
            let expanded = Self.expandedRect(track.boundingBox, scaleMultiplier: scaleMultiplier)
            return expanded.contains(visionPoint)
        }) {
            if let paletteCount, paletteCount > 0 {
                let trackID = tracks[hitIndex].trackID
                let baseMod = ((trackID % paletteCount) + paletteCount) % paletteCount
                tracks[hitIndex].paletteOffset = (paletteCount - baseMod) % paletteCount
            }
            tracks[hitIndex].paletteOffset &+= 1
            tracksBySource[source] = tracks
            return true
        }

        return false
    }

    /// Clears all active face tracks for all sources.
    func reset() {
        tracksBySource.removeAll()
    }

    // MARK: - Geometry Helpers

    private func bestMatchIndex(
        for target: CGRect,
        in tracks: [ActiveTrack],
        excluding excluded: Set<Int>
    ) -> Int? {
        var bestIndex: Int?
        var bestScore: CGFloat = -1

        for (index, track) in tracks.enumerated() where !excluded.contains(index) {
            let iou = Self.intersectionOverUnion(target, track.boundingBox)
            let distance = Self.centerDistance(target, track.boundingBox)
            let maxDimension = max(
                target.width,
                target.height,
                track.boundingBox.width,
                track.boundingBox.height,
                0.05
            )

            // Match if boxes overlap or if their centers moved by less than 1.25x face size.
            guard iou > 0.1 || distance < maxDimension * 1.25 else {
                continue
            }

            let score = iou - (distance / max(maxDimension, 0.05)) * 0.25
            if bestIndex == nil || score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestIndex
    }

    private static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull && !intersection.isEmpty else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (lhs.width * lhs.height) + (rhs.width * rhs.height) - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private static func centerDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let deltaX = lhs.midX - rhs.midX
        let deltaY = lhs.midY - rhs.midY
        return hypot(deltaX, deltaY)
    }

    private static func interpolateRect(from current: CGRect, to target: CGRect, alpha: CGFloat) -> CGRect {
        let clampedAlpha = min(max(alpha, 0), 1)
        let midX = current.midX + (target.midX - current.midX) * clampedAlpha
        let midY = current.midY + (target.midY - current.midY) * clampedAlpha
        let width = current.width + (target.width - current.width) * clampedAlpha
        let height = current.height + (target.height - current.height) * clampedAlpha
        return CGRect(
            x: midX - width / 2,
            y: midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func interpolateAngle(from current: CGFloat, to target: CGFloat, alpha: CGFloat) -> CGFloat {
        let clampedAlpha = min(max(alpha, 0), 1)
        var delta = (target - current).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta < -.pi {
            delta += 2 * .pi
        }
        return current + delta * clampedAlpha
    }

    private static func expandedRect(_ rect: CGRect, scaleMultiplier: CGFloat) -> CGRect {
        let width = rect.width * scaleMultiplier
        let height = rect.height * scaleMultiplier
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}
