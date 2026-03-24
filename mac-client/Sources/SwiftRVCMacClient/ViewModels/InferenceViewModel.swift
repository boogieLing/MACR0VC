import Foundation

@MainActor
final class InferenceViewModel: ObservableObject {
    @Published var inputFileURL: URL?
    @Published var selectedIndexPath: String?
    @Published var customIndexURL: URL?
    @Published var speakerID: Int = 0
    @Published var transpose: Double = 0
    @Published var f0Method: F0Method = .rmvpe
    @Published var indexRate: Double = 0.75
    @Published var filterRadius: Double = 3
    @Published var resampleSR: Double = 0
    @Published var rmsMixRate: Double = 0.25
    @Published var protect: Double = 0.33
    @Published var f0FileURL: URL?
    @Published var isRunning = false
    @Published var outputMessage = ""
    @Published var outputAudioURL: URL?
    @Published var errorMessage: String?
    @Published private(set) var lastRunSummary: String?

    private let bridgeClient: RVCBridgeClient
    private let audioPlayer: AudioPreviewPlayer

    /// Creates the inference view model around the bridge and local audio preview helper.
    init(bridgeClient: RVCBridgeClient, audioPlayer: AudioPreviewPlayer) {
        self.bridgeClient = bridgeClient
        self.audioPlayer = audioPlayer
    }

    /// Returns the effective index path, preferring a custom override when one is active.
    var effectiveIndexPath: String? {
        customIndexURL?.path ?? selectedIndexPath
    }

    /// Clears the selected index when the currently chosen path is no longer available in the catalog.
    func ensureSelectedIndexAvailable(_ indexPaths: [String]) {
        if customIndexURL != nil {
            return
        }
        if let selectedIndexPath, indexPaths.contains(selectedIndexPath) {
            return
        }
        selectedIndexPath = nil
    }

    /// Validates local state, serializes the request, and dispatches a single-file conversion.
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
            speakerID: speakerID,
            transpose: transpose,
            f0Method: f0Method,
            indexPath: selectedIndexPath,
            customIndexURL: customIndexURL,
            indexRate: indexRate,
            filterRadius: filterRadius,
            resampleSR: resampleSR,
            rmsMixRate: rmsMixRate,
            protect: protect,
            f0FileURL: f0FileURL
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
