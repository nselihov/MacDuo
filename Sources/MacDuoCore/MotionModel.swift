import Foundation

public struct FoldParameters: Equatable, Sendable {
    public let progress: Double
    public let tiltDegrees: Double
    public let blurRadius: Double
    public let blurBlend: Double
    public let brightnessOffset: Double
    public let glassIntensity: Double
    public let topShadeOpacity: Double
    public let topDissolve: Double

    public init(
        progress: Double,
        tiltDegrees: Double,
        blurRadius: Double,
        blurBlend: Double,
        brightnessOffset: Double,
        glassIntensity: Double,
        topShadeOpacity: Double,
        topDissolve: Double
    ) {
        self.progress = progress
        self.tiltDegrees = tiltDegrees
        self.blurRadius = blurRadius
        self.blurBlend = blurBlend
        self.brightnessOffset = brightnessOffset
        self.glassIntensity = glassIntensity
        self.topShadeOpacity = topShadeOpacity
        self.topDissolve = topDissolve
    }
}

public enum FoldMotionModel {
    public static let defaultOpenAngle = 115.0
    public static let defaultClosedAngle = 25.0
    /// Ignores roughly the first 2.5% of travel. The lid sensor naturally
    /// jitters around the calibrated open point, and that must still mean a
    /// completely sharp, untouched desktop.
    public static let openDeadZoneProgress = 0.025
    public static let overlayActivationProgress = 0.008
    public static let overlayDeactivationProgress = 0.002

    public static func parameters(
        angle: Double,
        velocity: Double,
        openAngle: Double = defaultOpenAngle,
        closedAngle: Double = defaultClosedAngle
    ) -> FoldParameters {
        let safeTravel = max(openAngle - closedAngle, 1)
        let linearProgress = clamp((openAngle - angle) / safeTravel, lower: 0, upper: 1)
        let openGate = smoothstep(
            linearProgress,
            from: openDeadZoneProgress,
            to: openDeadZoneProgress * 2
        )
        let progress = linearProgress * openGate
        let speedAmount = min(abs(velocity) / 80, 1)
        let motionGate = pow(progress, 0.35)
        let speedContribution = speedAmount * 32 * motionGate
        let blurEntrance = smoothstep(progress, from: 0, to: 0.16)
        let blurRadius = (pow(progress, 0.50) * 165 + speedContribution) * blurEntrance
        let blurBlend = clamp(
            (pow(progress, 0.32) * 1.05 + speedAmount * 0.12 * motionGate) * blurEntrance,
            lower: 0,
            upper: 1
        )

        return FoldParameters(
            progress: progress,
            tiltDegrees: progress * 82,
            blurRadius: blurRadius,
            blurBlend: blurBlend,
            brightnessOffset: -pow(progress, 1.08) * 0.06,
            glassIntensity: pow(progress, 0.82) * 0.62,
            topShadeOpacity: pow(progress, 1.02) * 0.14,
            topDissolve: pow(progress, 1.1) * 0.52
        )
    }

    public static func shouldPresentOverlay(
        for parameters: FoldParameters,
        activationProgress: Double = overlayActivationProgress
    ) -> Bool {
        parameters.progress >= activationProgress
    }

    public static func shouldKeepOverlayVisible(for parameters: FoldParameters) -> Bool {
        parameters.progress > overlayDeactivationProgress
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private static func smoothstep(_ value: Double, from lower: Double, to upper: Double) -> Double {
        let normalized = clamp((value - lower) / max(upper - lower, 0.0001), lower: 0, upper: 1)
        return normalized * normalized * (3 - 2 * normalized)
    }
}
