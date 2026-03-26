import SwiftUI

struct BusyFluorescentBarView: View {
    enum Style {
        case global
        case inline

        var height: CGFloat {
            switch self {
            case .global:
                return 8
            case .inline:
                return 6
            }
        }

        var sweepWidthRatio: CGFloat {
            switch self {
            case .global:
                return 0.44
            case .inline:
                return 0.58
            }
        }

        var glowRadius: CGFloat {
            switch self {
            case .global:
                return 7
            case .inline:
                return 4
            }
        }
    }

    let style: Style

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    /// 初始化统一等待条样式，供壳层和局部卡片复用同一视觉语言。
    init(style: Style) {
        self.style = style
    }

    var body: some View {
        GeometryReader { proxy in
            let sweepWidth = max(proxy.size.width * style.sweepWidthRatio, style == .global ? 96 : 52)

            RoundedRectangle(cornerRadius: style.height / 2, style: .continuous)
                .fill(AppTheme.busyTrack)
                .overlay {
                    RoundedRectangle(cornerRadius: style.height / 2, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: style.height / 2, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.busyGlowIndigo.opacity(0.22),
                                    AppTheme.busyGlowIndigo,
                                    AppTheme.busyGlowViolet,
                                    AppTheme.busyGlowPink,
                                    AppTheme.busyGlowYellow,
                                    AppTheme.busyGlowYellow.opacity(0.28),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: reduceMotion ? sweepWidth : sweepWidth * 0.82)
                        .blur(radius: style.glowRadius * 0.9)
                        .offset(x: sweepOffset(in: proxy.size.width, sweepWidth: sweepWidth))
                        .animation(animation, value: isAnimating)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: style.height / 2, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.busyGlowIndigo.opacity(0.2),
                                    AppTheme.busyGlowViolet.opacity(0.3),
                                    AppTheme.busyGlowPink.opacity(0.34),
                                    AppTheme.busyGlowYellow.opacity(0.24),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: style.height / 2, style: .continuous)
                        .fill(Color.white.opacity(style == .global ? 0.08 : 0.05))
                        .padding(1)
                }
                .clipShape(RoundedRectangle(cornerRadius: style.height / 2, style: .continuous))
        }
        .frame(height: style.height)
        .onAppear {
            guard !reduceMotion else { return }
            isAnimating = true
        }
        .onChange(of: reduceMotion) {
            isAnimating = !reduceMotion
        }
    }

    /// 根据是否启用动态效果，返回荧光扫光的位置。
    private func sweepOffset(in width: CGFloat, sweepWidth: CGFloat) -> CGFloat {
        if reduceMotion {
            return width * 0.14
        }
        return isAnimating ? width + sweepWidth : -sweepWidth
    }

    /// 统一控制荧光条的扫动节奏，避免在不同挂载点出现动画速度漂移。
    private var animation: Animation? {
        guard !reduceMotion else { return nil }
        return .linear(duration: style == .global ? 1.25 : 1.05).repeatForever(autoreverses: false)
    }
}
