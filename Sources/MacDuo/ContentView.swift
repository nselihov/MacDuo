import MacDuoCore
import SwiftUI

private enum DuoStyle {
    static let canvas = Color(red: 0.075, green: 0.085, blue: 0.105)
    static let rail = Color(red: 0.105, green: 0.115, blue: 0.138)
    static let surface = Color(red: 0.135, green: 0.147, blue: 0.173)
    static let border = Color.white.opacity(0.075)
    static let accent = Color(red: 0.46, green: 0.56, blue: 0.98)
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 0) {
                PreviewCanvas(
                    angle: model.effectiveAngle,
                    velocity: model.effectiveVelocity,
                    parameters: model.foldParameters,
                    tuning: model.effectTuning,
                    hasDesktopFrame: model.hasDesktopFrame,
                    frameStore: model.desktopFrameStore
                )
                .overlay {
                    if !model.hasDesktopFrame && model.source == .sensor {
                        VStack(spacing: 10) {
                            FoldGlyph()
                                .frame(width: 52, height: 52)
                            Text("Ваш экран появится здесь")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))
                            Text("Подключите рабочий стол в панели справа.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        .padding(20)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("ПРЕВЬЮ  /  ВСТРОЕННЫЙ ЭКРАН")
                            .tracking(0.7)
                        Spacer()
                        Text("\(model.effectiveAngle, specifier: "%.0f")°")
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.53))
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(DuoStyle.border)
                    .frame(width: 1)

                ControlRail()
                    .frame(width: 328)
            }
        }
        .background(DuoStyle.canvas)
        .preferredColorScheme(.dark)
        .tint(DuoStyle.accent)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            FoldGlyph()
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("Диагностика MacDuo")
                    .font(.system(size: 19, weight: .semibold))
                Text("Превью, датчик и тонкая настройка")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(model.sensorHasSample ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(model.sensorIndicatorText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(DuoStyle.surface, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 13)
        .background(DuoStyle.rail)
        .overlay(alignment: .bottom) {
            DuoStyle.border.frame(height: 1)
        }
    }
}

private struct FoldGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 34
            ZStack {
                RoundedRectangle(cornerRadius: 9 * unit, style: .continuous)
                    .fill(DuoStyle.surface)
                Path { path in
                    path.move(to: CGPoint(x: 6 * unit, y: 8 * unit))
                    path.addLine(to: CGPoint(x: 16 * unit, y: 11 * unit))
                    path.addLine(to: CGPoint(x: 16 * unit, y: 27 * unit))
                    path.addLine(to: CGPoint(x: 6 * unit, y: 24 * unit))
                    path.closeSubpath()
                }
                .fill(DuoStyle.accent)
                Path { path in
                    path.move(to: CGPoint(x: 18 * unit, y: 11 * unit))
                    path.addLine(to: CGPoint(x: 28 * unit, y: 8 * unit))
                    path.addLine(to: CGPoint(x: 28 * unit, y: 24 * unit))
                    path.addLine(to: CGPoint(x: 18 * unit, y: 27 * unit))
                    path.closeSubpath()
                }
                .fill(.white.opacity(0.8))
            }
        }
    }
}

private struct ControlRail: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ПРОВЕРКА ЭФФЕКТА")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)
                desktopSection
                lockScreenSection
                startupSection
                DisclosureGroup(isExpanded: $showsAdvanced) {
                    VStack(alignment: .leading, spacing: 24) {
                        sourceSection
                        angleSection
                        effectTuningSection
                        calibrationSection
                        metricsSection
                    }
                    .padding(.top, 18)
                } label: {
                    Text("Калибровка и настройка")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(16)
                .cardSurface()

                Text("Изображение обрабатывается на Mac и никуда не отправляется.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
            }
            .padding(18)
        }
        .background(DuoStyle.rail)
    }

    private var desktopSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("01  /  РАБОЧИЙ СТОЛ")

            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(captureStatusColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(captureStatusTitle)
                        .font(.system(size: 13, weight: .medium))
                    Text(captureStatusDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            captureAction

            Toggle(isOn: fullscreenBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Эффект на экране MacBook")
                        .font(.system(size: 12, weight: .medium))
                    Text(model.fullscreenEffectStatusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!model.canToggleFullscreenEffect)

            if !model.captureState.isRunning {
                Text(model.displayTopologyText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .cardSurface()
    }

    private var lockScreenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("02  /  ЭКРАН БЛОКИРОВКИ")
            Toggle(isOn: Binding(
                get: { model.isLockScreenEffectEnabled },
                set: { model.setLockScreenEffectEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Анимация крышки")
                        .font(.system(size: 12, weight: .medium))
                    Text("Повторяет движение на экране входа")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            Text(model.lockScreenStatus)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Посмотреть анимацию") { model.previewLockScreenEffect() }
                .controlSize(.small)
                .disabled(!model.isLockScreenEffectEnabled)
        }
        .padding(16)
        .cardSurface()
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("03  /  ПРИ ВХОДЕ В MACOS")
            Toggle(isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLoginEnabled($0) }
            )) {
                Text("Запускать MacDuo")
                    .font(.system(size: 12, weight: .medium))
            }
            .toggleStyle(.switch)
            Text(model.launchAtLoginMessage)
                .font(.system(size: 10))
                .foregroundStyle(model.launchAtLoginNeedsApproval ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.launchAtLoginNeedsApproval {
                Button("Открыть настройки macOS") { model.openLoginItemsSettings() }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .cardSurface()
        .onAppear { model.refreshLaunchAtLoginStatus() }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("ИСТОЧНИК ДВИЖЕНИЯ")

            Picker("Источник движения", selection: sourceBinding) {
                ForEach(AppModel.MotionSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)

            Text(model.sensorStatus)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var angleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                sectionLabel("УГОЛ КРЫШКИ")
                Spacer()
                Text("\(model.effectiveAngle, specifier: "%.1f")°")
                    .font(.system(size: 25, weight: .medium, design: .monospaced))
                    .contentTransition(.numericText())
            }

            Slider(value: $model.manualAngle, in: 20 ... 145, step: 0.5)
                .disabled(model.source == .sensor && model.isSensorAvailable)

            HStack {
                Text("закрыто")
                Spacer()
                Text("открыто")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("ЧТО ПРОИСХОДИТ")

            metric("Складывание", value: model.foldParameters.progress, suffix: "%", multiplier: 100)
            metric("Размытие", value: model.hasDesktopFrame
                   ? FoldAppearance.angleBlurRadius(progress: model.foldParameters.progress,
                                                    tuning: model.effectTuning)
                   : FoldAppearance.blurRadius(parameters: model.foldParameters,
                                               tuning: model.effectTuning), suffix: " pt")
            metric("Скорость", value: abs(model.effectiveVelocity), suffix: "°/с")
        }
    }

    private var effectTuningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("ТОНКАЯ НАСТРОЙКА ЭФФЕКТА")

            Text("Общие настройки для рабочего стола и экрана блокировки. Сохраняйте удачную комбинацию.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            tuningSlider(
                title: "Сила блюра",
                value: tuningBinding(\.blurStrength),
                range: 0.55 ... 1.6,
                step: 0.01,
                formattedValue: model.effectTuning.blurStrength.formatted(.number.precision(.fractionLength(2))) + "×"
            )

            tuningSlider(
                title: "Ширина перехода",
                value: tuningBinding(\.edgeDissolve),
                range: 0.55 ... 1.8,
                step: 0.01,
                formattedValue: model.effectTuning.edgeDissolve.formatted(.number.precision(.fractionLength(2))) + "×"
            )

            tuningSlider(
                title: "Глубина складывания",
                value: tuningBinding(\.perspectiveDepth),
                range: 0.65 ... 1.4,
                step: 0.01,
                formattedValue: model.effectTuning.perspectiveDepth.formatted(.number.precision(.fractionLength(2))) + "×"
            )

            tuningSlider(
                title: "Плавность реакции",
                value: tuningBinding(\.responseSeconds),
                range: 0.018 ... 0.12,
                step: 0.001,
                formattedValue: (model.effectTuning.responseSeconds * 1_000).formatted(.number.precision(.fractionLength(0))) + " мс"
            )

            HStack(spacing: 12) {
                Button("Базовые") {
                    model.resetEffectTuning()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

                Spacer()

                Button("Сохранить пресет") {
                    model.saveEffectTuning()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.effectTuningHasUnsavedChanges)
            }

            Text(model.effectPresetMessage)
                .font(.system(size: 10))
                .foregroundStyle(model.effectTuningHasUnsavedChanges ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("ТОЧКИ ЭФФЕКТА")

            Text("Поставьте крышку в нужное положение и запомните его как начало или финиш анимации.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            calibrationButton(
                title: "Запомнить открыто",
                angle: model.openAngle,
                action: model.calibrateOpenPoint
            )

            calibrationButton(
                title: "Запомнить финиш",
                angle: model.closedAngle,
                action: model.calibrateClosedPoint
            )

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.calibrationMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Button("Сбросить") {
                    model.resetCalibration()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var sourceBinding: Binding<AppModel.MotionSource> {
        Binding(
            get: { model.source },
            set: { model.selectSource($0) }
        )
    }

    private var fullscreenBinding: Binding<Bool> {
        Binding(
            get: { model.isFullscreenEffectEnabled },
            set: { model.setFullscreenEffectEnabled($0) }
        )
    }

    private func tuningBinding(_ keyPath: WritableKeyPath<EffectTuning, Double>) -> Binding<Double> {
        Binding(
            get: { model.effectTuning[keyPath: keyPath] },
            set: { nextValue in
                var tuning = model.effectTuning
                tuning[keyPath: keyPath] = nextValue
                model.setEffectTuning(tuning)
            }
        )
    }

    @ViewBuilder
    private var captureAction: some View {
        switch model.captureState {
        case .permissionRequired:
            Button("Разрешить запись экрана") {
                model.requestScreenCapturePermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .idle:
            if model.wantsDesktopConnected,
               model.isSystemSuspended || !model.displayEnvironment.supportsFullscreenEffect
            {
                Button("Отменить автовосстановление") {
                    model.disconnectDesktop()
                }
                .buttonStyle(.bordered)
            } else if model.wantsDesktopConnected {
                Button("Отключить рабочий стол") {
                    model.disconnectDesktop()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Подключить рабочий стол") {
                    model.connectDesktop()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .failed:
            Button("Повторить подключение") { model.connectDesktop() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

        case .starting:
            Button("Подключаем…") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)

        case .running:
            Button("Отключить рабочий стол") {
                model.disconnectDesktop()
            }
            .buttonStyle(.bordered)

        case .restartRequired:
            Text("Закройте MacDuo через ⌘Q и запустите снова — это нужно macOS только после первого разрешения.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var captureStatusTitle: String {
        if model.wantsDesktopConnected && model.isSystemSuspended {
            return "Ждём пробуждения"
        }
        if model.wantsDesktopConnected && !model.displayEnvironment.canCaptureBuiltInDisplay {
            return "Ждём экран MacBook"
        }
        if model.wantsDesktopConnected && model.displayEnvironment.isMirrored {
            return "Эффект временно выключен"
        }

        switch model.captureState {
        case .idle: return model.wantsDesktopConnected ? "Готов к движению крышки" : "Готов к подключению"
        case .permissionRequired: return "Нужно разрешение macOS"
        case .starting: return "Подключаем встроенный экран"
        case let .running(displayName): return displayName + " подключён"
        case .restartRequired: return "Разрешение выдано"
        case .failed: return "Не удалось подключиться"
        }
    }

    private var captureStatusDetail: String {
        if model.wantsDesktopConnected && model.isSystemSuspended {
            return "Захват и датчик восстановятся автоматически."
        }
        if model.wantsDesktopConnected && !model.displayEnvironment.canCaptureBuiltInDisplay {
            return "Внешний монитор продолжает работать без эффекта."
        }
        if model.wantsDesktopConnected && model.displayEnvironment.isMirrored {
            return "Вернётся автоматически после отключения зеркалирования."
        }

        switch model.captureState {
        case .idle:
            return model.wantsDesktopConnected
                ? "Захват начнётся при закрытии крышки и остановится после открытия."
                : "Захват начнётся только после нажатия кнопки."
        case .permissionRequired:
            return "Нужен доступ к изображению встроенного экрана, чтобы складывать рабочий стол. Кадры остаются на этом Mac."
        case .starting:
            return "Ищем экран MacBook по системному ID."
        case .running:
            return "Эффект готов и следует за крышкой."
        case .restartRequired:
            return "macOS применит доступ после перезапуска приложения."
        case let .failed(message):
            return message
        }
    }

    private var captureStatusColor: Color {
        if model.wantsDesktopConnected,
           model.isSystemSuspended || !model.displayEnvironment.supportsFullscreenEffect
        {
            return .orange
        }

        switch model.captureState {
        case .idle: return model.wantsDesktopConnected ? .green : .blue
        case .permissionRequired, .restartRequired: return .orange
        case .starting: return .blue
        case .running: return .green
        case .failed: return .red
        }
    }

    private func metric(
        _ title: String,
        value: Double,
        suffix: String,
        multiplier: Double = 1
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value * multiplier, specifier: "%.1f")\(suffix)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .contentTransition(.numericText())
        }
        .font(.system(size: 12))
    }

    private func calibrationButton(
        title: String,
        angle: Double,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(angle.formatted(.number.precision(.fractionLength(1))) + "°")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!model.canCalibrate)
    }

    private func tuningSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formattedValue: String
    ) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formattedValue)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }

            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }
}

private extension View {
    func cardSurface() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(DuoStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DuoStyle.border, lineWidth: 1)
            }
    }
}
