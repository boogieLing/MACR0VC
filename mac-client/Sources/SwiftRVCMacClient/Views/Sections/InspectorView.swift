import SwiftUI

struct InspectorView: View {
    let navigation: NavigationDestination
    let indexPaths: [String]
    let selectedModelName: String?
    let modelsCount: Int
    let indexCount: Int
    let modelInfoSummary: String
    let environment: AppEnvironment
    let statusMessage: String
    @ObservedObject var inferenceViewModel: InferenceViewModel
    @ObservedObject var batchViewModel: BatchViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch navigation {
                case .singleConvert:
                    singleInspector
                case .batchConvert:
                    batchInspector
                case .models:
                    modelInspector
                case .engine:
                    engineInspector
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .navigationSplitViewColumnWidth(min: 320, ideal: 340)
    }

    private var singleInspector: some View {
        SectionCard(L10n.tr("section.inspector.single.title"), subtitle: L10n.tr("section.inspector.single.subtitle")) {
            Picker(L10n.tr("picker.index_path"), selection: $inferenceViewModel.selectedIndexPath) {
                Text(L10n.tr("picker.auto")).tag(String?.none)
                ForEach(indexPaths, id: \.self) { path in
                    Text((path as NSString).lastPathComponent).tag(Optional(path))
                }
            }
            SliderRow(title: L10n.tr("slider.transpose"), value: $inferenceViewModel.transpose, range: -24...24, step: 1)
            Picker(L10n.tr("picker.f0_method"), selection: $inferenceViewModel.f0Method) {
                ForEach(F0Method.allCases) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            SliderRow(title: L10n.tr("slider.index_rate"), value: $inferenceViewModel.indexRate, range: 0...1, step: 0.01)
            SliderRow(title: L10n.tr("slider.filter_radius"), value: $inferenceViewModel.filterRadius, range: 0...7, step: 1)
            SliderRow(title: L10n.tr("slider.resample"), value: $inferenceViewModel.resampleSR, range: 0...48_000, step: 100)
            SliderRow(title: L10n.tr("slider.rms_mix"), value: $inferenceViewModel.rmsMixRate, range: 0...1, step: 0.01)
            SliderRow(title: L10n.tr("slider.protect"), value: $inferenceViewModel.protect, range: 0...0.5, step: 0.01)
        }
    }

    private var batchInspector: some View {
        SectionCard(L10n.tr("section.inspector.batch.title"), subtitle: L10n.tr("section.inspector.batch.subtitle")) {
            Picker(L10n.tr("picker.index_path"), selection: $batchViewModel.selectedIndexPath) {
                Text(L10n.tr("picker.auto")).tag(String?.none)
                ForEach(indexPaths, id: \.self) { path in
                    Text((path as NSString).lastPathComponent).tag(Optional(path))
                }
            }
            Picker(L10n.tr("picker.output_format"), selection: $batchViewModel.format) {
                ForEach(OutputFormat.allCases) { format in
                    Text(format.rawValue.uppercased()).tag(format)
                }
            }
            SliderRow(title: L10n.tr("slider.transpose"), value: $batchViewModel.transpose, range: -24...24, step: 1)
            SliderRow(title: L10n.tr("slider.index_rate"), value: $batchViewModel.indexRate, range: 0...1, step: 0.01)
            SliderRow(title: L10n.tr("slider.filter_radius"), value: $batchViewModel.filterRadius, range: 0...7, step: 1)
            SliderRow(title: L10n.tr("slider.resample"), value: $batchViewModel.resampleSR, range: 0...48_000, step: 100)
            SliderRow(title: L10n.tr("slider.rms_mix"), value: $batchViewModel.rmsMixRate, range: 0...1, step: 0.01)
            SliderRow(title: L10n.tr("slider.protect"), value: $batchViewModel.protect, range: 0...0.5, step: 0.01)
        }
    }

    private var modelInspector: some View {
        SectionCard(L10n.tr("section.inspector.model.title"), subtitle: L10n.tr("section.inspector.model.subtitle")) {
            LabeledContent(L10n.tr("label.selected_model"), value: selectedModelName ?? L10n.tr("status.none"))
            LabeledContent(L10n.tr("label.model_count"), value: "\(modelsCount)")
            LabeledContent(L10n.tr("label.index_count"), value: "\(indexCount)")
            Text(modelInfoSummary)
                .foregroundStyle(.secondary)
        }
    }

    private var engineInspector: some View {
        SectionCard(L10n.tr("section.inspector.system.title"), subtitle: L10n.tr("section.inspector.system.subtitle")) {
            Text("\(L10n.tr("label.engine_root")): \(environment.engineRoot.path)")
            Text("\(L10n.tr("label.bridge_script")): \(environment.bridgeScriptURL.path)")
            Text("\(L10n.tr("label.status")): \(statusMessage)")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(step < 1 ? 2 : 0))))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
