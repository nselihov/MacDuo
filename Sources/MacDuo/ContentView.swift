import AppKit
import MacDuoCore
import SwiftUI

private enum DuoStyle {
    static let canvas = MacDuoTheme.canvas
    static let rail = MacDuoTheme.background
    static let border = MacDuoTheme.line
    static let accent = MacDuoTheme.accent
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
                    showsArtwork: model.source == .manual,
                    frameStore: model.desktopFrameStore
                )
                .overlay {
                    if !model.hasDesktopFrame && model.source == .sensor {
                        VStack(spacing: 8) {
                            Text(model.wantsDesktopConnected
                                 ? "Предпросмотр появится при движении крышки"
                                 : "Включите рабочий стол")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(MacDuoTheme.primary)
                            if !model.wantsDesktopConnected {
                                Text("Переключатель находится в главном окне MacDuo.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MacDuoTheme.secondary)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("Предпросмотр · встроенный экран")
                        Spacer()
                        Text("\(model.effectiveAngle, specifier: "%.0f")°")
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacDuoTheme.secondary)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(DuoStyle.border)
                    .frame(width: 1)

                ControlRail()
                    .frame(width: 320)
            }
        }
        .background(DuoStyle.canvas)
        .preferredColorScheme(.dark)
        .tint(DuoStyle.accent)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("MacDuo")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacDuoTheme.primary)

            Text("/ Диагностика")
                .font(.system(size: 13))
                .foregroundStyle(MacDuoTheme.secondary)

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(model.sensorHasSample ? MacDuoTheme.ready : Color.orange)
                    .frame(width: 6, height: 6)
                Text(model.sensorIndicatorText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacDuoTheme.secondary)
            }
        }
        .padding(.horizontal, 27)
        .padding(.top, 25)
        .padding(.bottom, 21)
        .background(DuoStyle.rail)
        .overlay(alignment: .bottom) {
            DuoStyle.border.frame(height: 1)
        }
    }
}

private struct ControlRail: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                desktopSection
                lockScreenSection
                DisclosureGroup(isExpanded: $showsAdvanced) {
                    VStack(alignment: .leading, spacing: 26) {
                        sourceSection
                        angleSection
                        effectTuningSection
                        calibrationSection
                        metricsSection
                    }
                    .padding(.top, 21)
                } label: {
                    Text("Калибровка и параметры")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacDuoTheme.primary)
                }
                .padding(.vertical, 20)
                .separatedSection()
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .background(DuoStyle.rail)
    }

    private var desktopSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Рабочий стол")

            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(captureStatusColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(captureStatusTitle)
                        .font(.system(size: 13, weight: .medium))
                    Text(captureStatusDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(MacDuoTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            captureAction

            Toggle(isOn: fullscreenBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Эффект на экране MacBook")
                        .font(.system(size: 12, weight: .medium))
                    if !model.isFullscreenEffectEnabled {
                        Text(model.fullscreenEffectStatusText)
                            .font(.system(size: 10))
                            .foregroundStyle(MacDuoTheme.muted)
                    }
                }
            }
            .toggleStyle(.switch)
            .disabled(!model.canToggleFullscreenEffect)

            if !model.displayEnvironment.supportsFullscreenEffect {
                Text(model.displayTopologyText)
                    .font(.system(size: 10))
                    .foregroundStyle(MacDuoTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 20)
        .separatedSection()
    }

    private var lockScreenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Экран блокировки")
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
            if model.lockScreenStatus != "Живой локскрин + перспектива стекла",
               model.lockScreenStatus != "Выключен" {
                Text(model.lockScreenStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(MacDuoTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Посмотреть анимацию") { model.previewLockScreenEffect() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacDuoTheme.accent)
                .disabled(!model.isLockScreenEffectEnabled)
        }
        .padding(.vertical, 20)
        .separatedSection()
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Источник движения")

            Picker("Источник движения", selection: sourceBinding) {
                ForEach(AppModel.MotionSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(model.sensorStatus)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var angleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                sectionLabel("Угол крышки")
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
            sectionLabel("Что происходит")

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
            sectionLabel("Параметры эффекта")

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
            sectionLabel("Точки эффекта")

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
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacDuoTheme.secondary)
            } else if model.wantsDesktopConnected {
                Button("Отключить рабочий стол") {
                    model.disconnectDesktop()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacDuoTheme.secondary)
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
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MacDuoTheme.secondary)

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
        case .idle: return model.wantsDesktopConnected ? MacDuoTheme.ready : MacDuoTheme.muted
        case .permissionRequired, .restartRequired: return .orange
        case .starting: return MacDuoTheme.accent
        case .running: return MacDuoTheme.ready
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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MacDuoTheme.secondary)
    }
}

private extension View {
    func separatedSection() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                DuoStyle.border.frame(height: 1)
            }
    }
}
