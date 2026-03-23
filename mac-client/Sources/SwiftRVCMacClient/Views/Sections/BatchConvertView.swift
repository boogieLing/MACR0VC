import AppKit
import SwiftUI

struct BatchConvertView: View {
    let models: [ModelOption]
    let selectedModelName: String?
    let engineState: EngineState
    @ObservedObject var batchViewModel: BatchViewModel
    let selectModel: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(L10n.tr("section.batch.title"), subtitle: L10n.tr("section.batch.subtitle")) {
                    Picker(L10n.tr("picker.model"), selection: modelBinding) {
                        Text(L10n.tr("picker.select_model")).tag(String?.none)
                        ForEach(models) { model in
                            Text(model.name).tag(Optional(model.name))
                        }
                    }
                    .frame(maxWidth: 320)

                    HStack(spacing: 12) {
                        Button(L10n.tr("action.input_folder")) {
                            chooseInputDirectory()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(L10n.tr("action.input_files")) {
                            chooseInputFiles()
                        }
                        .buttonStyle(.bordered)

                        Button(L10n.tr("action.output_folder")) {
                            chooseOutputDirectory()
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(L10n.tr("label.input_directory"), value: batchViewModel.inputDirectoryURL?.path ?? L10n.tr("status.none"))
                        LabeledContent(
                            L10n.tr("label.input_files"),
                            value: batchViewModel.inputFileURLs.isEmpty
                                ? L10n.tr("status.none")
                                : L10n.tr("batch.files.selected", batchViewModel.inputFileURLs.count)
                        )
                        LabeledContent(L10n.tr("label.output_directory"), value: batchViewModel.outputDirectoryURL?.path ?? L10n.tr("status.none"))
                    }

                    HStack(spacing: 12) {
                        Button(batchViewModel.isRunning ? L10n.tr("action.running") : L10n.tr("action.convert_batch")) {
                            Task { await batchViewModel.convert(selectedModelName: selectedModelName) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(batchViewModel.isRunning || engineState != .ready)

                        Button(L10n.tr("action.open_output_folder")) {
                            batchViewModel.openOutputDirectory()
                        }
                        .buttonStyle(.bordered)
                        .disabled(batchViewModel.outputDirectoryURL == nil)
                    }

                    if !batchViewModel.outputMessage.isEmpty {
                        Text(batchViewModel.outputMessage)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage = batchViewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var modelBinding: Binding<String?> {
        Binding<String?>(
            get: { selectedModelName },
            set: { newValue in
                guard let newValue else { return }
                selectModel(newValue)
            }
        )
    }

    private func chooseInputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            batchViewModel.inputDirectoryURL = panel.url
            batchViewModel.inputFileURLs = []
        }
    }

    private func chooseInputFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            batchViewModel.inputFileURLs = panel.urls
            batchViewModel.inputDirectoryURL = nil
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            batchViewModel.outputDirectoryURL = panel.url
        }
    }
}
