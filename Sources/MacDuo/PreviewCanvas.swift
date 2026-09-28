import MacDuoCore
import SwiftUI

struct PreviewCanvas: View {
    let angle: Double
    let velocity: Double
    let parameters: FoldParameters
    let tuning: EffectTuning
    let hasDesktopFrame: Bool
    let showsArtwork: Bool
    let frameStore: DesktopFrameStore

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = min(geometry.size.width * 0.82, 660)
            let screenHeight = screenWidth * 0.63

            ZStack(alignment: .bottom) {
                stageBackground

                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    renderedScreenPlane
                        .frame(width: screenWidth, height: screenHeight)
                        .offset(y: -26)

                    hinge(width: screenWidth)
                        .offset(y: -26)

                    Spacer(minLength: 38)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(MacDuoTheme.line, lineWidth: 1)
            }
        }
    }

    private var stageBackground: some View {
        ZStack {
            Color.black.opacity(0.78)

            LinearGradient(
                colors: [
                    .white.opacity(0.035),
                    .clear,
                    .black.opacity(0.32),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                Spacer()
                Rectangle()
                    .fill(.white.opacity(0.045))
                    .frame(height: 1)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 52)
            }
        }
    }

    private var screenPlane: some View {
        ZStack {
            if hasDesktopFrame {
                MetalFoldPreviewSurface(frameStore: frameStore,
                                        parameters: parameters, tuning: tuning)
            } else if showsArtwork {
                FoldPreviewSurface(frameStore: frameStore,
                                   parameters: parameters, tuning: tuning,
                                   hasDesktopFrame: false)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MacDuoTheme.background)
            }

            if hasDesktopFrame {
                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(MacDuoTheme.ready)
                                .frame(width: 6, height: 6)
                            Text("LIVE · BUILT-IN")
                        }
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.48), in: Capsule())

                        Spacer()
                    }
                    Spacer()
                }
                .padding(14)
                .opacity(max(0, 1 - parameters.progress * 2.4))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.13), lineWidth: 1)
                .opacity(max(0, 1 - parameters.progress * 2.2))
                .blur(radius: parameters.progress * 3)
        }
        .shadow(color: .black.opacity(0.55), radius: 22, y: 16)
    }

    private var renderedScreenPlane: some View { screenPlane }

    private func hinge(width: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(0.86))
                .frame(width: width * 0.48, height: 8)

            Capsule()
                .fill(.white.opacity(0.18))
                .frame(width: width * 0.36, height: 1)
                .offset(y: -2)
        }
        .frame(height: 14)
    }
}

struct SpatialArtwork: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 13), count: 4)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.11, blue: 0.12),
                    Color(red: 0.16, green: 0.15, blue: 0.14),
                    Color(red: 0.055, green: 0.055, blue: 0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(MacDuoTheme.accent.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: -130, y: -90)

            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("ЭКРАН  /  ПРЕВЬЮ")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.74))
                    Spacer()
                    Text("MACDUO")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                }

                Spacer()

                LazyVGrid(columns: columns, spacing: 13) {
                    ForEach(0 ..< 8, id: \.self) { index in
                        RoundedRectangle(cornerRadius: index.isMultiple(of: 3) ? 16 : 10)
                            .fill(tileColor(for: index))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .topLeading) {
                                Circle()
                                    .fill(.white.opacity(0.62))
                                    .frame(width: 5, height: 5)
                                    .padding(9)
                            }
                    }
                }

                Text("Изображение остаётся. Плоскость движется.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(24)
        }
    }

    private func tileColor(for index: Int) -> Color {
        switch index % 4 {
        case 0: Color.white.opacity(0.14)
        case 1: MacDuoTheme.accent.opacity(0.30)
        case 2: Color.white.opacity(0.08)
        default: Color.white.opacity(0.18)
        }
    }
}
