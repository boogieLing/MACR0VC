import SwiftUI

struct ModelsView: View {
    let models: [ModelOption]
    let indexPaths: [String]
    let selectedModelName: String?
    let modelInfoSummary: String
    let isRefreshingModels: Bool
    let engineReady: Bool
    let refreshCatalog: () -> Void
    let openWeightsFolder: () -> Void
    let openIndexFolder: () -> Void
    let selectModel: (String) -> Void
    @State private var showsAllIndexPaths = false

    var body: some View {
        HStack(spacing: 18) {
            SectionCard(L10n.tr("section.models.available.title"), subtitle: L10n.tr("section.models.available.subtitle")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button(L10n.tr("action.refresh_catalog")) {
                            refreshCatalog()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!engineReady)

                        Button(L10n.tr("action.open_weights")) {
                            openWeightsFolder()
                        }
                        .buttonStyle(.bordered)

                        Button(L10n.tr("action.open_indices")) {
                            openIndexFolder()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Text(L10n.tr("models.loaded_count", models.count))
                            .foregroundStyle(.secondary)
                    }

                    Text(L10n.tr("models.drop_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isRefreshingModels && models.isEmpty {
                    LoadingSkeletonView(cardCount: 2)
                } else if models.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("models.empty.title"),
                        systemImage: "square.stack.3d.up.slash",
                        description: Text(L10n.tr("models.empty.body"))
                    )
                    .frame(minHeight: 420)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(models) { model in
                                modelRow(model)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 420)
                }
            }

            SectionCard(L10n.tr("section.models.summary.title"), subtitle: L10n.tr("section.models.summary.subtitle")) {
                Text(selectedModelName ?? L10n.tr("models.no_selection"))
                    .font(.title2.weight(.semibold))
                Text(modelInfoSummary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Divider()
                DisclosureGroup(isExpanded: $showsAllIndexPaths) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(indexPaths, id: \.self) { path in
                            Text(path)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text(L10n.tr("models.available_index_paths"))
                            .font(.headline)
                        Spacer()
                        Text(L10n.tr("models.index_count", indexPaths.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.easeOut(duration: 0.16), value: models.count)
    }

    private func modelRow(_ model: ModelOption) -> some View {
        Button {
            selectModel(model.name)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.name)
                        .font(.headline)
                    Spacer(minLength: 12)
                    if selectedModelName == model.name {
                        Text(L10n.tr("models.selected_badge"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }

                if !model.indexPath.isEmpty {
                    Text(model.indexPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(modelRowBackground(isSelected: selectedModelName == model.name))
            .overlay(modelRowBorder(isSelected: selectedModelName == model.name))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func modelRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                isSelected
                    ? AnyShapeStyle(AppTheme.selectedNavigationGradient)
                    : AnyShapeStyle(Color.white.opacity(0.10))
            )
    }

    private func modelRowBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                isSelected ? Color.white.opacity(0.24) : Color.white.opacity(0.10),
                lineWidth: 1
            )
    }
}
