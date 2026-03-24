import SwiftUI

struct CheckpointToolsSheet: View {
    @ObservedObject var viewModel: CheckpointToolsViewModel

    let onRunComparison: () -> Void
    let onChooseCheckpointFile: () -> Void
    let onLoadMetadata: () -> Void
    let onModifyMetadata: () -> Void
    let onChooseMergeModelA: () -> Void
    let onChooseMergeModelB: () -> Void
    let onRunMerge: () -> Void
    let onChooseExtractModel: () -> Void
    let onRunExtract: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("CKPT TOOLS")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))

                Text("MODEL COMPARISON")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("Model A long ID", text: $viewModel.modelIDA)
                    .textFieldStyle(.roundedBorder)

                TextField("Model B long ID", text: $viewModel.modelIDB)
                    .textFieldStyle(.roundedBorder)

                Divider()

                Text("MODEL METADATA")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Checkpoint File") { onChooseCheckpointFile() }
                    Text(viewModel.selectedCheckpointFileURL?.path ?? "Choose a checkpoint file")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                TextField("Save name (optional, defaults to source file name)", text: $viewModel.saveName)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $viewModel.metadataText)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .frame(minHeight: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                Divider()

                Text("MODEL FUSION")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Model A") { onChooseMergeModelA() }
                    Text(viewModel.mergeModelAURL?.path ?? "Choose checkpoint A")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button("Model B") { onChooseMergeModelB() }
                    Text(viewModel.mergeModelBURL?.path ?? "Choose checkpoint B")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Weight A")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        Spacer()
                        Text(viewModel.mergeWeightA.formatted(.number.precision(.fractionLength(2))))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.mergeWeightA, in: 0...1)
                }

                Picker("Target SR", selection: $viewModel.mergeTargetSampleRate) {
                    Text("32k").tag("32k")
                    Text("40k").tag("40k")
                    Text("48k").tag("48k")
                }
                .pickerStyle(.segmented)

                Picker("Version", selection: $viewModel.mergeVersion) {
                    Text("v1").tag("v1")
                    Text("v2").tag("v2")
                }
                .pickerStyle(.segmented)

                Toggle("Has pitch guidance", isOn: $viewModel.mergeHasPitchGuidance)

                TextField("Merged model save name", text: $viewModel.mergeSaveName)
                    .textFieldStyle(.roundedBorder)

                TextField("Merged model info", text: $viewModel.mergeInfoText)
                    .textFieldStyle(.roundedBorder)

                Divider()

                Text("MODEL EXTRACTION")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Training CKPT") { onChooseExtractModel() }
                    Text(viewModel.extractModelURL?.path ?? "Choose a training checkpoint")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Picker("Extract SR", selection: $viewModel.extractTargetSampleRate) {
                    Text("32k").tag("32k")
                    Text("40k").tag("40k")
                    Text("48k").tag("48k")
                }
                .pickerStyle(.segmented)

                Picker("Extract Version", selection: $viewModel.extractVersion) {
                    Text("v1").tag("v1")
                    Text("v2").tag("v2")
                }
                .pickerStyle(.segmented)

                Toggle("Extract with pitch guidance", isOn: $viewModel.extractHasPitchGuidance)

                TextField("Extracted model save name", text: $viewModel.extractSaveName)
                    .textFieldStyle(.roundedBorder)

                TextField("Author", text: $viewModel.extractAuthor)
                    .textFieldStyle(.roundedBorder)

                TextField("Extracted model info", text: $viewModel.extractInfoText)
                    .textFieldStyle(.roundedBorder)

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

                HStack {
                    Button("View Info") {
                        onLoadMetadata()
                    }
                    .disabled(viewModel.isRunning || viewModel.selectedCheckpointFileURL == nil)
                    Button("Save Info") {
                        onModifyMetadata()
                    }
                    .disabled(viewModel.isRunning || viewModel.selectedCheckpointFileURL == nil)
                    Button("Merge") {
                        onRunMerge()
                    }
                    .disabled(viewModel.isRunning || viewModel.mergeModelAURL == nil || viewModel.mergeModelBURL == nil)
                    Button("Extract") {
                        onRunExtract()
                    }
                    .disabled(viewModel.isRunning || viewModel.extractModelURL == nil)
                    Spacer()
                    Button(viewModel.isRunning ? "Running..." : "Compare") {
                        onRunComparison()
                    }
                    .disabled(viewModel.isRunning)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 460, idealHeight: 620)
    }
}
