import SwiftUI

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .fill(AppTheme.panelGradient)
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.42), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.68), lineWidth: 1)
        )
        .shadow(color: AppTheme.shadowColor, radius: 12, y: 6)
    }
}
