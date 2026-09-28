import Foundation
import IOKit.hid

let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)
let manager = IOHIDManagerCreate(kCFAllocatorDefault, noOptions)

guard IOHIDManagerOpen(manager, noOptions) == kIOReturnSuccess else {
    fputs("Датчик: не удалось открыть HID Manager\n", stderr)
    exit(1)
}
defer { IOHIDManagerClose(manager, noOptions) }

let matching: [String: Any] = [
    kIOHIDVendorIDKey as String: 0x05AC,
    kIOHIDProductIDKey as String: 0x8104,
    "UsagePage": 0x0020,
    "Usage": 0x008A,
]

IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
    fputs("Датчик: устройство Apple 0x8104 / 0x20 / 0x8A не найдено\n", stderr)
    exit(2)
}

print("Датчик: найдено устройств — \(devices.count)")

var didReadAngle = false

for (index, device) in devices.enumerated() {
    let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "без имени"
    let openResult = IOHIDDeviceOpen(device, noOptions)
    print("Устройство \(index + 1): \(product), open = 0x\(String(UInt32(bitPattern: openResult), radix: 16))")

    guard openResult == kIOReturnSuccess else { continue }
    defer { IOHIDDeviceClose(device, noOptions) }

    for attempt in 1 ... 3 {
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            1,
            &report,
            &length
        )

        let bytes = report.prefix(Int(length)).map { String(format: "%02X", $0) }.joined(separator: " ")
        print("Попытка \(attempt): result = 0x\(String(UInt32(bitPattern: result), radix: 16)), length = \(length), bytes = [\(bytes)]")

        if result == kIOReturnSuccess, length >= 3 {
            let rawValue = UInt16(report[2]) << 8 | UInt16(report[1])
            print("Угол: \(rawValue)°")
            didReadAngle = true
        }

        Thread.sleep(forTimeInterval: 0.08)
    }
}

exit(didReadAngle ? 0 : 3)
