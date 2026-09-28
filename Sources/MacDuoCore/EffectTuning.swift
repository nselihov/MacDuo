import Foundation

/// Live optical controls used while calibrating the MVP on a real MacBook.
/// Values are deliberately dimensionless except for responseSeconds, so the
/// renderer can apply them consistently on Retina displays of different sizes.
public struct EffectTuning: Codable, Equatable, Sendable {
    public var blurStrength: Double
    // Kept only for decoding existing v1 presets. The shared system blur is uniform.
    public var verticalContrast: Double
    public var edgeDissolve: Double
    public var perspectiveDepth: Double
    public var responseSeconds: Double

    public init(
        blurStrength: Double = 1,
        verticalContrast: Double = 0.92,
        edgeDissolve: Double = 1,
        perspectiveDepth: Double = 1,
        responseSeconds: Double = 0.045
    ) {
        self.blurStrength = blurStrength
        self.verticalContrast = verticalContrast
        self.edgeDissolve = edgeDissolve
        self.perspectiveDepth = perspectiveDepth
        self.responseSeconds = responseSeconds
    }

    public static let standard = EffectTuning()

    public func clamped() -> EffectTuning {
        EffectTuning(
            blurStrength: blurStrength.clamped(to: 0.55 ... 1.6),
            verticalContrast: verticalContrast.clamped(to: 0.4 ... 1),
            edgeDissolve: edgeDissolve.clamped(to: 0.55 ... 1.8),
            perspectiveDepth: perspectiveDepth.clamped(to: 0.65 ... 1.4),
            responseSeconds: responseSeconds.clamped(to: 0.018 ... 0.12)
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
