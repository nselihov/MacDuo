import Foundation
import IOKit.hid
import QuartzCore

/// Reads the built-in lid angle sensor when macOS exposes it as a HID device.
/// Discovery and report format are based on samhenrigold/LidAngleSensor (Apache-2.0).
@MainActor
final class LidAngleSensor {
    typealias SampleHandler = (_ angle: Double, _ velocity: Double) -> Void
    typealias StatusHandler = (_ status: String) -> Void

    nonisolated private static let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)

    private(set) var isAvailable = false
    private(set) var statusText = "Датчик крышки не найден"
    var onSample: SampleHandler?
    var onStatusChange: StatusHandler?

    private var device: IOHIDDevice?
    private var timer: Timer?
    private var report = [UInt8](repeating: 0, count: 8)
    private var lastAngle: Double?
    private var lastTimestamp: CFTimeInterval?
    private var smoothedVelocity = 0.0
    private var isOpen = false
    private var hasReceivedSample = false

    init() {
        device = Self.findSensor()
        isAvailable = device != nil
        statusText = isAvailable
            ? "Датчик найден — можно двигать крышку"
            : "Датчик недоступен — используйте ползунок"
    }

    deinit {
        timer?.invalidate()
        if isOpen, let device {
            IOHIDDeviceClose(device, Self.noOptions)
        }
    }

    func start() {
        guard timer == nil, let device else { return }

        guard IOHIDDeviceOpen(device, Self.noOptions) == kIOReturnSuccess else {
            statusText = "Датчик найден, но macOS не дала его открыть"
            return
        }

        isOpen = true
        updateStatus("Датчик найден — проверяем данные…")
        poll()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if isOpen, let device {
            IOHIDDeviceClose(device, Self.noOptions)
            isOpen = false
        }
    }

    func suspendForSleep() {
        stop()
        resetSamplingState()
        updateStatus("Датчик приостановлен на время сна")
    }

    @discardableResult
    func resumeAfterSleep() -> Bool {
        stop()
        device = Self.findSensor()
        isAvailable = device != nil
        resetSamplingState()

        guard isAvailable else {
            updateStatus("Датчик крышки пока не появился после пробуждения")
            return false
        }

        updateStatus("Датчик найден — восстанавливаем данные…")
        start()
        return isOpen && hasReceivedSample
    }

    private func poll() {
        guard let device else { return }

        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            1,
            &report,
            &length
        )

        guard result == kIOReturnSuccess, length >= 3 else { return }

        let rawValue = UInt16(report[2]) << 8 | UInt16(report[1])
        let angle = Double(rawValue)
        guard (0 ... 180).contains(angle) else { return }

        if !hasReceivedSample {
            hasReceivedSample = true
            updateStatus("Датчик работает — можно двигать крышку")
        }

        let now = CACurrentMediaTime()
        let velocity: Double

        if let lastAngle, let lastTimestamp {
            let elapsed = max(now - lastTimestamp, 1.0 / 240.0)
            let instantVelocity = (angle - lastAngle) / elapsed
            smoothedVelocity = instantVelocity * 0.28 + smoothedVelocity * 0.72

            if abs(angle - lastAngle) < 0.05 {
                smoothedVelocity *= 0.72
            }

            velocity = smoothedVelocity
        } else {
            velocity = 0
        }

        self.lastAngle = angle
        lastTimestamp = now
        onSample?(angle, velocity)
    }

    private func updateStatus(_ text: String) {
        statusText = text
        onStatusChange?(text)
    }

    private func resetSamplingState() {
        lastAngle = nil
        lastTimestamp = nil
        smoothedVelocity = 0
        hasReceivedSample = false
    }

    private static func findSensor() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, noOptions)
        guard IOHIDManagerOpen(manager, noOptions) == kIOReturnSuccess else { return nil }
        defer { IOHIDManagerClose(manager, noOptions) }

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            "UsagePage": 0x0020,
            "Usage": 0x008A,
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }

        for device in devices {
            guard IOHIDDeviceOpen(device, noOptions) == kIOReturnSuccess else { continue }

            var probeReport = [UInt8](repeating: 0, count: 8)
            var length = CFIndex(probeReport.count)
            let result = IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeFeature,
                1,
                &probeReport,
                &length
            )

            IOHIDDeviceClose(device, noOptions)

            if result == kIOReturnSuccess, length >= 3 {
                return device
            }
        }

        return nil
    }
}
