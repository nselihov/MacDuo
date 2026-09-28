import AppKit
import CoreGraphics
import Foundation

var displayCount: UInt32 = 0
guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success else {
    fputs("Экраны: macOS не вернула список подключённых дисплеев\n", stderr)
    exit(1)
}

var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
guard CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
    fputs("Экраны: не удалось прочитать системные ID\n", stderr)
    exit(2)
}

let screenNames: [CGDirectDisplayID: String] = Dictionary(
    uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return (CGDirectDisplayID(number.uint32Value), screen.localizedName)
    }
)

print("Экраны: подключено — \(displayCount)")

for id in displayIDs.prefix(Int(displayCount)) {
    let bounds = CGDisplayBounds(id)
    let name = screenNames[id] ?? "Без названия"
    let kind = CGDisplayIsBuiltin(id) != 0 ? "встроенный" : "внешний"
    let main = CGDisplayIsMain(id) != 0 ? ", основной" : ""
    let mirrored = CGDisplayIsInMirrorSet(id) != 0 ? ", зеркалирование" : ""
    let active = CGDisplayIsActive(id) != 0 ? "активен" : "неактивен"

    print(
        "• \(name): ID \(id), \(kind)\(main)\(mirrored), \(active), "
            + "\(Int(bounds.width))×\(Int(bounds.height)) pt, "
            + "\(CGDisplayPixelsWide(id))×\(CGDisplayPixelsHigh(id)) px"
    )
}

let builtInCount = displayIDs.prefix(Int(displayCount)).filter { CGDisplayIsBuiltin($0) != 0 }.count
let externalCount = Int(displayCount) - builtInCount

guard builtInCount == 1 else {
    fputs("Ожидался один встроенный дисплей, найдено: \(builtInCount)\n", stderr)
    exit(3)
}

print("Итог: встроенных — \(builtInCount), внешних — \(externalCount)")
