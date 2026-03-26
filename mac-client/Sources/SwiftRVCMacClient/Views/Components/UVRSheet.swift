import SwiftUI

struct UVRSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: UVRViewModel

    let onChooseInputDirectory: () -> Void
    let onChooseInputFiles: () -> Void
    let onChooseVocalOutputDirectory: () -> Void
    let onChooseInstrumentalOutputDirectory: () -> Void
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("UVR")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(UVRSheetHeaderActionButtonStyle())
                .keyboardShortcut(.cancelAction)
            }

            if viewModel.isRunning {
                UVRRuntimeProgressCard(
                    title: "UVR Separation Running",
                    subtitle: runningSubtitle,
                    modelName: viewModel.selectedModelName,
                    startedAt: viewModel.runStartedAt
                )
            }

            Picker("Model", selection: Binding(
                get: { viewModel.selectedModelName ?? "" },
                set: { viewModel.selectedModelName = $0.isEmpty ? nil : $0 }
            )) {
                Text("Select model").tag("")
                ForEach(viewModel.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            HStack(spacing: 10) {
                Button("Input Folder") { onChooseInputDirectory() }
                Button("Input Files") { onChooseInputFiles() }
                Text(inputSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button("Vocal Output") { onChooseVocalOutputDirectory() }
                Text(viewModel.vocalOutputDirectoryURL?.path ?? "Choose output folder")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button("Instrumental Output") { onChooseInstrumentalOutputDirectory() }
                Text(viewModel.instrumentalOutputDirectoryURL?.path ?? "Choose output folder")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Picker("Format", selection: $viewModel.format) {
                ForEach(OutputFormat.allCases) { format in
                    Text(format.rawValue.uppercased()).tag(format)
                }
            }
            .pickerStyle(.segmented)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if viewModel.isRunning || !viewModel.outputMessage.isEmpty {
                ScrollView {
                    Text(logOutput)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
            }

            HStack(spacing: 10) {
                Button("Open Vocals") { viewModel.openVocalOutputDirectory() }
                    .disabled(viewModel.vocalOutputDirectoryURL == nil)
                Button("Open Instrumentals") { viewModel.openInstrumentalOutputDirectory() }
                    .disabled(viewModel.instrumentalOutputDirectoryURL == nil)
                Spacer()
                Button(viewModel.isRunning ? "Running..." : "Run UVR") {
                    onRun()
                }
                .disabled(viewModel.isRunning || viewModel.selectedModelName == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 760, idealWidth: 840, minHeight: 420, idealHeight: 560)
    }

    private var inputSummary: String {
        if let directory = viewModel.inputDirectoryURL {
            return directory.path
        }
        if !viewModel.inputFileURLs.isEmpty {
            return viewModel.inputFileURLs.map(\.lastPathComponent).joined(separator: ", ")
        }
        return "Choose a folder or explicit files"
    }

    private var runningSubtitle: String {
        if let directory = viewModel.inputDirectoryURL {
            return "Directory source active: \(directory.lastPathComponent)"
        }
        let fileCount = viewModel.inputFileURLs.count
        if fileCount == 1, let file = viewModel.inputFileURLs.first {
            return "Separating 1 file: \(file.lastPathComponent)"
        }
        if fileCount > 1 {
            return "Separating \(fileCount) files in the current queue"
        }
        return "Preparing the UVR separation pipeline"
    }

    private var logOutput: String {
        if !viewModel.outputMessage.isEmpty {
            return viewModel.outputMessage
        }
        if viewModel.isRunning {
            return "UVR is preparing the separation pipeline. The fluorescent bar stays active until the engine returns the final result."
        }
        return ""
    }
}

private struct UVRRuntimeProgressCard: View {
    let title: String
    let subtitle: String
    let modelName: String?
    let startedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RUN WINDOW")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.72))

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    BusyFluorescentBarView(style: .global)

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(title.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.92))
                        Spacer()
                        Text(elapsedString(now: context.date))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.60))
                    }

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.74))

                    if let modelName, !modelName.isEmpty {
                        Text("MODEL \(modelName.uppercased())")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.58))
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func elapsedString(now: Date) -> String {
        guard let startedAt else { return "0.0S" }
        let elapsed = max(now.timeIntervalSince(startedAt), 0)
        return "\(elapsed.formatted(.number.precision(.fractionLength(1))))S"
    }
}

private struct UVRSheetHeaderActionButtonStyle: ButtonStyle {
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
