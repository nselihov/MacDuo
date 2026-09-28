import AppKit
import SwiftUI

private enum MainStyle {
    static let background = Color(red: 0.055, green: 0.057, blue: 0.061)
    static let line = Color.white.opacity(0.11)
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.52)
    static let accent = Color(red: 0.82, green: 0.78, blue: 0.72)
    static let ready = Color(red: 0.50, green: 0.72, blue: 0.56)
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var showsSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 32)

            Text("Экран следует\nза крышкой.")
                .font(.system(size: 32, weight: .regular))
                .tracking(-1.2)
                .foregroundStyle(MainStyle.primary)

            Text("Плавное складывание рабочего стола и экрана блокировки.")
                .font(.system(size: 12.5))
                .foregroundStyle(MainStyle.secondary)
                .padding(.top, 10)

            status
                .padding(.top, 24)
                .padding(.bottom, 25)

            Text("Анимация")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MainStyle.secondary)
                .padding(.bottom, 9)

            VStack(spacing: 0) {
                modeRow(
                    title: "Рабочий стол",
                    detail: "На встроенном экране MacBook",
                    isOn: Binding(
                        get: { model.isDesktopEffectRequested },
                        set: { model.setDesktopEffectRequested($0) }
                    )
                )

                MainStyle.line.frame(height: 1)

                modeRow(
                    title: "Экран блокировки",
                    detail: "Когда Mac запрашивает пароль",
                    isOn: Binding(
                        get: { model.isLockScreenEffectEnabled },
                        set: { model.setLockScreenEffectEnabled($0) }
                    )
                )
            }
            .overlay(alignment: .top) { MainStyle.line.frame(height: 1) }
            .overlay(alignment: .bottom) { MainStyle.line.frame(height: 1) }

            if model.isDesktopEffectRequested {
                desktopAction
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 27)
        .padding(.bottom, 25)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MainStyle.background)
        .preferredColorScheme(.dark)
        .tint(MainStyle.accent)
        .sheet(isPresented: $showsSettings) {
            settingsSheet
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("MacDuo")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MainStyle.primary)

            Spacer()

            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(MainStyle.secondary)
            .help("Настройки")
            .accessibilityLabel("Настройки")
        }
    }

    private var status: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MainStyle.primary)
                if !statusDetail.isEmpty {
                    Text(statusDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(MainStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modeRow(
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MainStyle.primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(MainStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
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
            case .idle: return model.sensorHasSample ? "" : "Ожидаем данные о положении крышки."
            case let .failed(message): return message
            case .running: break
            }
        }
        if !model.sensorHasSample && (model.isDesktopEffectRequested || model.isLockScreenEffectEnabled) {
            return "Ожидаем данные о положении крышки."
        }
        if model.isDesktopEffectRequested || model.isLockScreenEffectEnabled { return "" }
        return "Выберите, где показывать анимацию складывания."
    }

    private var statusColor: Color {
        if model.isDesktopEffectRequested {
            switch model.captureState {
            case .permissionRequired, .restartRequired: return .orange
            case .failed: return .red
            case .idle: return model.sensorHasSample ? MainStyle.ready : MainStyle.accent
            case .starting: return MainStyle.accent
            case .running: break
            }
        }
        if model.isDesktopEffectRequested || model.isLockScreenEffectEnabled {
            return model.sensorHasSample ? MainStyle.ready : .orange
        }
        return .white.opacity(0.35)
    }

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Настройки")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(MainStyle.primary)
                Spacer()
                Button("Готово") { showsSettings = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MainStyle.secondary)
            }
            .padding(.bottom, 27)

            HStack(spacing: 14) {
                Text("Запускать при входе в macOS")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MainStyle.primary)
                Spacer()
                Toggle("Запускать при входе в macOS", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLoginEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.bottom, model.launchAtLoginNeedsApproval
                || model.launchAtLoginMessage.hasPrefix("Не удалось") ? 8 : 19)

            if model.launchAtLoginNeedsApproval
                || model.launchAtLoginMessage.hasPrefix("Не удалось") {
                Text(model.launchAtLoginMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(MainStyle.secondary)
                if model.launchAtLoginNeedsApproval {
                    Button("Разрешить в настройках macOS") { model.openLoginItemsSettings() }
                        .controlSize(.small)
                }
                Spacer().frame(height: 18)
            }

            MainStyle.line.frame(height: 1)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Диагностика")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MainStyle.primary)
                    Text("Превью, датчик, калибровка и параметры эффекта")
                        .font(.system(size: 11))
                        .foregroundStyle(MainStyle.secondary)
                }
                Spacer()
                Button("Открыть…") {
                    showsSettings = false
                    openWindow(id: "diagnostics")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MainStyle.accent)
            }
            .padding(.top, 19)
        }
        .padding(28)
        .frame(width: 470)
        .fixedSize(horizontal: false, vertical: true)
        .background(MainStyle.background)
        .preferredColorScheme(.dark)
        .onAppear { model.refreshLaunchAtLoginStatus() }
    }
}
