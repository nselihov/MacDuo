import AppKit
import MacDuoCore
import QuartzCore

/// Hides inverse-mesh faces before their source coordinates hit a clamped
/// screen edge. The companion mask darkens the empty side regions.
@MainActor
enum ProjectionValidityMask {
    static func makeLayer() -> CALayer {
        let layer = CALayer()
        layer.contentsGravity = .resize
        layer.minificationFilter = .linear
        layer.magnificationFilter = .linear
        return layer
    }

    static func update(_ layer: CALayer, sideShadow: CALayer, bounds: CGRect,
                       progress: Double, tuning: EffectTuning) {
        // The mask only contains broad feathered edges. At 128 samples its
        // narrowest 0.06-wide transition still spans several texels, while
        // generating one quarter as many pixels on the lock-screen main thread.
        let size = 128
        let p = min(max(progress, 0), 1)
        let eye = 3.1 / tuning.clamped().perspectiveDepth
        let bend = p * 1.36135682
        let sine = sin(bend), cosine = cos(bend)
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        var shadowBytes = [UInt8](repeating: 0, count: size * size * 4)
        let top = FoldGlassGeometry.project(.init(x: 0.5, y: 1),
                                            progress: p, tuning: tuning).y
        let strength = min(p / 0.28, 1)
        for row in 0..<size {
            let y = 1 - (Double(row) + 0.5) / Double(size)
            let denominator = max(eye * cosine - (y - 0.5) * sine, 0.001)
            let sourceY = eye * y / denominator
            let horizontalScale = (eye + sourceY * sine) / eye
            for column in 0..<size {
                let x = (Double(column) + 0.5) / Double(size)
                let sourceX = 0.5 + (x - 0.5) * horizontalScale
                let distance = min(min(sourceX, 1 - sourceX), 1 - sourceY)
                let t = min(max(distance / 0.06, 0), 1)
                let alpha = t * t * (3 - 2 * t)
                let offset = (row * size + column) * 4
                let value = UInt8((alpha * 255).rounded())
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
                bytes[offset + 3] = value
                let sideDistance = min(sourceX, 1 - sourceX)
                let sideT = min(max(sideDistance / 0.15, 0), 1)
                let sideFalloff = 1 - sideT * sideT * (3 - 2 * sideT)
                let heightT = min(max((y / max(top, 0.001) - 0.02) / 0.20, 0), 1)
                let heightWeight = heightT * heightT * (3 - 2 * heightT)
                let shadow = UInt8((strength * sideFalloff * heightWeight * 255).rounded())
                shadowBytes[offset] = shadow
                shadowBytes[offset + 1] = shadow
                shadowBytes[offset + 2] = shadow
                shadowBytes[offset + 3] = shadow
            }
        }
        guard let projectedImage = image(from: bytes, size: size) else { return }
        guard let shadowImage = image(from: shadowBytes, size: size) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        layer.contents = projectedImage
        sideShadow.frame = bounds
        sideShadow.contents = shadowImage
        CATransaction.commit()
    }

    private static func image(from bytes: [UInt8], size: Int) -> CGImage? {
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else { return nil }
        return image
    }
}
