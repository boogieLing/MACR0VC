import SwiftUI

struct StatusBarView: View {
    @ObservedObject var engineController: EngineController
    let availablePortDescription: String
    let selectedModelName: String?
    let lastExecutionSummary: String

    var body: some View {
        HStack(spacing: 12) {
            StatusPill(
                label: L10n.tr("status.engine"),
                value: engineController.state.label,
                systemImage: engineController.state.systemImage
            )
            StatusPill(
                label: L10n.tr("status.port"),
                value: availablePortDescription,
                systemImage: "point.3.connected.trianglepath.dotted"
            )
            StatusPill(
                label: L10n.tr("status.model"),
                value: selectedModelName ?? L10n.tr("status.none"),
                systemImage: "square.stack.3d.up"
            )
            Spacer()
            Text(lastExecutionSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [Color.white.opacity(0.46), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
    }
}
