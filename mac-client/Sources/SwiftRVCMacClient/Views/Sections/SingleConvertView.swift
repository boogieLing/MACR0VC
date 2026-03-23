import AppKit
import SwiftUI

struct SingleConvertView: View {
    let models: [ModelOption]
    let selectedModelName: String?
    let engineState: EngineState
    @ObservedObject var inferenceViewModel: InferenceViewModel
    @ObservedObject var audioPlayer: AudioPreviewPlayer
    let selectModel: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(L10n.tr("section.single.title"), subtitle: L10n.tr("section.single.subtitle")) {
                    HStack(spacing: 12) {
                        Picker(L10n.tr("picker.model"), selection: modelBinding) {
                            Text(L10n.tr("picker.select_model")).tag(String?.none)
                            ForEach(models) { model in
                                Text(model.name).tag(Optional(model.name))
                            }
                        }
                        .frame(maxWidth: 320)

                        Button(L10n.tr("action.choose_audio")) {
                            chooseAudioFile()
                        }
                        .buttonStyle(.borderedProminent)

                        if let inputFileURL = inferenceViewModel.inputFileURL {
                            Text(inputFileURL.lastPathComponent)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Button(inferenceViewModel.isRunning ? L10n.tr("action.converting") : L10n.tr("action.convert")) {
                            Task { await inferenceViewModel.convert(selectedModelName: selectedModelName) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inferenceViewModel.isRunning || engineState != .ready)

                        Button(L10n.tr("action.play_result")) {
                            audioPlayer.play()
                        }
                        .buttonStyle(.bordered)
                        .disabled(inferenceViewModel.outputAudioURL == nil)

                        Button(L10n.tr("action.stop_preview")) {
                            audioPlayer.stop()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!audioPlayer.isPlaying)

                        if let outputURL = inferenceViewModel.outputAudioURL {
                            Button(L10n.tr("action.reveal_output")) {
                                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if !inferenceViewModel.outputMessage.isEmpty {
                        Text(inferenceViewModel.outputMessage)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage = inferenceViewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                SectionCard(L10n.tr("section.single.current.title"), subtitle: L10n.tr("section.single.current.subtitle")) {
                    LabeledContent(L10n.tr("label.input_file"), value: inferenceViewModel.inputFileURL?.path ?? L10n.tr("status.none"))
                    LabeledContent(L10n.tr("label.selected_index"), value: inferenceViewModel.selectedIndexPath ?? L10n.tr("status.none"))
                    LabeledContent(L10n.tr("label.loaded_model"), value: selectedModelName ?? L10n.tr("status.none"))
                    LabeledContent(L10n.tr("label.preview_state"), value: audioPlayer.isPlaying ? L10n.tr("preview.playing") : L10n.tr("preview.stopped"))
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

    private func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            inferenceViewModel.inputFileURL = panel.url
        }
    }
}
