import SwiftUI

struct ONNXSheet: View {
    @ObservedObject var viewModel: ONNXViewModel

    let onChooseModelFile: () -> Void
    let onChooseExportFile: () -> Void
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EXPORT ONNX")
                .font(.system(size: 18, weight: .bold, design: .monospaced))

            HStack(spacing: 10) {
                Button("Checkpoint") { onChooseModelFile() }
                Text(viewModel.modelFileURL?.path ?? "Choose an input checkpoint")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button("Output") { onChooseExportFile() }
                Text(viewModel.exportFileURL?.path ?? "Choose an output .onnx path")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

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
                Button("Reveal Output") { viewModel.revealExportedFile() }
                    .disabled(viewModel.exportFileURL == nil)
                Spacer()
                Button(viewModel.isRunning ? "Exporting..." : "Export") {
                    onRun()
                }
                .disabled(viewModel.isRunning || viewModel.modelFileURL == nil || viewModel.exportFileURL == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 320, idealHeight: 420)
    }
}
