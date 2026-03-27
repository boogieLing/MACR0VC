@preconcurrency import AVFoundation
import Foundation

enum AudioCompositeError: LocalizedError {
    case missingForegroundTrack
    case missingBackgroundTrack
    case invalidBackgroundDuration
    case exportSessionUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingForegroundTrack:
            return "Foreground output does not contain a readable audio track."
        case .missingBackgroundTrack:
            return "Background source does not contain a readable audio track."
        case .invalidBackgroundDuration:
            return "Background source duration is invalid, so the mix could not be prepared."
        case .exportSessionUnavailable:
            return "The local audio compositor could not start an export session."
        case .exportFailed(let message):
            return "Background merge failed: \(message)"
        }
    }
}

actor AudioCompositeService {
    private let fileManager: FileManager

    /// Creates the local audio compositor used for preview mixes and persisted background merges.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Renders a temporary preview mix used by the waveform panel when background playback is enabled.
    func exportPreviewMix(
        foregroundURL: URL,
        backgroundURL: URL,
        cacheDirectoryURL: URL,
        backgroundGain: Float
    ) async throws -> URL {
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        let outputURL = cacheDirectoryURL
            .appendingPathComponent(previewStem(for: foregroundURL), isDirectory: false)
            .appendingPathExtension("m4a")
        return try await exportComposite(
            foregroundURL: foregroundURL,
            backgroundURL: backgroundURL,
            outputURL: outputURL,
            backgroundGain: backgroundGain
        )
    }

    /// Renders a persisted merged output into the current single-convert task directory.
    func exportMergedOutput(
        foregroundURL: URL,
        backgroundURL: URL,
        outputDirectoryURL: URL,
        backgroundGain: Float
    ) async throws -> URL {
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
        let outputURL = outputDirectoryURL
            .appendingPathComponent(mergedStem(for: foregroundURL), isDirectory: false)
            .appendingPathExtension("m4a")
        return try await exportComposite(
            foregroundURL: foregroundURL,
            backgroundURL: backgroundURL,
            outputURL: outputURL,
            backgroundGain: backgroundGain
        )
    }

    /// Builds a two-track composition, loops the background bed to foreground length, and exports the mixed result.
    private func exportComposite(
        foregroundURL: URL,
        backgroundURL: URL,
        outputURL: URL,
        backgroundGain: Float
    ) async throws -> URL {
        let foregroundAsset = AVURLAsset(url: foregroundURL)
        let backgroundAsset = AVURLAsset(url: backgroundURL)

        let foregroundTracks = try await foregroundAsset.loadTracks(withMediaType: .audio)
        let backgroundTracks = try await backgroundAsset.loadTracks(withMediaType: .audio)
        guard let foregroundTrack = foregroundTracks.first else {
            throw AudioCompositeError.missingForegroundTrack
        }
        guard let backgroundTrack = backgroundTracks.first else {
            throw AudioCompositeError.missingBackgroundTrack
        }

        let foregroundDuration = try await foregroundAsset.load(.duration)
        let backgroundDuration = try await backgroundAsset.load(.duration)
        guard backgroundDuration.isNumeric && CMTimeCompare(backgroundDuration, .zero) > 0 else {
            throw AudioCompositeError.invalidBackgroundDuration
        }

        let composition = AVMutableComposition()
        guard
            let foregroundCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
            let backgroundCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw AudioCompositeError.exportSessionUnavailable
        }

        try foregroundCompositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: foregroundDuration),
            of: foregroundTrack,
            at: .zero
        )

        var insertionTime = CMTime.zero
        while CMTimeCompare(insertionTime, foregroundDuration) < 0 {
            let remainingDuration = foregroundDuration - insertionTime
            let segmentDuration = CMTimeMinimum(backgroundDuration, remainingDuration)
            try backgroundCompositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: segmentDuration),
                of: backgroundTrack,
                at: insertionTime
            )
            insertionTime = insertionTime + segmentDuration
        }

        let foregroundMix = AVMutableAudioMixInputParameters(track: foregroundCompositionTrack)
        foregroundMix.setVolume(1.0, at: .zero)
        let backgroundMix = AVMutableAudioMixInputParameters(track: backgroundCompositionTrack)
        backgroundMix.setVolume(max(0, min(backgroundGain, 1)), at: .zero)

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [foregroundMix, backgroundMix]

        try? fileManager.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioCompositeError.exportSessionUnavailable
        }

        exportSession.audioMix = audioMix
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: AudioCompositeError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown export failure."))
                case .cancelled:
                    continuation.resume(throwing: AudioCompositeError.exportFailed("The export was cancelled."))
                default:
                    continuation.resume(throwing: AudioCompositeError.exportFailed("The export finished in status \(exportSession.status.rawValue)."))
                }
            }
        }

        return outputURL
    }

    /// Produces a deterministic preview file name so the cached preview can be replaced in place.
    private func previewStem(for foregroundURL: URL) -> String {
        sanitizedStem(from: foregroundURL.deletingPathExtension().lastPathComponent) + "-bg-preview"
    }

    /// Produces the persisted merged output name that sits beside the converted foreground output.
    private func mergedStem(for foregroundURL: URL) -> String {
        sanitizedStem(from: foregroundURL.deletingPathExtension().lastPathComponent) + "-bgmix"
    }

    /// Normalizes a file stem so the compositor can reuse safe path components across preview and merged outputs.
    private func sanitizedStem(from raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let stem = String(scalars)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return stem.isEmpty ? "mix" : stem
    }
}
