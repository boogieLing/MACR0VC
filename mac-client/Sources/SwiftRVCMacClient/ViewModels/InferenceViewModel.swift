import Foundation

@MainActor
final class InferenceViewModel: ObservableObject {
    @Published var inputFileURL: URL?
    @Published var selectedIndexPath: String?
    @Published var transpose: Double = 0
    @Published var f0Method: F0Method = .rmvpe
    @Published var indexRate: Double = 0.75
    @Published var filterRadius: Double = 3
    @Published var resampleSR: Double = 0
    @Published var rmsMixRate: Double = 0.25
    @Published var protect: Double = 0.33
    @Published var isRunning = false
    @Published var outputMessage = ""
    @Published var outputAudioURL: URL?
    @Published var errorMessage: String?
    @Published private(set) var lastRunSummary: String?

    private let bridgeClient: RVCBridgeClient
    private let audioPlayer: AudioPreviewPlayer

    init(bridgeClient: RVCBridgeClient, audioPlayer: AudioPreviewPlayer) {
        self.bridgeClient = bridgeClient
        self.audioPlayer = audioPlayer
    }

    func ensureSelectedIndexAvailable(_ indexPaths: [String]) {
        if let selectedIndexPath, indexPaths.contains(selectedIndexPath) {
            return
        }
        selectedIndexPath = indexPaths.first
    }

    func convert(selectedModelName: String?) async {
        errorMessage = nil
        outputMessage = ""

        guard let selectedModelName else {
            errorMessage = ValidationError.missingModel.errorDescription
            return
        }

        guard let inputFileURL else {
            errorMessage = ValidationError.missingInputFile.errorDescription
            return
        }

        let request = SingleInferenceRequest(
            modelName: selectedModelName,
            inputFileURL: inputFileURL,
            transpose: transpose,
            f0Method: f0Method,
            indexPath: selectedIndexPath,
            indexRate: indexRate,
            filterRadius: filterRadius,
            resampleSR: resampleSR,
            rmsMixRate: rmsMixRate,
            protect: protect,
            f0FileURL: nil
        )

        do {
            try request.validate()
            isRunning = true
            let startedAt = Date()
            let result = try await bridgeClient.convertSingle(request)
            let duration = Date().timeIntervalSince(startedAt)
            outputMessage = result.message
            outputAudioURL = result.outputAudioURL
            audioPlayer.load(url: result.outputAudioURL)
            lastRunSummary = L10n.tr(
                "status.summary.single",
                duration.formatted(.number.precision(.fractionLength(1)))
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }
}
