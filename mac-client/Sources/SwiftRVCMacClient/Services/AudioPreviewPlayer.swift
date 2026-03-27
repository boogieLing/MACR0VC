import AVFoundation
import Foundation

private func makePreviewWaveformSamples(for url: URL, sampleCount: Int = 120) -> [Double] {
    guard
        let file = try? AVAudioFile(forReading: url),
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        )
    else {
        return []
    }

    do {
        try file.read(into: buffer)
    } catch {
        return []
    }

    guard
        let channelData = buffer.floatChannelData?[0],
        buffer.frameLength > 0
    else {
        return []
    }

    let frameCount = Int(buffer.frameLength)
    let frames = UnsafeBufferPointer(start: channelData, count: frameCount)
    let stride = max(frameCount / sampleCount, 1)
    var samples: [Double] = []
    samples.reserveCapacity(sampleCount)

    var index = 0
    while index < frameCount {
        let end = min(index + stride, frameCount)
        var peak: Float = 0
        for frame in frames[index..<end] {
            peak = max(peak, abs(frame))
        }
        samples.append(Double(peak))
        index += stride
    }

    let normalizedPeak = max(samples.max() ?? 0.001, 0.001)
    return samples.map { min(max($0 / normalizedPeak, 0.08), 1) }
}

@MainActor
final class AudioPreviewPlayer: NSObject, ObservableObject, @preconcurrency AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var loadedURL: URL?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var waveformSamples: [Double] = []

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    /// Loads the selected output file and precomputes a lightweight waveform preview.
    func load(
        url: URL?,
        waveformSourceURL: URL? = nil,
        restoreProgress: Double? = nil,
        autoPlay: Bool = false,
        preserveWaveformWhileLoading: Bool = false
    ) {
        let preservedWaveformSamples = waveformSamples
        let preservedCurrentTime = currentTime
        let preservedDuration = duration

        stopProgressTimer()
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        loadedURL = url
        if preserveWaveformWhileLoading == false {
            waveformSamples = []
            currentTime = 0
            duration = 0
        }
        guard let url else { return }
        let resolvedWaveformSourceURL = waveformSourceURL ?? url

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            if preserveWaveformWhileLoading {
                waveformSamples = preservedWaveformSamples
                if restoreProgress == nil {
                    currentTime = preservedCurrentTime
                    if preservedDuration > 0 {
                        duration = preservedDuration
                    }
                }
            }
            if let restoreProgress, duration > 0 {
                let clampedProgress = min(max(restoreProgress, 0), 1)
                player?.currentTime = clampedProgress * duration
                currentTime = player?.currentTime ?? 0
            }
            Task.detached(priority: .userInitiated) {
                let samples = makePreviewWaveformSamples(for: resolvedWaveformSourceURL)
                await MainActor.run {
                    guard self.loadedURL == url else { return }
                    if preserveWaveformWhileLoading, samples.isEmpty == true {
                        return
                    }
                    self.waveformSamples = samples
                }
            }
            if autoPlay {
                play()
            }
        } catch {
            player = nil
        }
    }

    /// Starts preview playback from the current seek position.
    func play() {
        player?.play()
        isPlaying = player?.isPlaying ?? false
        startProgressTimerIfNeeded()
    }

    /// Toggles between preview playback and pause while preserving the current seek position.
    func togglePlayback() {
        guard player != nil else { return }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Pauses preview playback without discarding the current seek position.
    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    /// Seeks the loaded preview to the normalized progress value.
    func seek(progress: Double) {
        guard let player, duration > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        player.currentTime = clamped * duration
        currentTime = player.currentTime
    }

    /// Stops preview playback and rewinds to the beginning of the loaded output.
    func stop() {
        stopProgressTimer()
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
    }

    /// Clears play state when the preview reaches the end naturally.
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = duration
        stopProgressTimer()
    }

    /// Exposes the preview seek state as a normalized 0...1 progress value.
    var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    private func startProgressTimerIfNeeded() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = self.player?.currentTime ?? 0
                self.isPlaying = self.player?.isPlaying ?? false
                if self.isPlaying == false {
                    self.stopProgressTimer()
                }
            }
        }
        if let progressTimer {
            RunLoop.main.add(progressTimer, forMode: .common)
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}
