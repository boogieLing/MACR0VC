import SwiftUI

struct UVRSheet: View {
    @ObservedObject var viewModel: UVRViewModel

    let onChooseInputDirectory: () -> Void
    let onChooseInputFiles: () -> Void
    let onChooseVocalOutputDirectory: () -> Void
    let onChooseInstrumentalOutputDirectory: () -> Void
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("UVR")
                .font(.system(size: 18, weight: .bold, design: .monospaced))

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

            if !viewModel.outputMessage.isEmpty {
                ScrollView {
                    Text(viewModel.outputMessage)
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
}
