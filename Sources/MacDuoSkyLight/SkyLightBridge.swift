import AppKit
import Darwin

// Adapted from Lakr233/SkyLightWindow (MIT, Copyright 2025 Lakr Aream).
// See THIRD_PARTY_NOTICES.md and Resources/Licenses/SkyLightWindow.txt.
// Private ABI: isolated here; both fullscreen contexts share special-space
// presentation. SystemBackdrop provides their live blur and content projection.
public final class SkyLightBridge {
    private typealias Connection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SetLevel = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias Spaces = @convention(c) (Int32, CFArray) -> Void
    private typealias Attach = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    private typealias Destroy = @convention(c) (Int32, UInt64) -> Void
    private typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias BackgroundBlur = @convention(c) (Int32, UInt32, UInt32) -> Int32
    fileprivate typealias SetAlpha = @convention(c) (Int32, UInt32, Float) -> Int32

    public enum Failure: Error, CustomStringConvertible {
        case unavailable(String)
        case operation(String, Int32)

        public var description: String {
            switch self {
            case let .unavailable(name): return "Недоступна функция: \(name)"
            case let .operation(name, code): return "\(name): код \(code)"
            }
        }
    }

    private let handle: UnsafeMutableRawPointer
    private let mainConnection: Connection
    private let create: Create
    private let setLevel: SetLevel
    private let show: Spaces
    private let hide: Spaces
    private let attach: Attach
    private let destroy: Destroy
    private let copySpaces: CopySpaces
    private let backgroundBlur: BackgroundBlur?
    private let setAlpha: SetAlpha?
    private var connection: Int32 = 0
    private var space: UInt64?

    public init() throws {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW | RTLD_LOCAL
        ) else { throw Failure.unavailable("SkyLight") }

        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let address = dlsym(handle, name) else {
                throw Failure.unavailable(name)
            }
            return unsafeBitCast(address, to: T.self)
        }

        do {
            mainConnection = try symbol("SLSMainConnectionID", Connection.self)
            create = try symbol("SLSSpaceCreate", Create.self)
            setLevel = try symbol("SLSSpaceSetAbsoluteLevel", SetLevel.self)
            show = try symbol("SLSShowSpaces", Spaces.self)
            hide = try symbol("SLSHideSpaces", Spaces.self)
            attach = try symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", Attach.self)
            destroy = try symbol("SLSSpaceDestroy", Destroy.self)
            copySpaces = try symbol("SLSCopySpacesForWindows", CopySpaces.self)
        } catch {
            dlclose(handle)
            throw error
        }
        backgroundBlur = dlsym(handle, "SLSSetWindowBackgroundBlurRadius").map {
            unsafeBitCast($0, to: BackgroundBlur.self)
        }
        setAlpha = dlsym(handle, "SLSSetWindowAlpha").map {
            unsafeBitCast($0, to: SetAlpha.self)
        }
        self.handle = handle
    }

    public var supportsBackgroundBlur: Bool { backgroundBlur != nil }

    public func makeWindowLease(for window: NSWindow) throws -> SkyLightWindowLease {
        guard let setAlpha else { throw Failure.unavailable("SLSSetWindowAlpha") }
        return SkyLightWindowLease(owner: self, connection: mainConnection(),
                                  windowID: UInt32(window.windowNumber), setAlpha: setAlpha)
    }

    /// WindowServer blurs the existing backdrop; no image is captured or tinted.
    /// Zero-radius windows are retired instead of relying on private zero-reset
    /// behavior. The caller fades a one-point blur to transparent at the endpoint.
    public func setBackgroundBlur(_ radius: Double, for window: NSWindow) throws {
        guard let backgroundBlur else { throw Failure.unavailable("SLSSetWindowBackgroundBlurRadius") }
        let result = backgroundBlur(mainConnection(), UInt32(window.windowNumber),
                                    UInt32(min(max(radius.rounded(), 1), 80)))
        guard result == 0 else { throw Failure.operation("SLSSetWindowBackgroundBlurRadius", result) }
    }

    // Call only after NSApplication has connected to the WindowServer.
    public func present(_ window: NSWindow) throws {
        if space == nil {
            connection = mainConnection()
            guard connection != 0 else { throw Failure.unavailable("WindowServer connection") }
            let created = create(connection, 1, 0)
            guard created > 0 else { throw Failure.unavailable("SLSSpaceCreate returned zero") }
            space = created
            setLevel(connection, created, 400)
        }
        guard let space else { return }
        // These undocumented mutators have no reliable CGError return contract.
        // Check window membership separately instead of interpreting a return register.
        show(connection, [NSNumber(value: space)] as CFArray)
        attach(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
        window.orderFrontRegardless()
    }

    public func membershipDescription(_ window: NSWindow) -> String {
        let values = [Int32(0), 3, 7].map { mask -> String in
            guard let result = copySpaces(connection, mask, [NSNumber(value: window.windowNumber)] as CFArray)
            else { return "mask=\(mask):nil" }
            return "mask=\(mask):\(result.takeRetainedValue() as NSArray)"
        }
        // System spaces may not be returned by a query for ordinary user spaces.
        // This is diagnostic evidence, not a substitute for observing the lock screen.
        return "requested=\(space.map(String.init) ?? "nil") \(values.joined(separator: " "))"
    }

    public func conceal() {
        if let space { hide(connection, [NSNumber(value: space)] as CFArray) }
    }

    public func close() {
        if let space {
            conceal()
            destroy(connection, space)
            self.space = nil
        }
    }

    deinit {
        close()
        dlclose(handle)
    }
}
