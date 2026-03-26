import Combine
import Foundation
import AppKit
import Darwin

enum BusyScope: Hashable {
    case bootstrap
    case catalogRefresh
    case modelSelection

    var priority: Int {
        switch self {
        case .bootstrap:
            return 3
        case .modelSelection:
            return 2
        case .catalogRefresh:
            return 1
        }
    }
}

struct BusyDescriptor: Equatable {
    let scope: BusyScope
    let message: String
    let priority: Int
}

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
    @Published private(set) var activeBusyDescriptor: BusyDescriptor?
    @Published var toast: AppToast?
    @Published var selectedModelSizeLabel = "—"
    @Published var selectedIndexSizeLabel = "—"
    @Published var selectedSpeakerCount = 0
    @Published var appMemoryLabel = "—"
    @Published var engineMemoryLabel = "—"
    @Published private(set) var taskHistory: [TaskHistoryEntry] = []

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
    private let userDefaults: UserDefaults
    private var hasBootstrapped = false
    private var cancellables: Set<AnyCancellable> = []
    private var navigationResetTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?
    private var busyDescriptors: [BusyScope: BusyDescriptor] = [:]
    private let taskHistoryDefaultsKey = "local.r0.SwiftRVCMacClient.taskHistory.v1"
    private let maxTaskHistoryCount = 80

    /// 清洗后端返回的模型摘要，过滤空白内容和 traceback 噪音。
    private func sanitizedModelInfoSummary(_ raw: String) -> String {
        let summary = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return "" }
        if summary.contains("Traceback (most recent call last):") {
            return ""
        }
        return summary
    }

    /// 构建应用级状态容器，并允许测试注入轻量依赖替身。
    init(
        environment: AppEnvironment,
        engineController: EngineController? = nil,
        audioPlayer: AudioPreviewPlayer? = nil,
        bridgeClient: RVCBridgeClient? = nil,
        startMetricsTask: Bool = true,
        userDefaults: UserDefaults = .standard
    ) {
        self.environment = environment
        self.userDefaults = userDefaults

        let resolvedEngineController = engineController ?? EngineController(environment: environment)
        let resolvedAudioPlayer = audioPlayer ?? AudioPreviewPlayer()
        let resolvedBridgeClient = bridgeClient ?? PythonRVCBridgeClient(environment: environment) {
            resolvedEngineController.baseURL
        }

        self.engineController = resolvedEngineController
        self.audioPlayer = resolvedAudioPlayer
        self.bridgeClient = resolvedBridgeClient
        self.inferenceViewModel = InferenceViewModel(bridgeClient: resolvedBridgeClient, audioPlayer: resolvedAudioPlayer)
        self.batchViewModel = BatchViewModel(bridgeClient: resolvedBridgeClient)
        self.realtimeViewModel = RealtimeViewModel(bridgeClient: resolvedBridgeClient)
        self.uvrViewModel = UVRViewModel(bridgeClient: resolvedBridgeClient)
        self.assetAuditViewModel = AssetAuditViewModel(bridgeClient: resolvedBridgeClient)
        self.onnxViewModel = ONNXViewModel(bridgeClient: resolvedBridgeClient)
        self.checkpointToolsViewModel = CheckpointToolsViewModel(bridgeClient: resolvedBridgeClient)
        self.taskHistory = Self.loadTaskHistory(from: userDefaults, key: taskHistoryDefaultsKey)

        batchViewModel.outputDirectoryURL = environment.defaultBatchOutputDirectory
        uvrViewModel.vocalOutputDirectoryURL = environment.defaultBatchOutputDirectory.appendingPathComponent("uvr-vocals", isDirectory: true)
        uvrViewModel.instrumentalOutputDirectoryURL = environment.defaultBatchOutputDirectory.appendingPathComponent("uvr-instrumentals", isDirectory: true)

        inferenceViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
                self?.recordSingleTaskHistory(status: .success, summary: summary)
            }
            .store(in: &cancellables)

        batchViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.lastExecutionSummary = summary
                self?.presentToast(message: summary, style: .success)
                self?.recordBatchTaskHistory(status: .success, summary: summary)
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
                self?.recordSingleTaskHistory(status: .failure, summary: message)
            }
            .store(in: &cancellables)

        batchViewModel.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
                self?.recordBatchTaskHistory(status: .failure, summary: message)
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
                self?.recordRealtimeTaskHistory(status: .failure, summary: message)
            }
            .store(in: &cancellables)

        realtimeViewModel.$lastRunSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                self?.statusMessage = summary
                self?.presentToast(message: summary, style: .info)
                self?.recordRealtimeTaskHistory(status: .info, summary: summary)
            }
            .store(in: &cancellables)

        resolvedEngineController.$lastError
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.statusMessage = message
                self?.presentToast(message: message, style: .error)
            }
            .store(in: &cancellables)

        if startMetricsTask {
            startMetricsPolling()
        }
    }

    var availablePortDescription: String {
        engineController.port.map(String.init) ?? "—"
    }

    var effectiveSelectedIndexPath: String? {
        inferenceViewModel.effectiveIndexPath
    }

    var isBusy: Bool {
        activeBusyDescriptor != nil
    }

    var isBootstrapBusy: Bool {
        busyDescriptors[.bootstrap] != nil
    }

    var isCatalogBusy: Bool {
        busyDescriptors[.catalogRefresh] != nil
    }

    var isModelSelectionBusy: Bool {
        busyDescriptors[.modelSelection] != nil
    }

    var modelSelectionBusyMessage: String? {
        busyDescriptors[.modelSelection]?.message
    }

    /// 进入统一等待态，并按优先级刷新当前展示中的忙碌文案。
    func beginBusy(_ scope: BusyScope, modelName: String? = nil) {
        busyDescriptors[scope] = BusyDescriptor(
            scope: scope,
            message: busyMessage(for: scope, modelName: modelName),
            priority: scope.priority
        )
        synchronizeBusyDescriptor()
    }

    /// 结束指定等待态，并在多等待源并存时恢复到剩余的最高优先级提示。
    func endBusy(_ scope: BusyScope) {
        busyDescriptors.removeValue(forKey: scope)
        synchronizeBusyDescriptor()
    }

    /// 执行首次启动自举流程，并保证启动等待态覆盖整个初始化链路。
    func performInitialBootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        beginBusy(.bootstrap)
        defer { endBusy(.bootstrap) }
        await startEngine()
    }

    /// 启动本地引擎，并在成功后刷新模型目录和实时上下文。
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

    /// 重启本地引擎，并在成功后重新同步模型和实时状态。
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

    /// 停止本地引擎并广播已停止状态。
    func stopEngine() {
        engineController.stop()
        statusMessage = L10n.tr("status.engine.stopped")
        presentToast(message: statusMessage, style: .info)
    }

    /// 刷新模型与索引目录，并在非自举阶段独立维护目录刷新等待态。
    func refreshModels() async {
        guard engineController.state == .ready else {
            statusMessage = L10n.tr("status.engine.refresh_first")
            presentToast(message: statusMessage, style: .info)
            return
        }

        let managesCatalogBusy = !isBootstrapping
        if managesCatalogBusy {
            beginBusy(.catalogRefresh)
        }
        isRefreshingModels = true
        defer {
            isRefreshingModels = false
            if managesCatalogBusy {
                endBusy(.catalogRefresh)
            }
        }

        do {
            let catalog = try await bridgeClient.refreshModels()
            models = catalog.models.map { model in
                var sanitized = model
                sanitized.infoSummary = sanitizedModelInfoSummary(model.infoSummary)
                return sanitized
            }
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

    /// 将同一个索引路径同步给单文件和批处理两个推理面板。
    func selectSharedIndexPath(_ path: String?) {
        inferenceViewModel.customIndexURL = nil
        batchViewModel.customIndexURL = nil
        inferenceViewModel.selectedIndexPath = path
        batchViewModel.selectedIndexPath = path
    }

    /// 设置单文件输入音频，保留批处理输入队列不变。
    func setSingleInputFileURL(_ url: URL?) {
        inferenceViewModel.inputFileURL = url
    }

    /// 设置批处理输入目录，并清理互斥的显式文件队列与单文件输入。
    func setBatchInputDirectoryURL(_ url: URL?) {
        batchViewModel.inputDirectoryURL = url
        if url != nil {
            batchViewModel.inputFileURLs = []
            inferenceViewModel.inputFileURL = nil
        }
    }

    /// 设置批处理输入文件集合，并在仅选中一个文件时同步为单文件输入。
    func setBatchInputFileURLs(_ urls: [URL]) {
        batchViewModel.inputFileURLs = urls
        if !urls.isEmpty {
            batchViewModel.inputDirectoryURL = nil
        }
        inferenceViewModel.inputFileURL = urls.count == 1 ? urls[0] : nil
    }

    /// 设置共享自定义索引文件，并覆盖两个推理面板的当前索引来源。
    func setSharedCustomIndexURL(_ url: URL) {
        inferenceViewModel.customIndexURL = url
        batchViewModel.customIndexURL = url
        inferenceViewModel.selectedIndexPath = url.path
        batchViewModel.selectedIndexPath = url.path
    }

    /// 清空共享自定义索引文件，并回退仍指向该文件的索引选择状态。
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

    /// 从后端重新拉取实时设备和运行状态。
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

    /// 刷新 UVR 模型目录，供 UVR 面板下拉框使用。
    func refreshUVRModels() async {
        guard engineController.state == .ready else { return }
        do {
            try await uvrViewModel.refreshModels()
        } catch {
            statusMessage = error.localizedDescription
            presentToast(message: error.localizedDescription, style: .error)
        }
    }

    /// 使用当前模型和索引启动实时变声链路。
    func startRealtime() async {
        await realtimeViewModel.start(
            selectedModelName: selectedModelName,
            selectedIndexPath: effectiveSelectedIndexPath,
            inferenceViewModel: inferenceViewModel
        )
        await refreshRealtimeContext()
    }

    /// 停止实时变声链路，并刷新后端状态快照。
    func stopRealtime() async {
        await realtimeViewModel.stop()
        await refreshRealtimeContext()
    }

    /// 将当前实时参数重新推送到运行中的实时链路。
    func applyRealtimeConfiguration() async {
        await realtimeViewModel.configure(
            selectedModelName: selectedModelName,
            selectedIndexPath: effectiveSelectedIndexPath,
            inferenceViewModel: inferenceViewModel
        )
    }

    /// 切换当前模型，并让等待态持续到实时配置同步结束为止。
    func selectModel(_ name: String) async {
        guard !name.isEmpty else { return }

        beginBusy(.modelSelection, modelName: name)
        defer { endBusy(.modelSelection) }

        do {
            if let currentModel = selectedModelName, currentModel != name {
                _ = try await bridgeClient.unloadModel()
            }
            let result = try await bridgeClient.selectModel(name: name)
            let sanitizedSummary = sanitizedModelInfoSummary(result.modelInfoSummary)
            selectedModelName = result.modelName
            modelInfoSummary = sanitizedSummary.isEmpty ? L10n.tr("models.no_info") : sanitizedSummary
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
                models[modelIndex].infoSummary = sanitizedSummary
                models[modelIndex].speakerCount = result.speakerCount
            }
            if let modelInfoError = result.modelInfoError?.trimmingCharacters(in: .whitespacesAndNewlines),
               !modelInfoError.isEmpty {
                statusMessage = "Model loaded, but metadata inspection failed: \(modelInfoError)"
                presentToast(message: statusMessage, style: .error)
            } else {
                statusMessage = L10n.tr("status.model.loaded", name)
                presentToast(message: statusMessage, style: .success)
            }
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

    /// 卸载当前模型，并清空与模型相关的本地派生状态。
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

    /// 切换当前页面，并短暂标记导航过渡状态。
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

    /// 打开模型权重目录。
    func openWeightsDirectory() {
        openDirectory(environment.weightsDirectory, label: L10n.tr("status.folder.model_weights"))
    }

    /// 打开索引文件目录。
    func openIndicesDirectory() {
        openDirectory(environment.indicesDirectory, label: L10n.tr("status.folder.index_files"))
    }

    /// 确保目录存在后在 Finder 中打开，并反馈结果 toast。
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

    /// 立即关闭当前 toast，并取消自动消失任务。
    func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toast = nil
    }

    /// 展示一条新的 toast，并启动自动消失计时。
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

    /// 清空已持久化的任务历史，供 RES 面板快速重置。
    func clearTaskHistory() {
        taskHistory = []
        persistTaskHistory()
    }

    /// 将历史中的输出重新载入预览播放器，方便直接回听旧产物。
    func loadTaskHistoryOutput(_ entry: TaskHistoryEntry) {
        guard let outputPath = entry.outputPath else { return }
        let url = URL(fileURLWithPath: outputPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        inferenceViewModel.outputAudioURL = url
        audioPlayer.load(url: url)
    }

    /// 将历史中的产物重新载入预览播放器并立即开始播放。
    func playTaskHistoryOutput(_ entry: TaskHistoryEntry) {
        loadTaskHistoryOutput(entry)
        audioPlayer.play()
    }

    /// 在 Finder 中定位历史记录关联的产物文件。
    func revealTaskHistoryOutput(_ entry: TaskHistoryEntry) {
        guard let outputPath = entry.outputPath else { return }
        let url = URL(fileURLWithPath: outputPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 周期轮询应用、引擎、模型和索引的体积标签。
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

    /// 记录单文件推理任务结果，并将其持久化到 RES 历史。
    private func recordSingleTaskHistory(status: TaskHistoryStatus, summary: String) {
        appendTaskHistory(
            TaskHistoryEntry(
                id: UUID(),
                timestamp: Date(),
                kind: .single,
                status: status,
                title: status == .failure ? "Single convert failed" : "Single convert",
                summary: summary,
                modelName: selectedModelName,
                inputLabel: inferenceViewModel.inputFileURL?.lastPathComponent,
                inputPath: inferenceViewModel.inputFileURL?.path,
                outputLabel: status == .success ? inferenceViewModel.outputAudioURL?.lastPathComponent : nil,
                outputPath: status == .success ? inferenceViewModel.outputAudioURL?.path : nil,
                indexPath: effectiveSelectedIndexPath,
                f0Method: inferenceViewModel.f0Method.rawValue,
                speakerID: inferenceViewModel.speakerID,
                errorMessage: status == .failure ? inferenceViewModel.errorMessage ?? summary : nil
            )
        )
    }

    /// 记录批处理任务结果，并保留目录级输入输出上下文。
    private func recordBatchTaskHistory(status: TaskHistoryStatus, summary: String) {
        let batchInputLabel: String?
        let batchInputPath: String?
        if let directory = batchViewModel.inputDirectoryURL {
            batchInputLabel = directory.lastPathComponent
            batchInputPath = directory.path
        } else if let firstFile = batchViewModel.inputFileURLs.first {
            batchInputLabel = batchViewModel.inputFileURLs.count == 1 ? firstFile.lastPathComponent : "\(batchViewModel.inputFileURLs.count) files"
            batchInputPath = batchViewModel.inputFileURLs.map(\.path).joined(separator: "\n")
        } else {
            batchInputLabel = nil
            batchInputPath = nil
        }

        appendTaskHistory(
            TaskHistoryEntry(
                id: UUID(),
                timestamp: Date(),
                kind: .batch,
                status: status,
                title: status == .failure ? "Batch convert failed" : "Batch convert",
                summary: summary,
                modelName: selectedModelName,
                inputLabel: batchInputLabel,
                inputPath: batchInputPath,
                outputLabel: batchViewModel.outputDirectoryURL?.lastPathComponent,
                outputPath: batchViewModel.outputDirectoryURL?.path,
                indexPath: batchViewModel.effectiveIndexPath,
                f0Method: batchViewModel.f0Method.rawValue,
                speakerID: batchViewModel.speakerID,
                errorMessage: status == .failure ? batchViewModel.errorMessage ?? summary : nil
            )
        )
    }

    /// 记录实时链路的启动、停止与错误事件，便于回顾设备和模型上下文。
    private func recordRealtimeTaskHistory(status: TaskHistoryStatus, summary: String) {
        let inputLabel = realtimeViewModel.selectedInputDevice
        let outputLabel = realtimeViewModel.selectedOutputDevice
        let ioPath = [inputLabel, outputLabel]
            .compactMap { $0 }
            .joined(separator: " -> ")

        appendTaskHistory(
            TaskHistoryEntry(
                id: UUID(),
                timestamp: Date(),
                kind: .realtime,
                status: status,
                title: realtimeViewModel.isRunning ? "Live monitor active" : "Live monitor update",
                summary: summary,
                modelName: selectedModelName,
                inputLabel: inputLabel,
                inputPath: ioPath.isEmpty ? nil : ioPath,
                outputLabel: outputLabel,
                outputPath: nil,
                indexPath: effectiveSelectedIndexPath,
                f0Method: inferenceViewModel.f0Method.rawValue,
                speakerID: inferenceViewModel.speakerID,
                errorMessage: status == .failure ? realtimeViewModel.lastError ?? summary : nil
            )
        )
    }

    /// 将任务历史插入队首，并同步写入本地持久化存储。
    private func appendTaskHistory(_ entry: TaskHistoryEntry) {
        taskHistory.insert(entry, at: 0)
        if taskHistory.count > maxTaskHistoryCount {
            taskHistory = Array(taskHistory.prefix(maxTaskHistoryCount))
        }
        persistTaskHistory()
    }

    /// 将当前内存中的任务历史写回 UserDefaults。
    private func persistTaskHistory() {
        guard let data = try? JSONEncoder().encode(taskHistory) else { return }
        userDefaults.set(data, forKey: taskHistoryDefaultsKey)
    }

    /// 从 UserDefaults 中恢复历史任务列表，兼容首次启动或损坏数据。
    private static func loadTaskHistory(from defaults: UserDefaults, key: String) -> [TaskHistoryEntry] {
        guard
            let data = defaults.data(forKey: key),
            let entries = try? JSONDecoder().decode([TaskHistoryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    /// 读取当前 app 进程的驻留内存大小。
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

    /// 通过 `ps` 查询指定进程的驻留内存大小。
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

    /// 异步读取单个文件的体积。
    private static func fileSizeBytes(at url: URL?) async -> UInt64? {
        guard let url else { return nil }
        return await Task.detached(priority: .utility) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let fileSize = values?.fileSize else { return nil }
            return UInt64(fileSize)
        }.value
    }

    /// 将字节数格式化为适合 UI 展示的容量标签。
    private static func byteLabel(_ bytes: UInt64?) -> String {
        guard let bytes, bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// 将所有活跃等待态压缩成当前界面真正应该展示的那一个。
    private func synchronizeBusyDescriptor() {
        activeBusyDescriptor = busyDescriptors.values.max { lhs, rhs in
            lhs.priority < rhs.priority
        }
        isBootstrapping = busyDescriptors[.bootstrap] != nil
    }

    /// 为每种等待态生成统一文案，避免不同视图各自拼接提示文本。
    private func busyMessage(for scope: BusyScope, modelName: String?) -> String {
        switch scope {
        case .bootstrap:
            return L10n.tr("label.shell_loading")
        case .catalogRefresh:
            return L10n.tr("status.catalog.loading")
        case .modelSelection:
            return L10n.tr("status.model.loading", displayedModelName(from: modelName))
        }
    }

    /// 将模型文件名裁剪成更适合等待提示展示的短标签。
    private func displayedModelName(from rawName: String?) -> String {
        guard let rawName, !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return L10n.tr("picker.select_model")
        }
        return rawName.replacingOccurrences(of: ".pth", with: "")
    }
}
