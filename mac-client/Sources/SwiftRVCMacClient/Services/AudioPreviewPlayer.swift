import AVFoundation
import Foundation

@MainActor
final class AudioPreviewPlayer: NSObject, ObservableObject, @preconcurrency AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var loadedURL: URL?

    private var player: AVAudioPlayer?

    func load(url: URL?) {
        stop()
        loadedURL = url
        guard let url else { return }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
        } catch {
            player = nil
        }
    }

    func play() {
        player?.play()
        isPlaying = player?.isPlaying ?? false
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}
