import Foundation

@MainActor
final class InferenceViewModel: ObservableObject {
    private enum Defaults {
        static let speakerID = 0
        static let transpose = 0.0
        static let f0Method: F0Method = .crepe
        static let indexRate = 0.75
        static let filterRadius = 3.0
        static let resampleSR = 0.0
        static let rmsMixRate = 1.0
        static let protect = 0.33
    }

    @Published var inputFileURL: URL?
    @Published var selectedIndexPath: String?
    @Published var customIndexURL: URL?
    @Published var speakerID: Int = Defaults.speakerID
    @Published var transpose: Double = Defaults.transpose
    @Published var f0Method: F0Method = Defaults.f0Method
    @Published var indexRate: Double = Defaults.indexRate
    @Published var filterRadius: Double = Defaults.filterRadius
    @Published var resampleSR: Double = Defaults.resampleSR
    @Published var rmsMixRate: Double = Defaults.rmsMixRate
    @Published var protect: Double = Defaults.protect
    @Published var f0FileURL: URL?
    @Published var isRunning = false
    @Published var outputMessage = ""
    @Published var outputAudioURL: URL?
    @Published private(set) var outputDirectoryURL: URL?
    @Published var errorMessage: String?
    @Published private(set) var runStartedAt: Date?
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

    /// 将 patch 区共用的说话人和音高提取方式回退到默认状态。
    func resetPatchDefaults() {
        speakerID = Defaults.speakerID
        f0Method = Defaults.f0Method
    }

    /// 将当前单文件推理参数回退到应用默认基线。
    func resetParameterDefaults() {
        transpose = Defaults.transpose
        indexRate = Defaults.indexRate
        filterRadius = Defaults.filterRadius
        resampleSR = Defaults.resampleSR
        rmsMixRate = Defaults.rmsMixRate
        protect = Defaults.protect
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
    func convert(selectedModelName: String?, outputDirectoryURL: URL) async {
        errorMessage = nil
        outputMessage = ""
        outputAudioURL = nil
        self.outputDirectoryURL = outputDirectoryURL

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
            outputDirectoryURL: outputDirectoryURL,
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
            runStartedAt = startedAt
            defer {
                isRunning = false
                runStartedAt = nil
            }
            let result = try await bridgeClient.convertSingle(request)
            let duration = Date().timeIntervalSince(startedAt)
            outputMessage = result.message
            outputAudioURL = result.outputAudioURL
            self.outputDirectoryURL = result.outputDirectoryURL ?? outputDirectoryURL
            audioPlayer.load(url: result.outputAudioURL)
            lastRunSummary = L10n.tr(
                "status.summary.single",
                duration.formatted(.number.precision(.fractionLength(1)))
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
