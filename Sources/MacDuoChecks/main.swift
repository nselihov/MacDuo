import Foundation
import MacDuoCore

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
}

private func approximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

do {
    let open = FoldMotionModel.parameters(angle: 130, velocity: 0)
    try expect(approximatelyEqual(open.progress, 0), "Открытая крышка должна давать progress = 0")
    try expect(approximatelyEqual(open.tiltDegrees, 0), "Открытая крышка не должна наклонять сцену")
    try expect(approximatelyEqual(open.blurRadius, 0), "Открытая крышка не должна размывать сцену")

    let closed = FoldMotionModel.parameters(angle: 0, velocity: 0)
    try expect(approximatelyEqual(closed.progress, 1), "Закрытая крышка должна давать progress = 1")
    try expect(approximatelyEqual(closed.tiltDegrees, 82), "Максимальный наклон должен быть 82 градуса")
    try expect(closed.brightnessOffset < 0, "Закрытие должно затемнять сцену")
    try expect(approximatelyEqual(closed.blurBlend, 1), "В закрытой точке размытие должно полностью замещать резкое изображение")
    try expect(closed.topDissolve >= 0.51, "Верхняя кромка должна заметно растворяться в закрытой точке")
    try expect(closed.blurRadius >= 95, "В закрытой точке размытие должно быть визуально сильным")

    let still = FoldMotionModel.parameters(angle: 70, velocity: 0)
    let moving = FoldMotionModel.parameters(angle: 70, velocity: 90)
    let openAndMoving = FoldMotionModel.parameters(angle: 130, velocity: 90)
    try expect(moving.blurRadius > still.blurRadius, "Скорость должна добавлять размытие")
    try expect(approximatelyEqual(openAndMoving.blurRadius, 0), "Скорость не должна размывать открытую сцену")
    try expect(approximatelyEqual(openAndMoving.topDissolve, 0), "Открытая сцена не должна растворяться в фоне")

    let midpoint = FoldMotionModel.parameters(angle: 70, velocity: 0)
    try expect(approximatelyEqual(midpoint.progress, 0.5), "70 градусов должны быть серединой диапазона")
    try expect(midpoint.tiltDegrees > 0 && midpoint.tiltDegrees < 82, "Середина должна давать частичный наклон")

    let earlyFold = FoldMotionModel.parameters(angle: 100, velocity: 0)
    try expect(earlyFold.blurRadius > 60, "Сильное размытие должно начинаться задолго до закрытой точки")

    let almostClosed = FoldMotionModel.parameters(angle: 34, velocity: 0)
    try expect(almostClosed.blurRadius > 155, "Почти закрытая сцена должна превращаться в крупное цветовое поле")

    let fullyOpen = FoldMotionModel.parameters(angle: 115, velocity: 0)
    let firstMovement = FoldMotionModel.parameters(angle: 114, velocity: 0)
    let meaningfulMovement = FoldMotionModel.parameters(angle: 110, velocity: 0)
    try expect(!FoldMotionModel.shouldPresentOverlay(for: fullyOpen), "Оверлей не должен заслонять полностью открытый экран")
    try expect(approximatelyEqual(firstMovement.progress, 0), "Шум датчика у открытой точки должен попадать в мёртвую зону")
    try expect(approximatelyEqual(firstMovement.blurRadius, 0), "В мёртвой зоне рабочий стол должен оставаться полностью резким")
    try expect(!FoldMotionModel.shouldPresentOverlay(for: firstMovement), "Оверлей не должен появляться из-за микродвижения датчика")
    try expect(FoldMotionModel.shouldPresentOverlay(for: meaningfulMovement), "Оверлей должен появляться после заметного движения крышки")
    try expect(meaningfulMovement.blurRadius > 0, "Размытие должно начинаться после выхода из мёртвой зоны")

    var captureActivity = DesktopCaptureActivityGate()
    try expect(!captureActivity.receive(angle: 120, velocity: 0, at: 0, openAngle: 115),
               "При неподвижной открытой крышке захват не нужен")
    try expect(!captureActivity.receive(angle: 119, velocity: -1, at: 0.1, openAngle: 115),
               "Небольшой шум датчика не должен запускать захват")
    try expect(captureActivity.receive(angle: 118, velocity: -12, at: 0.2, openAngle: 115),
               "Захват должен начинаться до видимого складывания")
    try expect(!FoldMotionModel.shouldPresentOverlay(
        for: FoldMotionModel.parameters(angle: 118, velocity: -12)),
        "При запуске захвата настоящий экран ещё должен быть виден")
    try expect(captureActivity.receive(angle: 70, velocity: 0, at: 1, openAngle: 115),
               "На частично закрытой крышке захват остаётся активным")
    try expect(captureActivity.receive(angle: 120, velocity: 0, at: 2, openAngle: 115),
               "У открытой крышки захват ждёт завершения анимации")
    try expect(captureActivity.receive(angle: 120, velocity: 0, at: 3.4, openAngle: 115),
               "До окончания паузы захват не останавливается")
    try expect(!captureActivity.receive(angle: 120, velocity: 0, at: 3.6, openAngle: 115),
               "После паузы у открытой крышки захват останавливается")
    try expect(captureActivity.receive(angle: 118, velocity: -12, at: 3.7, openAngle: 115),
               "Новое закрытие должно снова запускать захват")
    captureActivity.reset()
    captureActivity.forceCapture()
    try expect(captureActivity.wantsCapture,
               "Восстановление после сна может заранее подготовить захват")
    try expect(captureActivity.receive(angle: 112, velocity: 0, at: 10, openAngle: 105),
               "После пробуждения захват ждёт устойчивого открытого положения")
    try expect(captureActivity.receive(angle: 111, velocity: -10, at: 10.7, openAngle: 105),
               "Новое движение прерывает ожидание остановки захвата")
    try expect(captureActivity.receive(angle: 112, velocity: 0, at: 10.8, openAngle: 105),
               "После движения отсчёт устойчивого открытия начинается заново")
    try expect(captureActivity.receive(angle: 112, velocity: 0, at: 12.1, openAngle: 105),
               "Захват не должен остановиться по старому таймеру")
    try expect(!captureActivity.receive(angle: 112, velocity: 0, at: 12.4, openAngle: 105),
               "Захват останавливается после новой полной паузы")

    let calibratedOpen = FoldMotionModel.parameters(angle: 112, velocity: 0, openAngle: 112, closedAngle: 34)
    let calibratedClosed = FoldMotionModel.parameters(angle: 34, velocity: 0, openAngle: 112, closedAngle: 34)
    try expect(approximatelyEqual(calibratedOpen.progress, 0), "Калиброванная точка открытия должна давать progress = 0")
    try expect(approximatelyEqual(calibratedClosed.progress, 1), "Калиброванная точка финиша должна давать progress = 1")

    let slowBlur = FoldMotionModel.parameters(angle: 70, velocity: 0)
    let fastBlur = FoldMotionModel.parameters(angle: 70, velocity: 80)
    try expect(fastBlur.blurRadius > slowBlur.blurRadius, "Быстрое движение должно усиливать радиус размытия")
    try expect(fastBlur.blurBlend > slowBlur.blurBlend, "Быстрое движение должно сильнее замещать резкое изображение")

    let invalidTuning = EffectTuning(
        blurStrength: 4,
        verticalContrast: -1,
        edgeDissolve: 0,
        perspectiveDepth: 8,
        responseSeconds: 1
    ).clamped()
    try expect(approximatelyEqual(invalidTuning.blurStrength, 1.6), "Сила блюра должна ограничиваться безопасным диапазоном")
    try expect(approximatelyEqual(invalidTuning.verticalContrast, 0.4), "Вертикальный контраст должен ограничиваться безопасным диапазоном")
    try expect(approximatelyEqual(invalidTuning.edgeDissolve, 0.55), "Растворение краёв должно иметь безопасный минимум")
    try expect(approximatelyEqual(invalidTuning.perspectiveDepth, 1.4), "Перспектива должна ограничиваться безопасным диапазоном")
    try expect(approximatelyEqual(invalidTuning.responseSeconds, 0.12), "Инерция должна ограничиваться безопасным диапазоном")

    // Locked lid movement must follow the hinge and hold at a paused angle;
    // only loss of fresh sensor samples may retire an active frame.
    var gate = LockScreenMotionGate()
    let partlyClosed = FoldMotionModel.parameters(angle: 45, velocity: -30)
    try expect(!gate.shouldShow(parameters: partlyClosed, at: 0), "Без свежего датчика слой не показывается")
    gate.receive(angle: 115, at: 0)
    try expect(!gate.shouldShow(parameters: fullyOpen, at: 0), "Одна блокировка открытого экрана не запускает эффект")
    gate.receive(angle: 100, at: 0.1)
    let closing = FoldMotionModel.parameters(angle: 100, velocity: -30)
    try expect(gate.shouldShow(parameters: closing, at: 0.1), "Закрытие на локскрине должно запускать эффект")
    // Longer than the old 2-second hard cap: continuing motion stays visible.
    for step in 2...30 {
        let time = Double(step) / 10
        let angle = 102 - Double(step)
        gate.receive(angle: angle, at: time)
        let parameters = FoldMotionModel.parameters(angle: angle, velocity: -10)
        try expect(gate.shouldShow(parameters: parameters, at: time), "Движение не должно обрываться через 2 секунды")
    }
    gate.receive(angle: 115, at: 3.1)
    try expect(!gate.shouldShow(parameters: fullyOpen, at: 3.1), "Полное раскрытие освобождает экран")
    gate.receive(angle: 45, at: 3.2)
    try expect(gate.shouldShow(parameters: partlyClosed, at: 3.2), "Повторное закрытие запускает новый проход")
    try expect(!gate.shouldShow(parameters: partlyClosed, at: 3.6), "Пропавший датчик не удерживает слой")
    gate.invalidate()
    try expect(!gate.shouldShow(parameters: partlyClosed, at: 4), "Сон сбрасывает показание и активный проход")
    gate.receive(angle: 45, at: 4)
    try expect(gate.shouldShow(parameters: partlyClosed, at: 4), "Свежий угол после сна снова запускает эффект")
    for step in 1...40 {
        let time = 4 + Double(step) / 10
        gate.receive(angle: step.isMultiple(of: 2) ? 45 : 44, at: time)
        let shown = gate.shouldShow(parameters: partlyClosed, at: time)
        if time >= 6 { try expect(shown, "Неподвижная крышка удерживает текущий кадр при свежем датчике") }
    }
    gate.receive(angle: 43, at: 8.1)
    try expect(gate.shouldShow(parameters: partlyClosed, at: 8.1), "Движение после паузы продолжает тот же проход")
    try expect(!gate.shouldShow(parameters: partlyClosed, at: 8.5), "Пропавший сигнал датчика освобождает слой")
    gate.invalidate()
    gate.receive(angle: .nan, at: 9)
    try expect(!gate.shouldShow(parameters: partlyClosed, at: 9), "Некорректный угол не запускает слой")
    // Threshold noise should retain an active presentation, avoiding rapid
    // order-out/order-in cycles while the lid reverses close to the open stop.
    gate.receive(angle: 110, at: 10)
    try expect(gate.shouldShow(parameters: meaningfulMovement, at: 10), "Движение активирует слой")
    let thresholdBand = FoldMotionModel.parameters(angle: 112.1, velocity: 0)
    try expect(thresholdBand.progress > FoldMotionModel.overlayDeactivationProgress &&
               thresholdBand.progress < FoldMotionModel.overlayActivationProgress, "Проверяем полосу гистерезиса")
    gate.receive(angle: 112.1, at: 10.1)
    try expect(gate.shouldShow(parameters: thresholdBand, at: 10.1), "Полоса гистерезиса не прерывает начатое движение")
    let openGlass = FoldGlassGeometry.corners(progress: 0, tuning: .standard)
    try expect(openGlass[0].x < 0 && openGlass[0].y < 0 && openGlass[2].x > 1 && openGlass[2].y > 1,
               "Открытая маска должна полностью освобождать настоящий экран")
    let halfGlass = FoldGlassGeometry.corners(progress: 0.5, tuning: .standard)
    let foldedGlass = FoldGlassGeometry.corners(progress: 1, tuning: .standard)
    try expect(halfGlass[3].y < 1 && foldedGlass[3].y < halfGlass[3].y,
               "Верхняя грань стекла должна уходить вниз при закрытии")
    try expect(approximatelyEqual(halfGlass[2].x, 1 - halfGlass[3].x), "Перспектива должна оставаться симметричной")
    var deepTuning = EffectTuning.standard
    deepTuning.perspectiveDepth = 1.4
    let deepGlass = FoldGlassGeometry.corners(progress: 0.5, tuning: deepTuning)
    try expect(deepGlass[3].x > halfGlass[3].x, "Настройка глубины должна менять перспективу живой маски")

    // Track points INSIDE the image: a moving silhouette alone cannot pass.
    for depth in [0.65, 1.0, 1.4] {
        var tuning = EffectTuning.standard
        tuning.perspectiveDepth = depth
        for progress in [0.0, 0.15, 0.5, 0.85, 1.0] {
            for y in [0.0, 0.25, 0.5, 0.75, 1.0] {
                for x in [0.0, 0.25, 0.5, 0.75, 1.0] {
                    let source = FoldGlassGeometry.Point(x: x, y: y)
                    let projected = FoldGlassGeometry.project(source, progress: progress, tuning: tuning)
                    let restored = FoldGlassGeometry.unproject(projected, progress: progress, tuning: tuning)
                    try expect(approximatelyEqual(restored.x, x) && approximatelyEqual(restored.y, y),
                               "Обратная проекция должна возвращать координаты содержимого")
                    if progress == 0 || y == 0 {
                        try expect(approximatelyEqual(projected.x, x) && approximatelyEqual(projected.y, y),
                                   "Открытое изображение и линия шарнира не должны сдвигаться")
                    }
                    if progress > 0 && y > 0 && x != 0.5 {
                        try expect(abs(projected.x - 0.5) < abs(x - 0.5), "Содержимое внутри экрана должно сходиться к центру в перспективе")
                    }
                }
            }
        }
    }

    var openStop = LockScreenOpenStop()
    try expect(!openStop.receive(angle: 105, openAngle: 105), "Открытый локскрин не запускает блюр")
    try expect(!openStop.receive(angle: 98, openAngle: 105), "Шум у верхней точки не перезапускает слой")
    try expect(openStop.receive(angle: 96, openAngle: 105), "Новое закрытие возвращает эффект после явного движения")
    try expect(openStop.receive(angle: 99, openAngle: 105), "Слой остаётся до точки завершения раскрытия")
    try expect(!openStop.receive(angle: 100, openAngle: 105), "Раскрытие завершается по свежему углу, без тайм-аута")
    try expect(!openStop.receive(angle: 99, openAngle: 105), "Гистерезис не допускает самоповтор у открытого края")

    var wake = WakeMotionGate()
    wake.begin(at: 0)
    try expect(!wake.allowsMotion(at: 0.1), "После сна ждём свежий угол на уже подготовленном слое")
    wake.receive(angle: 60, at: 0.12, openAngle: 115)
    try expect(wake.allowsMotion(at: 0.12), "Своевременный датчик сразу управляет раскрытием")
    wake.suppressUntilClosing(from: 83)
    wake.receive(angle: 89, at: 0.8, openAngle: 115)
    try expect(!wake.allowsMotion(at: 0.8), "После паузы раскрытие не должно запускаться повторно на 89°")
    wake.receive(angle: 105, at: 0.9, openAngle: 115)
    try expect(!wake.allowsMotion(at: 0.9), "Продолжение того же раскрытия не должно доигрывать слой само")
    wake.receive(angle: 103, at: 1.0, openAngle: 115)
    try expect(wake.allowsMotion(at: 1.0), "Новое закрытие после паузы снова разрешает слой")
    wake.begin(at: 10)
    try expect(!wake.allowsMotion(at: 10.5), "Просроченное пробуждение не начинает новый показ")
    wake.receive(angle: 60, at: 11, openAngle: 115)
    wake.receive(angle: 80, at: 11.1, openAngle: 115)
    try expect(!wake.allowsMotion(at: 11.1), "Поздние показания открытия не должны повторно заблюривать локскрин")
    wake.receive(angle: 77, at: 11.2, openAngle: 115)
    try expect(wake.allowsMotion(at: 11.2), "Новое закрытие после пропущенного раскрытия снова разрешено")
    wake.begin(at: 20)
    wake.receive(angle: 60, at: 20.6, openAngle: 115)
    try expect(!wake.allowsMotion(at: 20.6), "Сам поздний образец должен заметить дедлайн, даже если таймер не сработал")
    wake.receive(angle: 115, at: 21, openAngle: 115)
    try expect(wake.allowsMotion(at: 21), "Открытая крышка готова к следующему циклу")
    print("✓ Проверки движения, 3D-маски и отсутствия позднего показа после сна пройдены")
} catch {
    fputs("✗ \(error)\n", stderr)
    exit(1)
}
