import AppKit
import Foundation

@MainActor
final class BatchViewModel: ObservableObject {
    private enum Defaults {
        static let speakerID = 0
        static let transpose = 0.0
        static let f0Method: F0Method = .crepe
        static let indexRate = 0.75
        static let filterRadius = 3.0
        static let resampleSR = 0.0
        static let rmsMixRate = 1.0
        static let protect = 0.33
        static let format: OutputFormat = .wav
    }

    @Published var inputDirectoryURL: URL?
    @Published var inputFileURLs: [URL] = []
    @Published var outputDirectoryURL: URL?
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
    @Published var format: OutputFormat = Defaults.format
    @Published var isRunning = false
    @Published var outputMessage = ""
    @Published var errorMessage: String?
    @Published private(set) var lastRunSummary: String?
    @Published private(set) var outputFileURLs: [URL] = []

    private let bridgeClient: RVCBridgeClient

    /// Creates the batch view model around the bridge client.
    init(bridgeClient: RVCBridgeClient) {
        self.bridgeClient = bridgeClient
    }

    /// Returns the effective index path, preferring a custom override when one is active.
    var effectiveIndexPath: String? {
        customIndexURL?.path ?? selectedIndexPath
    }

    /// 将 patch 区共享的说话人与音高提取方式回退到默认状态。
    func resetPatchDefaults() {
        speakerID = Defaults.speakerID
        f0Method = Defaults.f0Method
    }

    /// 将当前批处理参数回退到默认基线，保留输入输出目录选择。
    func resetParameterDefaults() {
        transpose = Defaults.transpose
        indexRate = Defaults.indexRate
        filterRadius = Defaults.filterRadius
        resampleSR = Defaults.resampleSR
        rmsMixRate = Defaults.rmsMixRate
        protect = Defaults.protect
        format = Defaults.format
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

    /// Validates local state, serializes the request, and dispatches a batch conversion.
    func convert(selectedModelName: String?) async {
        errorMessage = nil
        outputMessage = ""
        outputFileURLs = []

        guard let selectedModelName else {
            errorMessage = ValidationError.missingModel.errorDescription
            return
        }

        guard let outputDirectoryURL else {
            errorMessage = L10n.tr("validation.batch.output_directory")
            return
        }

        let request = BatchInferenceRequest(
            modelName: selectedModelName,
            inputDirectoryURL: inputDirectoryURL,
            inputFileURLs: inputFileURLs,
            outputDirectoryURL: outputDirectoryURL,
            format: format,
            speakerID: speakerID,
            transpose: transpose,
            f0Method: f0Method,
            indexPath: selectedIndexPath,
            customIndexURL: customIndexURL,
            indexRate: indexRate,
            filterRadius: filterRadius,
            resampleSR: resampleSR,
            rmsMixRate: rmsMixRate,
            protect: protect
        )

        do {
            try request.validate()
            isRunning = true
            let startedAt = Date()
            let result = try await bridgeClient.convertBatch(request)
            let duration = Date().timeIntervalSince(startedAt)
            outputMessage = result.message
            outputFileURLs = result.outputFileURLs
            lastRunSummary = L10n.tr(
                "status.summary.batch",
                duration.formatted(.number.precision(.fractionLength(1)))
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    /// Opens the selected output directory in Finder.
    func openOutputDirectory() {
        guard let outputDirectoryURL else { return }
        NSWorkspace.shared.open(outputDirectoryURL)
    }
}
