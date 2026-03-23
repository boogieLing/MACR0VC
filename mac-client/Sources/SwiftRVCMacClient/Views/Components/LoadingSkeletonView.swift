import SwiftUI

struct LoadingSkeletonView: View {
    let cardCount: Int

    init(cardCount: Int = 3) {
        self.cardCount = cardCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(0..<cardCount, id: \.self) { index in
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.62))
                        .frame(width: index == 0 ? 220 : 180, height: 18)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.44))
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.34))
                        .frame(height: index == 1 ? 140 : 92)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.38), lineWidth: 1)
                )
            }
        }
        .redacted(reason: .placeholder)
    }
}
