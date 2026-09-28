import AppKit
import SwiftUI

private enum MainStyle {
    static let background = Color(red: 0.075, green: 0.079, blue: 0.088)
    static let surface = Color(red: 0.125, green: 0.13, blue: 0.145)
    static let line = Color.white.opacity(0.09)
    static let accent = Color(red: 0.72, green: 0.79, blue: 0.99)
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var showsSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 28)

            status
                .padding(.bottom, 24)

            Text("ГДЕ ПОКАЗЫВАТЬ")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.42))
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                modeRow(
                    symbol: "laptopcomputer",
                    title: "Рабочий стол",
                    detail: "Изображение складывается вместе с крышкой",
                    isOn: Binding(
                        get: { model.isDesktopEffectRequested },
                        set: { model.setDesktopEffectRequested($0) }
                    )
                )

                MainStyle.line.frame(height: 1).padding(.leading, 56)

                modeRow(
                    symbol: "lock.display",
                    title: "Экран блокировки",
                    detail: "Складывает экран входа вслед за крышкой",
                    isOn: Binding(
                        get: { model.isLockScreenEffectEnabled },
                        set: { model.setLockScreenEffectEnabled($0) }
                    )
                )
            }
            .background(MainStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(MainStyle.line, lineWidth: 1)
            }

            if model.isDesktopEffectRequested {
                desktopAction
                    .padding(.top, 12)
            }

            Spacer(minLength: 20)

            HStack(spacing: 7) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 12))
                Text("После закрытия окна MacDuo остаётся в строке меню")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(0.42))
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MainStyle.background)
        .preferredColorScheme(.dark)
        .tint(MainStyle.accent)
        .sheet(isPresented: $showsSettings) {
            settingsSheet
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 49, height: 49)
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text("MacDuo")
                    .font(.system(size: 21, weight: .semibold))
                Text("Экран следует за крышкой")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.54))
            }

            Spacer()

            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))
            .help("Настройки")
            .accessibilityLabel("Настройки")
        }
    }

    private var status: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 5) {
                Text(statusTitle)
                    .font(.system(size: 15, weight: .semibold))
                Text(statusDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.57))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MainStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(MainStyle.line, lineWidth: 1)
        }
    }

    private func modeRow(
        symbol: String,
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(MainStyle.accent)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }

    @ViewBuilder
    private var desktopAction: some View {
        switch model.captureState {
        case .permissionRequired:
            Button("Разрешить доступ к экрану…") {
                model.requestScreenCapturePermission()
            }
            .buttonStyle(.borderedProminent)
        case .restartRequired:
            Text("После разрешения закройте MacDuo через меню и откройте снова.")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        case .failed:
            Button("Повторить подключение") { model.connectDesktop() }
                .buttonStyle(.bordered)
        case .idle, .starting, .running:
            EmptyView()
        }
    }

    private var statusTitle: String {
        if model.isDesktopEffectRequested {
            if model.isSystemSuspended { return "Ждём пробуждения" }
            if !model.displayEnvironment.supportsFullscreenEffect { return "Ждём экран MacBook" }
            switch model.captureState {
            case .permissionRequired: return "Нужен доступ к экрану"
            case .restartRequired: return "Перезапустите MacDuo"
            case .starting: return "Подключаем экран"
            case .failed: return "Не удалось подключить экран"
            case .running: return model.sensorHasSample ? "Всё готово" : "Ждём датчик крышки"
            case .idle: return model.sensorHasSample ? "Всё готово" : "Ждём датчик крышки"
            }
        }
        if model.isLockScreenEffectEnabled {
            return model.sensorHasSample ? "Всё готово" : "Ждём датчик крышки"
        }
        return "Эффект выключен"
    }

    private var statusDetail: String {
        if model.isDesktopEffectRequested {
            if model.isSystemSuspended { return "Эффект восстановится после открытия крышки." }
            if !model.displayEnvironment.supportsFullscreenEffect {
                return "Эффект вернётся, когда встроенный экран снова будет доступен."
            }
            switch model.captureState {
            case .permissionRequired:
                return "Разрешите захват экрана в macOS. Изображение остаётся на этом Mac."
            case .restartRequired: return "macOS применит доступ после нового запуска."
            case .starting: return "Подготовка живого изображения…"
            case .idle: return "Захват включится, когда вы начнёте закрывать крышку."
            case let .failed(message): return message
            case .running: break
            }
        }
        if !model.sensorHasSample && (model.isDesktopEffectRequested || model.isLockScreenEffectEnabled) {
            return "Ожидаем данные о положении крышки."
        }
        if model.isDesktopEffectRequested || model.isLockScreenEffectEnabled {
            return "Прикройте крышку — изображение последует за её движением."
        }
        return "Выберите, где показывать анимацию складывания."
    }

    private var statusColor: Color {
        if model.isDesktopEffectRequested {
            switch model.captureState {
            case .permissionRequired, .restartRequired: return .orange
            case .failed: return .red
            case .idle, .starting: return MainStyle.accent
            case .running: break
            }
        }
        if model.isDesktopEffectRequested || model.isLockScreenEffectEnabled {
            return model.sensorHasSample ? .green : .orange
        }
        return .white.opacity(0.35)
    }

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Настройки")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Готово") { showsSettings = false }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 7) {
                Toggle("Запускать MacDuo при входе в macOS", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLoginEnabled($0) }
                ))
                .toggleStyle(.switch)
                Text(model.launchAtLoginMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if model.launchAtLoginNeedsApproval {
                    Button("Разрешить в настройках macOS") { model.openLoginItemsSettings() }
                        .controlSize(.small)
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Диагностика")
                        .font(.system(size: 13, weight: .medium))
                    Text("Превью, датчик, калибровка и параметры эффекта")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Открыть…") {
                    showsSettings = false
                    openWindow(id: "diagnostics")
                }
            }
        }
        .padding(24)
        .frame(width: 470)
        .fixedSize(horizontal: false, vertical: true)
        .background(MainStyle.background)
        .preferredColorScheme(.dark)
        .onAppear { model.refreshLaunchAtLoginStatus() }
    }
}
