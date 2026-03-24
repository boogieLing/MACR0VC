import Foundation

@MainActor
final class CheckpointToolsViewModel: ObservableObject {
    @Published var modelIDA = ""
    @Published var modelIDB = ""
    @Published var selectedCheckpointFileURL: URL?
    @Published var metadataText = ""
    @Published var saveName = ""
    @Published var mergeModelAURL: URL?
    @Published var mergeModelBURL: URL?
    @Published var mergeWeightA = 0.5
    @Published var mergeTargetSampleRate = "48k"
    @Published var mergeHasPitchGuidance = true
    @Published var mergeInfoText = ""
    @Published var mergeSaveName = ""
    @Published var mergeVersion = "v2"
    @Published var extractModelURL: URL?
    @Published var extractSaveName = ""
    @Published var extractAuthor = ""
    @Published var extractTargetSampleRate = "48k"
    @Published var extractHasPitchGuidance = true
    @Published var extractInfoText = ""
    @Published var extractVersion = "v2"
    @Published var isRunning = false
    @Published var outputMessage = ""
    @Published var errorMessage: String?
    @Published private(set) var lastRunSummary: String?

    private let bridgeClient: RVCBridgeClient

    init(bridgeClient: RVCBridgeClient) {
        self.bridgeClient = bridgeClient
    }

    func compareModels() async {
        errorMessage = nil
        outputMessage = ""

        let request = CheckpointSimilarityRequest(modelIDA: modelIDA, modelIDB: modelIDB)

        do {
            try request.validate()
            isRunning = true
            let startedAt = Date()
            let result = try await bridgeClient.compareCheckpointHashes(request)
            let duration = Date().timeIntervalSince(startedAt)
            outputMessage = result.message
            lastRunSummary = "CKPT compare finished in \(duration.formatted(.number.precision(.fractionLength(1))))s"
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    func loadMetadata() async {
        errorMessage = nil
        outputMessage = ""

        guard let selectedCheckpointURL = selectedCheckpointFileURL else {
            errorMessage = "Choose a checkpoint file before reading metadata."
            return
        }

        let request = CheckpointInfoRequest(modelPath: selectedCheckpointURL)

        do {
            try request.validate()
            isRunning = true
            let result = try await bridgeClient.showCheckpointInfo(request)
            metadataText = result.infoText
            outputMessage = result.message
            lastRunSummary = "Checkpoint metadata loaded"
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    func modifyMetadata() async {
        errorMessage = nil
        outputMessage = ""

        guard let selectedCheckpointURL = selectedCheckpointFileURL else {
            errorMessage = "Choose a checkpoint file before modifying metadata."
            return
        }

        let request = CheckpointModifyRequest(
            modelPath: selectedCheckpointURL,
            infoText: metadataText,
            saveName: saveName
        )

        do {
            try request.validate()
            isRunning = true
            let result = try await bridgeClient.modifyCheckpointInfo(request)
            outputMessage = result.message
            selectedCheckpointFileURL = result.outputModelPath
            if saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                saveName = result.outputModelPath.lastPathComponent
            }
            lastRunSummary = "Checkpoint metadata saved"
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    func mergeModels() async {
        errorMessage = nil
        outputMessage = ""

        guard let mergeModelAURL, let mergeModelBURL else {
            errorMessage = "Choose both checkpoint files before merging."
            return
        }

        let request = CheckpointMergeRequest(
            modelPathA: mergeModelAURL,
            modelPathB: mergeModelBURL,
            weightA: mergeWeightA,
            targetSampleRate: mergeTargetSampleRate,
            hasPitchGuidance: mergeHasPitchGuidance,
            infoText: mergeInfoText,
            saveName: mergeSaveName,
            version: mergeVersion
        )

        do {
            try request.validate()
            isRunning = true
            let result = try await bridgeClient.mergeCheckpoints(request)
            outputMessage = result.message
            lastRunSummary = "Checkpoint merge saved"
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    func extractSmallModel() async {
        errorMessage = nil
        outputMessage = ""

        guard let extractModelURL else {
            errorMessage = "Choose a training checkpoint before extracting a small model."
            return
        }

        let request = CheckpointExtractRequest(
            modelPath: extractModelURL,
            saveName: extractSaveName,
            author: extractAuthor,
            targetSampleRate: extractTargetSampleRate,
            hasPitchGuidance: extractHasPitchGuidance,
            infoText: extractInfoText,
            version: extractVersion
        )

        do {
            try request.validate()
            isRunning = true
            let result = try await bridgeClient.extractSmallCheckpoint(request)
            outputMessage = result.message
            lastRunSummary = "Small model extracted"
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }
}
