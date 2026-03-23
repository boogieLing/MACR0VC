import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { proxy in
            let compactShell = proxy.size.width < 1180
            let shortShell = proxy.size.height < 620
            let railWidth = compactShell
                ? max(228, min(proxy.size.width * 0.24, 280))
                : max(320, min(proxy.size.width * 0.26, 388))

            Group {
                if shortShell {
                    ScrollView(.vertical, showsIndicators: false) {
                        shellContent(proxy: proxy, railWidth: railWidth, contentHeight: max(proxy.size.height, 560))
                    }
                } else {
                    shellContent(proxy: proxy, railWidth: railWidth, contentHeight: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(consoleShellBackground)
        .ignoresSafeArea(.container, edges: [.leading, .trailing, .bottom])
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .frame(height: 1)
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
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: appState.toast?.id)
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
    }

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
                modelsCount: appState.models.count,
                statusMessage: appState.statusMessage,
                lastExecutionSummary: appState.lastExecutionSummary,
                onSelectModel: { model in
                    Task { await appState.selectModel(model) }
                },
                onSelectIndexPath: { indexPath in
                    appState.inferenceViewModel.selectedIndexPath = indexPath
                    appState.batchViewModel.selectedIndexPath = indexPath
                },
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
                models: appState.models,
                indexPaths: appState.indexPaths,
                selectedModelName: appState.selectedModelName,
                statusMessage: appState.statusMessage,
                lastExecutionSummary: appState.lastExecutionSummary,
                catalogModelCount: appState.models.count,
                catalogIndexCount: appState.indexPaths.count,
                selectedModelSizeLabel: appState.selectedModelSizeLabel,
                selectedIndexSizeLabel: appState.selectedIndexSizeLabel,
                appMemoryLabel: appState.appMemoryLabel,
                engineMemoryLabel: appState.engineMemoryLabel,
                isNavigating: appState.isNavigating,
                onContextAction: handleContextAction
            )
            .frame(width: max(proxy.size.width - railWidth - 1, 0), height: contentHeight, alignment: .topLeading)
        }
        .frame(width: proxy.size.width, height: contentHeight, alignment: .topLeading)
    }

    private func syncRealtimeControlsIfNeeded() {
        guard appState.realtimeViewModel.isRunning else { return }
        Task { await appState.applyRealtimeConfiguration() }
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
        case .chooseAudio:
            chooseAudioFile()
        case .convertSingle:
            Task { await appState.inferenceViewModel.convert(selectedModelName: appState.selectedModelName) }
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
            Task { await appState.batchViewModel.convert(selectedModelName: appState.selectedModelName) }
        case .openBatchOutput:
            appState.batchViewModel.openOutputDirectory()
        case .startRealtime:
            Task { await appState.startRealtime() }
        case .stopRealtime:
            Task { await appState.stopRealtime() }
        }
    }

    private func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            appState.inferenceViewModel.inputFileURL = panel.url
        }
    }

    private func chooseBatchInputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            appState.batchViewModel.inputDirectoryURL = panel.url
            appState.batchViewModel.inputFileURLs = []
        }
    }

    private func chooseBatchInputFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            appState.batchViewModel.inputFileURLs = panel.urls
            appState.batchViewModel.inputDirectoryURL = nil
        }
    }

    private func chooseBatchOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            appState.batchViewModel.outputDirectoryURL = panel.url
        }
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
    case chooseAudio
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

    var id: String { rawValue }
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

private struct ConsoleControlSpec: Identifiable {
    let id: String
    let title: String
    let shortTitle: String
    let color: Color
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let isInteractive: Bool
    let formatter: (Double) -> String

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
    let modelsCount: Int
    let statusMessage: String
    let lastExecutionSummary: String
    let onSelectModel: (String) -> Void
    let onSelectIndexPath: (String) -> Void
    let onContextAction: (ConsoleContextAction) -> Void

    var body: some View {
        GeometryReader { proxy in
            let shortRail = proxy.size.height < 820
            let tightRail = proxy.size.height < 760
            let ultraTightRail = proxy.size.height < 700
            let controlButtonSize = max(
                ultraTightRail ? 40 : (tightRail ? 44 : 50),
                min(
                    min(proxy.size.width * 0.185, ultraTightRail ? 54 : (shortRail ? 60 : 70)),
                    proxy.size.height * (ultraTightRail ? 0.064 : (tightRail ? 0.072 : 0.084))
                )
            )

            VStack(alignment: .leading, spacing: 0) {
                grille
                miniTransport
                    .padding(.top, ultraTightRail ? 10 : (shortRail ? 12 : 18))
                assetRack
                    .padding(.top, ultraTightRail ? 10 : (shortRail ? 16 : 22))
                Spacer(minLength: ultraTightRail ? 6 : (shortRail ? 10 : 18))
                actionPad(buttonSize: controlButtonSize, compact: shortRail, tight: ultraTightRail)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, ultraTightRail ? 20 : (shortRail ? 28 : 40))
            .padding(.bottom, ultraTightRail ? 10 : (shortRail ? 18 : 28))
            .padding(.leading, shortRail ? 22 : 30)
            .padding(.trailing, shortRail ? 18 : 28)
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
            Text("PATCH BAY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)

            VStack(spacing: 6) {
                ConsolePatchMenuCard(
                    title: "VOICE MODEL",
                    value: selectedModelName?.replacingOccurrences(of: ".pth", with: "") ?? "Choose a model",
                    detail: models.isEmpty ? "No models loaded" : "\(models.count) loaded",
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
                    onSelect: onSelectModel
                )

                ConsolePatchMenuCard(
                    title: "INDEX FILE",
                    value: inferenceViewModel.selectedIndexPath.map(lastPath) ?? "Auto match",
                    detail: indexPaths.isEmpty ? "No index files" : "\(indexPaths.count) loaded",
                    actionLabel: "PICK",
                    accent: inferenceViewModel.selectedIndexPath == nil ? nil : AppTheme.knobOchre,
                    options: indexPaths.map {
                        ConsolePickerOption(id: $0, title: lastPath($0), subtitle: nil)
                    },
                    selectedID: inferenceViewModel.selectedIndexPath,
                    emptyState: "Auto match",
                    compactHeight: true,
                    onSelect: onSelectIndexPath
                )

                ConsolePatchActionCard(
                    title: "INPUT AUDIO",
                    value: inferenceViewModel.inputFileURL?.lastPathComponent ?? "Choose source audio",
                    detail: inferenceViewModel.inputFileURL == nil ? "Browse a local file" : "Ready for convert",
                    actionLabel: "BROWSE",
                    accent: inferenceViewModel.inputFileURL == nil ? nil : AppTheme.knobBlue
                    ,
                    compactHeight: true
                ) {
                    onContextAction(.chooseAudio)
                }

                ConsolePatchActionCard(
                    title: "OUTPUT FOLDER",
                    value: batchViewModel.outputDirectoryURL?.lastPathComponent ?? "Set output folder",
                    detail: batchViewModel.outputDirectoryURL == nil ? "Optional for batch" : "Batch output ready",
                    actionLabel: "SET",
                    accent: batchViewModel.outputDirectoryURL == nil ? nil : AppTheme.knobGrey
                    ,
                    compactHeight: true
                ) {
                    onContextAction(.chooseBatchOutputFolder)
                }
            }
        }
        .padding(.top, 2)
    }

    private func actionPad(buttonSize: CGFloat, compact: Bool, tight: Bool) -> some View {
        VStack(alignment: .leading, spacing: tight ? 8 : (compact ? 10 : 16)) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: tight ? 6 : (compact ? 8 : 12)), count: 4), spacing: tight ? 6 : (compact ? 8 : 12)) {
                ForEach(contextActions) { item in
                    Button {
                        onContextAction(item.action)
                    } label: {
                        if item.title.count <= 3 {
                            VStack(spacing: tight ? 2 : (compact ? 3 : 4)) {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: tight ? 10 : (compact ? 11 : 13), weight: .semibold))
                                Text(item.title)
                                    .font(.system(size: tight ? 8 : (compact ? 9 : 10), weight: .medium, design: .rounded))
                            }
                            .frame(width: buttonSize, height: buttonSize)
                        } else {
                            Text(item.title)
                                .font(.system(size: tight ? 9 : (compact ? 10 : 12), weight: .medium, design: .rounded))
                                .frame(width: buttonSize, height: buttonSize)
                        }
                    }
                    .buttonStyle(ConsoleRoundButtonStyle(accent: item.accent))
                    .disabled(!item.isEnabled)
                    .opacity(item.isEnabled ? 1 : 0.48)
                }
            }

            Text(lastExecutionSummary)
                .font(.system(size: tight ? 9 : (compact ? 10 : 11), weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)
                .lineLimit(tight ? 1 : 2)
        }
        .padding(.top, tight ? 2 : 6)
    }

    private var contextActions: [ConsoleActionItem] {
        [
            ConsoleActionItem(id: "pth", title: "PTH", systemImage: "folder", action: .openWeights, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "idx", title: "IDX", systemImage: "folder.badge.gearshape", action: .openIndices, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "dir", title: "DIR", systemImage: "folder.fill", action: .chooseBatchInputFolder, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "files", title: "FILES", systemImage: "music.note.list", action: .chooseBatchInputFiles, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "out", title: "OUT", systemImage: "folder.badge.plus", action: .chooseBatchOutputFolder, isEnabled: true, accent: nil),
            ConsoleActionItem(id: "single", title: "REC", systemImage: "record.circle", action: .convertSingle, isEnabled: engineController.state == .ready && !inferenceViewModel.isRunning, accent: AppTheme.knobOrange),
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

    private func lastPath(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

private struct ConsoleDeck: View {
    @ObservedObject var engineController: EngineController
    @ObservedObject var inferenceViewModel: InferenceViewModel
    @ObservedObject var batchViewModel: BatchViewModel
    @ObservedObject var realtimeViewModel: RealtimeViewModel
    let models: [ModelOption]
    let indexPaths: [String]
    let selectedModelName: String?
    let statusMessage: String
    let lastExecutionSummary: String
    let catalogModelCount: Int
    let catalogIndexCount: Int
    let selectedModelSizeLabel: String
    let selectedIndexSizeLabel: String
    let appMemoryLabel: String
    let engineMemoryLabel: String
    let isNavigating: Bool
    let onContextAction: (ConsoleContextAction) -> Void

    var body: some View {
        GeometryReader { proxy in
            let compactDeck = proxy.size.width < 980
            let veryCompactDeck = proxy.size.width < 760
            let shortDeck = proxy.size.height < 820
            let tightDeck = proxy.size.height < 760
            let contentHeight = max(proxy.size.height - (tightDeck ? 36 : 44), 420)
            let monitorHeight = min(max(contentHeight * (tightDeck ? 0.10 : (shortDeck ? 0.15 : 0.18)), tightDeck ? 90 : 132), shortDeck ? 134 : 178)
            let faderModuleHeight = min(max(contentHeight * (tightDeck ? 0.27 : (shortDeck ? 0.35 : 0.40)), tightDeck ? 150 : 224), shortDeck ? 250 : 324)
            let trackHeight = min(max(faderModuleHeight - (tightDeck ? 42 : 92), tightDeck ? 92 : 148), shortDeck ? 170 : 224)
            let routingWidth = veryCompactDeck ? 132.0 : (compactDeck ? 168.0 : 220.0)
            let faderWidth = max(
                veryCompactDeck ? 38 : (compactDeck ? 46 : 70),
                min(
                    (proxy.size.width - routingWidth - (compactDeck ? 68 : 160)) / CGFloat(max(faderSpecs.count, 1)),
                    compactDeck ? 66 : 92
                )
            )

            VStack(spacing: tightDeck ? 2 : 18) {
                encoderRow(compact: tightDeck)
                divider
                utilityStrip(compact: compactDeck, tightHeight: tightDeck)
                monitorPanel(compact: compactDeck, tightHeight: tightDeck)
                    .frame(height: monitorHeight)
                Spacer(minLength: tightDeck ? 0 : 4)
                faderModule(
                    trackHeight: trackHeight,
                    faderWidth: faderWidth,
                    routingWidth: routingWidth,
                    compact: compactDeck,
                    veryCompact: veryCompactDeck,
                    tightHeight: tightDeck
                )
                    .frame(height: faderModuleHeight, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, tightDeck ? 0 : (compactDeck ? 28 : 34))
            .padding(.bottom, tightDeck ? 4 : 8)
            .padding(.leading, compactDeck ? 22 : 38)
            .padding(.trailing, compactDeck ? 18 : 36)
        }
    }

    private func encoderRow(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 14 : 42) {
            ForEach(topActionItems) { item in
                Button {
                    onContextAction(item.action)
                } label: {
                    ConsoleActionKnob(item: item, compact: compact)
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .opacity(item.isEnabled ? 1 : 0.46)
            }

            Spacer(minLength: compact ? 4 : 16)

            if let master = knobSpecs.last {
                ConsoleKnob(spec: master, compact: true, extraCompact: compact)
            }
        }
    }

    private var topActionItems: [ConsoleActionItem] {
        [
            ConsoleActionItem(id: "boot", title: "BOOT", systemImage: "bolt.fill", action: .startEngine, isEnabled: engineController.state != .ready && engineController.state != .starting, accent: AppTheme.knobBlue),
            ConsoleActionItem(id: "sync", title: "SYNC", systemImage: "arrow.clockwise", action: .refreshModels, isEnabled: engineController.state == .ready, accent: AppTheme.knobOchre),
            ConsoleActionItem(id: "audio", title: "AUDIO", systemImage: "speaker.wave.2.fill", action: .refreshRealtimeDevices, isEnabled: engineController.state == .ready, accent: AppTheme.knobGrey),
            ConsoleActionItem(id: "run", title: realtimeViewModel.isRunning ? "STOP" : "RUN", systemImage: realtimeViewModel.isRunning ? "stop.fill" : "play.fill", action: realtimeViewModel.isRunning ? .stopRealtime : .startRealtime, isEnabled: engineController.state == .ready && selectedModelName != nil && !realtimeMissingRoute, accent: realtimeViewModel.isRunning ? AppTheme.knobGrey : AppTheme.knobOrange),
        ]
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

    private func utilityStrip(compact: Bool, tightHeight: Bool) -> some View {
        let readouts = utilityReadouts

        return VStack(alignment: .leading, spacing: compact ? (tightHeight ? 2 : 10) : 0) {
            if compact {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: tightHeight ? 72 : 92), spacing: tightHeight ? 12 : 18, alignment: .leading),
                        GridItem(.flexible(minimum: tightHeight ? 72 : 92), spacing: tightHeight ? 12 : 18, alignment: .leading),
                        GridItem(.flexible(minimum: tightHeight ? 72 : 92), spacing: tightHeight ? 12 : 18, alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: tightHeight ? 2 : 10
                ) {
                    ForEach(readouts.indices, id: \.self) { index in
                        ConsoleReadout(
                            label: readouts[index].label,
                            value: readouts[index].value,
                            accent: readouts[index].accent
                        )
                    }
                }
            } else {
                HStack(spacing: 30) {
                    ForEach(readouts.indices, id: \.self) { index in
                        ConsoleReadout(
                            label: readouts[index].label,
                            value: readouts[index].value,
                            accent: readouts[index].accent
                        )
                    }
                    Spacer(minLength: 0)
                    if isNavigating {
                        Text(L10n.tr("label.shell_loading"))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.labelInk)
                    }
                }
            }
        }
    }

    private var utilityReadouts: [(label: String, value: String, accent: Color?)] {
        [
            (
                "MODEL",
                selectedModelName?.replacingOccurrences(of: ".pth", with: "").uppercased() ?? "NONE",
                selectedModelName == nil ? nil : AppTheme.knobOrange
            ),
            ("STATE", engineController.state.label.uppercased(), nil),
            (
                "INDEX",
                inferenceViewModel.selectedIndexPath.map(lastPath) ?? "AUTO",
                inferenceViewModel.selectedIndexPath == nil ? nil : AppTheme.knobOchre
            ),
            (
                "INPUT",
                realtimeViewModel.selectedInputDevice?.uppercased() ?? "NONE",
                realtimeViewModel.selectedInputDevice == nil ? nil : AppTheme.knobBlue
            ),
            (
                "OUTPUT",
                realtimeViewModel.selectedOutputDevice?.uppercased() ?? "NONE",
                realtimeViewModel.selectedOutputDevice == nil ? nil : AppTheme.knobOchre
            ),
            ("MODE", realtimeViewModel.monitorMode == .outputConverted ? "VC" : "MON", nil),
        ]
    }

    private func monitorPanel(compact: Bool, tightHeight: Bool) -> some View {
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

            ConsoleWaveformView()
                .frame(height: tightHeight ? 54 : 104)

            if tightHeight {
                compactMonitorSummary
            } else {
                HStack(alignment: .top, spacing: compact ? 10 : 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        monitorRow("MODEL", selectedModelName ?? "NONE", compact: tightHeight)
                        monitorRow("INPUT", realtimeViewModel.selectedInputDevice ?? "NONE", compact: tightHeight)
                        monitorRow("INDEX", inferenceViewModel.selectedIndexPath.map(lastPath) ?? "AUTO", compact: tightHeight)
                        monitorRow("MONITOR", realtimeViewModel.monitorMode == .outputConverted ? "VC" : "INPUT", compact: tightHeight)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 6) {
                        monitorRow("OUTPUT", realtimeViewModel.selectedOutputDevice ?? "NONE", compact: tightHeight)
                        monitorRow("RATE", realtimeViewModel.sampleRate > 0 ? "\(realtimeViewModel.sampleRate)" : "—", compact: tightHeight)
                        monitorRow("DELAY", "\(realtimeViewModel.delayTimeMs)MS", compact: tightHeight)
                        monitorRow("INFER", "\(realtimeViewModel.inferTimeMs)MS", compact: tightHeight)
                    }
                }
            }

            monitorMetricsBar(tightHeight: tightHeight)

            if !tightHeight && !models.isEmpty {
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
        .padding(tightHeight ? 7 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            compactMonitorToken("MON", realtimeViewModel.monitorMode == .outputConverted ? "VC" : "INPUT", accent: realtimeViewModel.isRunning ? AppTheme.knobOrange : nil)
            Spacer(minLength: 0)
        }
    }

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

    private func lastPath(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func faderModule(trackHeight: CGFloat, faderWidth: CGFloat, routingWidth: CGFloat, compact: Bool, veryCompact: Bool, tightHeight: Bool) -> some View {
        Group {
            if veryCompact {
                VStack(alignment: .leading, spacing: tightHeight ? 6 : 14) {
                    routingBank(tightHeight: tightHeight)
                    faderStack(trackHeight: trackHeight, faderWidth: faderWidth, compact: compact, tightHeight: tightHeight)
                }
            } else {
                HStack(alignment: .bottom, spacing: compact ? 12 : 32) {
                    routingBank(tightHeight: tightHeight)
                        .frame(width: routingWidth)
                        .frame(maxHeight: .infinity, alignment: .bottomLeading)
                    faderStack(trackHeight: trackHeight, faderWidth: faderWidth, compact: compact, tightHeight: tightHeight)
                }
            }
        }
        .padding(.top, tightHeight ? 0 : 6)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func faderStack(trackHeight: CGFloat, faderWidth: CGFloat, compact: Bool, tightHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: tightHeight ? 4 : 10) {
            Text("PARAMETER BANK")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)

            Spacer(minLength: tightHeight ? 0 : 6)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func routingBank(tightHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: tightHeight ? 6 : 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("ROUTING")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.labelInk)
                Spacer(minLength: 8)
                Button("SCAN") {
                    onContextAction(.refreshRealtimeDevices)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.knobBlue.opacity(0.84))
            }

            if tightHeight {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 64), spacing: 10, alignment: .leading),
                        GridItem(.flexible(minimum: 64), spacing: 10, alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    routingHostControl
                    routingInputControl
                    routingOutputControl
                    routingMonitorControl
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    routingHostControl
                    routingInputControl
                    routingOutputControl
                    routingMonitorControl
                }
            }
        }
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
                    selectedIndexPath: inferenceViewModel.selectedIndexPath,
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
                    selectedIndexPath: inferenceViewModel.selectedIndexPath,
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
                    selectedIndexPath: inferenceViewModel.selectedIndexPath,
                    inferenceViewModel: inferenceViewModel
                )
            }
        }
    }

    private var routingMonitorControl: some View {
        ConsoleInlineRouteControl(
            title: "MON",
            value: realtimeViewModel.monitorMode == .outputConverted ? "VC" : "INPUT",
            accent: AppTheme.knobOrange,
            options: RealtimeMonitorMode.allCases.map { mode in
                ConsolePickerOption(id: mode.rawValue, title: mode == .outputConverted ? "Converted Voice" : "Input Monitor", subtitle: nil)
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
                    selectedIndexPath: inferenceViewModel.selectedIndexPath,
                    inferenceViewModel: inferenceViewModel
                )
            }
        }
    }

    private var knobSpecs: [ConsoleControlSpec] {
        [
            ConsoleControlSpec(id: "pitch", title: L10n.tr("slider.transpose"), shortTitle: "PIT", color: AppTheme.knobBlue, value: $inferenceViewModel.transpose, range: -24...24, step: 1, isInteractive: true, formatter: integerString),
            ConsoleControlSpec(id: "index", title: L10n.tr("slider.index_rate"), shortTitle: "IDX", color: AppTheme.knobOchre, value: $inferenceViewModel.indexRate, range: 0...1, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "guard", title: L10n.tr("slider.protect"), shortTitle: "GRD", color: AppTheme.knobGrey, value: $inferenceViewModel.protect, range: 0...0.5, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "rms", title: L10n.tr("slider.rms_mix"), shortTitle: "RMS", color: AppTheme.knobOrange, value: $inferenceViewModel.rmsMixRate, range: 0...1, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "master", title: "MASTER", shortTitle: "MST", color: AppTheme.knobWhite, value: .constant(normalizedActivity), range: 0...1, step: 0.01, isInteractive: false, formatter: percentString),
        ]
    }

    private var faderSpecs: [ConsoleControlSpec] {
        [
            ConsoleControlSpec(id: "pitch", title: "PITCH", shortTitle: "PIT", color: AppTheme.knobWhite, value: $inferenceViewModel.transpose, range: -24...24, step: 1, isInteractive: true, formatter: integerString),
            ConsoleControlSpec(id: "index", title: "INDEX", shortTitle: "IDX", color: AppTheme.knobWhite, value: $inferenceViewModel.indexRate, range: 0...1, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "filter", title: "FILTER", shortTitle: "FLT", color: AppTheme.knobWhite, value: $inferenceViewModel.filterRadius, range: 0...7, step: 1, isInteractive: true, formatter: integerString),
            ConsoleControlSpec(id: "sample", title: "RESAMP", shortTitle: "RSP", color: AppTheme.knobWhite, value: $inferenceViewModel.resampleSR, range: 0...48_000, step: 100, isInteractive: true, formatter: integerString),
            ConsoleControlSpec(id: "rms", title: "RMS", shortTitle: "RMS", color: AppTheme.knobWhite, value: $inferenceViewModel.rmsMixRate, range: 0...1, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "protect", title: "GUARD", shortTitle: "GRD", color: AppTheme.knobWhite, value: $inferenceViewModel.protect, range: 0...0.5, step: 0.01, isInteractive: true, formatter: decimalString),
            ConsoleControlSpec(id: "batch", title: "QUEUE", shortTitle: "QUE", color: AppTheme.knobWhite, value: .constant(batchViewModel.inputDirectoryURL != nil || !batchViewModel.inputFileURLs.isEmpty ? 1 : 0.15), range: 0...1, step: 0.01, isInteractive: false, formatter: percentString),
            ConsoleControlSpec(id: "preview", title: "PLAY", shortTitle: "PLY", color: AppTheme.knobWhite, value: .constant(inferenceViewModel.outputAudioURL == nil ? 0.15 : 1), range: 0...1, step: 0.01, isInteractive: false, formatter: percentString),
        ]
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

    private func integerString(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private func decimalString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

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
        VStack(spacing: compact ? 3 : 12) {
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
                    .padding(compact ? 8 : 11)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            .padding(compact ? 8 : 11)
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
                            .padding(compact ? 8 : 11)
                    }
                    .overlay {
                        Image(systemName: item.systemImage)
                            .font(.system(size: compact ? 10 : 14, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
            }
            .frame(width: compact ? 34 : 66, height: compact ? 34 : 66)

            Text(item.title)
                .font(.system(size: compact ? 5 : 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)
        }
        .frame(width: compact ? 36 : 76)
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
            Text(spec.shortTitle)
                .font(.system(size: compactHeight ? 9 : 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)

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
                    .gesture(faderGesture)
            }
            .frame(width: max(50, width * 0.72), height: trackHeight)

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
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(spec.isInteractive ? 1 : 0.8)
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

    private func quantized(_ value: Double) -> Double {
        let stepped = (value / spec.step).rounded() * spec.step
        return min(max(stepped, spec.range.lowerBound), spec.range.upperBound)
    }
}

private struct ConsoleToastView: View {
    let toast: AppToast

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(iconTint)
            }

            Text(toast.message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.78))
                .lineLimit(2)
                .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.panelGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(iconTint.opacity(0.42), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.16), radius: 12, y: 8)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.labelInk)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle((accent ?? Color.black).opacity(accent == nil ? 0.62 : 0.78))
                .lineLimit(1)
        }
        .frame(minWidth: 72, alignment: .leading)
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
                        .foregroundStyle(accent.opacity(0.82))
                        .lineLimit(1)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.labelInk)

                if options.isEmpty {
                    Text(emptyState.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(options) { option in
                                Button {
                                    onSelect(option.id)
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(option.id == selectedID ? accent : Color.black.opacity(0.18))
                                            .frame(width: 8, height: 8)

                                        Text(option.title.uppercased())
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.black.opacity(0.78))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(option.id == selectedID ? accent.opacity(0.12) : Color.white.opacity(0.20))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
            .padding(14)
            .frame(width: 300)
            .background(AppTheme.panelGradient)
        }
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
    let onSelect: (String) -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: compactHeight ? 3 : 5) {
                    Text(title)
                        .font(.system(size: compactHeight ? 9 : 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk)
                    Text(value.uppercased())
                        .font(.system(size: compactHeight ? 11 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle((accent ?? Color.black).opacity(accent == nil ? 0.72 : 0.82))
                        .lineLimit(1)
                    Text(detail.uppercased())
                        .font(.system(size: compactHeight ? 8 : 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(spacing: compactHeight ? 4 : 6) {
                    Text(actionLabel)
                        .font(.system(size: compactHeight ? 8 : 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.68))
                    Image(systemName: "chevron.down")
                        .font(.system(size: compactHeight ? 10 : 11, weight: .bold))
                        .foregroundStyle((accent ?? Color.black).opacity(0.7))
                }
                .frame(width: compactHeight ? 42 : 48, height: compactHeight ? 36 : 44)
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
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.labelInk)
                    Spacer()
                    Text("\(options.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if options.isEmpty {
                    Text(emptyState.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(options) { option in
                                Button {
                                    onSelect(option.id)
                                    isPresented = false
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        ZStack {
                                            Circle()
                                                .fill(option.id == selectedID ? (accent ?? AppTheme.knobOrange).opacity(0.22) : Color.white.opacity(0.16))
                                                .frame(width: 26, height: 26)
                                            if option.id == selectedID {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle((accent ?? AppTheme.knobOrange).opacity(0.92))
                                            } else {
                                                Circle()
                                                    .fill(Color.black.opacity(0.32))
                                                    .frame(width: 7, height: 7)
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(option.title.uppercased())
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(Color.black.opacity(0.78))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            if let subtitle = option.subtitle, !subtitle.isEmpty {
                                                Text(subtitle)
                                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.secondary)
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
                                            .fill(option.id == selectedID ? (accent ?? AppTheme.knobOrange).opacity(0.14) : Color.white.opacity(0.24))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .strokeBorder(Color.black.opacity(option.id == selectedID ? 0.10 : 0.06), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 280)
                }
            }
            .padding(14)
            .frame(width: 320)
            .background(
                ZStack {
                    AppTheme.panelGradient
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
        }
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
                        .foregroundStyle((accent ?? Color.black).opacity(accent == nil ? 0.72 : 0.82))
                        .lineLimit(1)
                    Text(detail.uppercased())
                        .font(.system(size: compactHeight ? 8 : 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.8))
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

    private func lastPath(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

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
