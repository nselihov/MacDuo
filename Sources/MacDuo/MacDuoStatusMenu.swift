import AppKit
import SwiftUI

struct MacDuoStatusMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.sensorIndicatorText)

        Divider()

        Toggle("Рабочий стол", isOn: Binding(
            get: { model.isDesktopEffectRequested },
            set: { model.setDesktopEffectRequested($0) }
        ))

        Toggle("Экран блокировки", isOn: Binding(
            get: { model.isLockScreenEffectEnabled },
            set: { model.setLockScreenEffectEnabled($0) }
        ))

        if model.captureState == .permissionRequired && model.isDesktopEffectRequested {
            Button("Разрешить доступ к экрану…") { model.requestScreenCapturePermission() }
        }

        Divider()

        Button("Открыть MacDuo") {
            showWindow(id: "main", title: "MacDuo")
        }

        Button("Диагностика…") {
            showWindow(id: "diagnostics", title: "Диагностика MacDuo")
        }

        Button("Завершить MacDuo") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func showWindow(id: String, title: String) {
        if let window = NSApplication.shared.windows.first(where: {
            $0.title == title && $0.isVisible
        }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: id)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
