import AppKit
import ObjectiveC
import QuartzCore

/// Private Core Animation backdrop backend. WindowServer keeps the live source;
/// the application supplies only blur and geometry, never a screen snapshot.
@MainActor
public final class SystemBackdrop {
    public let layer: CALayer
    private let blur: NSObject

    public init() throws {
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let filterClass = NSClassFromString("CAFilter") else {
            throw SkyLightBridge.Failure.unavailable("CABackdropLayer / CAFilter")
        }
        let selector = NSSelectorFromString("filterWithType:")
        guard let method = class_getClassMethod(filterClass, selector) else {
            throw SkyLightBridge.Failure.unavailable("CAFilter.filterWithType")
        }
        typealias MakeFilter = @convention(c) (AnyClass, Selector, NSString) -> Unmanaged<NSObject>?
        let make = unsafeBitCast(method_getImplementation(method), to: MakeFilter.self)
        guard let blur = make(filterClass, selector, "gaussianBlur")?.takeUnretainedValue() else {
            throw SkyLightBridge.Failure.unavailable("gaussianBlur")
        }
        self.blur = blur
        layer = backdropClass.init()
        guard layer.responds(to: NSSelectorFromString("setMeshTransform:")) else {
            throw SkyLightBridge.Failure.unavailable("CALayer.meshTransform")
        }
        layer.setValue(true, forKey: "windowServerAware")
        layer.setValue(false, forKey: "allowsInPlaceFiltering")
        layer.setValue(1.0, forKey: "scale")
        layer.setValue(0.0, forKey: "bleedAmount")
        layer.setValue(0.0, forKey: "marginWidth")
        blur.setValue(1.0, forKey: "inputRadius")
        blur.setValue(true, forKey: "inputNormalizeEdges")
        blur.setValue(true, forKey: "inputHardEdges")
        layer.filters = [blur]
    }

    public func prepare(window: NSWindow) throws {
        guard window.responds(to: NSSelectorFromString("setCanHostLayersInWindowServer:")) else {
            throw SkyLightBridge.Failure.unavailable("NSWindow.canHostLayersInWindowServer")
        }
        window.setValue(true, forKey: "canHostLayersInWindowServer")
    }

    public func setRadius(_ radius: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Core Animation copies filters into its render tree. Mutating the
        // original object and assigning the same array can leave radius = 1.
        let updated = blur.copy() as! NSObject
        updated.setValue(max(radius, 0), forKey: "inputRadius")
        layer.filters = [updated]
        CATransaction.commit()
    }
}
