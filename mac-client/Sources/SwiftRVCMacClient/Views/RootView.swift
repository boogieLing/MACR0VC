import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    private let helpTooltipSpace = "root-help-tooltip-space"
    private enum PendingDestructiveAction: Identifiable {
        case unloadModel
        case clearCustomIndex
        case clearF0Curve

        var id: String {
            switch self {
            case .unloadModel:
                return "unload-model"
            case .clearCustomIndex:
                return "clear-custom-index"
            case .clearF0Curve:
                return "clear-f0-curve"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @State private var parameterBank: ConsoleParameterBank = .single
    @State private var isFAQPresented = false
    @State private var isAssetReportPresented = false
    @State private var isUVRPresented = false
    @State private var isONNXPresented = false
    @State private var isCheckpointToolsPresented = false
    @State private var isQueuePresented = false
    @State private var isHistoryPresented = false
    @State private var pendingDestructiveAction: PendingDestructiveAction?
    @StateObject private var helpTooltipCoordinator = HelpTooltipCoordinator()

    var body: some View {
        GeometryReader { proxy in
            let compactShell = proxy.size.width < 1180
            let railWidth = compactShell
                ? max(228, min(proxy.size.width * 0.24, 280))
                : max(320, min(proxy.size.width * 0.26, 388))

            shellContent(proxy: proxy, railWidth: railWidth, contentHeight: proxy.size.height)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .coordinateSpace(name: helpTooltipSpace)
        .environmentObject(helpTooltipCoordinator)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(consoleShellBackground)
        .ignoresSafeArea(.container, edges: [.top, .leading, .trailing, .bottom])
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .frame(height: 1)
        }
        .overlay(alignment: .top) {
            if let busyDescriptor = appState.activeBusyDescriptor {
                VStack(alignment: .leading, spacing: 8) {
                    Text(busyDescriptor.message)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .lineLimit(1)

                    BusyFluorescentBarView(style: .global)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(width: 320, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.78))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.64), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.14), radius: 18, y: 8)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
        .overlay(alignment: .topTrailing) {
            if let toast = appState.toast {
                ConsoleToastView(toast: toast)
                    .padding(.top, 16)
                    .padding(.trailing, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        appState.dismissToast()
                }
            }
        }
        .overlay {
            GlobalHelpTooltipLayer()
                .environmentObject(helpTooltipCoordinator)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $isFAQPresented) {
            HelpCenterSheet()
        }
        .sheet(isPresented: $isAssetReportPresented) {
            AssetReportSheet(viewModel: appState.assetAuditViewModel)
        }
        .sheet(isPresented: $isUVRPresented, onDismiss: {
            Task { await appState.uvrViewModel.releaseMemory() }
        }) {
            UVRSheet(
                viewModel: appState.uvrViewModel,
                onChooseInputDirectory: chooseUVRInputDirectory,
                onChooseInputFiles: chooseUVRInputFiles,
                onChooseVocalOutputDirectory: chooseUVRVocalOutputDirectory,
                onChooseInstrumentalOutputDirectory: chooseUVRInstrumentalOutputDirectory,
                onRun: {
                    Task { await appState.runUVRConvert() }
                }
            )
        }
        .sheet(isPresented: $isONNXPresented) {
            ONNXSheet(
                viewModel: appState.onnxViewModel,
                onChooseModelFile: chooseONNXModelFile,
                onChooseExportFile: chooseONNXExportFile,
                onRun: {
                    Task { await appState.onnxViewModel.export() }
                }
            )
        }
        .sheet(isPresented: $isCheckpointToolsPresented) {
            CheckpointToolsSheet(
                viewModel: appState.checkpointToolsViewModel,
                onRunComparison: {
                    Task { await appState.checkpointToolsViewModel.compareModels() }
                },
                onChooseCheckpointFile: chooseCheckpointModelFile,
                onLoadMetadata: {
                    Task { await appState.checkpointToolsViewModel.loadMetadata() }
                },
                onModifyMetadata: {
                    Task { await appState.checkpointToolsViewModel.modifyMetadata() }
                },
                onChooseMergeModelA: chooseMergeModelAFile,
                onChooseMergeModelB: chooseMergeModelBFile,
                onRunMerge: {
                    Task { await appState.checkpointToolsViewModel.mergeModels() }
                },
                onChooseExtractModel: chooseExtractModelFile,
                onRunExtract: {
                    Task { await appState.checkpointToolsViewModel.extractSmallModel() }
                }
            )
        }
        .sheet(isPresented: $isQueuePresented) {
            QueueInspectorSheet(
                selectedModelName: appState.selectedModelName,
                effectiveIndexPath: appState.effectiveSelectedIndexPath,
                f0Method: appState.inferenceViewModel.f0Method.rawValue,
                speakerID: appState.inferenceViewModel.speakerID,
                singleInputURL: appState.inferenceViewModel.inputFileURL,
                batchInputDirectoryURL: appState.batchViewModel.inputDirectoryURL,
                batchInputFileURLs: appState.batchViewModel.inputFileURLs,
                outputDirectoryURL: appState.batchViewModel.outputDirectoryURL,
                outputAudioURL: appState.inferenceViewModel.outputAudioURL,
                runStartedAt: appState.inferenceViewModel.runStartedAt,
                statusMessage: appState.statusMessage,
                lastExecutionSummary: appState.lastExecutionSummary,
                inferenceError: appState.inferenceViewModel.errorMessage,
                batchError: appState.batchViewModel.errorMessage,
                realtimeError: appState.realtimeViewModel.lastError,
                isSingleRunning: appState.inferenceViewModel.isRunning,
                isBatchRunning: appState.batchViewModel.isRunning,
                isRealtimeRunning: appState.realtimeViewModel.isRunning
            )
        }
        .sheet(isPresented: $isHistoryPresented) {
            ResultHistorySheet(
                entries: appState.taskHistory,
                onClear: { kind in appState.clearTaskHistory(kind: kind) },
                onDeleteEntry: appState.deleteTaskHistoryEntry(_:),
                onLoadOutput: appState.loadTaskHistoryOutput(_:),
                onPlayOutput: appState.playTaskHistoryOutput(_:),
                onRevealOutput: appState.revealTaskHistoryOutput(_:)
            )
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: appState.toast?.id)
        .alert(item: $pendingDestructiveAction) { action in
            switch action {
            case .unloadModel:
                return Alert(
                    title: Text("Unload current model?"),
                    message: Text("This will release the currently loaded voice model from memory. You will need to load it again before converting or running live voice change."),
                    primaryButton: .destructive(Text("Unload model")) {
                        Task { await appState.unloadModel() }
                    },
                    secondaryButton: .cancel()
                )
            case .clearCustomIndex:
                return Alert(
                    title: Text("Clear custom index?"),
                    message: Text("This will remove the current external index override and return index selection to catalog or auto mode."),
                    primaryButton: .destructive(Text("Clear index override")) {
                        appState.clearSharedCustomIndexURL()
                    },
                    secondaryButton: .cancel()
                )
            case .clearF0Curve:
                return Alert(
                    title: Text("Clear custom F0 curve?"),
                    message: Text("This will remove the currently selected external pitch curve from the single-file conversion setup."),
                    primaryButton: .destructive(Text("Clear F0 curve")) {
                        appState.inferenceViewModel.f0FileURL = nil
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .onChange(of: appState.inferenceViewModel.transpose) {
            syncRealtimeControlsIfNeeded()
        }
        .onChange(of: appState.inferenceViewModel.indexRate) {
            syncRealtimeControlsIfNeeded()
        }
        .onChange(of: appState.inferenceViewModel.rmsMixRate) {
            syncRealtimeControlsIfNeeded()
        }
        .onChange(of: appState.inferenceViewModel.f0Method) {
            syncRealtimeControlsIfNeeded()
        }
        .onChange(of: appState.inferenceViewModel.selectedIndexPath) {
            syncRealtimeControlsIfNeeded()
        }
        .onChange(of: appState.realtimeViewModel.sampleRateMode) {
            syncRealtimeControlsIfNeeded()
        }
        .onChange(of: appState.realtimeViewModel.extraInferenceTime) {
            syncRealtimeControlsIfNeeded()
        }
        .onChange(of: appState.realtimeViewModel.cpuProcesses) {
            syncRealtimeControlsIfNeeded()
        }
        .onChange(of: appState.navigation) {
            switch appState.navigation {
            case .singleConvert:
                parameterBank = .single
            case .batchConvert:
                parameterBank = .batch
            case .models, .engine:
                break
            }
        }
        .background(WindowChromeConfigurator())
    }

    /// 组装左右双栏的主控制台壳层。
    private func shellContent(proxy: GeometryProxy, railWidth: CGFloat, contentHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            ConsoleLeftRail(
                engineController: appState.engineController,
                inferenceViewModel: appState.inferenceViewModel,
                batchViewModel: appState.batchViewModel,
                realtimeViewModel: appState.realtimeViewModel,
                audioPlayer: appState.audioPlayer,
                models: appState.models,
                indexPaths: appState.indexPaths,
                selectedModelName: appState.selectedModelName,
                selectedSpeakerCount: appState.selectedSpeakerCount,
                parameterBank: parameterBank,
                modelsCount: appState.models.count,
                statusMessage: appState.statusMessage,
                lastExecutionSummary: appState.lastExecutionSummary,
                isBootstrapBusy: appState.isBootstrapBusy,
                isCatalogBusy: appState.isCatalogBusy,
                isModelSelectionBusy: appState.isModelSelectionBusy,
                modelSelectionBusyMessage: appState.modelSelectionBusyMessage,
                onSelectModel: { model in
                    Task { await appState.selectModel(model) }
                },
                onSelectIndexPath: { indexPath in
                    let resolvedIndexPath = indexPath == "__auto_optional__" ? nil : indexPath
                    appState.selectSharedIndexPath(resolvedIndexPath)
                },
                onSelectParameterBank: { bank in
                    parameterBank = bank
                },
                onResetPatchBay: resetPatchBayDefaults,
                onResetRealtimeLab: resetRealtimeLabDefaults,
                onContextAction: handleContextAction
            )
            .frame(width: railWidth, height: contentHeight, alignment: .topLeading)

            consoleDivider
                .frame(height: contentHeight)

            ConsoleDeck(
                engineController: appState.engineController,
                inferenceViewModel: appState.inferenceViewModel,
                batchViewModel: appState.batchViewModel,
                realtimeViewModel: appState.realtimeViewModel,
                audioPlayer: appState.audioPlayer,
                models: appState.models,
                indexPaths: appState.indexPaths,
                selectedModelName: appState.selectedModelName,
                parameterBank: parameterBank,
                statusMessage: appState.statusMessage,
                lastExecutionSummary: appState.lastExecutionSummary,
                catalogModelCount: appState.models.count,
                catalogIndexCount: appState.indexPaths.count,
                selectedModelSizeLabel: appState.selectedModelSizeLabel,
                selectedIndexSizeLabel: appState.selectedIndexSizeLabel,
                appMemoryLabel: appState.appMemoryLabel,
                engineMemoryLabel: appState.engineMemoryLabel,
                isNavigating: appState.isNavigating,
                isBootstrapBusy: appState.isBootstrapBusy,
                isCatalogBusy: appState.isCatalogBusy,
                isModelSelectionBusy: appState.isModelSelectionBusy,
                hasBackgroundTrack: appState.backgroundAudioURL != nil,
                isBackgroundEnabled: appState.isBackgroundMixEnabled,
                backgroundMixLevel: appState.backgroundMixLevel,
                isPreparingBackgroundMix: appState.isPreparingBackgroundMix,
                isPersistingBackgroundMix: appState.isPersistingBackgroundMix,
                onSelectParameterBank: { bank in
                    parameterBank = bank
                },
                onResetRouting: resetRealtimeRoutingDefaults,
                onResetPatchSidecar: resetPatchSidecarDefaults,
                onResetFaders: resetActiveParameterBankDefaults,
                onToggleBackgroundMix: {
                    Task { await appState.toggleBackgroundMix() }
                },
                onChangeBackgroundMixLevel: { value in
                    appState.setBackgroundMixLevel(value)
                },
                onMergeBackgroundMix: {
                    Task { await appState.mergeBackgroundMix() }
                },
                onContextAction: handleContextAction
            )
            .frame(width: max(proxy.size.width - railWidth - 1, 0), height: contentHeight, alignment: .topLeading)
        }
        .frame(width: proxy.size.width, height: contentHeight, alignment: .topLeading)
    }

    /// 仅在实时链路运行中时，同步滑杆和开关改动。
    private func syncRealtimeControlsIfNeeded() {
        guard appState.realtimeViewModel.isRunning else { return }
        Task { await appState.applyRealtimeConfiguration() }
    }

    /// 将 patch bay 中暴露的共享模型参数回退到默认值。
    private func resetPatchBayDefaults() {
        appState.inferenceViewModel.resetPatchDefaults()
        appState.batchViewModel.resetPatchDefaults()
        syncRealtimeControlsIfNeeded()
    }

    /// 将 realtime lab 区域中的实时参数回退到默认值。
    private func resetRealtimeLabDefaults() {
        appState.realtimeViewModel.resetLabDefaults()
        syncRealtimeControlsIfNeeded()
    }

    /// 将顶部路由区回退到自动路由与默认监听模式。
    private func resetRealtimeRoutingDefaults() {
        appState.realtimeViewModel.resetRoutingDefaults()
        guard appState.engineController.state == .ready else { return }
        Task {
            await appState.applyRealtimeConfiguration()
            await appState.refreshRealtimeContext()
        }
    }

    /// 将参数库和索引区回退到默认单文件参数库与自动索引模式。
    private func resetPatchSidecarDefaults() {
        parameterBank = .single
        appState.clearSharedCustomIndexURL()
        appState.selectSharedIndexPath(nil)
        syncRealtimeControlsIfNeeded()
    }

    /// 将当前可见的参数推子回退到对应参数库的默认值。
    private func resetActiveParameterBankDefaults() {
        switch parameterBank {
        case .single:
            appState.inferenceViewModel.resetParameterDefaults()
            syncRealtimeControlsIfNeeded()
        case .batch:
            appState.batchViewModel.resetParameterDefaults()
        }
    }

    private var consoleDivider: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 1)
            Rectangle()
                .fill(Color.white.opacity(0.40))
                .frame(width: 2)
                .offset(x: 1)
        }
    }

    private var consoleShellBackground: some View {
        ZStack {
            AppTheme.consoleShellGradient
            LinearGradient(
                colors: [Color.white.opacity(0.34), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// 将控制台按钮动作路由到对应的状态更新或文件面板。
    private func handleContextAction(_ action: ConsoleContextAction) {
        switch action {
        case .startEngine:
            Task { await appState.startEngine() }
        case .restartEngine:
            Task { await appState.restartEngine() }
        case .stopEngine:
            appState.stopEngine()
        case .refreshModels:
            Task { await appState.refreshModels() }
        case .refreshRealtimeDevices:
            Task { await appState.refreshRealtimeContext() }
        case .openWeights:
            appState.openWeightsDirectory()
        case .openIndices:
            appState.openIndicesDirectory()
        case .showUVR:
            isUVRPresented = true
        case .showONNX:
            prepareONNXExportDefaults()
            isONNXPresented = true
        case .showCheckpointTools:
            isCheckpointToolsPresented = true
        case .showAssetReport:
            isAssetReportPresented = true
            Task { await appState.assetAuditViewModel.refreshReport() }
        case .showFAQ:
            showFAQSheet()
        case .showQueue:
            isQueuePresented = true
        case .showHistory:
            isHistoryPresented = true
        case .releaseRuntimeCaches:
            Task { await appState.releaseRuntimeCaches() }
        case .chooseAudio:
            chooseAudioFile()
        case .chooseCustomIndexFile:
            chooseCustomIndexFile()
        case .clearCustomIndexFile:
            pendingDestructiveAction = .clearCustomIndex
        case .chooseF0CurveFile:
            chooseF0CurveFile()
        case .clearF0CurveFile:
            pendingDestructiveAction = .clearF0Curve
        case .convertSingle:
            isQueuePresented = true
            Task { await appState.runSingleConvert() }
        case .playPreview:
            appState.audioPlayer.play()
        case .revealOutput:
            if let outputURL = appState.inferenceViewModel.outputAudioURL {
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            }
        case .chooseBatchInputFolder:
            chooseBatchInputDirectory()
        case .chooseBatchInputFiles:
            chooseBatchInputFiles()
        case .chooseBatchOutputFolder:
            chooseBatchOutputDirectory()
        case .convertBatch:
            Task { await appState.runBatchConvert() }
        case .openBatchOutput:
            appState.batchViewModel.openOutputDirectory()
        case .startRealtime:
            Task { await appState.startRealtime() }
        case .stopRealtime:
            Task { await appState.stopRealtime() }
        case .unloadModel:
            pendingDestructiveAction = .unloadModel
        }
    }

    /// 选择单文件推理输入音频。
    private func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            appState.setSingleInputFileURL(panel.url)
        }
    }

    /// 选择批处理输入目录。
    private func chooseBatchInputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            appState.setBatchInputDirectoryURL(panel.url)
        }
    }

    /// 选择批处理输入文件集合。
    private func chooseBatchInputFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            appState.setBatchInputFileURLs(panel.urls)
        }
    }

    /// 选择批处理输出目录。
    private func chooseBatchOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            appState.batchViewModel.outputDirectoryURL = panel.url
        }
    }

    /// 选择 UVR 输入目录。
    private func chooseUVRInputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            appState.uvrViewModel.inputDirectoryURL = panel.url
            appState.uvrViewModel.inputFileURLs = []
        }
    }

    /// 选择 UVR 输入文件集合。
    private func chooseUVRInputFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            appState.uvrViewModel.inputFileURLs = panel.urls
            appState.uvrViewModel.inputDirectoryURL = nil
        }
    }

    /// 选择 UVR 人声输出目录。
    private func chooseUVRVocalOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            appState.uvrViewModel.vocalOutputDirectoryURL = panel.url
        }
    }

    /// 选择 UVR 伴奏输出目录。
    private func chooseUVRInstrumentalOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            appState.uvrViewModel.instrumentalOutputDirectoryURL = panel.url
        }
    }

    /// 根据当前选模预填 ONNX 导出源文件和目标文件。
    private func prepareONNXExportDefaults() {
        if appState.onnxViewModel.modelFileURL == nil, let selectedModelName = appState.selectedModelName {
            let candidate = appState.environment.engineRoot
                .appendingPathComponent("assets/weights", isDirectory: true)
                .appendingPathComponent(selectedModelName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                appState.onnxViewModel.modelFileURL = candidate
            }
        }

        if appState.onnxViewModel.exportFileURL == nil, let modelURL = appState.onnxViewModel.modelFileURL {
            let outputName = modelURL.deletingPathExtension().lastPathComponent + ".onnx"
            appState.onnxViewModel.exportFileURL = appState.environment.defaultONNXExportDirectory.appendingPathComponent(outputName)
        }
    }

    /// 选择待导出的 ONNX 源模型文件。
    private func chooseONNXModelFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "pth"),
            UTType(filenameExtension: "ckpt"),
            .data
        ].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            appState.onnxViewModel.modelFileURL = url
            if appState.onnxViewModel.exportFileURL == nil {
                appState.onnxViewModel.exportFileURL = appState.environment.defaultONNXExportDirectory
                    .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".onnx")
            }
        }
    }

    /// 选择 ONNX 导出目标文件路径。
    private func chooseONNXExportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "onnx") ?? .data]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = appState.onnxViewModel.exportFileURL?.lastPathComponent
            ?? appState.onnxViewModel.modelFileURL.map { $0.deletingPathExtension().lastPathComponent + ".onnx" }
            ?? "model.onnx"
        if panel.runModal() == .OK, let url = panel.url {
            appState.onnxViewModel.exportFileURL = url
        }
    }

    /// 选择 checkpoint 工具面板的目标模型文件。
    private func chooseCheckpointModelFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "pth"),
            UTType(filenameExtension: "ckpt"),
            .data
        ].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            appState.checkpointToolsViewModel.selectedCheckpointFileURL = url
            if appState.checkpointToolsViewModel.saveName.isEmpty {
                appState.checkpointToolsViewModel.saveName = url.lastPathComponent
            }
        }
    }

    /// 选择 merge 工具中的 A 模型。
    private func chooseMergeModelAFile() {
        if let url = chooseCheckpointLikeFile() {
            appState.checkpointToolsViewModel.mergeModelAURL = url
            if appState.checkpointToolsViewModel.mergeSaveName.isEmpty {
                appState.checkpointToolsViewModel.mergeSaveName = url.deletingPathExtension().lastPathComponent + "-merged"
            }
        }
    }

    /// 选择 merge 工具中的 B 模型。
    private func chooseMergeModelBFile() {
        if let url = chooseCheckpointLikeFile() {
            appState.checkpointToolsViewModel.mergeModelBURL = url
            if appState.checkpointToolsViewModel.mergeSaveName.isEmpty {
                appState.checkpointToolsViewModel.mergeSaveName = url.deletingPathExtension().lastPathComponent + "-merged"
            }
        }
    }

    /// 选择提取小模型的源 checkpoint。
    private func chooseExtractModelFile() {
        if let url = chooseCheckpointLikeFile() {
            appState.checkpointToolsViewModel.extractModelURL = url
            if appState.checkpointToolsViewModel.extractSaveName.isEmpty {
                appState.checkpointToolsViewModel.extractSaveName = url.deletingPathExtension().lastPathComponent + "-small"
            }
        }
    }

    /// 打开通用的 checkpoint 文件选择面板。
    private func chooseCheckpointLikeFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "pth"),
            UTType(filenameExtension: "ckpt"),
            .data
        ].compactMap { $0 }
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 选择自定义索引文件并同步到推理视图。
    private func chooseCustomIndexFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "index"),
            .plainText,
            .commaSeparatedText,
            .tabSeparatedText
        ].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            appState.setSharedCustomIndexURL(url)
        }
    }

    /// 选择单文件推理的 F0 曲线文件。
    private func chooseF0CurveFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, .tabSeparatedText]
        if panel.runModal() == .OK {
            appState.inferenceViewModel.f0FileURL = panel.url
        }
    }

    /// 打开应用内帮助中心。
    private func showFAQSheet() {
        isFAQPresented = true
    }
}

private enum ConsoleContextAction: String, Identifiable {
    case startEngine
    case restartEngine
    case stopEngine
    case refreshModels
    case refreshRealtimeDevices
    case openWeights
    case openIndices
    case showUVR
    case showONNX
    case showCheckpointTools
    case showAssetReport
    case showFAQ
    case showQueue
    case showHistory
    case chooseAudio
    case chooseCustomIndexFile
    case clearCustomIndexFile
    case chooseF0CurveFile
    case clearF0CurveFile
    case convertSingle
    case playPreview
    case revealOutput
    case chooseBatchInputFolder
    case chooseBatchInputFiles
    case chooseBatchOutputFolder
    case convertBatch
    case openBatchOutput
    case startRealtime
    case stopRealtime
    case unloadModel
    case releaseRuntimeCaches

    var id: String { rawValue }
}

private enum ConsoleParameterBank: String, CaseIterable, Identifiable {
    case single
    case batch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            return "Single"
        case .batch:
            return "Batch"
        }
    }

    var detail: String {
        switch self {
        case .single:
            return "Edit the faders used by one-file voice conversion."
        case .batch:
            return "Edit the faders used by folder or multi-file conversion."
        }
    }
}

private struct ConsoleActionItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let action: ConsoleContextAction
    let isEnabled: Bool
    let accent: Color?
}

private struct ConsolePickerOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
}

private struct ConsoleMetric {
    let title: String
    let value: String
}

private enum ConsolePatchPopoverLayout {
    case list
    case grid(columns: Int)
}

private struct ConsoleControlSpec: Identifiable {
    let id: String
    let title: String
    let shortTitle: String
    let helpText: String
    let color: Color
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let isInteractive: Bool
    let formatter: (Double) -> String

    /// 用当前 formatter 渲染控制项值。
    func displayValue() -> String {
        formatter(value.wrappedValue)
    }
}

private struct ConsoleLeftRail: View {
    @ObservedObject var engineController: EngineController
    @ObservedObject var inferenceViewModel: InferenceViewModel
    @ObservedObject var batchViewModel: BatchViewModel
    @ObservedObject var realtimeViewModel: RealtimeViewModel
    @ObservedObject var audioPlayer: AudioPreviewPlayer
    let models: [ModelOption]
    let indexPaths: [String]
    let selectedModelName: String?
    let selectedSpeakerCount: Int
    let parameterBank: ConsoleParameterBank
    let modelsCount: Int
    let statusMessage: String
    let lastExecutionSummary: String
    let isBootstrapBusy: Bool
    let isCatalogBusy: Bool
    let isModelSelectionBusy: Bool
    let modelSelectionBusyMessage: String?
    let onSelectModel: (String) -> Void
    let onSelectIndexPath: (String) -> Void
    let onSelectParameterBank: (ConsoleParameterBank) -> Void
    let onResetPatchBay: () -> Void
    let onResetRealtimeLab: () -> Void
    let onContextAction: (ConsoleContextAction) -> Void

    var body: some View {
        GeometryReader { proxy in
            let shortRail = proxy.size.height < 820
            let ultraTightRail = proxy.size.height < 700

            VStack(alignment: .leading, spacing: 0) {
                grille
                miniTransport
                    .padding(.top, ultraTightRail ? 8 : (shortRail ? 10 : 14))
                assetRack
                    .padding(.top, ultraTightRail ? 8 : (shortRail ? 12 : 16))
                Spacer(minLength: ultraTightRail ? 8 : (shortRail ? 12 : 18))
                realtimeLabRack(compact: shortRail, tight: ultraTightRail)
                    .padding(.top, ultraTightRail ? 0 : (shortRail ? 2 : 4))
                Spacer(minLength: ultraTightRail ? 4 : (shortRail ? 6 : 8))
                Text(lastExecutionSummary)
                    .font(.system(size: ultraTightRail ? 9 : (shortRail ? 10 : 11), weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.labelInk)
                    .lineLimit(ultraTightRail ? 1 : 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, ultraTightRail ? 18 : (shortRail ? 22 : 30))
            .padding(.bottom, ultraTightRail ? 8 : (shortRail ? 12 : 18))
            .padding(.leading, shortRail ? 20 : 28)
            .padding(.trailing, shortRail ? 16 : 24)
        }
    }

    private var grille: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(4), spacing: 3), count: 12), spacing: 3) {
            ForEach(0..<36, id: \.self) { _ in
                Circle()
                    .fill(Color.black.opacity(0.56))
                    .frame(width: 2, height: 2)
                    .shadow(color: Color.white.opacity(0.12), radius: 0.2, x: 0, y: 0.4)
            }
        }
        .frame(width: 68, height: 18, alignment: .leading)
    }

    private var miniTransport: some View {
        HStack(spacing: 16) {
            ConsoleMiniButton(systemImage: "record.circle.fill")
            ConsoleMiniButton(systemImage: "minus")
        }
    }

    private var assetRack: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConsoleSectionHeader(title: "PATCH BAY", compact: true, action: onResetPatchBay)

            VStack(spacing: 6) {
                ConsolePatchMenuCard(
                    title: "VOICE MODEL",
                    value: selectedModelName?.replacingOccurrences(of: ".pth", with: "") ?? "Choose target voice",
                    detail: models.isEmpty ? "Load a .pth voice model first." : "\(models.count) voice models ready to load.",
                    actionLabel: "SELECT",
                    accent: selectedModelName == nil ? nil : AppTheme.knobOrange,
                    options: models.map {
                        ConsolePickerOption(
                            id: $0.name,
                            title: $0.name.replacingOccurrences(of: ".pth", with: ""),
                            subtitle: $0.infoSummary.isEmpty ? nil : $0.infoSummary
                        )
                    },
                    selectedID: selectedModelName,
                    emptyState: "No models loaded",
                    compactHeight: true,
                    isEnabled: !isModelPickerDisabled,
                    popoverLayout: .grid(columns: 3),
                    popoverWidth: 704,
                    helpText: "Pick the target voice model. Loading a new model replaces the one currently in memory, so switch models only when you really want a different target tone.",
                    onSelect: onSelectModel
                )

                if isModelSelectionBusy, let modelSelectionBusyMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        BusyFluorescentBarView(style: .inline)
                        Text(modelSelectionBusyMessage)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.labelInk.opacity(0.86))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ConsolePatchMenuCard(
                    title: "SPEAKER ID",
                    value: "\(inferenceViewModel.speakerID)",
                    detail: selectedSpeakerCount > 1 ? "Choose which speaker slot to use in this multi-speaker model." : "This model has only one speaker, so keep it at 0.",
                    actionLabel: "SET",
                    accent: selectedSpeakerCount > 1 ? AppTheme.knobBlue : nil,
                    options: Array(0...max(selectedSpeakerCount - 1, 0)).map { speakerID in
                        ConsolePickerOption(id: "\(speakerID)", title: "Speaker \(speakerID)", subtitle: speakerID == 0 ? "Default voice slot" : nil)
                    },
                    selectedID: "\(min(inferenceViewModel.speakerID, max(selectedSpeakerCount - 1, 0)))",
                    emptyState: "Speaker 0",
                    compactHeight: true,
                    isEnabled: true,
                    helpText: "Use this only for multi-speaker models. Lower speaker IDs and higher speaker IDs are not 'better' or 'worse' by themselves; they are simply different trained voice slots.",
                    onSelect: { speakerID in
                        guard let parsedSpeakerID = Int(speakerID) else { return }
                        inferenceViewModel.speakerID = parsedSpeakerID
                        batchViewModel.speakerID = parsedSpeakerID
                    }
                )

                ConsolePatchMenuCard(
                    title: "F0 METHOD",
                    value: inferenceViewModel.f0Method.displayName,
                    detail: inferenceViewModel.f0Method.shortDescription,
                    actionLabel: "SET",
                    accent: AppTheme.knobOrange,
                    options: F0Method.allCases.map { method in
                        ConsolePickerOption(id: method.rawValue, title: method.displayName, subtitle: method.pickerDescription)
                    },
                    selectedID: inferenceViewModel.f0Method.rawValue,
                    emptyState: "No F0 methods available",
                    compactHeight: true,
                    isEnabled: true,
                    helpText: "Pitch extraction mode shared by single-file, batch, and live conversion. Open the menu to compare each method's trait, best use case, and tradeoff. RMVPE is the safest default.",
                    onSelect: { methodID in
                        guard let method = F0Method(rawValue: methodID) else { return }
                        inferenceViewModel.f0Method = method
                        batchViewModel.f0Method = method
                        pushRealtimeConfigIfNeeded()
                    }
                )
            }
        }
        .padding(.top, 2)
    }

    private var isModelPickerDisabled: Bool {
        isBootstrapBusy || isCatalogBusy || isModelSelectionBusy
    }

    /// 渲染左侧实时参数机架。
    private func realtimeLabRack(compact: Bool, tight: Bool) -> some View {
        VStack(alignment: .leading, spacing: tight ? 8 : 10) {
            ConsoleSectionHeader(title: "REALTIME LAB", compact: true, action: onResetRealtimeLab)

                ConsolePatchMenuCard(
                    title: "SR MODE",
                    value: realtimeViewModel.sampleRateMode.displayName,
                    detail: realtimeViewModel.sampleRateMode.shortDescription,
                    actionLabel: "SET",
                    accent: AppTheme.knobBlue,
                    options: SampleRateMode.allCases.map { mode in
                        ConsolePickerOption(
                            id: mode.rawValue,
                            title: mode.displayName == "MODEL" ? "Model rate" : "Device rate",
                            subtitle: mode.shortDescription
                        )
                    },
                    selectedID: realtimeViewModel.sampleRateMode.rawValue,
                    emptyState: "No sample rate modes available",
                    compactHeight: true,
                    isEnabled: true,
                    helpText: "Choose whether live conversion follows the model target sample rate or the active device sample rate. Model mode is usually safer for tone consistency; device mode can reduce resampling mismatch with your audio interface.",
                    onSelect: { modeID in
                        guard let mode = SampleRateMode(rawValue: modeID) else { return }
                        realtimeViewModel.sampleRateMode = mode
                        pushRealtimeConfigIfNeeded()
                    }
                )

                ConsoleCompactSliderRow(
                    title: "BUFFER",
                    valueText: "\(decimalString(realtimeViewModel.extraInferenceTime)) S",
                    value: Binding(
                        get: { realtimeViewModel.extraInferenceTime },
                        set: { newValue in
                            realtimeViewModel.extraInferenceTime = newValue
                            pushRealtimeConfigIfNeeded()
                        }
                    ),
                    range: 0...10,
                    step: 0.5,
                    accent: AppTheme.knobOrange,
                    compact: true,
                    helpText: "Extra realtime buffer. Lower values reduce latency, but can cause dropouts or crackle. Higher values improve stability, but increase delay."
                )

                ConsoleCompactSliderRow(
                    title: "CPU",
                    valueText: "\(Int(realtimeViewModel.cpuProcesses)) PROCS",
                    value: Binding(
                        get: { Double(realtimeViewModel.cpuProcesses) },
                        set: { newValue in
                            realtimeViewModel.cpuProcesses = max(1, Int(newValue.rounded()))
                            pushRealtimeConfigIfNeeded()
                        }
                    ),
                    range: 1...Double(max(ProcessInfo.processInfo.processorCount, 1)),
                    step: 1,
                    accent: AppTheme.knobGrey,
                    compact: true,
                    helpText: "How many CPU worker processes the live pipeline may use. Lower values reduce overhead on small machines. Higher values can help throughput, but too high may create scheduling overhead or heat."
                )

                ConsoleCompactSliderRow(
                    title: "GATE",
                    valueText: "\(realtimeViewModel.threshold) DB",
                    value: Binding(
                        get: { Double(realtimeViewModel.threshold) },
                        set: { newValue in
                            realtimeViewModel.threshold = Int(newValue.rounded())
                            pushRealtimeConfigIfNeeded()
                        }
                    ),
                    range: -90...0,
                    step: 1,
                    accent: AppTheme.knobOrange,
                    compact: true,
                    helpText: "Input threshold gate. Lower values keep quiet breaths and room tone. Higher values reject more background noise, but can also cut off soft syllables or word endings."
                )

            ConsoleCompactSliderRow(
                title: "FORMANT",
                valueText: decimalString(realtimeViewModel.formant),
                value: Binding(
                    get: { realtimeViewModel.formant },
                    set: { newValue in
                        realtimeViewModel.formant = newValue
                        pushRealtimeConfigIfNeeded()
                    }
                ),
                range: -12...12,
                step: 0.1,
                accent: AppTheme.knobBlue,
                compact: true,
                helpText: "Formant shift. Lower values darken or thicken tone. Higher values brighten or thin tone. Extreme values can sound artificial, so move in small steps."
            )

            ConsoleCompactSliderRow(
                title: "WINDOW",
                valueText: decimalString(realtimeViewModel.sampleLength),
                value: Binding(
                    get: { realtimeViewModel.sampleLength },
                    set: { newValue in
                        realtimeViewModel.sampleLength = newValue
                        pushRealtimeConfigIfNeeded()
                    }
                ),
                range: 0.05...3.0,
                step: 0.01,
                accent: AppTheme.knobOchre,
                compact: true,
                helpText: "Realtime analysis window length. Lower values feel more responsive, but may wobble more. Higher values sound steadier, but add latency and can smear fast articulation."
            )

            ConsoleCompactSliderRow(
                title: "FADE",
                valueText: decimalString(realtimeViewModel.fadeLength),
                value: Binding(
                    get: { realtimeViewModel.fadeLength },
                    set: { newValue in
                        realtimeViewModel.fadeLength = newValue
                        pushRealtimeConfigIfNeeded()
                    }
                ),
                range: 0...1.0,
                step: 0.01,
                accent: AppTheme.knobGrey,
                compact: true,
                helpText: "Crossfade length between realtime chunks. Lower values can sound sharper but risk clicks at chunk edges. Higher values smooth the joins, but can blur attacks if pushed too far."
            )

            HStack(spacing: 10) {
                ConsoleCompactToggleRow(
                    title: "IN CLEAN",
                    isOn: Binding(
                        get: { realtimeViewModel.inputNoiseReduction },
                        set: { newValue in
                            realtimeViewModel.inputNoiseReduction = newValue
                            pushRealtimeConfigIfNeeded()
                        }
                    ),
                    accent: Color(hex: 0x0984E3),
                    compact: true,
                    helpText: "Reduce noise before the voice conversion stage. Off keeps the raw mic character. On can clean room noise, but may also shave off fine breath detail."
                )
                ConsoleCompactToggleRow(
                    title: "OUT CLEAN",
                    isOn: Binding(
                        get: { realtimeViewModel.outputNoiseReduction },
                        set: { newValue in
                            realtimeViewModel.outputNoiseReduction = newValue
                            pushRealtimeConfigIfNeeded()
                        }
                    ),
                    accent: Color(hex: 0x0984E3),
                    compact: true,
                    helpText: "Reduce noise after conversion. Off keeps the full converted texture. On can reduce hiss, but may dull some high-frequency detail."
                )
                ConsoleCompactToggleRow(
                    title: "SMOOTH",
                    isOn: Binding(
                        get: { realtimeViewModel.usePhaseVocoder },
                        set: { newValue in
                            realtimeViewModel.usePhaseVocoder = newValue
                            pushRealtimeConfigIfNeeded()
                        }
                    ),
                    accent: Color(hex: 0x0984E3),
                    compact: true,
                    helpText: "Use a phase-vocoder style smoothing pass. Off keeps attacks sharper. On can make the output smoother and steadier, but sometimes slightly softer."
                )
            }
        }
    }

    /// 将实时参数格式化为两位小数。
    private func decimalString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    /// 在实时模式运行中推送当前参数改动。
    private func pushRealtimeConfigIfNeeded() {
        guard realtimeViewModel.isRunning else { return }
        Task {
            await realtimeViewModel.configure(
                selectedModelName: selectedModelName,
                selectedIndexPath: inferenceViewModel.effectiveIndexPath,
                inferenceViewModel: inferenceViewModel
            )
        }
    }

    private var contextActions: [ConsoleActionItem] {
        [
            ConsoleActionItem(id: "pth", title: "PTH", systemImage: "folder", action: .openWeights, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "idx", title: "IDX", systemImage: "folder.badge.gearshape", action: .openIndices, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "dir", title: "DIR", systemImage: "folder.fill", action: .chooseBatchInputFolder, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "files", title: "FILES", systemImage: "music.note.list", action: .chooseBatchInputFiles, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "task", title: "TASK", systemImage: "list.bullet.rectangle.portrait", action: .showQueue, isEnabled: true, accent: AppTheme.knobBlue),
            ConsoleActionItem(id: "res", title: "RES", systemImage: "clock.arrow.circlepath", action: .showHistory, isEnabled: true, accent: AppTheme.knobGrey),
            ConsoleActionItem(id: "out", title: "OUT", systemImage: "folder.badge.plus", action: .chooseBatchOutputFolder, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "single", title: "GO", systemImage: "record.circle", action: .convertSingle, isEnabled: engineController.state == .ready && !inferenceViewModel.isRunning, accent: AppTheme.knobOrange),
            ConsoleActionItem(id: "play", title: "PLAY", systemImage: "play.fill", action: .playPreview, isEnabled: inferenceViewModel.outputAudioURL != nil, accent: AppTheme.knobOrange),
            ConsoleActionItem(id: "open", title: "OPEN", systemImage: "folder.badge.waveform", action: .revealOutput, isEnabled: inferenceViewModel.outputAudioURL != nil, accent: nil),
        ]
    }

    private var batchInputLabel: String {
        if let directory = batchViewModel.inputDirectoryURL {
            return directory.lastPathComponent
        }
        if !batchViewModel.inputFileURLs.isEmpty {
            return "\(batchViewModel.inputFileURLs.count) FILES"
        }
        return "NONE"
    }

    /// 提取路径最后一级，避免监视面板显示完整绝对路径。
    private func lastPath(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

private struct ConsoleDeck: View {
    @ObservedObject var engineController: EngineController
    @ObservedObject var inferenceViewModel: InferenceViewModel
    @ObservedObject var batchViewModel: BatchViewModel
    @ObservedObject var realtimeViewModel: RealtimeViewModel
    @ObservedObject var audioPlayer: AudioPreviewPlayer
    let models: [ModelOption]
    let indexPaths: [String]
    let selectedModelName: String?
    let parameterBank: ConsoleParameterBank
    let statusMessage: String
    let lastExecutionSummary: String
    let catalogModelCount: Int
    let catalogIndexCount: Int
    let selectedModelSizeLabel: String
    let selectedIndexSizeLabel: String
    let appMemoryLabel: String
    let engineMemoryLabel: String
    let isNavigating: Bool
    let isBootstrapBusy: Bool
    let isCatalogBusy: Bool
    let isModelSelectionBusy: Bool
    let hasBackgroundTrack: Bool
    let isBackgroundEnabled: Bool
    let backgroundMixLevel: Double
    let isPreparingBackgroundMix: Bool
    let isPersistingBackgroundMix: Bool
    let onSelectParameterBank: (ConsoleParameterBank) -> Void
    let onResetRouting: () -> Void
    let onResetPatchSidecar: () -> Void
    let onResetFaders: () -> Void
    let onToggleBackgroundMix: () -> Void
    let onChangeBackgroundMixLevel: (Double) -> Void
    let onMergeBackgroundMix: () -> Void
    let onContextAction: (ConsoleContextAction) -> Void

    var body: some View {
        GeometryReader { proxy in
            let compactDeck = proxy.size.width < 980
            let veryCompactDeck = proxy.size.width < 760
            let compactTopBar = proxy.size.width < 780
            let shortDeck = proxy.size.height < 820
            let tightDeck = proxy.size.height < 760
            let contentHeight = max(proxy.size.height - (tightDeck ? 36 : 44), 420)
            let actionPadWidth = compactDeck ? 308.0 : 560.0
            let monitorHeight = min(max(contentHeight * (tightDeck ? 0.17 : (shortDeck ? 0.38 : 0.45)), tightDeck ? 132 : 244), shortDeck ? 292 : 384)
            let verticalReserve = tightDeck ? 254.0 : (compactDeck ? 372.0 : 504.0)
            let availableFaderHeight = max(proxy.size.height - monitorHeight - verticalReserve, tightDeck ? 214.0 : 288.0)
            let faderModuleHeight = min(availableFaderHeight, shortDeck ? 292.0 : 352.0)
            let trackHeight = min(max(faderModuleHeight - (tightDeck ? 78 : 118), tightDeck ? 88.0 : 118.0), shortDeck ? 156.0 : 176.0)
            let faderWidth = max(
                veryCompactDeck ? 36 : (compactDeck ? 42 : 62),
                min(
                    (proxy.size.width - actionPadWidth - (compactDeck ? 20 : 44)) / CGFloat(max(faderSpecs.count, 1)),
                    compactDeck ? 60 : 78
                )
            )

            VStack(spacing: tightDeck ? 4 : 6) {
                encoderRow(compact: compactTopBar)
                divider
                utilityStrip(compact: compactDeck, tightHeight: tightDeck)
                monitorPanel(compact: compactDeck, tightHeight: tightDeck, panelHeight: monitorHeight)
                faderModule(
                    trackHeight: trackHeight,
                    faderWidth: faderWidth,
                    compact: compactDeck,
                    veryCompact: veryCompactDeck,
                    tightHeight: tightDeck,
                    actionPadWidth: actionPadWidth
                )
                    .padding(.top, tightDeck ? 2 : 4)
                    .frame(height: faderModuleHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, tightDeck ? 0 : (compactDeck ? 28 : 34))
            .padding(.bottom, tightDeck ? 10 : 18)
            .padding(.leading, compactDeck ? 22 : 38)
            .padding(.trailing, compactDeck ? 18 : 36)
        }
    }

    /// 渲染顶部路由条、动作旋钮和主输出旋钮。
    private func encoderRow(compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 12) {
                    topRouteStrip(compact: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .top, spacing: 18) {
                        ForEach(topActionItems) { item in
                            Button {
                                onContextAction(item.action)
                            } label: {
                                ConsoleActionKnob(item: item, compact: false)
                            }
                            .buttonStyle(.plain)
                            .disabled(!item.isEnabled)
                            .opacity(item.isEnabled ? 1 : 0.46)
                        }

                        if let master = knobSpecs.last {
                            ConsoleKnob(spec: master, compact: true, extraCompact: false)
                        }

                        Spacer(minLength: 0)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    topRouteStrip(compact: false)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .top, spacing: 24) {
                        ForEach(topActionItems) { item in
                            Button {
                                onContextAction(item.action)
                            } label: {
                                ConsoleActionKnob(item: item, compact: false)
                            }
                            .buttonStyle(.plain)
                            .disabled(!item.isEnabled)
                            .opacity(item.isEnabled ? 1 : 0.46)
                        }

                        Spacer(minLength: 10)

                        if let master = knobSpecs.last {
                            ConsoleKnob(spec: master, compact: true, extraCompact: false)
                        }
                    }
                }
            }
        }
    }

    /// 渲染顶部的 host、input、output、monitor 路由条。
    private func topRouteStrip(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            ConsoleSectionHeader(title: "ROUTE", compact: true, action: onResetRouting)

            Group {
                if compact {
                    HStack(spacing: 16) {
                        routingHostControl
                        routingInputControl
                        routingOutputControl
                        routingMonitorControl
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 14) {
                        routingHostControl.frame(maxWidth: .infinity, alignment: .leading)
                        routingInputControl.frame(maxWidth: .infinity, alignment: .leading)
                        routingOutputControl.frame(maxWidth: .infinity, alignment: .leading)
                        routingMonitorControl.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var topActionItems: [ConsoleActionItem] {
        [
            ConsoleActionItem(id: "boot", title: "BOOT", systemImage: "bolt.fill", action: .startEngine, isEnabled: engineController.state != .ready && engineController.state != .starting && !isTopTransportBusy, accent: AppTheme.knobBlue),
            ConsoleActionItem(id: "sync", title: "SYNC", systemImage: "arrow.clockwise", action: .refreshModels, isEnabled: engineController.state == .ready && !isTopTransportBusy, accent: AppTheme.knobOchre),
            ConsoleActionItem(id: "uvr", title: "UVR", systemImage: "waveform.badge.magnifyingglass", action: .showUVR, isEnabled: engineController.state == .ready, accent: AppTheme.knobOrange),
            ConsoleActionItem(id: "onnx", title: "ONNX", systemImage: "point.3.connected.trianglepath.dotted", action: .showONNX, isEnabled: engineController.state == .ready, accent: AppTheme.knobBlue),
            ConsoleActionItem(id: "ckpt", title: "CKPT", systemImage: "cpu", action: .showCheckpointTools, isEnabled: engineController.state == .ready, accent: AppTheme.knobOchre),
            ConsoleActionItem(id: "audio", title: "AUDIO", systemImage: "speaker.wave.2.fill", action: .refreshRealtimeDevices, isEnabled: engineController.state == .ready, accent: AppTheme.knobGrey),
            ConsoleActionItem(id: "asset", title: "ASSET", systemImage: "shippingbox", action: .showAssetReport, isEnabled: true, accent: AppTheme.knobGrey),
            ConsoleActionItem(id: "help", title: "HELP", systemImage: "questionmark.circle", action: .showFAQ, isEnabled: true, accent: AppTheme.knobBlue),
            ConsoleActionItem(id: "run", title: realtimeViewModel.isRunning ? "STOP" : "LIVE", systemImage: realtimeViewModel.isRunning ? "stop.fill" : "play.fill", action: realtimeViewModel.isRunning ? .stopRealtime : .startRealtime, isEnabled: engineController.state == .ready && selectedModelName != nil && !realtimeMissingRoute && !isModelSelectionBusy, accent: realtimeViewModel.isRunning ? AppTheme.knobGrey : AppTheme.knobOrange),
        ]
    }

    private var isTopTransportBusy: Bool {
        isBootstrapBusy || isCatalogBusy
    }

    private var realtimeMissingRoute: Bool {
        realtimeViewModel.selectedInputDevice == nil || realtimeViewModel.selectedOutputDevice == nil
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(height: 1)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(height: 1)
                    .offset(y: -1)
            }
    }

    /// 预留顶部工具条占位，当前保持空实现以维持布局节奏。
    private func utilityStrip(compact: Bool, tightHeight: Bool) -> some View {
        EmptyView()
    }

    /// 渲染中部黑色监视屏及其摘要信息。
    private func monitorPanel(compact: Bool, tightHeight: Bool, panelHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: tightHeight ? 3 : 12) {
            HStack {
                Text("VOICE PATCH")
                Spacer()
                Text(statusMessage.uppercased())
                    .minimumScaleFactor(compact ? 0.58 : 0.7)
                    .lineLimit(1)
                    .frame(maxWidth: compact ? 180 : 280, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.82))

            if tightHeight {
                monitorWaveform(tightHeight: true)
                    .frame(height: 58)

                compactMonitorSummary
            } else {
                Group {
                    if compact {
                        VStack(alignment: .leading, spacing: 10) {
                            monitorWaveform(tightHeight: false)
                                .frame(maxWidth: .infinity)
                                .frame(height: 84)

                            monitorSummaryGrid(compact: true)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            monitorWaveform(tightHeight: false)
                                .frame(maxWidth: .infinity)
                                .frame(height: 198)

                            monitorSummaryGrid(compact: false)
                                .frame(width: 286, alignment: .leading)
                        }
                    }
                }
            }

            monitorMetricsBar(tightHeight: tightHeight)
        }
        .padding(tightHeight ? 7 : 14)
        .frame(maxWidth: .infinity, minHeight: panelHeight, maxHeight: panelHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hex: 0x080808))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.black.opacity(0.86), lineWidth: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    /// 在单文件转换页优先展示产物波形与播放控制，其余页面保留演示波形。
    @ViewBuilder
    private func monitorWaveform(tightHeight: Bool) -> some View {
        ConsolePreviewWaveformPanel(
            audioPlayer: audioPlayer,
            isRunning: inferenceViewModel.isRunning,
            tightHeight: tightHeight,
            hasBackgroundTrack: hasBackgroundTrack,
            isBackgroundEnabled: isBackgroundEnabled,
            backgroundMixLevel: backgroundMixLevel,
            isPreparingBackgroundMix: isPreparingBackgroundMix,
            isPersistingBackgroundMix: isPersistingBackgroundMix,
            onToggleBackgroundMix: onToggleBackgroundMix,
            onChangeBackgroundMixLevel: onChangeBackgroundMixLevel,
            onMergeBackgroundMix: onMergeBackgroundMix
        )
    }

    /// 将监视摘要按双列网格排布。
    private func monitorSummaryGrid(compact: Bool) -> some View {
        let items: [(String, String)] = [
            ("MODEL", selectedModelName ?? "NONE"),
            ("INPUT", realtimeViewModel.selectedInputDevice ?? "NONE"),
            ("OUTPUT", realtimeViewModel.selectedOutputDevice ?? "NONE"),
            ("INDEX", inferenceViewModel.selectedIndexPath.map(lastPath) ?? "AUTO"),
            ("BANK", parameterBank.title.uppercased()),
            ("MONITOR", realtimeViewModel.monitorMode == .outputConverted ? "VC" : "INPUT"),
            ("RATE", realtimeViewModel.sampleRate > 0 ? "\(realtimeViewModel.sampleRate)" : "—"),
            ("DELAY", "\(realtimeViewModel.delayTimeMs)MS"),
            ("INFER", "\(realtimeViewModel.inferTimeMs)MS"),
        ]

        return LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: compact ? 96 : 122), spacing: compact ? 10 : 16, alignment: .leading),
                GridItem(.flexible(minimum: compact ? 96 : 122), spacing: compact ? 10 : 16, alignment: .leading),
            ],
            alignment: .leading,
            spacing: compact ? 6 : 8
        ) {
            ForEach(items.indices, id: \.self) { index in
                monitorRow(items[index].0, items[index].1, compact: compact)
            }
        }
    }

    /// 渲染单行监视读数。
    private func monitorRow(_ label: String, _ value: String, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.56))
            Spacer()
            Text(value.uppercased())
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(1)
        }
        .font(.system(size: compact ? 9 : 10, weight: .medium, design: .monospaced))
    }

    private var compactMonitorSummary: some View {
        HStack(spacing: 12) {
            compactMonitorToken("MODEL", selectedModelName?.replacingOccurrences(of: ".pth", with: "") ?? "NONE", accent: selectedModelName == nil ? nil : AppTheme.knobOrange)
            compactMonitorToken("INPUT", realtimeViewModel.selectedInputDevice ?? "NONE", accent: realtimeViewModel.selectedInputDevice == nil ? nil : AppTheme.knobBlue)
            compactMonitorToken("OUTPUT", realtimeViewModel.selectedOutputDevice ?? "NONE", accent: realtimeViewModel.selectedOutputDevice == nil ? nil : AppTheme.knobOchre)
            compactMonitorToken("BANK", parameterBank.title.uppercased(), accent: parameterBank == .single ? AppTheme.knobOrange : AppTheme.knobBlue)
            compactMonitorToken("MON", realtimeViewModel.monitorMode == .outputConverted ? "VC" : "INPUT", accent: realtimeViewModel.isRunning ? AppTheme.knobOrange : nil)
            Spacer(minLength: 0)
        }
    }

    /// 渲染紧凑模式下的监视摘要 token。
    private func compactMonitorToken(_ label: String, _ value: String, accent: Color?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
            Text(value.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent ?? Color.white.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
    }

    /// 渲染监视屏底部的核心指标条。
    private func monitorMetricsBar(tightHeight: Bool) -> some View {
        let items = monitorMetricItems

        return VStack(alignment: .leading, spacing: tightHeight ? 5 : 7) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            Group {
                if tightHeight {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 68), spacing: 10, alignment: .leading),
                            GridItem(.flexible(minimum: 68), spacing: 10, alignment: .leading),
                            GridItem(.flexible(minimum: 68), spacing: 10, alignment: .leading),
                        ],
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(items.indices, id: \.self) { index in
                            monitorMetricItem(
                                label: items[index].label,
                                value: items[index].value,
                                accent: items[index].accent,
                                compact: true
                            )
                        }
                    }
                } else {
                    HStack(spacing: 14) {
                        ForEach(items.indices, id: \.self) { index in
                            monitorMetricItem(
                                label: items[index].label,
                                value: items[index].value,
                                accent: items[index].accent,
                                compact: false
                            )
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var monitorMetricItems: [(label: String, value: String, accent: Color?)] {
        [
            ("MODEL", selectedModelSizeLabel, selectedModelName == nil ? nil : AppTheme.knobOrange),
            ("APP", appMemoryLabel, AppTheme.knobBlue),
            ("ENGINE", engineMemoryLabel, engineController.state == .ready ? AppTheme.ledGreen : nil),
            ("DELAY", "\(realtimeViewModel.delayTimeMs) MS", realtimeViewModel.isRunning ? AppTheme.knobOrange : nil),
            ("INFER", "\(realtimeViewModel.inferTimeMs) MS", realtimeViewModel.isRunning ? AppTheme.knobBlue : nil),
            ("PORT", engineController.port.map(String.init) ?? "—", nil),
        ]
    }

    /// 渲染单个监视指标读数。
    private func monitorMetricItem(label: String, value: String, accent: Color?, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            Text(label)
                .font(.system(size: compact ? 7 : 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.36))
                .tracking(compact ? 0.2 : 0.4)
            Text(value.uppercased())
                .font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced))
                .foregroundStyle(accent ?? Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var batchInputLabel: String {
        if let directory = batchViewModel.inputDirectoryURL {
            return directory.lastPathComponent
        }
        if !batchViewModel.inputFileURLs.isEmpty {
            return "\(batchViewModel.inputFileURLs.count) FILES"
        }
        return "NONE"
    }

    /// 提取路径最后一级，便于在 deck 侧摘要中显示。
    private func lastPath(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private var contextActions: [ConsoleActionItem] {
        [
            ConsoleActionItem(id: "pth", title: "PTH", systemImage: "folder", action: .openWeights, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "idx", title: "IDX", systemImage: "folder.badge.gearshape", action: .openIndices, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "dir", title: "DIR", systemImage: "folder.fill", action: .chooseBatchInputFolder, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "files", title: "FILES", systemImage: "music.note.list", action: .chooseBatchInputFiles, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "task", title: "TASK", systemImage: "list.bullet.rectangle.portrait", action: .showQueue, isEnabled: true, accent: AppTheme.knobBlue),
            ConsoleActionItem(id: "res", title: "RES", systemImage: "clock.arrow.circlepath", action: .showHistory, isEnabled: true, accent: AppTheme.knobGrey),
            ConsoleActionItem(id: "out", title: "OUT", systemImage: "folder.badge.plus", action: .chooseBatchOutputFolder, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "single", title: "GO", systemImage: "record.circle", action: .convertSingle, isEnabled: engineController.state == .ready && !inferenceViewModel.isRunning, accent: AppTheme.knobOrange),
            ConsoleActionItem(id: "play", title: "PLAY", systemImage: "play.fill", action: .playPreview, isEnabled: inferenceViewModel.outputAudioURL != nil, accent: AppTheme.knobOrange),
            ConsoleActionItem(id: "open", title: "OPEN", systemImage: "folder.badge.waveform", action: .revealOutput, isEnabled: inferenceViewModel.outputAudioURL != nil, accent: nil),
            ConsoleActionItem(id: "unld", title: "UNLD", systemImage: "eject.fill", action: .unloadModel, isEnabled: selectedModelName != nil && !isModelSelectionBusy, accent: AppTheme.knobGrey),
            ConsoleActionItem(id: "cache", title: "CACHE", systemImage: "memorychip", action: .releaseRuntimeCaches, isEnabled: engineController.state == .ready, accent: AppTheme.knobBlue),
        ]
    }

    /// 组合底部动作面板和推子区。
    private func faderModule(trackHeight: CGFloat, faderWidth: CGFloat, compact: Bool, veryCompact: Bool, tightHeight: Bool, actionPadWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: compact ? 8 : 12) {
                deckActionPad(compact: compact, tight: tightHeight, width: actionPadWidth)
                    .frame(width: actionPadWidth, alignment: .leading)
                faderStack(trackHeight: trackHeight, faderWidth: faderWidth, compact: compact, tightHeight: tightHeight)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    /// 渲染底部动作按钮矩阵及 patch 侧栏。
    private func deckActionPad(compact: Bool, tight: Bool, width: CGFloat) -> some View {
        let buttonSize: CGFloat = tight ? 36 : (compact ? 36 : 42)
        let actionColumnCount = tight ? 2 : (compact ? 4 : contextActions.count)
        let actionColumnSpacing = tight ? 8.0 : (compact ? 8.0 : 10.0)
        let actionGridWidth = (CGFloat(actionColumnCount) * buttonSize) + (CGFloat(max(actionColumnCount - 1, 0)) * actionColumnSpacing)
        let actionRows: [[ConsoleActionItem]] = stride(from: 0, to: contextActions.count, by: actionColumnCount).map { start in
            let end = min(start + actionColumnCount, contextActions.count)
            return Array(contextActions[start..<end])
        }
        return VStack(alignment: .leading, spacing: tight ? 5 : 7) {
            patchSidecar(compact: compact)

            Group {
                if !compact && !tight {
                    HStack(spacing: actionColumnSpacing) {
                        ForEach(contextActions) { item in
                            contextActionButton(item, buttonSize: buttonSize, tight: tight)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(alignment: .leading, spacing: tight ? 6 : 12) {
                        ForEach(Array(actionRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 0) {
                                ForEach(0..<actionColumnCount, id: \.self) { column in
                                    Group {
                                        if column < row.count {
                                            contextActionButton(row[column], buttonSize: buttonSize, tight: tight)
                                        } else {
                                            Color.clear
                                                .frame(width: buttonSize, height: buttonSize)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: compact ? width : actionGridWidth, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(.bottom, tight ? 2 : 4)
    }

    /// 渲染单个底部上下文动作按钮。
    @ViewBuilder
    private func contextActionButton(_ item: ConsoleActionItem, buttonSize: CGFloat, tight: Bool) -> some View {
        Button {
            onContextAction(item.action)
        } label: {
            if item.title.count <= 3 {
                VStack(spacing: tight ? 2 : 3) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: tight ? 10 : 11, weight: .semibold))
                    Text(item.title)
                        .font(.system(size: tight ? 8 : 9, weight: .medium, design: .rounded))
                }
                .frame(width: buttonSize, height: buttonSize)
            } else {
                Text(item.title)
                    .font(.system(size: tight ? 8 : 9, weight: .medium, design: .rounded))
                    .frame(width: buttonSize, height: buttonSize)
            }
        }
        .buttonStyle(ConsoleRoundButtonStyle(accent: item.accent))
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.48)
    }

    /// 渲染多通道推子列。
    private func faderStack(trackHeight: CGFloat, faderWidth: CGFloat, compact: Bool, tightHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: tightHeight ? 4 : 10) {
            ConsoleSectionHeader(title: "FADERS", compact: true, action: onResetFaders)

            HStack(alignment: .bottom, spacing: compact ? max(6, faderWidth * 0.08) : max(16, faderWidth * 0.14)) {
                if !compact {
                    Spacer(minLength: 0)
                }
                ForEach(faderSpecs) { spec in
                    ConsoleFader(spec: spec, trackHeight: trackHeight, width: faderWidth, compactHeight: tightHeight)
                }
                if !compact {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    /// 渲染参数库和索引文件的 patch 侧栏。
    private func patchSidecar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            ConsoleSectionHeader(title: "PATCH CONFIG", compact: true, action: onResetPatchSidecar)

            HStack(alignment: .top, spacing: compact ? 10 : 12) {
                ConsolePatchMenuCard(
                    title: "PARAM BANK",
                    value: parameterBank.title.uppercased(),
                    detail: parameterBank.detail,
                    actionLabel: "SET",
                    accent: parameterBank == .single ? AppTheme.knobOrange : AppTheme.knobBlue,
                    options: ConsoleParameterBank.allCases.map { bank in
                        ConsolePickerOption(id: bank.rawValue, title: bank.title.uppercased(), subtitle: bank.detail)
                    },
                    selectedID: parameterBank.rawValue,
                    emptyState: "Choose parameter bank",
                    compactHeight: true,
                    isEnabled: true,
                    helpText: "Choose whether the bottom faders edit one-file conversion or batch conversion parameters. This does not change the model; it only changes which parameter set the faders write into.",
                    onSelect: { bankID in
                        guard let bank = ConsoleParameterBank(rawValue: bankID) else { return }
                        onSelectParameterBank(bank)
                    }
                )
                .frame(maxWidth: .infinity, minHeight: compact ? 72 : 74, alignment: .leading)

                ConsolePatchMenuCard(
                    title: "INDEX FILE",
                    value: inferenceViewModel.customIndexURL?.lastPathComponent ?? inferenceViewModel.selectedIndexPath.map(lastPath) ?? "Optional / auto",
                    detail: inferenceViewModel.customIndexURL == nil ? (indexPaths.isEmpty ? "Optional. Skip it if the voice already sounds right." : "\(indexPaths.count) indexes available. Auto-match if needed.") : "External index override is active.",
                    actionLabel: "PICK",
                    accent: inferenceViewModel.selectedIndexPath == nil ? nil : AppTheme.knobOchre,
                    options: (inferenceViewModel.customIndexURL.map {
                        [ConsolePickerOption(id: "__custom_active__", title: "Custom override", subtitle: $0.lastPathComponent)]
                    } ?? []) + [
                        ConsolePickerOption(id: "__choose_custom__", title: "Choose external index", subtitle: "Use a custom .index file or compatible path"),
                    ] + (inferenceViewModel.customIndexURL == nil ? [] : [
                        ConsolePickerOption(id: "__clear_custom__", title: "Clear override", subtitle: "Return to catalog or auto index")
                    ]) + [
                        ConsolePickerOption(id: "__auto_optional__", title: "No index", subtitle: "Optional, auto-match if available")
                    ] + indexPaths.map {
                        ConsolePickerOption(id: $0, title: lastPath($0), subtitle: nil)
                    },
                    selectedID: inferenceViewModel.customIndexURL != nil ? "__custom_active__" : (inferenceViewModel.selectedIndexPath ?? "__auto_optional__"),
                    emptyState: "No index needed",
                    compactHeight: true,
                    isEnabled: true,
                    helpText: "Indexes can preserve more target voice color. Lower index use sounds closer to raw conversion. Higher index use sounds more like the trained target, but can exaggerate artifacts if the index does not match well.",
                    onSelect: { selection in
                        switch selection {
                        case "__choose_custom__":
                            onContextAction(.chooseCustomIndexFile)
                        case "__clear_custom__":
                            onContextAction(.clearCustomIndexFile)
                        case "__custom_active__":
                            break
                        case "__auto_optional__":
                            inferenceViewModel.customIndexURL = nil
                            batchViewModel.customIndexURL = nil
                            inferenceViewModel.selectedIndexPath = nil
                            batchViewModel.selectedIndexPath = nil
                        default:
                            inferenceViewModel.customIndexURL = nil
                            batchViewModel.customIndexURL = nil
                            inferenceViewModel.selectedIndexPath = selection
                            batchViewModel.selectedIndexPath = selection
                        }
                    }
                )
                .frame(maxWidth: .infinity, minHeight: compact ? 72 : 74, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routingHostControl: some View {
        ConsoleInlineRouteControl(
            title: "HOST",
            value: realtimeViewModel.selectedHostapi ?? "AUTO",
            accent: AppTheme.knobBlue,
            options: realtimeViewModel.hostapis.map { ConsolePickerOption(id: $0, title: $0, subtitle: nil) },
            selectedID: realtimeViewModel.selectedHostapi,
            emptyState: "No host APIs",
            compactHeight: true
        ) { hostapi in
            realtimeViewModel.selectedHostapi = hostapi
            Task {
                await realtimeViewModel.configure(
                    selectedModelName: selectedModelName,
                    selectedIndexPath: inferenceViewModel.effectiveIndexPath,
                    inferenceViewModel: inferenceViewModel
                )
                onContextAction(.refreshRealtimeDevices)
            }
        }
    }

    private var routingInputControl: some View {
        ConsoleInlineRouteControl(
            title: "INPUT",
            value: realtimeViewModel.selectedInputDevice ?? "NONE",
            accent: AppTheme.knobBlue,
            options: realtimeViewModel.inputDevices.map { ConsolePickerOption(id: $0, title: $0, subtitle: nil) },
            selectedID: realtimeViewModel.selectedInputDevice,
            emptyState: "No input devices",
            compactHeight: true
        ) { inputDevice in
            realtimeViewModel.selectedInputDevice = inputDevice
            Task {
                await realtimeViewModel.configure(
                    selectedModelName: selectedModelName,
                    selectedIndexPath: inferenceViewModel.effectiveIndexPath,
                    inferenceViewModel: inferenceViewModel
                )
            }
        }
    }

    private var routingOutputControl: some View {
        ConsoleInlineRouteControl(
            title: "OUTPUT",
            value: realtimeViewModel.selectedOutputDevice ?? "NONE",
            accent: AppTheme.knobOchre,
            options: realtimeViewModel.outputDevices.map { ConsolePickerOption(id: $0, title: $0, subtitle: nil) },
            selectedID: realtimeViewModel.selectedOutputDevice,
            emptyState: "No output devices",
            compactHeight: true
        ) { outputDevice in
            realtimeViewModel.selectedOutputDevice = outputDevice
            Task {
                await realtimeViewModel.configure(
                    selectedModelName: selectedModelName,
                    selectedIndexPath: inferenceViewModel.effectiveIndexPath,
                    inferenceViewModel: inferenceViewModel
                )
            }
        }
    }

    private var routingMonitorControl: some View {
        ConsoleInlineRouteControl(
            title: "MON",
            value: realtimeViewModel.monitorMode.displayName,
            accent: AppTheme.knobOrange,
            options: RealtimeMonitorMode.allCases.map { mode in
                ConsolePickerOption(id: mode.rawValue, title: mode.displayName == "VC" ? "Converted voice" : "Input monitor", subtitle: mode.shortDescription)
            },
            selectedID: realtimeViewModel.monitorMode.rawValue,
            emptyState: "No monitor modes",
            compactHeight: true
        ) { modeRawValue in
            guard let mode = RealtimeMonitorMode(rawValue: modeRawValue) else { return }
            realtimeViewModel.monitorMode = mode
            Task {
                await realtimeViewModel.configure(
                    selectedModelName: selectedModelName,
                    selectedIndexPath: inferenceViewModel.effectiveIndexPath,
                    inferenceViewModel: inferenceViewModel
                )
            }
        }
    }

    private var knobSpecs: [ConsoleControlSpec] {
        [
            ConsoleControlSpec(id: "pitch", title: "\(parameterBank.title.uppercased()) PIT", shortTitle: "PIT", helpText: "Pitch shift in semitones for the current parameter bank. Lower values push the voice down and can make it heavier. Higher values push it up and can make it brighter or thinner.", color: parameterBank == .single ? AppTheme.knobBlue : AppTheme.knobOrange, value: parameterTranspose, range: -24...24, step: 1, isInteractive: true, formatter: integerString),
            ConsoleControlSpec(id: "index", title: "\(parameterBank.title.uppercased()) IDX", shortTitle: "IDX", helpText: "How strongly the index file should influence the current conversion bank. Lower values lean toward the raw model output. Higher values lean toward the indexed target identity, but mismatched indexes can sound brittle.", color: AppTheme.knobOchre, value: parameterIndexRate, range: 0...1, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "guard", title: "\(parameterBank.title.uppercased()) GRD", shortTitle: "GRD", helpText: "Protection amount that keeps consonants and noisy edges from over-converting. Lower values let the model convert more aggressively. Higher values keep more of the source articulation and reduce tearing.", color: AppTheme.knobGrey, value: parameterProtect, range: 0...0.5, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "rms", title: "\(parameterBank.title.uppercased()) RMS", shortTitle: "RMS", helpText: "Loudness mix ratio between the source and converted result for the current bank. Lower values keep the converted level behavior more directly. Higher values preserve more source loudness contour.", color: parameterBank == .single ? AppTheme.knobOrange : AppTheme.knobBlue, value: parameterRMSMixRate, range: 0...1, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "master", title: "MASTER", shortTitle: "MST", helpText: "Read-only activity meter for the current app state.", color: AppTheme.knobWhite, value: .constant(normalizedActivity), range: 0...1, step: 0.01, isInteractive: false, formatter: percentString),
        ]
    }

    private var faderSpecs: [ConsoleControlSpec] {
        [
            ConsoleControlSpec(id: "pitch", title: "PITCH", shortTitle: parameterBank == .single ? "S-P" : "B-P", helpText: "Pitch shift in semitones for the \(parameterBank.title.lowercased()) workflow. Lower makes the voice deeper. Higher makes it brighter or younger, but extreme values can sound synthetic.", color: AppTheme.knobWhite, value: parameterTranspose, range: -24...24, step: 1, isInteractive: true, formatter: integerString),
            ConsoleControlSpec(id: "index", title: "INDEX", shortTitle: parameterBank == .single ? "S-I" : "B-I", helpText: "Index blend amount for the \(parameterBank.title.lowercased()) workflow. Lower is safer and cleaner. Higher usually increases target identity, but a mismatched index can create metallic or brittle artifacts.", color: AppTheme.knobWhite, value: parameterIndexRate, range: 0...1, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "filter", title: "FILTER", shortTitle: parameterBank == .single ? "S-F" : "B-F", helpText: "Median filter radius for smoothing pitch before conversion. Lower keeps fast pitch movement and vibrato. Higher smooths jumps and wobble, but can flatten expressive pitch detail.", color: AppTheme.knobWhite, value: parameterFilterRadius, range: 0...7, step: 1, isInteractive: true, formatter: integerString),
            ConsoleControlSpec(id: "sample", title: "RESAMP", shortTitle: parameterBank == .single ? "S-R" : "B-R", helpText: "Optional output resample target. Lower or near-zero values keep the original output rate. Higher values force a new sample rate and may help compatibility, but can add another resampling stage.", color: AppTheme.knobWhite, value: parameterResampleSR, range: 0...48_000, step: 100, isInteractive: true, formatter: integerString),
            ConsoleControlSpec(id: "rms", title: "RMS", shortTitle: parameterBank == .single ? "S-M" : "B-M", helpText: "Loudness blend amount for the \(parameterBank.title.lowercased()) workflow. Lower values let the converted audio define dynamics more directly. Higher values preserve more of the source loudness envelope.", color: AppTheme.knobWhite, value: parameterRMSMixRate, range: 0...1, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "protect", title: "GUARD", shortTitle: parameterBank == .single ? "S-G" : "B-G", helpText: "Protection amount that reduces brittle consonants or over-conversion artifacts. Lower values sound more fully converted. Higher values keep more source texture and can reduce tearing or hiss on consonants.", color: AppTheme.knobWhite, value: parameterProtect, range: 0...0.5, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "batch", title: "QUEUE", shortTitle: "QUE", helpText: "Read-only indicator showing whether batch input files are ready.", color: AppTheme.knobWhite, value: .constant(batchViewModel.inputDirectoryURL != nil || !batchViewModel.inputFileURLs.isEmpty ? 1 : 0.15), range: 0...1, step: 0.01, isInteractive: false, formatter: percentString),
            ConsoleControlSpec(id: "preview", title: "PLAY", shortTitle: "PLY", helpText: "Read-only indicator showing whether a previewable output is available.", color: AppTheme.knobWhite, value: .constant(inferenceViewModel.outputAudioURL == nil ? 0.15 : 1), range: 0...1, step: 0.01, isInteractive: false, formatter: percentString),
        ]
    }

    private var parameterTranspose: Binding<Double> {
        parameterBank == .single ? $inferenceViewModel.transpose : $batchViewModel.transpose
    }

    private var parameterIndexRate: Binding<Double> {
        parameterBank == .single ? $inferenceViewModel.indexRate : $batchViewModel.indexRate
    }

    private var parameterFilterRadius: Binding<Double> {
        parameterBank == .single ? $inferenceViewModel.filterRadius : $batchViewModel.filterRadius
    }

    private var parameterResampleSR: Binding<Double> {
        parameterBank == .single ? $inferenceViewModel.resampleSR : $batchViewModel.resampleSR
    }

    private var parameterRMSMixRate: Binding<Double> {
        parameterBank == .single ? $inferenceViewModel.rmsMixRate : $batchViewModel.rmsMixRate
    }

    private var parameterProtect: Binding<Double> {
        parameterBank == .single ? $inferenceViewModel.protect : $batchViewModel.protect
    }

    private var normalizedActivity: Double {
        if inferenceViewModel.isRunning || batchViewModel.isRunning {
            return 1
        }
        if realtimeViewModel.isRunning {
            return 0.92
        }
        if inferenceViewModel.outputAudioURL != nil {
            return 0.76
        }
        if batchViewModel.outputDirectoryURL != nil {
            return 0.62
        }
        return engineController.state == .ready ? 0.48 : 0.18
    }

    private var portLevel: Double {
        guard let port = engineController.port else { return 0.1 }
        return min(max(Double(port - 7865) / 10.0, 0), 1)
    }

    /// 将推子值格式化为整数文本。
    private func integerString(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    /// 将推子值格式化为两位小数文本。
    private func decimalString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    /// 将 0...1 数值格式化为百分比文本。
    private func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

}

private struct ConsoleKnob: View {
    let spec: ConsoleControlSpec
    var compact = false
    var extraCompact = false
    @State private var dragOrigin: Double?

    var body: some View {
        VStack(spacing: compact ? (extraCompact ? 3 : 8) : 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xF8F8FA), Color(hex: 0xD7D9DE)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.2)
                    )
                    .shadow(color: AppTheme.contactShadow.opacity(0.18), radius: 1.5, y: 1)
                    .shadow(color: AppTheme.hardShadow.opacity(0.24), radius: 6, y: 5)

                Circle()
                    .fill(spec.color)
                    .padding(compact ? (extraCompact ? 7 : 9) : 11)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            .padding(compact ? (extraCompact ? 7 : 9) : 11)
                    )
                    .shadow(color: Color.black.opacity(0.30), radius: 2.5, y: 2)
                    .shadow(color: Color.black.opacity(0.12), radius: 5, y: 4)
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.30), Color.black.opacity(0.12)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(compact ? (extraCompact ? 7 : 9) : 11)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.72))
                            .frame(width: 3.5, height: compact ? (extraCompact ? 6 : 10) : 12)
                            .offset(y: compact ? (extraCompact ? -7 : -11) : -15)
                            .rotationEffect(.degrees(rotationDegrees))
                    }
            }
            .frame(width: compact ? (extraCompact ? 30 : 48) : 66, height: compact ? (extraCompact ? 30 : 48) : 66)
            .gesture(knobGesture)

            VStack(spacing: 2) {
                Text(spec.title.uppercased())
                    .font(.system(size: compact ? (extraCompact ? 5 : 9) : 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.labelInk)
                Text(spec.displayValue())
                    .font(.system(size: compact ? (extraCompact ? 5 : 9) : 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: compact ? (extraCompact ? 34 : 60) : 76)
        .opacity(spec.isInteractive ? 1 : 0.88)
    }

    private var rotationDegrees: Double {
        let fraction = normalizedValue
        return -135 + (fraction * 270)
    }

    private var normalizedValue: Double {
        guard spec.range.upperBound > spec.range.lowerBound else { return 0 }
        return (spec.value.wrappedValue - spec.range.lowerBound) / (spec.range.upperBound - spec.range.lowerBound)
    }

    private var knobGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard spec.isInteractive else { return }
                if dragOrigin == nil {
                    dragOrigin = spec.value.wrappedValue
                }
                guard let dragOrigin else { return }
                let delta = Double(-gesture.translation.height) / 140.0 * (spec.range.upperBound - spec.range.lowerBound)
                spec.value.wrappedValue = quantized(dragOrigin + delta)
            }
            .onEnded { _ in
                dragOrigin = nil
            }
    }

    /// 按步进和取值范围收敛旋钮拖拽值。
    private func quantized(_ value: Double) -> Double {
        let stepped = (value / spec.step).rounded() * spec.step
        return min(max(stepped, spec.range.lowerBound), spec.range.upperBound)
    }
}

private struct ConsoleHeaderAction: View {
    let item: ConsoleActionItem

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xF9F9FA), Color(hex: 0xD7D9DE)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.1)
                    )
                    .shadow(color: AppTheme.contactShadow.opacity(0.16), radius: 1.2, y: 1)
                    .shadow(color: AppTheme.hardShadow.opacity(0.22), radius: 5, y: 4)

                Circle()
                    .fill(item.accent ?? AppTheme.knobWhite)
                    .padding(10)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            .padding(10)
                    )
                    .shadow(color: Color.black.opacity(0.28), radius: 2, y: 2)
                    .shadow(color: Color.black.opacity(0.10), radius: 4, y: 4)
                    .overlay {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
            }
            .frame(width: 48, height: 48)

            Text(item.title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)
        }
        .frame(width: 56)
    }
}

private struct ConsoleActionKnob: View {
    let item: ConsoleActionItem
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 2 : 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xF8F8FA), Color(hex: 0xD7D9DE)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.2)
                    )
                    .shadow(color: AppTheme.contactShadow.opacity(0.18), radius: 1.5, y: 1)
                    .shadow(color: AppTheme.hardShadow.opacity(0.24), radius: 6, y: 5)

                Circle()
                    .fill(item.accent ?? AppTheme.knobWhite)
                    .padding(compact ? 6 : 8)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            .padding(compact ? 6 : 8)
                    )
                    .shadow(color: Color.black.opacity(0.30), radius: 2.5, y: 2)
                    .shadow(color: Color.black.opacity(0.12), radius: 5, y: 4)
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.30), Color.black.opacity(0.12)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(compact ? 6 : 8)
                    }
                    .overlay {
                        Image(systemName: item.systemImage)
                            .font(.system(size: compact ? 8 : 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
            }
            .frame(width: compact ? 26 : 46, height: compact ? 26 : 46)

            Text(item.title)
                .font(.system(size: compact ? 5 : 7, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)
        }
        .frame(width: compact ? 30 : 50)
    }
}

private enum InlineHelpPlacement {
    case belowLeading
    case aboveLeading
}

private struct HelpTooltipPayload: Equatable {
    let message: String
    let anchorFrame: CGRect
    let placement: InlineHelpPlacement
}

private final class HelpTooltipCoordinator: ObservableObject {
    @Published var tooltip: HelpTooltipPayload?

    /// 显示指定位置的全局 tooltip。
    func show(message: String, frame: CGRect, placement: InlineHelpPlacement) {
        tooltip = HelpTooltipPayload(message: message, anchorFrame: frame, placement: placement)
    }

    /// 仅当当前 tooltip 与消息匹配时才隐藏，避免互相抢状态。
    func hide(message: String) {
        guard tooltip?.message == message else { return }
        tooltip = nil
    }
}

private struct GlobalHelpTooltipLayer: View {
    @EnvironmentObject private var coordinator: HelpTooltipCoordinator
    private let bubbleWidth: CGFloat = 240
    private let horizontalInset: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            if let tooltip = coordinator.tooltip {
                helpBubble(message: tooltip.message)
                    .frame(width: bubbleWidth, alignment: .leading)
                    .position(
                        x: clampedCenterX(for: tooltip.anchorFrame, containerWidth: proxy.size.width),
                        y: resolvedCenterY(for: tooltip.anchorFrame, placement: tooltip.placement)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                    .zIndex(100_000)
            }
        }
    }

    /// 约束 tooltip 水平位置，避免跑出窗口外。
    private func clampedCenterX(for frame: CGRect, containerWidth: CGFloat) -> CGFloat {
        let desired = frame.minX - 6 + bubbleWidth / 2
        let minX = horizontalInset + bubbleWidth / 2
        let maxX = containerWidth - horizontalInset - bubbleWidth / 2
        return min(max(desired, minX), maxX)
    }

    /// 根据控件位置决定 tooltip 出现在上方还是下方。
    private func resolvedCenterY(for frame: CGRect, placement: InlineHelpPlacement) -> CGFloat {
        switch placement {
        case .belowLeading:
            return frame.maxY + 20
        case .aboveLeading:
            return frame.minY - 20
        }
    }

    /// 渲染深黑半透明磨砂说明气泡。
    private func helpBubble(message: String) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.96))
            .frame(width: bubbleWidth, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.48))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.10))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.36), lineWidth: 1)
                }
            )
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.34), radius: 18, y: 12)
    }
}

private struct InlineHelpButton: View {
    let message: String
    let compact: Bool
    let placement: InlineHelpPlacement
    @EnvironmentObject private var coordinator: HelpTooltipCoordinator

    init(message: String, compact: Bool, placement: InlineHelpPlacement = .belowLeading) {
        self.message = message
        self.compact = compact
        self.placement = placement
    }

    var body: some View {
        GeometryReader { proxy in
            Image(systemName: "questionmark.circle")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(AppTheme.labelInk.opacity(0.64))
                .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        if hovering {
                            coordinator.show(
                                message: message,
                                frame: proxy.frame(in: .named("root-help-tooltip-space")),
                                placement: placement
                            )
                        } else {
                            coordinator.hide(message: message)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)
    }
}

private struct ConsoleFader: View {
    let spec: ConsoleControlSpec
    let trackHeight: CGFloat
    let width: CGFloat
    let compactHeight: Bool
    private var knobHeight: CGFloat { compactHeight ? 40 : 48 }
    private let topInset: CGFloat = 4
    private let bottomInset: CGFloat = 6
    @State private var dragOriginOffset: CGFloat?

    var body: some View {
        VStack(spacing: compactHeight ? 4 : 8) {
            HStack(spacing: 4) {
                Text(spec.shortTitle)
                    .font(.system(size: compactHeight ? 9 : 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.labelInk)
                InlineHelpButton(message: spec.helpText, compact: compactHeight, placement: .aboveLeading)
            }

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xC9CDD4), Color(hex: 0xB3B8C0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 16)
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                .offset(x: -0.5, y: -0.5)

                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.16), lineWidth: 1.2)
                                .offset(x: 0.6, y: 0.8)

                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 2)
                                .blur(radius: 1.2)
                                .offset(y: 0.8)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.10), lineWidth: 1)
                    }

                Rectangle()
                    .fill(Color(hex: 0x848A93).opacity(0.62))
                    .frame(width: 2)
                    .padding(.vertical, 8)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.panelGradient)
                    .frame(width: 36, height: knobHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.88), lineWidth: 1)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color(hex: 0xC3C4C8))
                            .frame(width: compactHeight ? 16 : 20, height: 2)
                    }
                    .offset(y: faderOffset)
                    .shadow(color: AppTheme.contactShadow.opacity(0.22), radius: 1.2, y: 1)
                    .shadow(color: AppTheme.hardShadow.opacity(0.26), radius: 4, y: 4)
            }
            .frame(width: max(50, width * 0.72), height: trackHeight)
            .contentShape(Rectangle())
            .highPriorityGesture(faderGesture, including: .all)

            ZStack {
                Circle()
                    .fill(Color(hex: 0x212121))
                    .frame(width: compactHeight ? 22 : 32, height: compactHeight ? 22 : 32)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.contactShadow.opacity(0.25), radius: 2, y: 1)
                    .shadow(color: Color.black.opacity(0.22), radius: 5, y: 4)
                Circle()
                    .fill(indicatorColor)
                    .frame(width: compactHeight ? 6 : 9, height: compactHeight ? 6 : 9)
                    .shadow(color: indicatorColor.opacity(0.85), radius: compactHeight ? 4 : 8)
            }

            if !compactHeight {
                Text(spec.displayValue())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(valueTint)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(spec.isInteractive ? 1 : 0.8)
        .help(spec.helpText)
    }

    private var normalizedValue: Double {
        guard spec.range.upperBound > spec.range.lowerBound else { return 0 }
        return (spec.value.wrappedValue - spec.range.lowerBound) / (spec.range.upperBound - spec.range.lowerBound)
    }

    private var faderOffset: CGFloat {
        topInset + ((1 - normalizedValue) * travel)
    }

    private var indicatorColor: Color {
        normalizedValue > 0.6 ? AppTheme.ledGreen : Color(hex: 0x3A3A3A)
    }

    private var valueTint: Color {
        Color(hex: 0x7A7F87)
    }

    private var travel: CGFloat {
        max(trackHeight - knobHeight - topInset - bottomInset, 72)
    }

    private var faderGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard spec.isInteractive else { return }
                if dragOriginOffset == nil {
                    dragOriginOffset = faderOffset
                }
                let origin = dragOriginOffset ?? faderOffset
                let clamped = min(max(Double(origin) + Double(gesture.translation.height), Double(topInset)), Double(topInset + travel))
                let newNormalized = 1 - ((clamped - Double(topInset)) / Double(travel))
                let rawValue = spec.range.lowerBound + (newNormalized * (spec.range.upperBound - spec.range.lowerBound))
                spec.value.wrappedValue = quantized(rawValue)
            }
            .onEnded { _ in
                dragOriginOffset = nil
            }
    }

    /// 按步进和取值范围收敛推子拖拽值。
    private func quantized(_ value: Double) -> Double {
        let stepped = (value / spec.step).rounded() * spec.step
        return min(max(stepped, spec.range.lowerBound), spec.range.upperBound)
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    /// 创建用于配置窗口 chrome 的空宿主视图。
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    /// 在视图更新时重复应用窗口 chrome 配置。
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    /// 统一配置 mac 窗口标题栏和背景外观。
    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }

        let background = NSColor(
            calibratedRed: 0xF3 / 255.0,
            green: 0xF3 / 255.0,
            blue: 0xF5 / 255.0,
            alpha: 1
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.backgroundColor = background
        window.toolbar = nil
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: .aqua)

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = background.cgColor
    }
}

private struct ConsoleToastView: View {
    let toast: AppToast

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0xF4F4F6))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.contactShadow.opacity(0.18), radius: 1.2, y: 1)
                    .shadow(color: AppTheme.hardShadow.opacity(0.18), radius: 4, y: 3)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(iconTint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(styleLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.52))

                Text(toast.message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .lineLimit(2)
                    .frame(maxWidth: 300, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: 0xF5F5F7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.09), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                            .padding(0.5)
                    )

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconTint.opacity(0.92))
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.leading, 6)
            }
        )
        .shadow(color: AppTheme.contactShadow.opacity(0.18), radius: 2, y: 1)
        .shadow(color: AppTheme.hardShadow.opacity(0.24), radius: 12, y: 8)
    }

    private var iconName: String {
        switch toast.style {
        case .error:
            return "exclamationmark.triangle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var iconTint: Color {
        switch toast.style {
        case .error:
            return AppTheme.knobOrange
        case .success:
            return AppTheme.ledGreen
        case .info:
            return AppTheme.knobBlue
        }
    }

    private var styleLabel: String {
        switch toast.style {
        case .error:
            return "ERROR"
        case .success:
            return "SUCCESS"
        case .info:
            return "INFO"
        }
    }
}

private struct ConsoleWaveformView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    waveformPath(in: proxy.size, index: index)
                    .stroke(index == 2 ? AppTheme.knobOrange : Color.white.opacity(0.78), lineWidth: index == 2 ? 1.4 : 1)
                }
            }
        }
    }

    /// 生成指定通道的演示波形路径。
    private func waveformPath(in size: CGSize, index: Int) -> Path {
        var path = Path()
        let width = size.width
        let height = size.height
        let baseline = height * (0.28 + (CGFloat(index) * 0.18))
        path.move(to: CGPoint(x: 0, y: baseline))

        for step in stride(from: 0.0, through: Double(width), by: 6.0) {
            let phase = CGFloat(step / width)
            let amplitude = 14.0 + (Double(index) * 4.0)
            let y = baseline + CGFloat(sin((phase * .pi * 3) + Double(index))) * amplitude
            path.addLine(to: CGPoint(x: step, y: y))
        }

        return path
    }
}

private struct ConsoleReadout: View {
    let label: String
    let value: String
    var accent: Color? = nil
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 6 : 8) {
            Text(label)
                .font(.system(size: compact ? 8 : 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)
                .fixedSize()
            Text(value)
                .font(.system(size: compact ? 9 : 10, weight: .medium, design: .monospaced))
                .foregroundStyle((accent ?? Color.black).opacity(accent == nil ? 0.62 : 0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minWidth: compact ? 84 : 92, alignment: .leading)
    }
}

private struct ConsoleSelectStrip<MenuContent: View>: View {
    let label: String
    let value: String
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)
                .frame(width: 44, alignment: .leading)

            Menu {
                menuContent()
            } label: {
                HStack {
                    Text(value.uppercased())
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.66))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.panelGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
        }
    }
}

private struct ConsoleInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)
                .frame(width: 44, alignment: .leading)

            Text(value.uppercased())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.62))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.50), lineWidth: 1)
                        )
                )
        }
    }
}

private struct ConsoleInlineRouteControl: View {
    let title: String
    let value: String
    let accent: Color
    let options: [ConsolePickerOption]
    let selectedID: String?
    let emptyState: String
    let compactHeight: Bool
    let onSelect: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            VStack(alignment: .leading, spacing: compactHeight ? 4 : 6) {
                Text(title)
                    .font(.system(size: compactHeight ? 9 : 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.labelInk)

                HStack(spacing: 8) {
                    Text(value.uppercased())
                        .font(.system(size: compactHeight ? 10 : 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.valueInk)
                        .lineLimit(1)
                        .minimumScaleFactor(compactHeight ? 0.84 : 0.9)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: compactHeight ? 9 : 10, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.48))
                }

                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .frame(height: 1)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.40))
                            .frame(height: 1)
                            .offset(y: -1)
                    }
            }
            .frame(minWidth: compactHeight ? 112 : 132, maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                ConsolePopoverHeader(
                    eyebrow: "ROUTE",
                    title: title,
                    trailing: "\(options.count)"
                )

                if options.isEmpty {
                    ConsolePopoverEmptyState(message: emptyState)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(options) { option in
                                ConsoleRouteOptionRow(
                                    title: option.title,
                                    accent: accent,
                                    isSelected: option.id == selectedID
                                ) {
                                    onSelect(option.id)
                                    isPresented = false
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
            .padding(14)
            .frame(width: 300)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: 0xF5F5F7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.09), lineWidth: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                                .padding(0.5)
                        )

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.92))
                        .frame(width: 4)
                        .padding(.vertical, 12)
                        .padding(.leading, 6)
                }
            )
            .shadow(color: AppTheme.contactShadow.opacity(0.18), radius: 2, y: 1)
            .shadow(color: AppTheme.hardShadow.opacity(0.24), radius: 12, y: 8)
        }
    }
}

private struct ConsoleSectionHeader: View {
    let title: String
    let compact: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)

            Spacer(minLength: 8)

            Button(action: action) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.64))
                    .frame(width: compact ? 28 : 30, height: compact ? 28 : 30)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.28))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .help("Reset to defaults")
        }
    }
}

private struct ConsolePopoverHeader: View {
    let eyebrow: String
    let title: String
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.44))

                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.labelInk)
            }

            Spacer()

            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(hex: 0xF0F0F2))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                            )
                    )
            }
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.62))
                        .frame(height: 1)
                }
                .offset(y: 6)
        }
        .padding(.bottom, 10)
    }
}

private struct ConsolePopoverEmptyState: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .frame(width: 10, height: 10)

            Text(message.uppercased())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.54))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0xF2F2F4))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct ConsoleRouteOptionRow: View {
    let title: String
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Capsule(style: .continuous)
                    .fill(isSelected ? accent : Color.black.opacity(isHovered ? 0.24 : 0.18))
                    .frame(width: 10, height: 6)

                Text(title.uppercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accent.opacity(0.92))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
                    .shadow(color: shadowColor, radius: 3, y: 2)
            )
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.14), value: isSelected)
        }
        .buttonStyle(ConsolePopoverRowButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundFill: Color {
        if isSelected {
            return accent.opacity(0.14)
        }
        return isHovered ? Color(hex: 0xEFEFF2) : Color(hex: 0xF7F7F8)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.black.opacity(0.10)
        }
        return Color.black.opacity(isHovered ? 0.09 : 0.06)
    }

    private var shadowColor: Color {
        isSelected || isHovered ? AppTheme.contactShadow.opacity(0.12) : .clear
    }
}

private struct ConsoleCompactSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accent: Color
    let compact: Bool
    let helpText: String?

    init(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        accent: Color,
        compact: Bool,
        helpText: String? = nil
    ) {
        self.title = title
        self.valueText = valueText
        self._value = value
        self.range = range
        self.step = step
        self.accent = accent
        self.compact = compact
        self.helpText = helpText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk)
                    if let helpText, !helpText.isEmpty {
                        InlineHelpButton(message: helpText, compact: compact)
                    }
                }
                .frame(width: compact ? 76 : 86, alignment: .leading)

                Text(valueText.uppercased())
                    .font(.system(size: compact ? 11 : 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.valueInk)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Slider(value: $value, in: range, step: step)
                .tint(accent)
                .colorMultiply(AppTheme.labelInk.opacity(0.92))
                .controlSize(.small)
                .padding(.vertical, compact ? 1 : 2)
        }
        .help(helpText ?? title)
    }
}

private struct ConsoleCompactToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let accent: Color
    let compact: Bool
    let helpText: String?
    var onLabel: String = "ON"
    var offLabel: String = "OFF"

    init(
        title: String,
        isOn: Binding<Bool>,
        accent: Color,
        compact: Bool,
        helpText: String? = nil,
        onLabel: String = "ON",
        offLabel: String = "OFF"
    ) {
        self.title = title
        self._isOn = isOn
        self.accent = accent
        self.compact = compact
        self.helpText = helpText
        self.onLabel = onLabel
        self.offLabel = offLabel
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk)
                    if let helpText, !helpText.isEmpty {
                        InlineHelpButton(message: helpText, compact: compact)
                    }
                }

                HStack(spacing: 8) {
                    Capsule(style: .continuous)
                        .fill(isOn ? accent : Color.black.opacity(0.16))
                        .frame(width: compact ? 24 : 28, height: compact ? 10 : 12)
                        .overlay(alignment: isOn ? .trailing : .leading) {
                            Circle()
                                .fill(Color.white.opacity(0.96))
                                .frame(width: compact ? 14 : 16, height: compact ? 14 : 16)
                                .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 1)
                        }

                    Text((isOn ? onLabel : offLabel).uppercased())
                        .font(.system(size: compact ? 11 : 12, weight: .medium, design: .monospaced))
                        .foregroundStyle((isOn ? accent : Color.black).opacity(isOn ? 0.84 : 0.56))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText ?? title)
    }
}

private struct ConsolePatchMenuCard: View {
    let title: String
    let value: String
    let detail: String
    let actionLabel: String
    let accent: Color?
    let options: [ConsolePickerOption]
    let selectedID: String?
    let emptyState: String
    let compactHeight: Bool
    let isEnabled: Bool
    let popoverLayout: ConsolePatchPopoverLayout
    let popoverWidth: CGFloat
    let helpText: String?
    let onSelect: (String) -> Void
    @State private var isPresented = false

    init(
        title: String,
        value: String,
        detail: String,
        actionLabel: String,
        accent: Color?,
        options: [ConsolePickerOption],
        selectedID: String?,
        emptyState: String,
        compactHeight: Bool,
        isEnabled: Bool,
        popoverLayout: ConsolePatchPopoverLayout = .list,
        popoverWidth: CGFloat = 320,
        helpText: String? = nil,
        onSelect: @escaping (String) -> Void
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.actionLabel = actionLabel
        self.accent = accent
        self.options = options
        self.selectedID = selectedID
        self.emptyState = emptyState
        self.compactHeight = compactHeight
        self.isEnabled = isEnabled
        self.popoverLayout = popoverLayout
        self.popoverWidth = popoverWidth
        self.helpText = helpText
        self.onSelect = onSelect
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(alignment: .top, spacing: compactHeight ? 8 : 10) {
                VStack(alignment: .leading, spacing: compactHeight ? 3 : 5) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: compactHeight ? 9 : 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.labelInk)
                        if let helpText, !helpText.isEmpty {
                            InlineHelpButton(message: helpText, compact: compactHeight)
                        }
                    }
                    Text(value.uppercased())
                        .font(.system(size: compactHeight ? 11 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.valueInk)
                        .lineLimit(1)
                    Text(detail.uppercased())
                        .font(.system(size: compactHeight ? 8 : 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk.opacity(0.82))
                        .lineLimit(1)
                }

                Spacer(minLength: compactHeight ? 6 : 8)

                VStack(spacing: compactHeight ? 4 : 6) {
                    Text(actionLabel)
                        .font(.system(size: compactHeight ? 8 : 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.68))
                    Image(systemName: "chevron.down")
                        .font(.system(size: compactHeight ? 10 : 11, weight: .bold))
                        .foregroundStyle((accent ?? Color.black).opacity(0.7))
                }
                .frame(width: compactHeight ? 40 : 48, height: compactHeight ? 32 : 44)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill((accent ?? Color.white).opacity(accent == nil ? 0.18 : 0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, compactHeight ? 9 : 12)
            .padding(.vertical, compactHeight ? 6 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 1)
                    .padding(.leading, 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .help(helpText ?? detail)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                ConsolePopoverHeader(
                    eyebrow: "PATCH",
                    title: title,
                    trailing: "\(options.count)"
                )

                if options.isEmpty {
                    ConsolePopoverEmptyState(message: emptyState)
                } else {
                    ScrollView {
                        switch popoverLayout {
                        case .list:
                            VStack(spacing: 8) {
                                ForEach(options) { option in
                                    ConsolePatchOptionRow(
                                        title: option.title,
                                        subtitle: option.subtitle,
                                        accent: accent ?? AppTheme.knobOrange,
                                        isSelected: option.id == selectedID
                                    ) {
                                        onSelect(option.id)
                                        isPresented = false
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.trailing, 14)
                        case let .grid(columns):
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(minimum: 168), spacing: 12, alignment: .top),
                                    count: max(columns, 1)
                                ),
                                alignment: .leading,
                                spacing: 12
                            ) {
                                ForEach(options) { option in
                                    ConsolePatchOptionTile(
                                        title: option.title,
                                        subtitle: option.subtitle,
                                        accent: accent ?? AppTheme.knobOrange,
                                        isSelected: option.id == selectedID
                                    ) {
                                        onSelect(option.id)
                                        isPresented = false
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.trailing, 14)
                        }
                    }
                    .frame(maxHeight: popoverLayoutMaxHeight)
                }
            }
            .padding(14)
            .frame(width: popoverWidth)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: 0xF5F5F7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.09), lineWidth: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                                .padding(0.5)
                        )

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((accent ?? AppTheme.knobOrange).opacity(0.92))
                        .frame(width: 4)
                        .padding(.vertical, 12)
                        .padding(.leading, 6)
                }
            )
            .shadow(color: AppTheme.contactShadow.opacity(0.18), radius: 2, y: 1)
            .shadow(color: AppTheme.hardShadow.opacity(0.24), radius: 12, y: 8)
        }
    }

    /// 根据菜单布局切换 popover 的最大滚动高度。
    private var popoverLayoutMaxHeight: CGFloat {
        switch popoverLayout {
        case .list:
            return 280
        case .grid:
            return 420
        }
    }
}

private struct ConsolePatchOptionRow: View {
    let title: String
    let subtitle: String?
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accent.opacity(0.22) : Color(hex: isHovered ? 0xEFEFF2 : 0xF7F7F8))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.black.opacity(isSelected ? 0.10 : (isHovered ? 0.08 : 0.05)), lineWidth: 1)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent.opacity(0.92))
                    } else {
                        Circle()
                            .fill(Color.black.opacity(0.32))
                            .frame(width: 7, height: 7)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.labelInk.opacity(0.82))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
                    .shadow(color: shadowColor, radius: 4, y: 2)
            )
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.14), value: isSelected)
        }
        .buttonStyle(ConsolePopoverRowButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundFill: Color {
        if isSelected {
            return accent.opacity(0.14)
        }
        return isHovered ? Color(hex: 0xEFEFF2) : Color(hex: 0xF7F7F8)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.black.opacity(0.10)
        }
        return Color.black.opacity(isHovered ? 0.09 : 0.06)
    }

    private var shadowColor: Color {
        isSelected || isHovered ? AppTheme.contactShadow.opacity(0.12) : .clear
    }
}

private struct ConsolePatchOptionTile: View {
    let title: String
    let subtitle: String?
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                availabilityBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.labelInk.opacity(0.72))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
                    .shadow(color: shadowColor, radius: 4, y: 2)
            )
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.14), value: isSelected)
        }
        .buttonStyle(ConsolePopoverRowButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    /// 用亮点状态表示该模型当前可用。
    private var availabilityBadge: some View {
        ZStack {
            Circle()
                .fill(isSelected ? accent.opacity(0.16) : Color(hex: isHovered ? 0xF0F1F4 : 0xF7F7F8))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(isSelected ? 0.10 : (isHovered ? 0.08 : 0.05)), lineWidth: 1)
                )

            Circle()
                .fill(isSelected ? accent.opacity(0.96) : Color(hex: 0xB6BAC3))
                .frame(width: 7, height: 7)
                .shadow(color: (isSelected ? accent : Color.white).opacity(isSelected ? 0.52 : 0.20), radius: 4)
        }
    }

    private var backgroundFill: Color {
        if isSelected {
            return accent.opacity(0.14)
        }
        return isHovered ? Color(hex: 0xEFEFF2) : Color(hex: 0xF7F7F8)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.black.opacity(0.10)
        }
        return Color.black.opacity(isHovered ? 0.09 : 0.06)
    }

    private var shadowColor: Color {
        isSelected || isHovered ? AppTheme.contactShadow.opacity(0.12) : .clear
    }
}

private struct ConsolePopoverRowButtonStyle: ButtonStyle {
    /// 为 popover 行按钮提供轻量按压反馈。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .brightness(configuration.isPressed ? -0.01 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.86), value: configuration.isPressed)
    }
}

private struct ConsolePatchActionCard: View {
    let title: String
    let value: String
    let detail: String
    let actionLabel: String
    let accent: Color?
    let compactHeight: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: compactHeight ? 3 : 5) {
                    Text(title)
                        .font(.system(size: compactHeight ? 9 : 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk)
                    Text(value.uppercased())
                        .font(.system(size: compactHeight ? 11 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.valueInk)
                        .lineLimit(1)
                    Text(detail.uppercased())
                        .font(.system(size: compactHeight ? 8 : 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk.opacity(0.82))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(actionLabel)
                    .font(.system(size: compactHeight ? 8 : 9, weight: .bold, design: .monospaced))
                    .foregroundStyle((accent ?? Color.black).opacity(0.78))
                .frame(width: compactHeight ? 42 : 48, height: compactHeight ? 24 : 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill((accent ?? Color.white).opacity(accent == nil ? 0.18 : 0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, compactHeight ? 10 : 12)
            .padding(.vertical, compactHeight ? 8 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 1)
                    .padding(.leading, 2)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ConsoleMetricReadout: View {
    let label: String
    let value: String
    var accent: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.52))
            Text(value.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent ?? Color.white.opacity(0.88))
                .lineLimit(1)
        }
        .frame(minWidth: 74, alignment: .leading)
    }
}

private struct ConsoleMonitorPanel: View {
    let navigation: NavigationDestination
    @ObservedObject var engineController: EngineController
    @ObservedObject var inferenceViewModel: InferenceViewModel
    @ObservedObject var batchViewModel: BatchViewModel
    let models: [ModelOption]
    let indexPaths: [String]
    let selectedModelName: String?
    let modelInfoSummary: String
    let statusMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            monitorScreen
            embeddedNotes
        }
    }

    private var monitorScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(screenTitle)
                Spacer()
                Text(engineController.state.label.uppercased())
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.82))

            ConsoleWaveformView()
                .frame(height: 92)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(primaryRows, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .foregroundStyle(Color.white.opacity(0.56))
                        Spacer()
                        Text(row.1)
                            .foregroundStyle(Color.white.opacity(0.86))
                            .lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }

            if !models.isEmpty, navigation != .engine {
                Divider()
                    .overlay(Color.white.opacity(0.12))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(models.prefix(8)) { model in
                            Text(model.name.replacingOccurrences(of: ".pth", with: "").uppercased())
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(model.name == selectedModelName ? AppTheme.knobOrange.opacity(0.34) : Color.white.opacity(0.08))
                                )
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hex: 0x080808))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.black.opacity(0.86), lineWidth: 4)
        )
    }

    private var embeddedNotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(secondaryTitle)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.labelInk)
                Spacer()
                Text(summaryBadge)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(secondaryRows, id: \.0) { row in
                HStack(alignment: .top, spacing: 10) {
                    Text(row.0)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk)
                        .frame(width: 72, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.65))
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private var screenTitle: String {
        switch navigation {
        case .engine:
            return "ENGINE BUS"
        case .models:
            return "MODEL CATALOG"
        case .singleConvert:
            return "VOICE PATCH"
        case .batchConvert:
            return "BATCH ROUTER"
        }
    }

    private var secondaryTitle: String {
        switch navigation {
        case .engine:
            return "SYSTEM NOTES"
        case .models:
            return "CATALOG NOTES"
        case .singleConvert:
            return "TAKE NOTES"
        case .batchConvert:
            return "QUEUE NOTES"
        }
    }

    private var summaryBadge: String {
        switch navigation {
        case .engine:
            return statusMessage
        case .models:
            return "\(models.count) / \(indexPaths.count)"
        case .singleConvert:
            return inferenceViewModel.outputMessage.isEmpty ? L10n.tr("status.last_run.none") : inferenceViewModel.outputMessage
        case .batchConvert:
            return batchViewModel.outputMessage.isEmpty ? L10n.tr("status.last_run.none") : batchViewModel.outputMessage
        }
    }

    private var primaryRows: [(String, String)] {
        switch navigation {
        case .engine:
            return [
                ("PORT", engineController.port.map(String.init) ?? "NONE"),
                ("STATE", engineController.state.label.uppercased()),
                ("READY", engineController.state == .ready ? "ONLINE" : "WAIT"),
                ("LOG", engineController.recentLog.components(separatedBy: "\n").last ?? "NO LOG"),
            ]
        case .models:
            return [
                ("SELECT", selectedModelName ?? "NONE"),
                ("MODELS", "\(models.count)"),
                ("INDEX", "\(indexPaths.count)"),
                ("INFO", short(modelInfoSummary)),
            ]
        case .singleConvert:
            return [
                ("MODEL", selectedModelName ?? "NONE"),
                ("INPUT", inferenceViewModel.inputFileURL?.lastPathComponent ?? "NONE"),
                ("INDEX", inferenceViewModel.selectedIndexPath.map(lastPath) ?? "AUTO"),
                ("OUT", inferenceViewModel.outputAudioURL?.lastPathComponent ?? "PENDING"),
            ]
        case .batchConvert:
            return [
                ("MODEL", selectedModelName ?? "NONE"),
                ("INPUT", batchInputLabel),
                ("FORMAT", batchViewModel.format.rawValue.uppercased()),
                ("OUT", batchViewModel.outputDirectoryURL?.lastPathComponent ?? "NONE"),
            ]
        }
    }

    private var secondaryRows: [(String, String)] {
        switch navigation {
        case .engine:
            return [
                ("STATUS", statusMessage),
                ("LAST", engineController.recentLog.components(separatedBy: "\n").suffix(2).joined(separator: " / ")),
            ]
        case .models:
            return [
                ("ACTIVE", selectedModelName ?? L10n.tr("models.no_selection")),
                ("SUMMARY", modelInfoSummary),
            ]
        case .singleConvert:
            return [
                ("FILE", inferenceViewModel.inputFileURL?.path ?? L10n.tr("status.none")),
                ("RESULT", inferenceViewModel.outputAudioURL?.path ?? inferenceViewModel.errorMessage ?? L10n.tr("status.none")),
            ]
        case .batchConvert:
            return [
                ("INPUT", batchViewModel.inputDirectoryURL?.path ?? batchViewModel.inputFileURLs.map(\.lastPathComponent).joined(separator: ", ")),
                ("OUTPUT", batchViewModel.outputDirectoryURL?.path ?? L10n.tr("status.none")),
            ]
        }
    }

    private var batchInputLabel: String {
        if let directory = batchViewModel.inputDirectoryURL {
            return directory.lastPathComponent
        }
        if !batchViewModel.inputFileURLs.isEmpty {
            return "\(batchViewModel.inputFileURLs.count) FILES"
        }
        return "NONE"
    }

    /// 提取路径最后一级，压缩 monitor notes 文本。
    private func lastPath(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// 截断过长摘要，避免监视面板撑裂。
    private func short(_ value: String) -> String {
        let trimmed = value.replacingOccurrences(of: "\n", with: " ")
        return trimmed.count > 42 ? String(trimmed.prefix(42)) + "…" : trimmed
    }
}

private struct ConsoleMiniButton: View {
    let systemImage: String

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.panelGradient)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.94), lineWidth: 1)
                )
                .shadow(color: AppTheme.contactShadow.opacity(0.16), radius: 1.2, y: 1)
                .shadow(color: AppTheme.hardShadow.opacity(0.20), radius: 4, y: 4)
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.56))
        }
        .frame(width: 34, height: 34)
    }
}

private struct ConsoleStateLamp: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x1E1E1E))
                .frame(width: 22, height: 22)
            Circle()
                .fill(isActive ? AppTheme.ledGreen : Color(hex: 0x4A4A4A))
                .frame(width: 7, height: 7)
                .shadow(color: isActive ? AppTheme.ledGreen.opacity(0.9) : .clear, radius: 6)
        }
    }
}

private struct ConsoleRoundButtonStyle: ButtonStyle {
    let accent: Color?

    /// 为圆形按钮提供按压态的阴影和位移反馈。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(accent ?? Color.black.opacity(0.68))
            .background(
                Circle()
                    .fill(AppTheme.panelGradient)
                    .overlay(alignment: .top) {
                        Circle()
                            .stroke(Color.white.opacity(0.78), lineWidth: 1)
                    }
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
            .shadow(color: AppTheme.contactShadow.opacity(configuration.isPressed ? 0.10 : 0.18), radius: configuration.isPressed ? 1 : 1.2, y: 1)
            .shadow(color: AppTheme.hardShadow.opacity(configuration.isPressed ? 0.10 : 0.22), radius: configuration.isPressed ? 2 : 4, y: configuration.isPressed ? 1 : 4)
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

private struct ConsoleCapsuleButtonStyle: ButtonStyle {
    let isSelected: Bool
    let accent: Color

    /// 为胶囊按钮提供选中与按压态外观。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? Color.black.opacity(0.82) : Color.black.opacity(0.62))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(accent.opacity(0.24)) : AnyShapeStyle(AppTheme.panelGradient))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.06 : 0.16), radius: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 3)
            .offset(y: configuration.isPressed ? 1.5 : 0)
    }
}

private struct HelpCenterSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HELP CENTER")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk.opacity(0.66))
                    Text("Swift RVC Mac quick guide")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.valueInk)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .foregroundStyle(AppTheme.labelInk.opacity(0.82))
                .buttonStyle(SheetHeaderActionButtonStyle())
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    helpHeroCard
                    helpSection(
                        title: "START HERE",
                        rows: [
                            ("1", "BOOT the engine, then SYNC models and indexes."),
                            ("2", "Choose VOICE MODEL, SPEAKER ID, and F0 METHOD in PATCH BAY."),
                            ("3", "Use FILES for one file, or DIR / FILES for batch input."),
                            ("4", "Press GO for single conversion, or LIVE for realtime voice change."),
                        ]
                    )
                    helpSection(
                        title: "PATCH BAY",
                        rows: [
                            ("VOICE MODEL", "Loads the target voice. Changing it unloads the previous model first."),
                            ("SPEAKER ID", "Choose the speaker slot only for multi-speaker models. Single-speaker models stay on 0."),
                            ("F0 METHOD", "Choose how pitch is extracted. CREPE is now the default. RMVPE is still the safest fallback when you want stability."),
                        ]
                    )
                    helpSection(
                        title: "LIVE CONTROLS",
                        rows: [
                            ("BUFFER", "Higher is safer, lower is faster."),
                            ("GATE", "Higher cuts more noise, but can eat soft syllables."),
                            ("WINDOW", "Higher is steadier, lower is more responsive."),
                            ("FADE", "Higher smooths chunk joins, lower keeps attacks sharper."),
                        ]
                    )
                    helpSection(
                        title: "OFFLINE FADERS",
                        rows: [
                            ("PITCH", "Lower for deeper tone, higher for brighter tone."),
                            ("INDEX", "Lower for cleaner output, higher for stronger target identity."),
                            ("FILTER", "Lower keeps pitch detail, higher smooths pitch wobble."),
                            ("RMS", "Higher keeps more of the source loudness contour."),
                            ("GUARD", "Higher protects consonants and reduces brittle artifacts."),
                        ]
                    )
                    helpSection(
                        title: "TASK / RES",
                        rows: [
                            ("TASK", "Current task queue, active state, inputs, outputs, and errors."),
                            ("RES", "History archive. You can filter, replay, reveal, merge, and delete old results."),
                            ("DELETE", "Destructive actions now ask for confirmation before removing files."),
                        ]
                    )
                    helpSection(
                        title: "BG MIX",
                        rows: [
                            ("BG", "Preview the converted voice with its linked background track."),
                            ("LVL", "Controls how loud the background track is. Lower isolates vocals, higher feels closer to a full song."),
                            ("MERGE", "Exports the current foreground + background mix as a new result."),
                        ]
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 700)
        .background(AppTheme.consoleShellGradient)
    }

    private var helpHeroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Everything important is now grouped by the same areas you see on screen: PATCH BAY, ROUTE, REALTIME LAB, PATCH CONFIG, FADERS, TASK, RES, and BG MIX.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.valueInk)
            HStack(spacing: 10) {
                helpChip("Default F0: CREPE")
                helpChip("Use RMVPE when you want safer stability")
                helpChip("Hover-independent ? buttons are available in UI")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func helpSection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 10) {
                        Text(row.0)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.knobOrange)
                            .frame(width: 100, alignment: .leading)
                        Text(row.1)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.valueInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    private func helpChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(AppTheme.labelInk.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.36))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
    }
}

private struct QueueRuntimeProgressCard: View {
    let title: String
    let startedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RUN WINDOW")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    BusyFluorescentBarView(style: .global)
                    HStack(alignment: .firstTextBaseline) {
                        Text(title.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.valueInk)
                        Spacer()
                        Text(elapsedString(now: context.date))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.labelInk.opacity(0.72))
                    }
                    Text("Indeterminate progress. The bar stays active until the engine returns a result.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.labelInk.opacity(0.74))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func elapsedString(now: Date) -> String {
        guard let startedAt else { return "0.0S" }
        let elapsed = max(now.timeIntervalSince(startedAt), 0)
        return "\(elapsed.formatted(.number.precision(.fractionLength(1))))S"
    }
}

private struct ConsolePreviewWaveformPanel: View {
    @ObservedObject var audioPlayer: AudioPreviewPlayer
    let isRunning: Bool
    let tightHeight: Bool
    let hasBackgroundTrack: Bool
    let isBackgroundEnabled: Bool
    let backgroundMixLevel: Double
    let isPreparingBackgroundMix: Bool
    let isPersistingBackgroundMix: Bool
    let onToggleBackgroundMix: () -> Void
    let onChangeBackgroundMixLevel: (Double) -> Void
    let onMergeBackgroundMix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: tightHeight ? 6 : 10) {
            waveformBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: tightHeight ? 8 : 12) {
                Button {
                    audioPlayer.togglePlayback()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: tightHeight ? 11 : 12, weight: .bold))
                        .frame(width: tightHeight ? 24 : 28, height: tightHeight ? 24 : 28)
                }
                .buttonStyle(ConsoleRoundButtonStyle(accent: AppTheme.knobOrange))
                .disabled(audioPlayer.loadedURL == nil)
                .opacity(audioPlayer.loadedURL == nil ? 0.42 : 1)

                Button(action: onToggleBackgroundMix) {
                    HStack(spacing: 5) {
                        Image(systemName: isBackgroundEnabled ? "waveform.badge.plus" : "waveform")
                            .font(.system(size: tightHeight ? 9 : 10, weight: .bold))
                        Text(isBackgroundEnabled ? "BG ON" : "BG")
                            .font(.system(size: tightHeight ? 8 : 9, weight: .bold, design: .monospaced))
                        if isPreparingBackgroundMix {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.6)
                                .tint(mixButtonInk)
                        }
                    }
                    .foregroundStyle(mixButtonInk)
                    .padding(.horizontal, tightHeight ? 8 : 10)
                    .frame(height: tightHeight ? 24 : 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(mixButtonBackground)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(mixButtonBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasBackgroundTrack || audioPlayer.loadedURL == nil)
                .opacity((hasBackgroundTrack && audioPlayer.loadedURL != nil) ? 1 : 0.42)

                Button(action: onMergeBackgroundMix) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: tightHeight ? 9 : 10, weight: .bold))
                        Text(isPersistingBackgroundMix ? "MIX..." : "MERGE")
                            .font(.system(size: tightHeight ? 8 : 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(mergeButtonInk)
                    .padding(.horizontal, tightHeight ? 8 : 10)
                    .frame(height: tightHeight ? 24 : 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(mergeButtonFill)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(mergeButtonBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasBackgroundTrack || isPersistingBackgroundMix || audioPlayer.loadedURL == nil)
                .opacity(hasBackgroundTrack ? 1 : 0.42)

                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text("LVL")
                            .font(.system(size: tightHeight ? 8 : 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.62))
                        Text("\(Int((backgroundMixLevel * 100).rounded()))%")
                            .font(.system(size: tightHeight ? 8 : 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.74))
                            .frame(minWidth: tightHeight ? 28 : 32, alignment: .leading)
                    }
                    Slider(
                        value: Binding(
                            get: { backgroundMixLevel },
                            set: { onChangeBackgroundMixLevel($0) }
                        ),
                        in: 0...1
                    )
                    .tint(AppTheme.knobBlue)
                    .frame(width: tightHeight ? 72 : 96)
                    .disabled(!hasBackgroundTrack)
                }
                .opacity(hasBackgroundTrack ? 1 : 0.38)

                Slider(
                    value: Binding(
                        get: { audioPlayer.playbackProgress },
                        set: { audioPlayer.seek(progress: $0) }
                    ),
                    in: 0...1
                )
                .tint(AppTheme.knobOrange)
                .disabled(audioPlayer.loadedURL == nil)

                Text(timeLabel(audioPlayer.currentTime))
                    .frame(width: 46, alignment: .trailing)
                Text("/")
                    .foregroundStyle(Color.white.opacity(0.36))
                Text(timeLabel(audioPlayer.duration))
                    .frame(width: 46, alignment: .leading)
            }
            .font(.system(size: tightHeight ? 9 : 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.82))
        }
    }

    @ViewBuilder
    private var waveformBody: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if audioPlayer.waveformSamples.isEmpty {
                    ConsoleWaveformView()
                    if isRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            Spacer()
                            BusyFluorescentBarView(style: .global)
                                .frame(width: min(proxy.size.width * 0.34, 180))
                            Text("PROCESSING OUTPUT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.74))
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                } else {
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(Array(audioPlayer.waveformSamples.enumerated()), id: \.offset) { index, sample in
                            Capsule(style: .continuous)
                                .fill(barColor(for: index))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(8, proxy.size.height * sample * 0.88))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
    }

    private func barColor(for index: Int) -> Color {
        guard !audioPlayer.waveformSamples.isEmpty else { return AppTheme.knobOrange }
        let playedCount = Int((Double(audioPlayer.waveformSamples.count) * audioPlayer.playbackProgress).rounded(.down))
        return index <= playedCount ? AppTheme.knobOrange : Color.white.opacity(0.72)
    }

    private var mixButtonBorder: Color {
        (isBackgroundEnabled || isPreparingBackgroundMix) ? Color.white.opacity(0.30) : Color.white.opacity(0.12)
    }

    private var mixButtonInk: Color {
        (isBackgroundEnabled || isPreparingBackgroundMix) ? Color.white.opacity(0.96) : Color.white.opacity(0.82)
    }

    private var mixButtonBackground: AnyShapeStyle {
        if isBackgroundEnabled || isPreparingBackgroundMix {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(hex: 0xFF3CAC).opacity(0.86),
                    Color(hex: 0x562B7C).opacity(0.82),
                    Color(hex: 0x2B86C5).opacity(0.84),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        return AnyShapeStyle(Color.white.opacity(0.12))
    }

    private var mergeButtonFill: Color {
        if isPersistingBackgroundMix {
            return AppTheme.knobOrange.opacity(0.28)
        }
        return Color.white.opacity(0.10)
    }

    private var mergeButtonBorder: Color {
        isPersistingBackgroundMix ? AppTheme.knobOrange.opacity(0.42) : Color.white.opacity(0.12)
    }

    private var mergeButtonInk: Color {
        isPersistingBackgroundMix ? AppTheme.knobOrange : Color.white.opacity(0.76)
    }

    private func timeLabel(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = Int(value.rounded(.down))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):" + String(format: "%02d", remainder)
    }
}

private struct QueueInspectorSheet: View {
    let selectedModelName: String?
    let effectiveIndexPath: String?
    let f0Method: String
    let speakerID: Int
    let singleInputURL: URL?
    let batchInputDirectoryURL: URL?
    let batchInputFileURLs: [URL]
    let outputDirectoryURL: URL?
    let outputAudioURL: URL?
    let runStartedAt: Date?
    let statusMessage: String
    let lastExecutionSummary: String
    let inferenceError: String?
    let batchError: String?
    let realtimeError: String?
    let isSingleRunning: Bool
    let isBatchRunning: Bool
    let isRealtimeRunning: Bool

    @Environment(\.dismiss) private var dismiss

    private var taskSummary: String {
        if isSingleRunning {
            return "Single convert running"
        }
        if isBatchRunning {
            return "Batch convert running"
        }
        if isRealtimeRunning {
            return "Realtime monitoring active"
        }
        if singleInputURL != nil {
            return "Single input ready"
        }
        if batchInputDirectoryURL != nil || !batchInputFileURLs.isEmpty {
            return "Batch queue ready"
        }
        return "Idle"
    }

    private var errorRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let inferenceError, !inferenceError.isEmpty {
            rows.append(("SINGLE", inferenceError))
        }
        if let batchError, !batchError.isEmpty {
            rows.append(("BATCH", batchError))
        }
        if let realtimeError, !realtimeError.isEmpty {
            rows.append(("LIVE", realtimeError))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TASK QUEUE")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk)
                    Text(taskSummary.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk.opacity(0.76))
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(SheetHeaderActionButtonStyle())
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    queueGroup(
                        title: "ACTIVE",
                        rows: [
                            ("MODEL", selectedModelName ?? "NONE"),
                            ("TASK", taskSummary),
                            ("INDEX", effectiveIndexPath ?? "AUTO"),
                            ("F0", f0Method.uppercased()),
                            ("SPK", "\(speakerID)"),
                            ("STATUS", statusMessage),
                            ("LAST", lastExecutionSummary),
                        ]
                    )

                    if isSingleRunning || isBatchRunning || isRealtimeRunning {
                        QueueRuntimeProgressCard(
                            title: taskSummary,
                            startedAt: runStartedAt
                        )
                    }

                    if !errorRows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("ERROR")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(AppTheme.labelInk)
                                Spacer()
                                copyButton(label: "COPY ALL", value: errorRows.map { "[\($0.0)] \($0.1)" }.joined(separator: "\n\n"))
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(errorRows.indices, id: \.self) { index in
                                    queueValueCard(
                                        title: errorRows[index].0,
                                        value: errorRows[index].1,
                                        accent: AppTheme.knobOrange,
                                        allowCopy: true
                                    )
                                }
                            }
                        }
                    }

                    queueGroup(
                        title: "SINGLE INPUT",
                        rows: [
                            ("FILE", singleInputURL?.lastPathComponent ?? "NONE"),
                            ("PATH", singleInputURL?.path ?? "No audio selected"),
                            ("OUTPUT", outputAudioURL?.lastPathComponent ?? "PENDING"),
                        ]
                    )

                    queueGroup(
                        title: "BATCH",
                        rows: [
                            ("DIRECTORY", batchInputDirectoryURL?.lastPathComponent ?? "NONE"),
                            ("FILES", batchInputFileURLs.isEmpty ? "0" : "\(batchInputFileURLs.count)"),
                            ("OUT DIR", outputDirectoryURL?.lastPathComponent ?? "NONE"),
                        ]
                    )

                    if !batchInputFileURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("QUEUED FILES")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(AppTheme.labelInk)
                                Spacer()
                                copyButton(
                                    label: "COPY PATHS",
                                    value: batchInputFileURLs.map(\.path).joined(separator: "\n")
                                )
                            }

                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(batchInputFileURLs, id: \.path) { url in
                                        queueValueCard(
                                            title: url.lastPathComponent,
                                            value: url.path,
                                            accent: AppTheme.knobBlue,
                                            allowCopy: true
                                        )
                                    }
                                }
                            }
                            .frame(maxHeight: 220)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
        .background(AppTheme.consoleShellGradient)
    }

    private func queueGroup(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(rows[index].0)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.labelInk.opacity(0.72))
                            .frame(width: 72, alignment: .leading)
                        Text(rows[index].1.uppercased())
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.valueInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer(minLength: 0)
                        if shouldAllowCopy(for: rows[index].0) {
                            copyButton(label: "COPY", value: rows[index].1)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                    )
            )
        }
    }

    private func shouldAllowCopy(for label: String) -> Bool {
        ["STATUS", "LAST", "PATH", "OUTPUT", "OUT DIR", "INDEX"].contains(label)
    }

    private func queueValueCard(title: String, value: String, accent: Color, allowCopy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer()
                if allowCopy {
                    copyButton(label: "COPY", value: value)
                }
            }

            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.valueInk)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func copyButton(label: String, value: String) -> some View {
        Button(label) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
        .buttonStyle(.plain)
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .foregroundStyle(Color.black.opacity(0.62))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.38))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ResultHistorySheet: View {
    private enum PendingDestructiveAction: Identifiable {
        case clear(TaskHistoryKind?)
        case delete(TaskHistoryEntry)

        var id: String {
            switch self {
            case .clear(let kind):
                return "clear-\(kind?.rawValue ?? "all")"
            case .delete(let entry):
                return "delete-\(entry.id.uuidString)"
            }
        }
    }

    let entries: [TaskHistoryEntry]
    let onClear: (TaskHistoryKind?) -> Void
    let onDeleteEntry: (TaskHistoryEntry) -> Void
    let onLoadOutput: (TaskHistoryEntry) -> Void
    let onPlayOutput: (TaskHistoryEntry) -> Void
    let onRevealOutput: (TaskHistoryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: TaskHistoryKind?
    @State private var pendingDestructiveAction: PendingDestructiveAction?

    private var entriesByID: [UUID: TaskHistoryEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    private var derivedCountByID: [UUID: Int] {
        Dictionary(entries.compactMap { entry in
            guard let sourceTaskID = entry.sourceTaskID else { return nil }
            return (sourceTaskID, 1)
        }, uniquingKeysWith: +)
    }

    private var filteredEntries: [TaskHistoryEntry] {
        guard let selectedKind else { return entries }
        return entries.filter { $0.kind == selectedKind }
    }

    private var clearLabel: String {
        guard let selectedKind else { return "CLEAR ALL" }
        return "CLEAR \(selectedKind.rawValue.uppercased())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RES ARCHIVE")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk)
                    Text("\(filteredEntries.count) / \(entries.count) task records")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk.opacity(0.76))
                }

                Spacer()

                Button(clearLabel) {
                    pendingDestructiveAction = .clear(selectedKind)
                }
                .buttonStyle(SheetHeaderActionButtonStyle())
                .disabled(entries.isEmpty)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(SheetHeaderActionButtonStyle())
                .keyboardShortcut(.cancelAction)
            }

            historyFilterBar

            if filteredEntries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entries.isEmpty ? "NO HISTORY YET" : "NO MATCHING RECORDS")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.valueInk)
                    Text(entries.isEmpty ? "Single convert, batch convert, and live monitor events will appear here after they run." : "Switch filters to inspect single, batch, or live records.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.labelInk.opacity(0.74))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.32))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                        )
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filteredEntries) { entry in
                            ResultHistoryCard(
                                entry: entry,
                                relatedEntriesByID: entriesByID,
                                derivedCount: derivedCountByID[entry.id] ?? 0,
                                onDelete: {
                                    pendingDestructiveAction = .delete(entry)
                                },
                                onLoadOutput: {
                                    onLoadOutput(entry)
                                    dismiss()
                                },
                                onPlayOutput: {
                                    onPlayOutput(entry)
                                    dismiss()
                                },
                                onRevealOutput: { onRevealOutput(entry) }
                            )
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 540)
        .background(AppTheme.consoleShellGradient)
        .alert(item: $pendingDestructiveAction) { action in
            switch action {
            case .clear(let kind):
                return Alert(
                    title: Text("Delete history?"),
                    message: Text(clearConfirmationMessage(kind: kind)),
                    primaryButton: .destructive(Text(clearLabelForConfirmation(kind: kind))) {
                        onClear(kind)
                    },
                    secondaryButton: .cancel()
                )
            case .delete(let entry):
                return Alert(
                    title: Text("Delete this record?"),
                    message: Text("This will remove the history entry and delete its stored outputs from disk when they still exist."),
                    primaryButton: .destructive(Text("Delete \(entry.kind.rawValue.capitalized)")) {
                        onDeleteEntry(entry)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private func clearLabelForConfirmation(kind: TaskHistoryKind?) -> String {
        guard let kind else { return "Delete all" }
        return "Delete \(kind.rawValue)"
    }

    private func clearConfirmationMessage(kind: TaskHistoryKind?) -> String {
        if let kind {
            return "This will remove every \(kind.rawValue) history record in the current filter and delete the related stored outputs from disk."
        }
        return "This will remove every history record and delete all related stored outputs from disk."
    }

    private var historyFilterBar: some View {
        HStack(spacing: 8) {
            historyFilterChip(label: "ALL", count: entries.count, isSelected: selectedKind == nil) {
                selectedKind = nil
            }
            historyFilterChip(label: "SINGLE", count: entries.filter { $0.kind == .single }.count, isSelected: selectedKind == .single) {
                selectedKind = .single
            }
            historyFilterChip(label: "BATCH", count: entries.filter { $0.kind == .batch }.count, isSelected: selectedKind == .batch) {
                selectedKind = .batch
            }
            historyFilterChip(label: "LIVE", count: entries.filter { $0.kind == .realtime }.count, isSelected: selectedKind == .realtime) {
                selectedKind = .realtime
            }
            historyFilterChip(label: "UVR", count: entries.filter { $0.kind == .uvr }.count, isSelected: selectedKind == .uvr) {
                selectedKind = .uvr
            }
            Spacer()
        }
    }

    private func historyFilterChip(label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.26) : Color.black.opacity(0.06))
                    )
            }
            .foregroundStyle(isSelected ? Color.white.opacity(0.92) : Color.black.opacity(0.64))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AppTheme.knobBlue.opacity(0.92) : Color.white.opacity(0.32))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.black.opacity(isSelected ? 0.0 : 0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ResultHistoryCard: View {
    let entry: TaskHistoryEntry
    let relatedEntriesByID: [UUID: TaskHistoryEntry]
    let derivedCount: Int
    let onDelete: () -> Void
    let onLoadOutput: () -> Void
    let onPlayOutput: () -> Void
    let onRevealOutput: () -> Void

    private enum ArtifactState {
        case file(TimeInterval?)
        case directory
        case missing
        case unavailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Text(entry.kind.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(kindAccent)
                    Text(statusLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(statusAccent.opacity(0.14))
                        )
                }

                Spacer()

                Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.labelInk.opacity(0.68))
            }

            Text(entry.title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.valueInk)

            Text(entry.summary)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.labelInk.opacity(0.78))

            VStack(alignment: .leading, spacing: 8) {
                historyRow("MODEL", entry.modelName ?? "NONE")
                historyRow("INPUT", entry.inputLabel ?? "NONE", copyValue: entry.inputPath)
                historyRow("OUTPUT", entry.outputLabel ?? "NONE", copyValue: entry.outputPath)
                historyRow("STORE", entry.taskDirectoryPath.map(lastPath) ?? "NONE", copyValue: entry.taskDirectoryPath)
                if let mergedArtifact {
                    historyRow("MERGED", mergedArtifact.label, accent: AppTheme.knobBlue, copyValue: mergedArtifact.path)
                }
                historyRow("FILE", outputStateLabel, accent: outputStateAccent)
                historyRow("LEN", outputDurationLabel)
                historyRow("INDEX", entry.indexPath.map(lastPath) ?? "AUTO", copyValue: entry.indexPath)
                historyRow("F0", entry.f0Method?.uppercased() ?? "—")
                historyRow("SPK", entry.speakerID.map(String.init) ?? "—")
                if let sourceEntry {
                    historyRow("SOURCE", "\(sourceEntry.kind.rawValue.uppercased()) / \(sourceEntry.title.uppercased())")
                }
                if let sourceEntry, sourceEntry.kind == .uvr {
                    if let sourceVocal = sourceEntry.outputArtifacts.first(where: { $0.role == .uvrVocal }) {
                        historyRow("SRC VOC", sourceVocal.label, copyValue: sourceVocal.path)
                    }
                    if let sourceInstrumental = sourceEntry.outputArtifacts.first(where: { $0.role == .uvrInstrumental }) {
                        historyRow("SRC INS", sourceInstrumental.label, copyValue: sourceInstrumental.path)
                    }
                }
                if entry.kind == .uvr {
                    historyRow("VOCALS", "\(entry.outputArtifacts.filter { $0.role == .uvrVocal }.count)")
                    historyRow("INST", "\(entry.outputArtifacts.filter { $0.role == .uvrInstrumental }.count)")
                    historyRow("USED BY", "\(derivedCount)")
                }
                if let errorMessage = entry.errorMessage, !errorMessage.isEmpty {
                    historyRow("ERROR", errorMessage, accent: AppTheme.knobOrange, copyValue: errorMessage)
                }
            }

            HStack(spacing: 8) {
                if hasPlayableOutput {
                    buttonChip(label: "LOAD", action: onLoadOutput)
                    buttonChip(label: "PLAY", action: onPlayOutput)
                }
                if entry.outputPath != nil || entry.taskDirectoryPath != nil {
                    buttonChip(label: "OPEN", action: onRevealOutput)
                }
                buttonChip(label: "COPY", action: copyRecord)
                destructiveChip(label: "DELETE", action: onDelete)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var kindAccent: Color {
        switch entry.kind {
        case .single:
            return AppTheme.knobOrange
        case .batch:
            return AppTheme.knobBlue
        case .realtime:
            return AppTheme.ledGreen
        case .uvr:
            return AppTheme.knobOrange
        }
    }

    private var sourceEntry: TaskHistoryEntry? {
        guard let sourceTaskID = entry.sourceTaskID else { return nil }
        return relatedEntriesByID[sourceTaskID]
    }

    private var mergedArtifact: TaskHistoryArtifact? {
        entry.outputArtifacts.first(where: { $0.role == .mixedOutput })
    }

    private var hasPlayableOutput: Bool {
        if case .file = outputState {
            return true
        }
        return false
    }

    private var outputState: ArtifactState {
        let candidatePath = mergedArtifact?.path
            ?? entry.outputPath
            ?? entry.outputArtifacts.first(where: { $0.role == .singleOutput || $0.role == .uvrVocal })?.path
        guard let candidatePath, !candidatePath.isEmpty else { return .unavailable }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidatePath, isDirectory: &isDirectory) else {
            return .missing
        }
        if isDirectory.boolValue {
            return .directory
        }
        let url = URL(fileURLWithPath: candidatePath)
        guard let file = try? AVAudioFile(forReading: url) else {
            return .file(nil)
        }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        return .file(duration)
    }

    private var outputStateLabel: String {
        switch outputState {
        case .file:
            return "FOUND"
        case .directory:
            return "DIR"
        case .missing:
            return "MISSING"
        case .unavailable:
            return "N/A"
        }
    }

    private var outputStateAccent: Color {
        switch outputState {
        case .file:
            return AppTheme.ledGreen
        case .directory:
            return AppTheme.knobBlue
        case .missing:
            return AppTheme.knobOrange
        case .unavailable:
            return AppTheme.labelInk
        }
    }

    private var outputDurationLabel: String {
        switch outputState {
        case let .file(duration):
            guard let duration else { return "—" }
            return timeLabel(duration)
        case .directory, .missing, .unavailable:
            return "—"
        }
    }

    private var statusAccent: Color {
        switch entry.status {
        case .success:
            return AppTheme.ledGreen
        case .failure:
            return AppTheme.knobOrange
        case .info:
            return AppTheme.knobBlue
        }
    }

    private var statusLabel: String {
        switch entry.status {
        case .success:
            return "OK"
        case .failure:
            return "ERR"
        case .info:
            return "INFO"
        }
    }

    private func historyRow(_ label: String, _ value: String, accent: Color? = nil, copyValue: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle((accent ?? AppTheme.labelInk).opacity(0.78))
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.valueInk)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if let copyValue, !copyValue.isEmpty {
                buttonChip(label: "COPY") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyValue, forType: .string)
                }
            }
        }
    }

    private func buttonChip(label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.black.opacity(0.64))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.38))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
    }

    private func destructiveChip(label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(AppTheme.knobOrange.opacity(0.92))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.knobOrange.opacity(0.10))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(AppTheme.knobOrange.opacity(0.24), lineWidth: 1)
                    )
            )
    }

    private func copyRecord() {
        let lines = [
            "time: \(entry.timestamp.formatted(date: .abbreviated, time: .standard))",
            "kind: \(entry.kind.rawValue)",
            "status: \(entry.status.rawValue)",
            "title: \(entry.title)",
            "summary: \(entry.summary)",
            "model: \(entry.modelName ?? "none")",
            "input: \(entry.inputPath ?? entry.inputLabel ?? "none")",
            "output: \(entry.outputPath ?? entry.outputLabel ?? "none")",
            "merged: \(mergedArtifact?.path ?? "none")",
            "store: \(entry.taskDirectoryPath ?? "none")",
            "index: \(entry.indexPath ?? "auto")",
            "f0: \(entry.f0Method ?? "—")",
            "speaker: \(entry.speakerID.map(String.init) ?? "—")",
            "sourceTask: \(entry.sourceTaskID?.uuidString ?? "none")",
            "error: \(entry.errorMessage ?? "none")",
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func lastPath(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func timeLabel(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = Int(value.rounded(.down))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes):" + String(format: "%02d", remainder)
    }
}

private struct SheetHeaderActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black.opacity(configuration.isPressed ? 0.82 : 0.68))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.48 : 0.34))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                    )
            )
    }
}

private struct AssetReportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: AssetAuditViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ASSET REPORT")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                    Text(summaryLine)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.primary)
                }
                Spacer()
                Button(viewModel.isChecking ? "Checking..." : "Check") {
                    Task { await viewModel.refreshReport() }
                }
                .disabled(viewModel.isChecking || viewModel.isDownloading)
                Button(viewModel.isDownloading ? "Downloading..." : "Download") {
                    Task { await viewModel.downloadAssets() }
                }
                .disabled(viewModel.isChecking || viewModel.isDownloading)
                Button("Close") {
                    dismiss()
                }
                .foregroundStyle(AppTheme.labelInk.opacity(0.82))
                .keyboardShortcut(.cancelAction)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.red)
            } else if let message = viewModel.report?.message {
                Text(message)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }

            ScrollView {
                if viewModel.items.isEmpty {
                    Text("No asset report available yet. Run CHECK to query the backend.")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.title.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Spacer()
                                    Text(item.status.label)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(statusColor(for: item.status))
                                }

                                Text(item.path)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.primary.opacity(0.82))
                                    .textSelection(.enabled)

                                Text(item.note)
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundStyle(Color.secondary)

                                if let expectedHash = item.expectedHash {
                                    Text("Expected: \(expectedHash)")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.secondary)
                                        .textSelection(.enabled)
                                }

                                if let actualHash = item.actualHash {
                                    Text("Actual:   \(actualHash)")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 700, idealWidth: 820, minHeight: 480, idealHeight: 620)
    }

    private var summaryLine: String {
        let items = viewModel.items
        let okCount = items.filter(\.isHealthy).count
        return "\(okCount)/\(items.count) tracked assets verified"
    }

    /// 将资产检查状态映射为对应强调色。
    private func statusColor(for status: AssetIntegrityStatus) -> Color {
        switch status {
        case .ok:
            return .green
        case .missing, .mismatch, .error:
            return .red
        }
    }
}

private extension NavigationDestination {
    var consoleAccent: Color {
        switch self {
        case .engine:
            return AppTheme.knobBlue
        case .models:
            return AppTheme.knobOchre
        case .singleConvert:
            return AppTheme.knobOrange
        case .batchConvert:
            return AppTheme.knobGrey
        }
    }
}
