import Combine
import Foundation
import AppKit
import Darwin

@MainActor
final class AppState: ObservableObject {
    @Published var navigation: NavigationDestination = .singleConvert
    @Published var models: [ModelOption] = []
    @Published var indexPaths: [String] = []
    @Published var selectedModelName: String?
    @Published var modelInfoSummary = L10n.tr("status.model_info.initial")
    @Published var statusMessage = L10n.tr("status.waiting_engine")
    @Published var lastExecutionSummary = L10n.tr("status.last_run.none")
    @Published var isRefreshingModels = false
    @Published var isNavigating = false
    @Published var isBootstrapping = false
    @Published var toast: AppToast?
    @Published var selectedModelSizeLabel = "—"
    @Published var selectedIndexSizeLabel = "—"
    @Published var selectedSpeakerCount = 0
    @Published var appMemoryLabel = "—"
    @Published var engineMemoryLabel = "—"

    let environment: AppEnvironment
    var engineController: EngineController
    var audioPlayer: AudioPreviewPlayer
    var inferenceViewModel: InferenceViewModel
    var batchViewModel: BatchViewModel
    var realtimeViewModel: RealtimeViewModel
    var uvrViewModel: UVRViewModel
    var assetAuditViewModel: AssetAuditViewModel
    var onnxViewModel: ONNXViewModel
    var checkpointToolsViewModel: CheckpointToolsViewModel

    private let bridgeClient: RVCBridgeClient
    private var hasBootstrapped = false
    private var cancellables: Set<AnyCancellable> = []
    private var navigationResetTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment

        let engineController = EngineController(environment: environment)
        let audioPlayer = AudioPreviewPlayer()
        let bridgeClient = PythonRVCBridgeClient(environment: environment) {
            engineController.baseURL
        }

        self.engineController = engineController
        self.audioPlayer = audioPlayer
        self.bridgeClient = bridgeClient
        self.inferenceViewModel = InferenceViewModel(bridgeClient: bridgeClient, audioPlayer: audioPlayer)
        self.batchViewModel = BatchViewModel(bridgeClient: bridgeClient)
        self.realtimeViewModel = RealtimeViewModel(bridgeClient: bridgeClient)
        self.uvrViewModel = UVRViewModel(bridgeClient: bridgeClient)
        self.assetAuditViewModel = AssetAuditViewModel(bridgeClient: bridgeClient)
        self.onnxViewModel = ONNXViewModel(bridgeClient: bridgeClient)
        self.checkpointToolsViewModel = CheckpointToolsViewModel(bridgeClient: bridgeClient)

        batchViewModel.outputDirectoryURL = environment.defaultBatchOutputDirectory
        uvrViewModel.vocalOutputDirectoryURL = environment.defaultBatchOutputDirectory.appendingPathComponent("uvr-vocals", isDirectory: true)
        uvrViewModel.instrumentalOutputDirectoryURL = environment.defaultBatchOutputDirectory.appendingPathComponent("uvr-instrumentals", isDirectory: true)

        inferenceViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
            }
            .store(in: &cancellables)

        batchViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
            }
            .store(in: &cancellables)

        uvrViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
            }
            .store(in: &cancellables)

        assetAuditViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.statusMessage = summary
                self?.presentToast(message: summary, style: .info)
            }
            .store(in: &cancellables)

        onnxViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
            }
            .store(in: &cancellables)

        checkpointToolsViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
            }
            .store(in: &cancellables)

        inferenceViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        batchViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        uvrViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        assetAuditViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        onnxViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        checkpointToolsViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        realtimeViewModel.$lastError
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        realtimeViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.statusMessage = summary
                self?.presentToast(message: summary, style: .info)
            }
            .store(in: &cancellables)

        engineController.$lastError
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        startMetricsPolling()
    }

    var availablePortDescription: String {
        engineController.port.map(String.init) ?? "—"
    }

    var effectiveSelectedIndexPath: String? {
        inferenceViewModel.effectiveIndexPath
    }

    func performInitialBootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        isBootstrapping = true
        await startEngine()
        isBootstrapping = false
    }

    func startEngine() async {
        statusMessage = L10n.tr("status.engine.starting")
        await engineController.start()
        if engineController.state == .ready {
            statusMessage = L10n.tr("status.engine.ready", availablePortDescription)
            presentToast(message: statusMessage, style: .success)
            await refreshModels()
            await refreshRealtimeContext()
        }
    }

    func restartEngine() async {
        statusMessage = L10n.tr("status.engine.restart")
        await engineController.restart()
        if engineController.state == .ready {
            statusMessage = L10n.tr("status.engine.restarted", availablePortDescription)
            presentToast(message: statusMessage, style: .success)
            await refreshModels()
            await refreshRealtimeContext()
        }
    }

    func stopEngine() {
        engineController.stop()
        statusMessage = L10n.tr("status.engine.stopped")
        presentToast(message: statusMessage, style: .info)
    }

    func refreshModels() async {
        guard engineController.state == .ready else {
            statusMessage = L10n.tr("status.engine.refresh_first")
            presentToast(message: statusMessage, style: .info)
            return
        }

        isRefreshingModels = true
        defer { isRefreshingModels = false }

        do {
            let catalog = try await bridgeClient.refreshModels()
            models = catalog.models
            indexPaths = catalog.indexPaths
            inferenceViewModel.ensureSelectedIndexAvailable(indexPaths)
            batchViewModel.ensureSelectedIndexAvailable(indexPaths)
            try await uvrViewModel.refreshModels()
            statusMessage = L10n.tr("status.catalog.loaded", models.count, indexPaths.count)
            presentToast(message: statusMessage, style: .success)
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    func selectSharedIndexPath(_ path: String?) {
        inferenceViewModel.customIndexURL = nil
        batchViewModel.customIndexURL = nil
        inferenceViewModel.selectedIndexPath = path
        batchViewModel.selectedIndexPath = path
    }

    func setSharedCustomIndexURL(_ url: URL) {
        inferenceViewModel.customIndexURL = url
        batchViewModel.customIndexURL = url
        inferenceViewModel.selectedIndexPath = url.path
        batchViewModel.selectedIndexPath = url.path
    }

    func clearSharedCustomIndexURL() {
        let currentCustomPath = inferenceViewModel.customIndexURL?.path ?? batchViewModel.customIndexURL?.path
        inferenceViewModel.customIndexURL = nil
        batchViewModel.customIndexURL = nil
        if inferenceViewModel.selectedIndexPath == currentCustomPath {
            inferenceViewModel.selectedIndexPath = nil
        }
        if batchViewModel.selectedIndexPath == currentCustomPath {
            batchViewModel.selectedIndexPath = nil
        }
    }

    func refreshRealtimeContext() async {
        guard engineController.state == .ready else { return }
        do {
            try await realtimeViewModel.refreshDevices()
            try await realtimeViewModel.refreshStatus()
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    func refreshUVRModels() async {
        guard engineController.state == .ready else { return }
        do {
            try await uvrViewModel.refreshModels()
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    func startRealtime() async {
        await realtimeViewModel.start(
            selectedModelName: selectedModelName,
            selectedIndexPath: effectiveSelectedIndexPath,
            inferenceViewModel: inferenceViewModel
        )
        await refreshRealtimeContext()
    }

    func stopRealtime() async {
        await realtimeViewModel.stop()
        await refreshRealtimeContext()
    }

    func applyRealtimeConfiguration() async {
        await realtimeViewModel.configure(
            selectedModelName: selectedModelName,
            selectedIndexPath: effectiveSelectedIndexPath,
            inferenceViewModel: inferenceViewModel
        )
    }

    func selectModel(_ name: String) async {
        guard !name.isEmpty else { return }

        do {
            let result = try await bridgeClient.selectModel(name: name)
            selectedModelName = result.modelName
            modelInfoSummary = result.modelInfoSummary.isEmpty ? L10n.tr("models.no_info") : result.modelInfoSummary
            selectedSpeakerCount = result.speakerCount
            if !result.indexPaths.isEmpty {
                indexPaths = result.indexPaths
            }
            clearSharedCustomIndexURL()
            inferenceViewModel.speakerID = 0
            batchViewModel.speakerID = 0
            let normalizedModelName = name.replacingOccurrences(of: ".pth", with: "")
            let indexMatch = indexPaths.first {
                $0.localizedCaseInsensitiveContains(normalizedModelName)
            }

            selectSharedIndexPath(indexMatch)

            if let modelIndex = models.firstIndex(where: { $0.name == name }) {
                models[modelIndex].indexPath = indexMatch ?? ""
                models[modelIndex].infoSummary = modelInfoSummary
                models[modelIndex].speakerCount = result.speakerCount
            }
            statusMessage = L10n.tr("status.model.loaded", name)
            presentToast(message: statusMessage, style: .success)
            await realtimeViewModel.configure(
                selectedModelName: selectedModelName,
                selectedIndexPath: effectiveSelectedIndexPath,
                inferenceViewModel: inferenceViewModel
            )
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    func unloadModel() async {
        guard engineController.state == .ready else {
            statusMessage = L10n.tr("status.engine.refresh_first")
            presentToast(message: statusMessage, style: .info)
            return
        }

        do {
            let result = try await bridgeClient.unloadModel()
            selectedModelName = nil
            modelInfoSummary = L10n.tr("status.model_info.initial")
            indexPaths = result.indexPaths
            selectedSpeakerCount = result.speakerCount
            selectedModelSizeLabel = "—"
            selectedIndexSizeLabel = "—"
            inferenceViewModel.selectedIndexPath = nil
            inferenceViewModel.customIndexURL = nil
            inferenceViewModel.f0FileURL = nil
            inferenceViewModel.speakerID = 0
            batchViewModel.selectedIndexPath = nil
            batchViewModel.customIndexURL = nil
            batchViewModel.speakerID = 0
            statusMessage = result.unloaded ? "Model unloaded." : "Model unload returned no-op."
            presentToast(message: statusMessage, style: .info)
            await refreshRealtimeContext()
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    func navigate(to destination: NavigationDestination) {
        guard navigation != destination else { return }
        navigation = destination
        isNavigating = true
        navigationResetTask?.cancel()
        navigationResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard let self, !Task.isCancelled else { return }
            self.isNavigating = false
        }
    }

    func openWeightsDirectory() {
        openDirectory(environment.weightsDirectory, label: L10n.tr("status.folder.model_weights"))
    }

    func openIndicesDirectory() {
        openDirectory(environment.indicesDirectory, label: L10n.tr("status.folder.index_files"))
    }

    private func openDirectory(_ directoryURL: URL, label: String) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directoryURL)
            statusMessage = L10n.tr("status.folder.opened", label)
            presentToast(message: statusMessage, style: .info)
        } catch {
            let message = L10n.tr("status.folder.failed", label, error.localizedDescription)
            statusMessage = message
            presentToast(message: message, style: .error)
        }
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toast = nil
    }

    func presentToast(message: String, style: AppToast.Style) {
        toastDismissTask?.cancel()
        toast = AppToast(message: message, style: style)
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            self.toast = nil
            self.toastDismissTask = nil
        }
    }

    deinit {
        metricsTask?.cancel()
    }

    private func startMetricsPolling() {
        metricsTask?.cancel()
        metricsTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let selectedModelName = self.selectedModelName
                let selectedIndexPath = self.effectiveSelectedIndexPath
                let weightsDirectory = self.environment.weightsDirectory
                let enginePID = self.engineController.processIdentifier

                let appMemoryBytes = Self.currentAppResidentBytes()
                let engineMemoryBytes = await Self.processResidentBytes(pid: enginePID)
                let modelSizeBytes = await Self.fileSizeBytes(
                    at: selectedModelName.map { weightsDirectory.appendingPathComponent($0) }
                )
                let indexSizeBytes = await Self.fileSizeBytes(
                    at: selectedIndexPath.map { URL(fileURLWithPath: $0) }
                )

                self.appMemoryLabel = Self.byteLabel(appMemoryBytes)
                self.engineMemoryLabel = Self.byteLabel(engineMemoryBytes)
                self.selectedModelSizeLabel = Self.byteLabel(modelSizeBytes)
                self.selectedIndexSizeLabel = Self.byteLabel(indexSizeBytes)

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private static func currentAppResidentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }

    private static func processResidentBytes(pid: Int32?) async -> UInt64? {
        guard let pid else { return nil }
        return await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-o", "rss=", "-p", "\(pid)"]

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      let kilobytes = UInt64(output) else { return nil }
                return kilobytes * 1024
            } catch {
                return nil
            }
        }.value
    }

    private static func fileSizeBytes(at url: URL?) async -> UInt64? {
        guard let url else { return nil }
        return await Task.detached(priority: .utility) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let fileSize = values?.fileSize else { return nil }
            return UInt64(fileSize)
        }.value
    }

    private static func byteLabel(_ bytes: UInt64?) -> String {
        guard let bytes, bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
