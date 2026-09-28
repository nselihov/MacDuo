import CoreGraphics
import Foundation

// Read-only diagnosis of real window movement during a lid transition.
// Prints counts and distances only; no window names or screen contents.
struct WindowPosition {
    let x: Double
    let y: Double
}

private func positions() -> [Int: WindowPosition] {
    guard let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return [:] }

    var result: [Int: WindowPosition] = [:]
    for window in windows {
        guard let number = window[kCGWindowNumber as String] as? Int,
              let layer = window[kCGWindowLayer as String] as? Int,
              layer == 0,
              let owner = window[kCGWindowOwnerName as String] as? String,
              owner != "MacDuo",
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let x = (bounds["X"] as? NSNumber)?.doubleValue,
              let y = (bounds["Y"] as? NSNumber)?.doubleValue,
              let width = (bounds["Width"] as? NSNumber)?.doubleValue,
              let height = (bounds["Height"] as? NSNumber)?.doubleValue,
              width >= 100, height >= 100
        else { continue }
        result[number] = WindowPosition(x: x, y: y)
    }
    return result
}

private func activeDisplays() -> (count: Int, builtInActive: Bool) {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success else { return (0, false) }
    var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return (0, false) }
    return (Int(count), displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 })
}

let duration = Double(CommandLine.arguments.dropFirst().first ?? "90") ?? 90
let start = Date()
var previous = positions()
var displayState = activeDisplays()
var lastMotionLog = Date.distantPast
print("start displays=\(displayState.count) builtIn=\(displayState.builtInActive) windows=\(previous.count)")
fflush(stdout)

while Date().timeIntervalSince(start) < duration {
    Thread.sleep(forTimeInterval: 0.05)
    let currentDisplays = activeDisplays()
    let current = positions()
    let elapsed = Date().timeIntervalSince(start)

    if currentDisplays.count != displayState.count ||
        currentDisplays.builtInActive != displayState.builtInActive {
        print(String(format: "%.2fs displays=%d builtIn=%@ windows=%d", elapsed,
                     currentDisplays.count, String(currentDisplays.builtInActive), current.count))
        displayState = currentDisplays
        fflush(stdout)
    }

    let distances = current.compactMap { id, position -> Double? in
        guard let old = previous[id] else { return nil }
        return hypot(position.x - old.x, position.y - old.y)
    }
    let moved = distances.filter { $0 >= 20 }
    if !moved.isEmpty, Date().timeIntervalSince(lastMotionLog) >= 0.2 {
        print(String(format: "%.2fs moved=%d max=%.0fpt tracked=%d", elapsed,
                     moved.count, moved.max() ?? 0, distances.count))
        lastMotionLog = Date()
        fflush(stdout)
    }
    previous = current
}

print("done")
