import AppKit
import Foundation

@MainActor
final class BatchViewModel: ObservableObject {
    @Published var inputDirectoryURL: URL?
    @Published var inputFileURLs: [URL] = []
    @Published var outputDirectoryURL: URL?
    @Published var selectedIndexPath: String?
    @Published var customIndexURL: URL?
    @Published var speakerID: Int = 0
    @Published var transpose: Double = 0
    @Published var f0Method: F0Method = .rmvpe
    @Published var indexRate: Double = 1
    @Published var filterRadius: Double = 3
    @Published var resampleSR: Double = 0
    @Published var rmsMixRate: Double = 1
    @Published var protect: Double = 0.33
    @Published var format: OutputFormat = .wav
    @Published var isRunning = false
    @Published var outputMessage = ""
    @Published var errorMessage: String?
    @Published private(set) var lastRunSummary: String?

    private let bridgeClient: RVCBridgeClient

    /// Creates the batch view model around the bridge client.
    init(bridgeClient: RVCBridgeClient) {
        self.bridgeClient = bridgeClient
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

    /// Validates local state, serializes the request, and dispatches a batch conversion.
    func convert(selectedModelName: String?) async {
        errorMessage = nil
        outputMessage = ""

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
