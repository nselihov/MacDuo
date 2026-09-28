import AppKit
import MacDuoCore
import MacDuoSkyLight

@MainActor
final class OverlayController {
    private weak var model: AppModel?
    private var bridge: SkyLightBridge?
    private var surface: FoldOverlaySurface?
    private var metalSurface: MetalFoldOverlaySurface?
    private let useMetal = !CommandLine.arguments.contains("--legacy-desktop-renderer")

    init(model: AppModel) { self.model = model }

    func setVisible(_ visible: Bool) {
        guard let model else { return }
        guard visible else {
            surface?.retire(tuning: model.effectTuning)
            metalSurface?.retire(tuning: model.effectTuning)
            return
        }
        guard let screen = Self.builtInScreen() else { hide(); return }
        do {
            if bridge == nil { bridge = try SkyLightBridge() }
            if useMetal {
                guard model.hasDesktopFrame else {
                    metalSurface?.retire(tuning: model.effectTuning)
                    return
                }
                if metalSurface == nil, let bridge {
                    metalSurface = try MetalFoldOverlaySurface(
                        screen: screen, bridge: bridge,
                        frameStore: model.desktopFrameStore)
                }
                try metalSurface?.show(on: screen, parameters: model.foldParameters,
                                       tuning: model.effectTuning)
                return
            }
            if surface == nil, let bridge {
                surface = try FoldOverlaySurface(screen: screen, bridge: bridge, presentation: .desktop)
            }
            try surface?.show(on: screen, parameters: model.foldParameters, tuning: model.effectTuning)
        } catch {
            hide()
            model.setFullscreenEffectFailure("Эффект недоступен: \(error)")
        }
    }

    func hide() {
        surface?.hideImmediately()
        metalSurface?.hideImmediately()
    }

    func close() {
        surface?.close()
        surface = nil
        metalSurface?.close()
        metalSurface = nil
        bridge?.close()
        bridge = nil
    }

    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            let id = CGDirectDisplayID(number.uint32Value)
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0 && CGDisplayIsInMirrorSet(id) == 0
        }
    }
}
