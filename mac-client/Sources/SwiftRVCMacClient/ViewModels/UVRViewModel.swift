import AppKit
import Foundation

@MainActor
final class UVRViewModel: ObservableObject {
    @Published var availableModels: [String] = []
    @Published var selectedModelName: String?
    @Published var inputDirectoryURL: URL?
    @Published var inputFileURLs: [URL] = []
    @Published var vocalOutputDirectoryURL: URL?
    @Published var instrumentalOutputDirectoryURL: URL?
    @Published var format: OutputFormat = .flac
    @Published var isRunning = false
    @Published var outputMessage = ""
    @Published var errorMessage: String?
    @Published private(set) var runStartedAt: Date?
    @Published private(set) var lastRunSummary: String?

    private let bridgeClient: RVCBridgeClient

    init(bridgeClient: RVCBridgeClient) {
        self.bridgeClient = bridgeClient
    }

    /// Refreshes the UVR model catalog and keeps the current selection valid after sync.
    func refreshModels() async throws {
        let catalog = try await bridgeClient.refreshUVRModels()
        availableModels = catalog.modelNames
        if selectedModelName == nil || !catalog.modelNames.contains(selectedModelName ?? "") {
            selectedModelName = catalog.modelNames.first
        }
    }

    /// Validates the current UVR request and runs the separation pipeline.
    func convert() async {
        errorMessage = nil
        outputMessage = ""

        guard let selectedModelName else {
            errorMessage = ValidationError.missingModel.errorDescription
            return
        }

        guard let vocalOutputDirectoryURL, let instrumentalOutputDirectoryURL else {
            errorMessage = L10n.tr("validation.batch.output_directory")
            return
        }

        let request = UVRRequest(
            modelName: selectedModelName,
            inputDirectoryURL: inputDirectoryURL,
            inputFileURLs: inputFileURLs,
            vocalOutputDirectoryURL: vocalOutputDirectoryURL,
            instrumentalOutputDirectoryURL: instrumentalOutputDirectoryURL,
            format: format
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
            let result = try await bridgeClient.convertUVR(request)
            let duration = Date().timeIntervalSince(startedAt)
            outputMessage = result.message
            lastRunSummary = "UVR finished in \(duration.formatted(.number.precision(.fractionLength(1))))s"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Explicitly releases UVR-side runtime memory when the sheet is dismissed.
    func releaseMemory() async {
        guard !isRunning else { return }
        do {
            _ = try await bridgeClient.releaseUVRMemory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Opens the vocals export folder in Finder for quick inspection.
    func openVocalOutputDirectory() {
        guard let vocalOutputDirectoryURL else { return }
        NSWorkspace.shared.open(vocalOutputDirectoryURL)
    }

    /// Opens the instrumentals export folder in Finder for quick inspection.
    func openInstrumentalOutputDirectory() {
        guard let instrumentalOutputDirectoryURL else { return }
        NSWorkspace.shared.open(instrumentalOutputDirectoryURL)
    }
}
