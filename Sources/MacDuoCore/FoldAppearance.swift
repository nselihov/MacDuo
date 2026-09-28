import Foundation

/// Shared optical values for both fullscreen contexts and the small preview.
/// The accepted lock-screen effect is the reference; presentation adds no tuning.
public enum FoldAppearance {
    public static func blurRadius(parameters: FoldParameters, tuning: EffectTuning) -> Double {
        min(parameters.blurRadius * tuning.clamped().blurStrength * 0.45, 80)
    }

    /// Desktop Metal optics follow the calibrated lid angle alone. Velocity
    /// can still affect the legacy renderer without changing focus at a fixed
    /// position of the physical lid.
    public static func angleBlurRadius(progress: Double, tuning: EffectTuning) -> Double {
        let p = min(max(progress, 0), 1)
        let entrance = min(max(p / 0.16, 0), 1)
        let smoothEntrance = entrance * entrance * (3 - 2 * entrance)
        return min(sqrt(p) * 165 * smoothEntrance * tuning.clamped().blurStrength * 0.45, 80)
    }

    public static func response(deltaTime: Double, responseSeconds: Double) -> Double {
        1 - exp(-min(max(deltaTime, 0), 0.05) / max(responseSeconds, 0.001))
    }

    public static func opacity(radius: Double, progress: Double) -> Double {
        let amount = min(max(max(radius / 3, progress / 0.035), 0), 1)
        return amount * amount * (3 - 2 * amount)
    }

    /// The base projected image stays readable near the hinge. The stronger
    /// projected layer supplies most of the blur toward the free edge.
    public static func backgroundBlurFactor(progress: Double) -> Double {
        let t = min(max(progress / 0.85, 0), 1)
        return 0.08 + 0.04 * t * t * (3 - 2 * t)
    }
}
