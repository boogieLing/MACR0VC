import SwiftUI

struct EngineView: View {
    let environment: AppEnvironment
    @ObservedObject var engineController: EngineController
    let statusMessage: String
    let startAction: () -> Void
    let restartAction: () -> Void
    let stopAction: () -> Void
    @State private var showsRecentLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(L10n.tr("section.engine.title"), subtitle: L10n.tr("section.engine.subtitle")) {
                    HStack(spacing: 12) {
                        Button(L10n.tr("action.start")) {
                            startAction()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(engineController.state == .starting || engineController.state == .ready)

                        Button(L10n.tr("action.restart")) {
                            restartAction()
                        }
                        .buttonStyle(.bordered)
                        .disabled(engineController.state == .starting)

                        Button(L10n.tr("action.stop")) {
                            stopAction()
                        }
                        .buttonStyle(.borderless)
                    }

                    LabeledContent(L10n.tr("label.repository_root"), value: environment.repoRoot.path)
                    LabeledContent(L10n.tr("label.engine_root"), value: environment.engineRoot.path)
                    LabeledContent(L10n.tr("label.port"), value: engineController.port.map(String.init) ?? "—")
                    LabeledContent(L10n.tr("label.status"), value: engineController.state.label)
                }

                SectionCard(L10n.tr("section.diagnostics.title"), subtitle: L10n.tr("section.diagnostics.subtitle")) {
                    Text(statusMessage)
                        .font(.headline)
                    if let lastError = engineController.lastError {
                        Text(lastError)
                            .foregroundStyle(.red)
                    }
                    if !engineController.recentLog.isEmpty {
                        DisclosureGroup(isExpanded: $showsRecentLog) {
                            ScrollView {
                                Text(verbatim: engineController.recentLog)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                            }
                            .frame(minHeight: 160, maxHeight: 220)
                            .background(Color.black.opacity(0.82))
                            .foregroundStyle(Color.green.opacity(0.88))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 8)
                        } label: {
                            HStack {
                                Text(L10n.tr("diagnostics.recent_log"))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(
                                    L10n.tr(
                                        "diagnostics.log_lines_count",
                                        engineController.recentLog.split(separator: "\n", omittingEmptySubsequences: false).count
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 4)
        }
    }
}
