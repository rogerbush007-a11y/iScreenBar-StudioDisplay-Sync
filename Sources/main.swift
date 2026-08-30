import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit.hid
import ObjectiveC.runtime
import UniformTypeIdentifiers

private let benqVendorID = 0x04A5
private let iScreenBarProductID = 0x2501
private let pollInterval: TimeInterval = 0.25

private func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    print("[\(formatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

private let activeControlColor = NSColor.controlAccentColor

private enum UIStyle {
    static let panelWidth: CGFloat = 344
    static let contentWidth: CGFloat = 312
    static let outerInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 8
    static let bodyFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let controlFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let captionFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let iconSize: CGFloat = 15
}

private final class HighlightSliderCell: NSSliderCell {
    let activeColor: NSColor
    var isInteracting = false

    init(activeColor: NSColor) {
        self.activeColor = activeColor
        super.init()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard isInteracting else {
            super.drawBar(inside: rect, flipped: flipped)
            return
        }
        let track = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        activeColor.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
    }
}

private final class InteractiveSlider: NSSlider {
    private let activeColor: NSColor
    private let highlightCell: HighlightSliderCell

    init(value: Double, minValue: Double, maxValue: Double, activeColor: NSColor) {
        self.activeColor = activeColor
        highlightCell = HighlightSliderCell(activeColor: activeColor)
        super.init(frame: .zero)
        cell = highlightCell
        self.minValue = minValue
        self.maxValue = maxValue
        self.doubleValue = value
        wantsLayer = true
        layer?.cornerRadius = 7
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        highlightCell.isInteracting = true
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            layer?.backgroundColor = activeColor.withAlphaComponent(0.14).cgColor
        }
        super.mouseDown(with: event)
        highlightCell.isInteracting = false
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

private func displayPowerIcon() -> NSImage {
    let size = NSSize(width: 21, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        let displayConfig = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let powerConfig = NSImage.SymbolConfiguration(pointSize: 7, weight: .semibold)
        let display = NSImage(systemSymbolName: "display", accessibilityDescription: "内屏开关")?
            .withSymbolConfiguration(displayConfig)
        let power = NSImage(systemSymbolName: "power", accessibilityDescription: nil)?
            .withSymbolConfiguration(powerConfig)
        display?.draw(in: rect)
        power?.draw(in: NSRect(x: 7, y: 6, width: 7, height: 7))
        return true
    }
    image.isTemplate = true
    return image
}

private final class FeatureButton: NSButton {
    private let accentColor: NSColor

    init(title: String, symbol: String, accentColor: NSColor) {
        self.accentColor = accentColor
        super.init(frame: .zero)
        self.title = title
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = .imageLeading
        imageHugsTitle = true
        font = UIStyle.controlFont
        alignment = .center
        setButtonType(.toggle)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        layer?.shadowRadius = 6
        focusRingType = .none
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override var state: NSControl.StateValue {
        didSet { updateAppearance() }
    }

    override func updateLayer() {
        super.updateLayer()
        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        let foregroundColor: NSColor = state == .on ? .white : .black
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIStyle.controlFont,
            .foregroundColor: foregroundColor
        ]
        attributedTitle = NSAttributedString(string: title, attributes: titleAttributes)
        if state == .on {
            layer.backgroundColor = accentColor.withAlphaComponent(0.88).cgColor
            layer.borderColor = accentColor.cgColor
            layer.shadowColor = accentColor.withAlphaComponent(0.18).cgColor
            layer.shadowOpacity = 1
            contentTintColor = .white
        } else {
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.045).cgColor
            layer.borderColor = NSColor.black.withAlphaComponent(0.09).cgColor
            layer.shadowColor = NSColor.clear.cgColor
            layer.shadowOpacity = 0
            contentTintColor = .black
        }
        layer.borderWidth = 0.5
    }
}

/// 保留 macOS 开关的尺寸与滑块形态，只固定开启态的高亮颜色。
private final class AccentSwitch: NSButton {
    private let accentColor: NSColor
    private let knobLayer = CALayer()

    init(accentColor: NSColor = .systemBlue) {
        self.accentColor = accentColor
        super.init(frame: .zero)
        title = ""
        setButtonType(.toggle)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        knobLayer.backgroundColor = NSColor.white.cgColor
        knobLayer.shadowColor = NSColor.black.cgColor
        knobLayer.shadowOpacity = 0.18
        knobLayer.shadowRadius = 1.5
        knobLayer.shadowOffset = NSSize(width: 0, height: -0.5)
        layer?.addSublayer(knobLayer)
        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 38, height: 22) }

    override var state: NSControl.StateValue {
        didSet { updateAppearance(animated: window != nil) }
    }

    override var isEnabled: Bool {
        didSet { updateAppearance(animated: false) }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        updateAppearance(animated: false)
    }

    private func updateAppearance(animated: Bool) {
        guard let layer else { return }
        let knobSize = max(0, bounds.height - 4)
        let knobX = state == .on ? max(2, bounds.width - knobSize - 2) : 2
        let changes = {
            layer.backgroundColor = (self.state == .on
                ? self.accentColor
                : NSColor.systemGray.withAlphaComponent(0.34)).cgColor
            layer.opacity = self.isEnabled ? 1 : 0.45
            self.knobLayer.cornerRadius = knobSize / 2
            self.knobLayer.frame = NSRect(x: knobX, y: 2, width: knobSize, height: knobSize)
        }
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.16)
            changes()
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            changes()
            CATransaction.commit()
        }
    }
}

private struct SavedMode: Codable {
    let name: String
    let brightness: Int
    let temperature: Int
    let videoMode: Bool
}

private struct DisplayPreset: Codable {
    var name: String
    var builtinEnabled: Bool
    var rotation: Int
    var builtinPrimary: Bool
}

private final class DisplayController {
    private typealias GetDisplayList = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    private typealias ConfigureEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private let skyLightHandle: UnsafeMutableRawPointer?
    private let monitorPanelHandle: UnsafeMutableRawPointer?
    private let getDisplayList: GetDisplayList?
    private let configureEnabled: ConfigureEnabled?

    init() {
        skyLightHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        monitorPanelHandle = dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_LAZY)
        if let handle = skyLightHandle, let symbol = dlsym(handle, "CGSGetDisplayList") {
            getDisplayList = unsafeBitCast(symbol, to: GetDisplayList.self)
        } else { getDisplayList = nil }
        if let handle = skyLightHandle, let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") {
            configureEnabled = unsafeBitCast(symbol, to: ConfigureEnabled.self)
        } else { configureEnabled = nil }
    }

    deinit {
        if let skyLightHandle { dlclose(skyLightHandle) }
        if let monitorPanelHandle { dlclose(monitorPanelHandle) }
    }

    var isAvailable: Bool { getDisplayList != nil && configureEnabled != nil && monitorPanelHandle != nil }

    private func displays() -> [CGDirectDisplayID] {
        guard let getDisplayList else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard getDisplayList(32, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func isGhost(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayIsOnline(id) == 0 && CGDisplayVendorNumber(id) == 0 &&
            CGDisplayModelNumber(id) == 0 && CGDisplaySerialNumber(id) == 0
    }

    func builtinDisplay() -> CGDirectDisplayID? {
        displays().first { CGDisplayIsBuiltin($0) != 0 && !isGhost($0) }
    }

    func externalDisplays() -> [CGDirectDisplayID] {
        displays().filter {
            CGDisplayIsBuiltin($0) == 0 && !isGhost($0) && CGDisplayIsOnline($0) != 0 &&
                CGDisplayIsActive($0) != 0 && (CGDisplayVendorNumber($0) != 0 || CGDisplayModelNumber($0) != 0)
        }
    }

    func currentPreset(name: String) -> DisplayPreset? {
        guard let builtin = builtinDisplay() else { return nil }
        return DisplayPreset(name: name,
                             builtinEnabled: CGDisplayIsOnline(builtin) != 0,
                             rotation: Int(CGDisplayRotation(builtin).rounded()),
                             builtinPrimary: CGMainDisplayID() == builtin)
    }

    private func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) -> Bool {
        guard let configureEnabled else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        if !enabled, CGDisplayIsInMirrorSet(id) != 0,
           CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay) != .success {
            CGCancelDisplayConfiguration(config); return false
        }
        guard configureEnabled(config, id, enabled) == .success else {
            CGCancelDisplayConfiguration(config); return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    func enableBuiltin() -> Bool {
        for attempt in 0..<3 {
            guard let builtin = builtinDisplay() else { return false }
            if CGDisplayIsOnline(builtin) != 0 { return true }
            _ = setEnabled(builtin, true)
            if CGDisplayIsOnline(builtin) != 0 { return true }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.4) }
        }
        return false
    }

    func disableBuiltin() -> Bool {
        guard !externalDisplays().isEmpty, let builtin = builtinDisplay() else { return false }
        if CGDisplayIsOnline(builtin) == 0 { return true }
        return setEnabled(builtin, false) && CGDisplayIsOnline(builtin) == 0
    }

    func restoreBuiltinDefault() -> Bool {
        guard enableBuiltin(),
              let builtin = builtinDisplay(),
              CGDisplayIsOnline(builtin) != 0 else { return false }
        let rotationRestored = Int(CGDisplayRotation(builtin).rounded()) == 0 || rotateBuiltin(to: 0)
        let primaryRestored = CGMainDisplayID() == builtin || makePrimary(builtin)
        return rotationRestored && primaryRestored
    }

    func rotateBuiltin(to degrees: Int) -> Bool {
        guard let builtin = builtinDisplay(), CGDisplayIsOnline(builtin) != 0,
              let cls: AnyClass = NSClassFromString("MPDisplay"),
              let rawObject = class_createInstance(cls, 0) else { return false }
        let object = rawObject as AnyObject
        let initSelector = NSSelectorFromString("initWithCGSDisplayID:")
        let setSelector = NSSelectorFromString("setOrientation:")
        guard let initMethod = class_getInstanceMethod(cls, initSelector),
              let setMethod = class_getInstanceMethod(cls, setSelector) else { return false }
        typealias InitFunction = @convention(c) (AnyObject, Selector, UInt32) -> Unmanaged<AnyObject>
        typealias SetFunction = @convention(c) (AnyObject, Selector, Int32) -> Void
        // class_createInstance 已持有对象；init 返回同一实例，不能再次按 retained 接管，
        // 否则函数结束时会重复 release，并在启用旋转预设时触发 EXC_BAD_ACCESS。
        let initialized = unsafeBitCast(method_getImplementation(initMethod), to: InitFunction.self)(object, initSelector, builtin).takeUnretainedValue()
        unsafeBitCast(method_getImplementation(setMethod), to: SetFunction.self)(initialized, setSelector, Int32(degrees))
        return true
    }

    func makePrimary(_ target: CGDirectDisplayID) -> Bool {
        let targetBounds = CGDisplayBounds(target)
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for display in displays() where CGDisplayIsOnline(display) != 0 && !isGhost(display) {
            let bounds = CGDisplayBounds(display)
            let error = CGConfigureDisplayOrigin(config, display,
                Int32(bounds.origin.x - targetBounds.origin.x), Int32(bounds.origin.y - targetBounds.origin.y))
            if error != .success { CGCancelDisplayConfiguration(config); return false }
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    func apply(_ preset: DisplayPreset) -> Bool {
        if preset.builtinEnabled {
            guard enableBuiltin(), let builtin = builtinDisplay() else { return false }
            _ = rotateBuiltin(to: preset.rotation)
            let primary = preset.builtinPrimary ? builtin : (externalDisplays().first ?? builtin)
            if CGMainDisplayID() != primary { _ = makePrimary(primary) }
            return true
        }
        guard let external = externalDisplays().first else { return false }
        if let builtin = builtinDisplay(), CGDisplayIsOnline(builtin) != 0 {
            _ = rotateBuiltin(to: preset.rotation)
            _ = makePrimary(external)
        }
        return disableBuiltin()
    }
}

private final class StatusIndicator: NSObject {
    private let presenceDelayOptions = [180, 300, 600]
    private let item: NSStatusItem
    private let lamp: LampController
    private let popover = NSPopover()
    private let powerSwitch = FeatureButton(title: "灯光", symbol: "power", accentColor: activeControlColor)
    private let brightnessSlider = InteractiveSlider(value: 50, minValue: 1, maxValue: 100, activeColor: .systemBlue)
    private let brightnessValueLabel = NSTextField(labelWithString: "50%")
    private let temperatureSlider = InteractiveSlider(value: 5000, minValue: 2700, maxValue: 6500, activeColor: .systemYellow)
    private let temperatureValueLabel = NSTextField(labelWithString: "5000K")
    private let timeTemperatureSwitch = FeatureButton(title: "自动色温", symbol: "circle.lefthalf.filled", accentColor: activeControlColor)
    private let autoLightSwitch = FeatureButton(title: "自动感光", symbol: "sun.max", accentColor: activeControlColor)
    private let presenceSwitch = FeatureButton(title: "入座检测", symbol: "figure.seated.side", accentColor: activeControlColor)
    private let presenceDelayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let presenceSensitivityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var presenceDelaySeconds = 180
    private var presenceSensitivity = 2
    private let videoModeSwitch = FeatureButton(title: "视频模式", symbol: "video", accentColor: activeControlColor)
    private let modeButton = NSButton(title: "我的最爱", target: nil, action: nil)
    private let rotationModeButton = NSButton(title: "竖屏双屏", target: nil, action: nil)
    private var modeCenterWindow: NSWindow?
    private let bindAppButton = NSButton(title: "绑定应用", target: nil, action: nil)
    private let brightnessFollowSwitch = FeatureButton(title: "亮度跟随", symbol: "display", accentColor: activeControlColor)
    private let powerSyncSwitch = FeatureButton(title: "熄屏同步", symbol: "moon.zzz", accentColor: activeControlColor)
    private let captureBrightButton = FeatureButton(title: "明亮关灯", symbol: "sun.max.fill", accentColor: .systemOrange)
    private let captureDarkButton = FeatureButton(title: "昏暗开灯", symbol: "moon.fill", accentColor: .systemBlue)
    private let ambientEnableSwitch = AccentSwitch()
    private let brightThresholdLabel = NSTextField(labelWithString: "--")
    private let darkThresholdLabel = NSTextField(labelWithString: "--")
    private let ambientStatusLabel = NSTextField(labelWithString: "尚未完成环境标定")
    private let displayPowerSwitch: FeatureButton = {
        let button = FeatureButton(title: "内屏", symbol: "display", accentColor: activeControlColor)
        button.image = displayPowerIcon()
        return button
    }()
    private let displayRotateButton = FeatureButton(title: "旋转 0°", symbol: "arrow.clockwise", accentColor: activeControlColor)
    private let displayAutoPresetSwitch = AccentSwitch()
    private let displayController = DisplayController()
    private(set) var isBrightnessFollowEnabled: Bool
    private(set) var isPowerSyncEnabled: Bool
    private(set) var isTimeTemperatureEnabled: Bool
    private(set) var ambientCloseThreshold: Int?
    private(set) var ambientOpenThreshold: Int?
    private(set) var currentDisplayAmbientProxy: Int?
    private var currentAmbientSourceName = "显示器"
    private var ambientThresholdSource: String?
    private var areAmbientRulesEnabled: Bool
    private var isDisplayAutoPresetEnabled: Bool
    private var isHealthy = true
    private var isAsleep: Bool
    private var autoLightChangePendingUntil: Date?
    private var pendingAutoLightState: Bool?
    private var lastScheduledTemperature: Int?
    private var lastScheduledTemperatureChangeAt = Date.distantPast
    private var lastFrontmostBundleID: String?
    private var isAmbientPresenceLockActive = false
    private var presenceWasEnabledBeforeAmbientLock = false
    private var isDisplaySessionSafe = false
    private var pendingDisplayConnectionState: Bool?
    private var pendingDisplayPolicyWorkItem: DispatchWorkItem?

    private var isBuiltinManuallyDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: "builtinManuallyDisabled") }
        set { UserDefaults.standard.set(newValue, forKey: "builtinManuallyDisabled") }
    }

    init(isAsleep: Bool, lamp: LampController) {
        self.lamp = lamp
        self.isAsleep = isAsleep
        isBrightnessFollowEnabled = UserDefaults.standard.bool(forKey: "brightnessFollowEnabled")
        isPowerSyncEnabled = UserDefaults.standard.object(forKey: "powerSyncEnabled") as? Bool ?? true
        isTimeTemperatureEnabled = UserDefaults.standard.bool(forKey: "timeTemperatureEnabled")
        ambientCloseThreshold = UserDefaults.standard.object(forKey: "ambientCloseThreshold") as? Int
        ambientOpenThreshold = UserDefaults.standard.object(forKey: "ambientOpenThreshold") as? Int
        ambientThresholdSource = UserDefaults.standard.string(forKey: "ambientThresholdSource")
        areAmbientRulesEnabled = UserDefaults.standard.object(forKey: "ambientRulesEnabled") as? Bool
            ?? (ambientCloseThreshold != nil || ambientOpenThreshold != nil)
        UserDefaults.standard.removeObject(forKey: "ambientLinkEnabled")
        if ambientThresholdSource != "studioDisplayALS-v1" {
            ambientCloseThreshold = nil
            ambientOpenThreshold = nil
            areAmbientRulesEnabled = false
        }
        presenceWasEnabledBeforeAmbientLock = UserDefaults.standard.bool(forKey: "ambientSuspendedPresenceWasEnabled")
        isDisplayAutoPresetEnabled = UserDefaults.standard.bool(forKey: "displayAutoPresetEnabled")
        presenceDelaySeconds = UserDefaults.standard.object(forKey: "presenceDelaySeconds") as? Int ?? 180
        if !presenceDelayOptions.contains(presenceDelaySeconds) {
            presenceDelaySeconds = 180
        }
        presenceSensitivity = UserDefaults.standard.object(forKey: "presenceSensitivity") as? Int ?? 2
        presenceSensitivity = max(0, min(2, presenceSensitivity))
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        migrateDisplayPresetIfNeeded()
        configurePanel()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate),
                                               name: NSApplication.willTerminateNotification, object: nil)
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameUnsafe),
                                           name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameUnsafe),
                                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameActive),
                                           name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameActive),
                                           name: NSWorkspace.screensDidWakeNotification, object: nil)
        scheduleDisplaySessionActivation()
        update(isAsleep: isAsleep, healthy: true)
    }

    func update(isAsleep: Bool, healthy: Bool) {
        self.isAsleep = isAsleep
        isHealthy = healthy
        if lamp.isAutoLightEnabled == true, isBrightnessFollowEnabled {
            isBrightnessFollowEnabled = false
            brightnessFollowSwitch.state = .off
            UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
            log("检测到灯具自动感光已开启，已自动关闭 Studio Display 亮度跟随")
        }
        updateIcon(healthy: healthy)
        let displayState = isAsleep ? "Studio Display 已熄屏" : "Studio Display 已唤醒"
        let brightnessStatus = isBrightnessFollowEnabled ? "亮度跟随已开启" : "亮度跟随已关闭"
        let powerStatus = isPowerSyncEnabled ? "熄屏同步已开启" : "熄屏同步已关闭"
        let status = healthy ? "同步正常" : "同步异常"
        _ = (displayState, brightnessStatus, powerStatus)
        let brightnessText = healthy ? lamp.currentBrightness.map { "\($0)%" } ?? "--%" : "--%"
        let temperatureText = healthy ? lamp.currentTemperature.map { "\($0)K" } ?? "----K" : "----K"
        item.button?.toolTip = "\(brightnessText) · \(temperatureText)"
        item.button?.setAccessibilityLabel("iScreenBar \(status)")
        if popover.isShown { refreshControls() }
    }

    @objc private func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            lamp.requestStatus()
            refreshControls()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func powerChanged() {
        let requested = powerSwitch.state == .on
        if !lamp.setPower(on: requested) { powerSwitch.state = requested ? .off : .on }
        updateIcon(healthy: isHealthy && lamp.isConnected)
        lamp.requestStatus()
    }

    @objc private func captureBrightThreshold() {
        guard let value = currentDisplayAmbientProxy else {
            captureBrightButton.state = .off
            ambientStatusLabel.stringValue = "暂时无法读取 Studio Display 光线传感器"
            NSSound.beep()
            return
        }
        ambientCloseThreshold = value
        UserDefaults.standard.set(value, forKey: "ambientCloseThreshold")
        ambientThresholdSource = "studioDisplayALS-v1"
        UserDefaults.standard.set("studioDisplayALS-v1", forKey: "ambientThresholdSource")
        updateAmbientStatusLabel()
        flashCaptureSuccess(button: captureBrightButton, valueLabel: brightThresholdLabel)
        log("已采集环境关灯点：\(currentAmbientSourceName) 响应分数 \(value)")
    }

    @objc private func captureDarkThreshold() {
        guard let value = currentDisplayAmbientProxy else {
            captureDarkButton.state = .off
            ambientStatusLabel.stringValue = "暂时无法读取 Studio Display 光线传感器"
            NSSound.beep()
            return
        }
        ambientOpenThreshold = value
        UserDefaults.standard.set(value, forKey: "ambientOpenThreshold")
        ambientThresholdSource = "studioDisplayALS-v1"
        UserDefaults.standard.set("studioDisplayALS-v1", forKey: "ambientThresholdSource")
        updateAmbientStatusLabel()
        flashCaptureSuccess(button: captureDarkButton, valueLabel: darkThresholdLabel)
        log("已采集环境开灯点：\(currentAmbientSourceName) 响应分数 \(value)")
    }

    private func flashCaptureSuccess(button: FeatureButton, valueLabel: NSTextField) {
        button.state = .on
        valueLabel.textColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak button, weak valueLabel] in
            button?.state = .off
            valueLabel?.textColor = .secondaryLabelColor
        }
    }

    @objc private func ambientEnableChanged() {
        areAmbientRulesEnabled = ambientEnableSwitch.state == .on
        UserDefaults.standard.set(areAmbientRulesEnabled, forKey: "ambientRulesEnabled")
        updateAmbientStatusLabel()
        log(areAmbientRulesEnabled ? "已启用保存的环境光规则" : "已停用环境光规则，保留标定数值")
    }

    func updateDisplayAmbientProxy(_ value: Int?, sourceName: String) {
        currentDisplayAmbientProxy = value
        currentAmbientSourceName = sourceName
        if popover.isShown { updateAmbientStatusLabel() }
    }

    @discardableResult
    func suspendPresenceForAmbientLock() -> Bool {
        if isAmbientPresenceLockActive {
            maintainPresenceSuspendedForAmbientLock()
            return true
        }
        isAmbientPresenceLockActive = true
        presenceWasEnabledBeforeAmbientLock = presenceWasEnabledBeforeAmbientLock || lamp.isPresenceDetectionEnabled == true
        if presenceWasEnabledBeforeAmbientLock {
            guard lamp.setPresenceDetection(enabled: false, delaySeconds: presenceDelaySeconds,
                                            sensitivity: presenceSensitivity) else {
                isAmbientPresenceLockActive = false
                presenceWasEnabledBeforeAmbientLock = false
                return false
            }
            UserDefaults.standard.set(true, forKey: "ambientSuspendedPresenceWasEnabled")
            log("环境关灯锁定已临时暂停入座检测")
        }
        refreshControls()
        return true
    }

    func maintainPresenceSuspendedForAmbientLock() {
        guard isAmbientPresenceLockActive, lamp.isPresenceDetectionEnabled == true else { return }
        presenceWasEnabledBeforeAmbientLock = true
        if lamp.setPresenceDetection(enabled: false, delaySeconds: presenceDelaySeconds,
                                     sensitivity: presenceSensitivity) {
            UserDefaults.standard.set(true, forKey: "ambientSuspendedPresenceWasEnabled")
            log("检测到环境锁定期间入座检测仍开启，已临时暂停")
        }
    }

    func restorePresenceAfterAmbientLock() {
        guard isAmbientPresenceLockActive || presenceWasEnabledBeforeAmbientLock else { return }
        let shouldRestore = presenceWasEnabledBeforeAmbientLock
        isAmbientPresenceLockActive = false
        presenceWasEnabledBeforeAmbientLock = false
        UserDefaults.standard.removeObject(forKey: "ambientSuspendedPresenceWasEnabled")
        if shouldRestore {
            if lamp.setPresenceDetection(enabled: true, delaySeconds: presenceDelaySeconds,
                                         sensitivity: presenceSensitivity) {
                log("环境关灯锁定已解除，已恢复入座检测")
            } else {
                log("环境关灯锁定已解除，但入座检测恢复失败")
            }
        }
        refreshControls()
    }

    var hasPendingAmbientPresenceRestore: Bool {
        return presenceWasEnabledBeforeAmbientLock
    }

    private func updateAmbientStatusLabel() {
        brightThresholdLabel.stringValue = ambientCloseThreshold.map(String.init) ?? "--"
        darkThresholdLabel.stringValue = ambientOpenThreshold.map(String.init) ?? "--"
        captureBrightButton.state = .off
        captureDarkButton.state = .off
        ambientEnableSwitch.state = areAmbientRulesEnabled ? .on : .off
        ambientEnableSwitch.isEnabled = currentDisplayAmbientProxy != nil &&
            (ambientCloseThreshold != nil || ambientOpenThreshold != nil)
        let currentText = currentDisplayAmbientProxy.map { "当前环境 \($0)" } ?? "当前环境 --"
        if let close = ambientCloseThreshold, let open = ambientOpenThreshold, open >= close {
            ambientStatusLabel.stringValue = "\(currentText)  ·  阈值重叠，可能反复开关"
        } else if !areAmbientRulesEnabled, ambientCloseThreshold != nil || ambientOpenThreshold != nil {
            ambientStatusLabel.stringValue = "\(currentText)  ·  已保存，未启用"
        } else {
            ambientStatusLabel.stringValue = currentText
        }
    }

    var isAmbientLinkEnabled: Bool {
        return areAmbientRulesEnabled && (ambientCloseThreshold != nil || ambientOpenThreshold != nil)
    }

    @objc private func brightnessChanged() {
        let value = Int(brightnessSlider.doubleValue.rounded())
        brightnessValueLabel.stringValue = "\(value)%"
        _ = lamp.setBrightness(value)
        lamp.requestStatus()
    }

    @objc private func temperatureChanged() {
        let value = Int((temperatureSlider.doubleValue / 100).rounded()) * 100
        temperatureSlider.doubleValue = Double(value)
        temperatureValueLabel.stringValue = "\(value)K"
        _ = lamp.setTemperature(value)
        lamp.requestStatus()
    }

    @objc private func timeTemperatureChanged() {
        isTimeTemperatureEnabled = timeTemperatureSwitch.state == .on
        UserDefaults.standard.set(isTimeTemperatureEnabled, forKey: "timeTemperatureEnabled")
        lastScheduledTemperature = nil
        lastScheduledTemperatureChangeAt = .distantPast
        refreshControls()
        if isTimeTemperatureEnabled {
            applyScheduledTemperatureIfNeeded(isAsleep: isAsleep, force: true)
            log("已开启色温随时间")
        } else {
            log("已关闭色温随时间，保持当前色温")
        }
    }

    func applyScheduledTemperatureIfNeeded(isAsleep: Bool, force: Bool = false) {
        guard isTimeTemperatureEnabled,
              !isAsleep,
              lamp.isConnected,
              lamp.isPowerOn == true else { return }
        let target = scheduledTemperature(at: Date())
        guard force || target != lastScheduledTemperature || lamp.currentTemperature != target else { return }
        guard force || Date().timeIntervalSince(lastScheduledTemperatureChangeAt) >= 60 else { return }
        if lamp.setTemperature(target) {
            lastScheduledTemperature = target
            lastScheduledTemperatureChangeAt = Date()
            log("色温随时间已调整为 \(target)K")
        }
    }

    private func scheduledTemperature(at date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let value: Double
        switch minute {
        case 0..<(6 * 60):
            value = 3000
        case (6 * 60)..<(10 * 60):
            value = interpolate(minute: minute, from: 6 * 60, to: 10 * 60, start: 3000, end: 5500)
        case (10 * 60)..<(16 * 60):
            value = 5500
        case (16 * 60)..<(21 * 60):
            value = interpolate(minute: minute, from: 16 * 60, to: 21 * 60, start: 5500, end: 3500)
        default:
            value = interpolate(minute: minute, from: 21 * 60, to: 24 * 60, start: 3500, end: 3000)
        }
        return max(2700, min(6500, Int((value / 50).rounded()) * 50))
    }

    private func interpolate(minute: Int, from: Int, to: Int, start: Double, end: Double) -> Double {
        let progress = Double(minute - from) / Double(to - from)
        return start + (end - start) * max(0, min(1, progress))
    }

    @objc private func autoLightChanged() {
        let requested = autoLightSwitch.state == .on
        if !lamp.setAutoLight(enabled: requested) {
            autoLightSwitch.state = requested ? .off : .on
            return
        }
        autoLightChangePendingUntil = Date().addingTimeInterval(1)
        pendingAutoLightState = requested
        if requested, isBrightnessFollowEnabled {
            isBrightnessFollowEnabled = false
            brightnessFollowSwitch.state = .off
            UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
            update(isAsleep: isAsleep, healthy: isHealthy)
            log("已关闭 Studio Display 亮度跟随，改用灯具自动感光")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.lamp.requestStatus()
        }
    }

    @objc private func presenceChanged() {
        let requested = presenceSwitch.state == .on
        if !lamp.setPresenceDetection(enabled: requested, delaySeconds: presenceDelaySeconds, sensitivity: presenceSensitivity) {
            presenceSwitch.state = requested ? .off : .on
        }
        lamp.requestStatus()
    }

    @objc private func presenceDelayChanged() {
        let seconds = selectedPresenceDelaySeconds()
        presenceDelaySeconds = seconds
        UserDefaults.standard.set(seconds, forKey: "presenceDelaySeconds")
        log("入座检测时间设置为 \(seconds) 秒")
        if lamp.isPresenceDetectionEnabled == true {
            let requested = presenceSwitch.state == .on
            if !lamp.setPresenceDetection(enabled: requested, delaySeconds: seconds, sensitivity: presenceSensitivity) {
                log("入座检测时间未成功下发到灯具，已保持本地设置")
            }
            lamp.requestStatus()
        }
    }

    @objc private func presenceSensitivityChanged() {
        presenceSensitivity = presenceSensitivityPopup.selectedItem?.tag ?? 2
        UserDefaults.standard.set(presenceSensitivity, forKey: "presenceSensitivity")
        log("离席侦测灵敏度设置为 \(presenceSensitivityPopup.titleOfSelectedItem ?? "高")")
        if lamp.isPresenceDetectionEnabled == true {
            if !lamp.setPresenceDetection(enabled: true, delaySeconds: presenceDelaySeconds, sensitivity: presenceSensitivity) {
                log("离席侦测灵敏度未成功下发到灯具，已保持本地设置")
            }
            lamp.requestStatus()
        }
    }

    @objc private func videoModeChanged() {
        let requested = videoModeSwitch.state == .on
        if !lamp.setVideoMode(enabled: requested) {
            videoModeSwitch.state = requested ? .off : .on
        }
        lamp.requestStatus()
    }

    @objc private func presetChanged(_ sender: NSMenuItem) {
        let index = sender.tag
        let preset: (brightness: Int, temperature: Int, video: Bool)
        if (index == 0 || index >= 3),
           let data = UserDefaults.standard.data(forKey: "savedCustomMode"),
           let saved = try? JSONDecoder().decode(SavedMode.self, from: data) {
            preset = (saved.brightness, saved.temperature, saved.videoMode)
        } else {
            switch index {
            case 1: preset = (30, 4000, false)
            case 2: preset = (20, 3000, false)
            default: preset = (47, 5500, false)
            }
        }
        isBrightnessFollowEnabled = false
        brightnessFollowSwitch.state = .off
        UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
        _ = lamp.setPower(on: true)
        _ = lamp.setBrightness(preset.brightness)
        _ = lamp.setTemperature(preset.temperature)
        _ = lamp.setVideoMode(enabled: preset.video)
        refreshControls()
        modeButton.title = sender.title
        log("已应用模式预设：\(sender.title)")
        lamp.requestStatus()
    }

    @objc private func showModeMenu() {
        let menu = NSMenu()
        for (index, title) in modeNames().enumerated() {
            let item = NSMenuItem(title: title, action: #selector(presetChanged(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            if title == modeButton.title { item.state = .on }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let center = NSMenuItem(title: "模式中心设置…", action: #selector(showModeCenter), keyEquivalent: "")
        center.target = self
        menu.addItem(center)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: modeButton.bounds.height + 4), in: modeButton)
    }

    private func modeNames() -> [String] {
        var names = ["我的最爱", "夜间工作", "睡前放松"]
        if let data = UserDefaults.standard.data(forKey: "savedCustomMode"),
           let mode = try? JSONDecoder().decode(SavedMode.self, from: data),
           !names.contains(mode.name) {
            names.append(mode.name)
        }
        return names
    }

    @objc private func showModeCenter() {
        if let window = modeCenterWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 270),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "模式中心"
        let title = NSTextField(labelWithString: "模式中心")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "快速切换预设灯光场景")
        subtitle.font = UIStyle.bodyFont
        subtitle.textColor = .secondaryLabelColor
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 1
        rows.wantsLayer = true
        rows.layer?.cornerRadius = 10
        rows.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        for (index, name) in modeNames().enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(modeCenterPresetChanged(_:)))
            button.tag = index
            button.isBordered = false
            button.setAccessibilityTitle(name)
            button.translatesAutoresizingMaskIntoConstraints = false
            let label = NSTextField(labelWithString: name)
            label.font = UIStyle.bodyFont
            label.translatesAutoresizingMaskIntoConstraints = false
            let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
            chevron.contentTintColor = .tertiaryLabelColor
            chevron.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
            chevron.translatesAutoresizingMaskIntoConstraints = false
            let row = NSView()
            row.addSubview(button)
            row.addSubview(label)
            row.addSubview(chevron)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 44),
                button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                button.topAnchor.constraint(equalTo: row.topAnchor),
                button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
                chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                chevron.widthAnchor.constraint(equalToConstant: 10),
                chevron.heightAnchor.constraint(equalToConstant: 14)
            ])
            rows.addArrangedSubview(row)
        }
        let add = NSButton(title: "新增场景模式", target: self, action: #selector(saveCurrentMode))
        add.bezelStyle = .rounded
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        add.imagePosition = .imageLeading
        let bind = NSButton(title: "绑定应用", target: self, action: #selector(bindCurrentModeToApp))
        bind.bezelStyle = .rounded
        bind.image = NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)
        bind.imagePosition = .imageLeading
        let leadingSpace = NSView()
        let trailingSpace = NSView()
        leadingSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailingSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [leadingSpace, add, bind, trailingSpace])
        actions.orientation = .horizontal
        actions.spacing = 10
        actions.distribution = .fill
        actions.widthAnchor.constraint(equalToConstant: 512).isActive = true
        leadingSpace.widthAnchor.constraint(equalTo: trailingSpace.widthAnchor).isActive = true
        let stack = NSStackView(views: [title, subtitle, rows, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            rows.widthAnchor.constraint(equalToConstant: 512)
        ])
        window.contentView = content
        window.isReleasedWhenClosed = false
        if let screen = item.button?.window?.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                          y: visible.midY - frame.height / 2))
        } else {
            window.center()
        }
        modeCenterWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func modeCenterPresetChanged(_ sender: NSButton) {
        let item = NSMenuItem(title: modeNames()[sender.tag], action: nil, keyEquivalent: "")
        item.tag = sender.tag
        presetChanged(item)
    }

    @objc private func saveCurrentMode() {
        guard let brightness = lamp.currentBrightness,
              let temperature = lamp.currentTemperature else {
            log("尚未获取灯具状态，无法保存模式")
            return
        }
        let alert = NSAlert()
        alert.messageText = "保存新模式"
        alert.informativeText = "记录当前亮度、色温和视频模式。"
        let field = NSTextField(string: "我的模式")
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let mode = SavedMode(name: field.stringValue.isEmpty ? "我的模式" : field.stringValue,
                             brightness: brightness,
                             temperature: temperature,
                             videoMode: lamp.isVideoModeEnabled == true)
        if let data = try? JSONEncoder().encode(mode) {
            UserDefaults.standard.set(data, forKey: "savedCustomMode")
            modeButton.title = mode.name
            log("已保存模式：\(mode.name)")
            modeCenterWindow?.close()
            modeCenterWindow = nil
        }
    }

    @objc private func bindCurrentModeToApp() {
        guard let brightness = lamp.currentBrightness,
              let temperature = lamp.currentTemperature else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要绑定的应用"
        panel.prompt = "绑定"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let mode = SavedMode(name: url.deletingPathExtension().lastPathComponent,
                             brightness: brightness,
                             temperature: temperature,
                             videoMode: lamp.isVideoModeEnabled == true)
        var mappings = loadAppModes()
        mappings[bundleID] = mode
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: "appModes")
            bindAppButton.title = "已绑定 \(mode.name)"
            log("已绑定应用模式：\(mode.name)")
        }
    }

    func applyModeForFrontmostAppIfNeeded() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              bundleID != lastFrontmostBundleID else { return }
        lastFrontmostBundleID = bundleID
        guard let mode = loadAppModes()[bundleID] else { return }
        _ = lamp.setPower(on: true)
        _ = lamp.setBrightness(mode.brightness)
        _ = lamp.setTemperature(mode.temperature)
        _ = lamp.setVideoMode(enabled: mode.videoMode)
        log("已应用应用模式：\(mode.name)")
    }

    private func loadAppModes() -> [String: SavedMode] {
        guard let data = UserDefaults.standard.data(forKey: "appModes") else { return [:] }
        return (try? JSONDecoder().decode([String: SavedMode].self, from: data)) ?? [:]
    }

    @objc private func brightnessFollowChanged() {
        let requested = brightnessFollowSwitch.state == .on
        if requested, lamp.isAutoLightEnabled == true {
            guard lamp.setAutoLight(enabled: false) else {
                brightnessFollowSwitch.state = .off
                log("关闭自动感光失败，未开启 Studio Display 亮度跟随")
                return
            }
            autoLightSwitch.state = .off
            autoLightChangePendingUntil = Date().addingTimeInterval(1)
            pendingAutoLightState = false
            lamp.requestStatus()
            log("已关闭自动感光，改用 Studio Display 亮度跟随")
        }
        isBrightnessFollowEnabled = requested
        UserDefaults.standard.set(isBrightnessFollowEnabled, forKey: "brightnessFollowEnabled")
        update(isAsleep: isAsleep, healthy: isHealthy)
        log(isBrightnessFollowEnabled ? "已开启 Studio Display 亮度跟随" : "已关闭 Studio Display 亮度跟随")
    }

    @objc private func powerSyncChanged() {
        isPowerSyncEnabled = powerSyncSwitch.state == .on
        UserDefaults.standard.set(isPowerSyncEnabled, forKey: "powerSyncEnabled")
        update(isAsleep: isAsleep, healthy: isHealthy)
        log(isPowerSyncEnabled ? "已开启熄屏电源同步" : "已关闭熄屏电源同步")
    }

    private func migrateDisplayPresetIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: "rotationPreset") == nil else { return }
        if let old = UserDefaults(suiteName: "local.qiu.builtin-display-rotation"),
           old.bool(forKey: "DisplayPresetSaved") {
            let preset = DisplayPreset(name: "我的旋转预设",
                                       builtinEnabled: old.bool(forKey: "DisplayPresetBuiltinEnabled"),
                                       rotation: old.integer(forKey: "DisplayPresetRotation"),
                                       builtinPrimary: old.bool(forKey: "DisplayPresetBuiltinPrimary"))
            saveRotationPreset(preset)
            return
        }
        saveRotationPreset(DisplayPreset(name: "竖屏双屏", builtinEnabled: true, rotation: 90, builtinPrimary: false))
    }

    private func saveRotationPreset(_ preset: DisplayPreset) {
        if let data = try? JSONEncoder().encode(preset) {
            UserDefaults.standard.set(data, forKey: "rotationPreset")
            rotationModeButton.title = preset.name
        }
    }

    private func loadRotationPreset() -> DisplayPreset {
        if let data = UserDefaults.standard.data(forKey: "rotationPreset"),
           let preset = try? JSONDecoder().decode(DisplayPreset.self, from: data) { return preset }
        return DisplayPreset(name: "竖屏双屏", builtinEnabled: true, rotation: 90, builtinPrimary: false)
    }

    private func saveDisplayBaselineIfNeeded() {
        guard UserDefaults.standard.data(forKey: "displayAutoBaseline") == nil,
              let baseline = displayController.currentPreset(name: "自动启用前") else { return }
        if let data = try? JSONEncoder().encode(baseline) {
            UserDefaults.standard.set(data, forKey: "displayAutoBaseline")
        }
    }

    private func restoreDisplayBaseline(clear: Bool) {
        guard let data = UserDefaults.standard.data(forKey: "displayAutoBaseline"),
              let baseline = try? JSONDecoder().decode(DisplayPreset.self, from: data) else {
            _ = displayController.enableBuiltin(); return
        }
        _ = displayController.apply(baseline)
        if clear { UserDefaults.standard.removeObject(forKey: "displayAutoBaseline") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc private func displayPowerChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else {
            refreshControls()
            return
        }
        let requested = displayPowerSwitch.state == .on
        let success = requested ? displayController.enableBuiltin() : displayController.disableBuiltin()
        if success {
            isBuiltinManuallyDisabled = !requested
        } else {
            displayPowerSwitch.state = requested ? .off : .on
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc private func displaySessionBecameUnsafe() {
        isDisplaySessionSafe = false
        pendingDisplayPolicyWorkItem?.cancel()
        pendingDisplayPolicyWorkItem = nil
        log("锁屏或显示器休眠，已暂停内屏配置写入")
    }

    @objc private func displaySessionBecameActive() {
        scheduleDisplaySessionActivation()
    }

    private func scheduleDisplaySessionActivation() {
        isDisplaySessionSafe = false
        pendingDisplayPolicyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isDisplaySessionSafe = true
            let pendingState = self.pendingDisplayConnectionState
            self.pendingDisplayConnectionState = nil
            if let pendingState {
                self.scheduleDisplayPolicy(forExternalConnection: pendingState)
            }
            self.refreshControls()
            log("显示会话已稳定，恢复内屏手动控制")
        }
        pendingDisplayPolicyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func scheduleDisplayPolicy(forExternalConnection connected: Bool) {
        pendingDisplayPolicyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isDisplaySessionSafe, !isConsoleSessionLocked() else { return }
            let externalStillConnected = studioDisplayID() != nil
            guard externalStillConnected == connected else { return }
            if connected {
                if self.isDisplayAutoPresetEnabled {
                    self.saveDisplayBaselineIfNeeded()
                    _ = self.displayController.apply(self.automaticRotationPreset())
                } else if !self.isBuiltinManuallyDisabled {
                    _ = self.displayController.enableBuiltin()
                }
            } else {
                self.isBuiltinManuallyDisabled = false
                _ = self.displayController.restoreBuiltinDefault()
            }
            self.refreshControls()
        }
        pendingDisplayPolicyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func automaticRotationPreset() -> DisplayPreset {
        var preset = loadRotationPreset()
        preset.builtinEnabled = !isBuiltinManuallyDisabled
        return preset
    }

    @objc private func displayRotationChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else { return }
        guard let builtin = displayController.builtinDisplay(), CGDisplayIsOnline(builtin) != 0 else { return }
        let current = Int(CGDisplayRotation(builtin).rounded())
        let next = current == 0 ? 90 : (current == 90 ? 270 : 0)
        _ = displayController.rotateBuiltin(to: next)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc private func displayAutoPresetChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else {
            refreshControls()
            return
        }
        isDisplayAutoPresetEnabled = displayAutoPresetSwitch.state == .on
        UserDefaults.standard.set(isDisplayAutoPresetEnabled, forKey: "displayAutoPresetEnabled")
        if isDisplayAutoPresetEnabled {
            saveDisplayBaselineIfNeeded()
            if !displayController.externalDisplays().isEmpty { _ = displayController.apply(automaticRotationPreset()) }
        } else {
            restoreDisplayBaseline(clear: true)
        }
        refreshControls()
    }

    @objc private func showRotationModeMenu() {
        let menu = NSMenu()
        let preset = loadRotationPreset()
        let apply = NSMenuItem(title: "应用“\(preset.name)”", action: #selector(applyRotationPreset), keyEquivalent: "")
        apply.target = self; menu.addItem(apply)
        let save = NSMenuItem(title: "保存当前为旋转预设…", action: #selector(saveCurrentRotationPreset), keyEquivalent: "")
        save.target = self; menu.addItem(save)
        menu.addItem(.separator())
        let automatic = NSMenuItem(title: "连接 Studio Display 时自动启用", action: #selector(toggleRotationPresetAutomation), keyEquivalent: "")
        automatic.target = self; automatic.state = isDisplayAutoPresetEnabled ? .on : .off
        menu.addItem(automatic)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: rotationModeButton.bounds.height + 4), in: rotationModeButton)
    }

    @objc private func applyRotationPreset() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else { return }
        if !displayController.apply(loadRotationPreset()) { log("应用旋转预设失败") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc private func saveCurrentRotationPreset() {
        guard let current = displayController.currentPreset(name: "我的旋转预设") else { return }
        let alert = NSAlert()
        alert.messageText = "保存旋转预设"
        alert.informativeText = "记录内屏开关、旋转角度和主屏角色。"
        let field = NSTextField(string: loadRotationPreset().name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var preset = current
        preset.name = field.stringValue.isEmpty ? "我的旋转预设" : field.stringValue
        saveRotationPreset(preset)
        log("已保存旋转预设：\(preset.name)")
    }

    @objc private func toggleRotationPresetAutomation() {
        displayAutoPresetSwitch.state = isDisplayAutoPresetEnabled ? .off : .on
        displayAutoPresetChanged()
    }

    func handleStudioDisplayConnection(connected: Bool) {
        pendingDisplayConnectionState = connected
        guard isDisplaySessionSafe else { return }
        pendingDisplayConnectionState = nil
        scheduleDisplayPolicy(forExternalConnection: connected)
    }

    @objc private func applicationWillTerminate() {
        pendingDisplayPolicyWorkItem?.cancel()
    }

    private func configurePanel() {
        powerSwitch.target = self
        powerSwitch.action = #selector(powerChanged)
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        brightnessSlider.isContinuous = false
        temperatureSlider.target = self
        temperatureSlider.action = #selector(temperatureChanged)
        temperatureSlider.isContinuous = false
        temperatureSlider.numberOfTickMarks = 5
        temperatureSlider.tickMarkPosition = .below
        timeTemperatureSwitch.target = self
        timeTemperatureSwitch.action = #selector(timeTemperatureChanged)
        timeTemperatureSwitch.toolTip = "根据当前时间自动调整色温"
        autoLightSwitch.target = self
        autoLightSwitch.action = #selector(autoLightChanged)
        autoLightSwitch.toolTip = "使用官方 HID 切换指令开启或关闭自动感光"
        presenceSwitch.target = self
        presenceSwitch.action = #selector(presenceChanged)
        for seconds in presenceDelayOptions {
            let title = "\(seconds / 60) 分钟"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = seconds
            presenceDelayPopup.menu?.addItem(item)
        }
        presenceDelayPopup.target = self
        presenceDelayPopup.action = #selector(presenceDelayChanged)
        selectPresenceDelay(presenceDelaySeconds)
        for (title, value) in [("低", 0), ("中", 1), ("高", 2)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = value
            presenceSensitivityPopup.menu?.addItem(item)
        }
        presenceSensitivityPopup.selectItem(withTag: presenceSensitivity)
        presenceSensitivityPopup.target = self
        presenceSensitivityPopup.action = #selector(presenceSensitivityChanged)
        videoModeSwitch.target = self
        videoModeSwitch.action = #selector(videoModeChanged)
        modeButton.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)
        modeButton.imagePosition = .imageTrailing
        modeButton.alignment = .left
        modeButton.bezelStyle = .rounded
        modeButton.controlSize = .large
        modeButton.font = UIStyle.bodyFont
        modeButton.target = self
        modeButton.action = #selector(showModeMenu)
        bindAppButton.image = NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)
        bindAppButton.imagePosition = .imageLeading
        bindAppButton.bezelStyle = .roundRect
        bindAppButton.controlSize = .small
        bindAppButton.target = self
        bindAppButton.action = #selector(bindCurrentModeToApp)
        brightnessFollowSwitch.target = self
        brightnessFollowSwitch.action = #selector(brightnessFollowChanged)
        powerSyncSwitch.target = self
        powerSyncSwitch.action = #selector(powerSyncChanged)
        captureBrightButton.target = self
        captureBrightButton.action = #selector(captureBrightThreshold)
        captureBrightButton.setButtonType(.momentaryPushIn)
        captureBrightButton.toolTip = "点击后将当前环境值保存为明亮关灯点"
        captureDarkButton.target = self
        captureDarkButton.action = #selector(captureDarkThreshold)
        captureDarkButton.setButtonType(.momentaryPushIn)
        captureDarkButton.toolTip = "点击后将当前环境值保存为昏暗开灯点"
        ambientEnableSwitch.target = self
        ambientEnableSwitch.action = #selector(ambientEnableChanged)
        for label in [brightThresholdLabel, darkThresholdLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
        }
        ambientStatusLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        ambientStatusLabel.textColor = .secondaryLabelColor
        displayPowerSwitch.target = self
        displayPowerSwitch.action = #selector(displayPowerChanged)
        displayRotateButton.setButtonType(.momentaryPushIn)
        displayRotateButton.target = self
        displayRotateButton.action = #selector(displayRotationChanged)
        displayAutoPresetSwitch.target = self
        displayAutoPresetSwitch.action = #selector(displayAutoPresetChanged)
        rotationModeButton.title = loadRotationPreset().name
        rotationModeButton.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)
        rotationModeButton.imagePosition = .imageTrailing
        rotationModeButton.alignment = .left
        rotationModeButton.bezelStyle = .rounded
        rotationModeButton.controlSize = .large
        rotationModeButton.font = UIStyle.bodyFont
        rotationModeButton.target = self
        rotationModeButton.action = #selector(showRotationModeMenu)

        [brightnessSlider, temperatureSlider].forEach { $0.controlSize = .small }
        [presenceDelayPopup, presenceSensitivityPopup].forEach { $0.controlSize = .small }
        brightnessValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        brightnessValueLabel.textColor = .secondaryLabelColor
        temperatureValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        temperatureValueLabel.textColor = .secondaryLabelColor

        let title = NSTextField(labelWithString: "iScreenBar")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Studio Display 控制")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2

        let brightnessRow = sliderRow(symbol: "sun.max", title: "亮度", slider: brightnessSlider, valueLabel: brightnessValueLabel)
        let temperatureRow = sliderRow(symbol: "thermometer.medium", title: "色温", slider: temperatureSlider, valueLabel: temperatureValueLabel)
        let delayField = optionField(symbol: "clock", title: "离席时间", control: presenceDelayPopup)
        let sensitivityField = optionField(symbol: "gauge", title: "侦测灵敏度", control: presenceSensitivityPopup)
        let presenceOptions = NSStackView(views: [delayField, sensitivityField])
        presenceOptions.orientation = .horizontal
        presenceOptions.alignment = .top
        presenceOptions.spacing = 12
        delayField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        sensitivityField.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let featureTitle = sectionLabel("快捷控制")
        let featureGrid = NSGridView(views: [
            [powerSwitch, autoLightSwitch, presenceSwitch],
            [videoModeSwitch, brightnessFollowSwitch, powerSyncSwitch],
            [timeTemperatureSwitch, NSView(), NSView()]
        ])
        featureGrid.rowSpacing = 6
        featureGrid.columnSpacing = 6
        featureGrid.xPlacement = .fill
        for button in [powerSwitch, autoLightSwitch, presenceSwitch, videoModeSwitch, brightnessFollowSwitch, powerSyncSwitch, timeTemperatureSwitch] {
            button.widthAnchor.constraint(equalToConstant: 100).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        let featureContainer = NSStackView(views: [featureTitle, featureGrid])
        featureContainer.orientation = .vertical
        featureContainer.alignment = .leading
        featureContainer.spacing = UIStyle.sectionSpacing

        let adjustmentTitle = sectionLabel("灯光调节")
        let adjustmentContainer = NSStackView(views: [adjustmentTitle, brightnessRow, temperatureRow])
        adjustmentContainer.orientation = .vertical
        adjustmentContainer.alignment = .leading
        adjustmentContainer.spacing = 8

        let presetTitle = sectionLabel("灯光预设")
        modeButton.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        modeButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let rotationPresetTitle = sectionLabel("旋转预设")
        rotationModeButton.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        rotationModeButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let presetContainer = NSStackView(views: [presetTitle, modeButton, rotationPresetTitle, rotationModeButton])
        presetContainer.orientation = .vertical
        presetContainer.alignment = .leading
        presetContainer.spacing = UIStyle.sectionSpacing

        let presenceTitle = sectionLabel("入座检测设置")
        let presenceContainer = NSStackView(views: [presenceTitle, presenceOptions])
        presenceContainer.orientation = .vertical
        presenceContainer.alignment = .leading
        presenceContainer.spacing = UIStyle.sectionSpacing

        let ambientTitle = sectionLabel("环境光标定")
        let ambientEnableLabel = NSTextField(labelWithString: "启用")
        ambientEnableLabel.font = UIStyle.bodyFont
        ambientEnableLabel.textColor = .secondaryLabelColor
        let ambientHeader = NSStackView(views: [ambientTitle, flexibleSpace(), ambientEnableLabel, ambientEnableSwitch])
        ambientHeader.orientation = .horizontal
        ambientHeader.alignment = .centerY
        ambientHeader.spacing = 6
        ambientHeader.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        for button in [captureBrightButton, captureDarkButton] {
            button.widthAnchor.constraint(equalToConstant: 106).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        for label in [brightThresholdLabel, darkThresholdLabel] {
            label.widthAnchor.constraint(equalToConstant: 34).isActive = true
        }
        let brightCapture = NSStackView(views: [captureBrightButton, brightThresholdLabel])
        brightCapture.orientation = .horizontal
        brightCapture.alignment = .centerY
        brightCapture.spacing = 4
        let darkCapture = NSStackView(views: [captureDarkButton, darkThresholdLabel])
        darkCapture.orientation = .horizontal
        darkCapture.alignment = .centerY
        darkCapture.spacing = 4
        let ambientActions = NSStackView(views: [brightCapture, darkCapture])
        ambientActions.orientation = .horizontal
        ambientActions.alignment = .centerY
        ambientActions.spacing = 12
        ambientActions.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        ambientStatusLabel.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        let ambientContainer = NSStackView(views: [ambientHeader, ambientActions, ambientStatusLabel])
        ambientContainer.orientation = .vertical
        ambientContainer.alignment = .leading
        ambientContainer.spacing = 6

        let displayGrid = NSGridView(views: [[displayPowerSwitch, displayRotateButton]])
        displayGrid.rowSpacing = 0
        displayGrid.columnSpacing = 6
        displayGrid.xPlacement = .fill
        for button in [displayPowerSwitch, displayRotateButton] {
            button.widthAnchor.constraint(equalToConstant: 153).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        let displayTitle = sectionLabel("内屏与旋转")
        let displayContainer = NSStackView(views: [displayTitle, displayGrid])
        displayContainer.orientation = .vertical
        displayContainer.alignment = .leading
        displayContainer.spacing = UIStyle.sectionSpacing

        let autoPresetLabel = NSTextField(labelWithString: "启用预设")
        autoPresetLabel.font = UIStyle.bodyFont
        autoPresetLabel.textColor = .secondaryLabelColor
        let rotationPresetHeader = NSStackView(views: [rotationPresetTitle, flexibleSpace(), autoPresetLabel, displayAutoPresetSwitch])
        rotationPresetHeader.orientation = .horizontal
        rotationPresetHeader.alignment = .centerY
        rotationPresetHeader.spacing = 6
        rotationPresetHeader.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        presetContainer.setViews([presetTitle, modeButton, rotationPresetHeader, rotationModeButton], in: .top)

        let stack = NSStackView(views: [header, separator(), featureContainer, separator(), adjustmentContainer,
                                       separator(), ambientContainer, separator(), presenceContainer, separator(), displayContainer,
                                       separator(), presetContainer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: UIStyle.outerInset, bottom: 14, right: UIStyle.outerInset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [brightnessRow, temperatureRow, presenceOptions] {
            view.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        }

        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: UIStyle.panelWidth, height: 580))
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: controller.view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: controller.view.bottomAnchor)
        ])
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: UIStyle.panelWidth, height: 580)
        popover.behavior = .transient
    }

    private func sliderRow(symbol: String, title: String, slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        let label = rowLabel(title)
        label.widthAnchor.constraint(equalToConstant: 32).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 184).isActive = true
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let row = NSStackView(views: [symbolView(symbol), label, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func optionField(symbol: String, title: String, control: NSView) -> NSStackView {
        let heading = NSStackView(views: [symbolView(symbol), rowLabel(title)])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 6
        let field = NSStackView(views: [heading, control])
        field.orientation = .vertical
        field.alignment = .leading
        field.spacing = 5
        control.widthAnchor.constraint(equalToConstant: 150).isActive = true
        return field
    }

    private func optionsRow(symbol: String, title: String, controls: [NSView]) -> NSStackView {
        let row = NSStackView(views: [symbolView(symbol), rowLabel(title), flexibleSpace()] + controls)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func symbolView(_ name: String) -> NSImageView {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = .secondaryLabelColor
        view.symbolConfiguration = .init(pointSize: UIStyle.iconSize, weight: .regular)
        view.widthAnchor.constraint(equalToConstant: 18).isActive = true
        view.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    private func rowLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = UIStyle.bodyFont
        return label
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = UIStyle.captionFont
        label.textColor = .secondaryLabelColor
        return label
    }

    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private func separator() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        divider.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        return divider
    }

    private func refreshControls() {
        let displayControlsAllowed = isDisplaySessionSafe && !isConsoleSessionLocked()
        powerSwitch.state = lamp.isPowerOn == true ? .on : .off
        let autoLightChangePending = autoLightChangePendingUntil.map { Date() < $0 } ?? false
        if autoLightChangePending, let pendingAutoLightState {
            autoLightSwitch.state = pendingAutoLightState ? .on : .off
            autoLightSwitch.toolTip = pendingAutoLightState ? "正在开启自动感光" : "正在关闭自动感光"
        } else if lamp.isAutoLightEnabled == true {
            autoLightChangePendingUntil = nil
            pendingAutoLightState = nil
            autoLightSwitch.state = .on
            autoLightSwitch.toolTip = "关闭自动感光"
        } else {
            autoLightChangePendingUntil = nil
            pendingAutoLightState = nil
            autoLightSwitch.state = .off
            autoLightSwitch.toolTip = "开启自动感光"
        }
        if isAmbientPresenceLockActive {
            presenceSwitch.title = presenceWasEnabledBeforeAmbientLock ? "入座暂停" : "入座检测"
            presenceSwitch.state = presenceWasEnabledBeforeAmbientLock ? .on : .off
            presenceSwitch.toolTip = presenceWasEnabledBeforeAmbientLock
                ? "原设置已开启；环境关灯锁定期间临时暂停，解除后自动恢复"
                : "环境关灯锁定期间不可开启入座检测"
        } else {
            presenceSwitch.title = "入座检测"
            presenceSwitch.state = lamp.isPresenceDetectionEnabled == true ? .on : .off
            presenceSwitch.toolTip = "开启或关闭灯体入座检测"
        }
        videoModeSwitch.state = lamp.isVideoModeEnabled == true ? .on : .off
        brightnessFollowSwitch.state = isBrightnessFollowEnabled ? .on : .off
        powerSyncSwitch.state = isPowerSyncEnabled ? .on : .off
        timeTemperatureSwitch.state = isTimeTemperatureEnabled ? .on : .off
        updateAmbientStatusLabel()
        if let builtin = displayController.builtinDisplay() {
            let online = CGDisplayIsOnline(builtin) != 0
            displayPowerSwitch.state = online ? .on : .off
            displayPowerSwitch.isEnabled = displayControlsAllowed && displayController.isAvailable
            displayRotateButton.isEnabled = displayControlsAllowed && online && displayController.isAvailable
            rotationModeButton.isEnabled = displayControlsAllowed && online && displayController.isAvailable
            displayRotateButton.title = online ? "旋转 \(Int(CGDisplayRotation(builtin).rounded()))°" : "旋转 —"
        } else {
            displayPowerSwitch.state = .off
            displayPowerSwitch.isEnabled = false
            displayRotateButton.isEnabled = false
            rotationModeButton.isEnabled = false
            displayRotateButton.title = "旋转 —"
        }
        displayAutoPresetSwitch.state = isDisplayAutoPresetEnabled ? .on : .off
        displayAutoPresetSwitch.isEnabled = displayControlsAllowed && displayController.isAvailable && displayController.builtinDisplay() != nil
        rotationModeButton.title = loadRotationPreset().name
        selectPresenceDelay(presenceDelaySeconds)
        presenceSensitivityPopup.selectItem(withTag: presenceSensitivity)
        if let brightness = lamp.currentBrightness {
            brightnessSlider.doubleValue = Double(brightness)
            brightnessValueLabel.stringValue = "\(brightness)%"
        }
        if let temperature = lamp.currentTemperature {
            temperatureSlider.doubleValue = Double(temperature)
            temperatureValueLabel.stringValue = "\(temperature)K"
        }
        let enabled = lamp.isConnected
        powerSwitch.isEnabled = enabled
        autoLightSwitch.isEnabled = enabled
        brightnessSlider.isEnabled = enabled
        temperatureSlider.isEnabled = enabled && !isTimeTemperatureEnabled
        timeTemperatureSwitch.isEnabled = enabled
        presenceSwitch.isEnabled = enabled && !isAmbientPresenceLockActive
        videoModeSwitch.isEnabled = enabled
        powerSyncSwitch.isEnabled = enabled
        captureBrightButton.isEnabled = currentDisplayAmbientProxy != nil
        captureDarkButton.isEnabled = currentDisplayAmbientProxy != nil
        presenceDelayPopup.isEnabled = enabled
        presenceSensitivityPopup.isEnabled = enabled
    }

    private func updateIcon(healthy: Bool) {
        let iconColor: NSColor
        if !healthy {
            iconColor = .systemRed
        } else if lamp.isPowerOn == true {
            iconColor = .systemYellow
        } else {
            iconColor = .systemGray
        }
        let configuration = NSImage.SymbolConfiguration(paletteColors: [iconColor])
        let symbol = NSImage(systemSymbolName: "sun.min.fill", accessibilityDescription: "iScreenBar 状态")?
            .withSymbolConfiguration(configuration)
        symbol?.isTemplate = false
        item.button?.attributedTitle = NSAttributedString(string: "")
        item.button?.image = symbol
    }

    private func selectPresenceDelay(_ seconds: Int) {
        if let item = presenceDelayPopup.menu?.item(withTag: seconds) {
            presenceDelayPopup.select(item)
            return
        }
        if let fallback = presenceDelayPopup.itemArray.first(where: { $0.tag == 180 }) {
            presenceDelayPopup.select(fallback)
        }
    }

    private func selectedPresenceDelaySeconds() -> Int {
        return presenceDelayPopup.selectedItem?.tag ?? presenceDelaySeconds
    }

}

private final class LampController {
    private var manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private(set) var currentBrightness: Int?
    private(set) var currentTemperature: Int?
    private(set) var isPowerOn: Bool?
    private(set) var isAutoLightEnabled: Bool?
    private(set) var isPresenceDetectionEnabled: Bool?
    private(set) var isVideoModeEnabled: Bool?
    private(set) var statusRevision = 0
    private var lastTemperatureValues: (Int, Int)?
    private var lastStatusHex: String?

    var isConnected: Bool { device != nil }

    init() {
        manager = Self.makeManager()
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            log("无法打开 iScreenBar USB HID 设备")
            return
        }
        guard attachFirstDevice() else {
            log("未检测到 iScreenBar USB HID 设备，等待重新连接")
            return
        }
        _ = requestStatus()
    }

    deinit {
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        inputBuffer.deallocate()
    }

    func setPower(on: Bool) -> Bool {
        if sendPowerReport(on: on) {
            isPowerOn = on
            log("灯已\(on ? "开启" : "关闭")")
            return true
        }

        log("USB HID 连接已失效，正在重新连接")
        guard reconnect(), sendPowerReport(on: on) else {
            log("USB HID 重连后指令仍失败")
            return false
        }

        isPowerOn = on
        log("重连成功，灯已\(on ? "开启" : "关闭")")
        return true
    }

    func setBrightness(_ brightness: Int) -> Bool {
        let value = UInt8(clamping: max(1, min(100, brightness)))
        guard sendCommand(0x04, payload: [value, value]) else { return false }
        currentBrightness = Int(value)
        log("灯亮度已调整为 \(brightness)%")
        return true
    }

    func setTemperature(_ temperature: Int) -> Bool {
        let value = max(2700, min(6500, temperature))
        let high = UInt8((value >> 8) & 0xFF)
        let low = UInt8(value & 0xFF)
        // iScreenBar 有主灯和背灯两组独立色温；两组都必须写入完整的 16 位 Kelvin 值。
        guard sendCommand(0x03, payload: [high, low, high, low]) else { return false }
        currentTemperature = value
        log("灯色温已调整为 \(value)K（主灯与背灯同步）")
        return true
    }

    func setAutoLight(enabled: Bool) -> Bool {
        if isAutoLightEnabled == enabled {
            return true
        }
        if enabled {
            // 官方 App 用 01 F0 01 04 F5 进入自动感光。
            guard sendCommand(0x01, payload: []) else { return false }
        } else {
            // 灯具固件不会用同一指令退出自动感光；官方控制逻辑通过写入手动亮度退出。
            guard let brightness = currentBrightness else {
                log("尚未获取当前亮度，无法关闭自动感光")
                return false
            }
            guard setBrightness(brightness) else { return false }
        }
        isAutoLightEnabled = enabled
        log(enabled ? "已开启自动感光" : "已关闭自动感光")
        return true
    }

    func setPresenceDetection(enabled: Bool, delaySeconds: Int, sensitivity: Int) -> Bool {
        let basePayload = [UInt8(enabled ? 1 : 0)]
        let delayMinutes = UInt8(clamping: delaySeconds / 60)
        let sensitivityValue = UInt8(clamping: max(0, min(2, sensitivity)))
        if !sendCommand(0x06, payload: basePayload + [delayMinutes, sensitivityValue]) {
            if !sendCommand(0x06, payload: basePayload) {
                return false
            }
            log("入座检测时间参数发送失败，已回退为仅开关命令")
        }
        isPresenceDetectionEnabled = enabled
        presenceDetectionDelaySeconds = delaySeconds
        log(enabled ? "已开启入座检测" : "已关闭入座检测")
        return true
    }

    private(set) var presenceDetectionDelaySeconds: Int?

    func setVideoMode(enabled: Bool) -> Bool {
        guard sendCommand(0x09, payload: [enabled ? 1 : 0]) else { return false }
        isVideoModeEnabled = enabled
        log(enabled ? "已开启视频模式" : "已关闭视频模式")
        return true
    }

    @discardableResult
    func requestStatus() -> Bool {
        var report = [UInt8](repeating: 0, count: 33)
        report[0] = 0x01
        report[1] = 0xF0
        report[2] = 0x20
        report[3] = 0x04
        report[4] = 0x14
        return send(report)
    }

    func checkConnection() -> Bool {
        if requestStatus() { return true }
        guard reconnect(), requestStatus() else { return false }
        log("USB HID 已重新连接")
        return true
    }

    private func sendPowerReport(on: Bool) -> Bool {
        var report = [UInt8](repeating: 0, count: 33)
        report[0] = 0x01
        report[1] = 0xF0
        report[2] = 0x07
        report[3] = 0x05
        report[4] = on ? 0xFD : 0xFC
        report[5] = on ? 0x01 : 0x00
        return send(report)
    }

    private func sendCommand(_ command: UInt8, payload: [UInt8]) -> Bool {
        var report = [UInt8](repeating: 0, count: 33)
        report[0] = 0x01
        report[1] = 0xF0
        report[2] = command
        report[3] = UInt8(payload.count + 4)
        report[4] = UInt8(truncatingIfNeeded: Int(report[1]) + Int(command) + Int(report[3]) + payload.reduce(0) { $0 + Int($1) })
        for (index, value) in payload.enumerated() {
            report[5 + index] = value
        }
        return send(report)
    }

    private func send(_ report: [UInt8]) -> Bool {
        guard let device else { return false }
        let result = report.withUnsafeBytes { bytes in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 1,
                                 bytes.bindMemory(to: UInt8.self).baseAddress!, report.count)
        }
        if result != kIOReturnSuccess {
            log(String(format: "USB HID 指令失败：0x%08X", result))
        }
        return result == kIOReturnSuccess
    }

    private func configureInputCallback(for device: IOHIDDevice) {
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(
            device, inputBuffer, 64,
            { context, _, _, _, _, report, reportLength in
                guard let context, reportLength >= 5 else { return }
                let controller = Unmanaged<LampController>.fromOpaque(context).takeUnretainedValue()
                if report[0] == 0x02, report[1] == 0xE1, report[2] == 0x20,
                   report[3] == 0x0D, reportLength >= 15 {
                    let statusHex = (0..<reportLength).map { String(format: "%02X", report[$0]) }.joined(separator: " ")
                    if controller.lastStatusHex != statusHex {
                        controller.lastStatusHex = statusHex
                        log("状态原始报文：\(statusHex)")
                    }
                    controller.isPowerOn = (report[6] & 0x01) != 0
                    controller.isAutoLightEnabled = (report[6] & 0x04) != 0
                    controller.isPresenceDetectionEnabled = (report[6] & 0x20) != 0
                    controller.isVideoModeEnabled = (report[6] & 0x80) != 0
                    let mainTemperature = (Int(report[8]) << 8) | Int(report[9])
                    let backTemperature = (Int(report[11]) << 8) | Int(report[12])
                    if controller.lastTemperatureValues?.0 != mainTemperature ||
                        controller.lastTemperatureValues?.1 != backTemperature {
                        controller.lastTemperatureValues = (mainTemperature, backTemperature)
                        log("色温回读：主灯=\(mainTemperature)K，背灯=\(backTemperature)K")
                    }
                    controller.currentTemperature = mainTemperature
                    controller.currentBrightness = Int(report[10])
                    controller.statusRevision += 1
                }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func reconnect() -> Bool {
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        device = nil
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = Self.makeManager()
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return false }
        return attachFirstDevice()
    }

    private static func makeManager() -> IOHIDManager {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: benqVendorID,
            kIOHIDProductIDKey as String: iScreenBarProductID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        return manager
    }

    private func attachFirstDevice() -> Bool {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let first = devices.first else { return false }
        device = first
        configureInputCallback(for: first)
        return true
    }
}

private final class DisplayBrightnessReader {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let handle: UnsafeMutableRawPointer?
    private let getter: GetBrightness?

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getter = unsafeBitCast(symbol, to: GetBrightness.self)
        } else {
            getter = nil
        }
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func percent(for displayID: CGDirectDisplayID) -> Int? {
        guard let getter else { return nil }
        var value: Float = 0
        guard getter(displayID, &value) == 0 else { return nil }
        return Int((max(0, min(1, value)) * 100).rounded())
    }
}

private final class StudioDisplayAmbientSensor {
    private var manager: IOHIDManager
    private var device: IOHIDDevice?
    private var illuminanceElement: IOHIDElement?
    private var lastReconnectAttempt = Date.distantPast

    init() {
        manager = Self.makeManager()
        guard openManager() else {
            log("无法打开 Studio Display 环境光传感器")
            return
        }
        _ = attachSensor()
    }

    deinit {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func rawIlluminance() -> Int? {
        if device == nil || illuminanceElement == nil,
           !attachSensor(),
           !reconnectIfNeeded() {
            return nil
        }
        if let value = readCurrentValue() { return value }

        // Studio Display 在锁屏、睡眠或显示器重新排列后会重建 HID 服务。
        // 旧 IOHIDDevice 对象仍可能存在，但 GetValue 会持续失败，必须重建 manager。
        device = nil
        illuminanceElement = nil
        guard reconnectIfNeeded() else { return nil }
        return readCurrentValue()
    }

    private static func makeManager() -> IOHIDManager {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x1118,
            kIOHIDPrimaryUsagePageKey as String: 0x20,
            kIOHIDPrimaryUsageKey as String: 0x41
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        return manager
    }

    private func openManager() -> Bool {
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
    }

    private func readCurrentValue() -> Int? {
        guard let device, let illuminanceElement else { return nil }
        var rawValue: Unmanaged<IOHIDValue> = .fromOpaque(UnsafeRawPointer(bitPattern: 1)!)
        guard IOHIDDeviceGetValue(device, illuminanceElement, &rawValue) == kIOReturnSuccess else {
            return nil
        }
        let raw = IOHIDValueGetIntegerValue(rawValue.takeUnretainedValue())
        // Studio Display 以约千分之一照度单位回传；转换为易读的相对环境分数。
        return max(0, raw / 1_000)
    }

    private func reconnectIfNeeded() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastReconnectAttempt) >= 2 else { return false }
        lastReconnectAttempt = now
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = Self.makeManager()
        guard openManager(), attachSensor() else { return false }
        log("Studio Display 环境光传感器已重新连接")
        return true
    }

    private func attachSensor() -> Bool {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else { return false }
        let elements = (IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
        guard let element = elements.first(where: {
            IOHIDElementGetUsagePage($0) == 0x20 && IOHIDElementGetUsage($0) == 0x04D1
        }) else { return false }
        self.device = device
        illuminanceElement = element
        return true
    }
}

private func studioDisplayID() -> CGDirectDisplayID? {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
    return displays.prefix(Int(count))
        .filter { CGDisplayIsBuiltin($0) == 0 }
        .max { CGDisplayPixelsWide($0) < CGDisplayPixelsWide($1) }
}

private func isConsoleSessionLocked() -> Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
}

var displayID = studioDisplayID()
private let lamp = LampController()
private let displayBrightnessReader = DisplayBrightnessReader()
private let studioAmbientSensor = StudioDisplayAmbientSensor()

if let displayID {
    log("开始监听 Studio Display ID=\(displayID)，分辨率=\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))")
} else {
    log("未找到外接显示器，程序保持运行并等待 Studio Display 连接")
}
var wasAsleep = displayID.map { CGDisplayIsAsleep($0) != 0 } ?? false
var helperTurnedLampOff = false
var ambientTurnedLampOff = UserDefaults.standard.bool(forKey: "ambientLampLockActive")
var ambientCloseCandidateSince: Date?
var ambientOpenCandidateSince: Date?
var ambientProxySamples: [(Date, Int)] = []
var ambientProxySourceName: String?
var lastLoggedAmbientProxy: Int?

private func setAmbientLampLock(_ active: Bool) {
    ambientTurnedLampOff = active
    if active {
        UserDefaults.standard.set(true, forKey: "ambientLampLockActive")
    } else {
        UserDefaults.standard.removeObject(forKey: "ambientLampLockActive")
    }
}
private let statusIndicator = StatusIndicator(isAsleep: wasAsleep, lamp: lamp)
statusIndicator.handleStudioDisplayConnection(connected: displayID != nil)
var wasBrightnessFollowEnabled = statusIndicator.isBrightnessFollowEnabled
var wasPowerSyncEnabled = statusIndicator.isPowerSyncEnabled
var wasAmbientLinkEnabled = statusIndicator.isAmbientLinkEnabled
var wasAmbientCloseThreshold = statusIndicator.ambientCloseThreshold
var brightnessOffset: Int?
var anchorStatusRevision: Int?
var lastDisplayBrightness: Int?
var lastStatusRequest = Date.distantPast
var wasLampConnected = lamp.isConnected
if !wasAmbientLinkEnabled, ambientTurnedLampOff || statusIndicator.hasPendingAmbientPresenceRestore {
    if ambientTurnedLampOff, !wasAsleep { _ = lamp.setPower(on: true) }
    setAmbientLampLock(false)
    statusIndicator.restorePresenceAfterAmbientLock()
    log("已清理上次环境规则遗留的关灯与入座暂停状态")
}
if wasBrightnessFollowEnabled {
    anchorStatusRevision = lamp.statusRevision
    lamp.requestStatus()
    log("Studio Display 亮度跟随已开启，正在锁定当前亮度差")
}

private func pollDisplayAndLamp() {
    statusIndicator.applyModeForFrontmostAppIfNeeded()
    let detectedDisplayID = studioDisplayID()
    if detectedDisplayID != displayID {
        displayID = detectedDisplayID
        brightnessOffset = nil
        lastDisplayBrightness = nil
        anchorStatusRevision = nil
        if let displayID {
            wasAsleep = CGDisplayIsAsleep(displayID) != 0
            log("检测到 Studio Display 已连接：ID=\(displayID)，分辨率=\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))")
        } else {
            wasAsleep = false
            log("Studio Display 已断开，程序继续驻留等待重连")
        }
        statusIndicator.handleStudioDisplayConnection(connected: displayID != nil)
    }
    let isAsleep = displayID.map { CGDisplayIsAsleep($0) != 0 } ?? false
    let brightnessFollowEnabled = statusIndicator.isBrightnessFollowEnabled
    let powerSyncEnabled = statusIndicator.isPowerSyncEnabled
    let ambientLinkEnabled = statusIndicator.isAmbientLinkEnabled
    let ambientCloseThreshold = statusIndicator.ambientCloseThreshold
    let rawAmbientSource = (value: studioAmbientSensor.rawIlluminance(), name: "Studio Display 光线传感器")
    if ambientProxySourceName != rawAmbientSource.name {
        ambientProxySamples.removeAll()
        ambientProxySourceName = rawAmbientSource.name
        lastLoggedAmbientProxy = nil
        log("环境响应数据源切换为 \(rawAmbientSource.name)")
    }
    let sampleTime = Date()
    if let value = rawAmbientSource.value {
        ambientProxySamples.append((sampleTime, value))
    }
    let sampleCutoff = sampleTime.addingTimeInterval(-10)
    ambientProxySamples.removeAll { $0.0 < sampleCutoff }
    let sortedAmbientValues = ambientProxySamples.map { $0.1 }.sorted()
    let displayAmbientProxy = sortedAmbientValues.isEmpty ? nil : sortedAmbientValues[sortedAmbientValues.count / 2]
    if let displayAmbientProxy, lastLoggedAmbientProxy != displayAmbientProxy {
        log("环境响应分数：\(displayAmbientProxy)（\(rawAmbientSource.name)，10 秒中位数）")
        lastLoggedAmbientProxy = displayAmbientProxy
    }
    statusIndicator.updateDisplayAmbientProxy(displayAmbientProxy, sourceName: rawAmbientSource.name)

    // 熄屏同步是最高优先级：屏幕熄灭期间，环境光、入座检测或灯体自身逻辑
    // 都不得重新点亮灯。持续检测可覆盖灯体在熄屏后中途自行亮起的情况。
    if powerSyncEnabled, isAsleep, lamp.isPowerOn == true {
        let turnedOff = lamp.setPower(on: false)
        helperTurnedLampOff = helperTurnedLampOff || turnedOff
        if turnedOff {
            log("熄屏同步优先级已压制灯体自动重新点亮")
        }
        statusIndicator.update(isAsleep: true, healthy: turnedOff)
    }

    if wasAmbientCloseThreshold != nil, ambientCloseThreshold == nil, ambientTurnedLampOff {
        if !isAsleep { _ = lamp.setPower(on: true) }
        setAmbientLampLock(false)
        statusIndicator.restorePresenceAfterAmbientLock()
        ambientCloseCandidateSince = nil
        log("明亮关灯规则已关闭，已解除关灯锁定并恢复入座检测")
    }
    wasAmbientCloseThreshold = ambientCloseThreshold

    if ambientLinkEnabled != wasAmbientLinkEnabled {
        ambientCloseCandidateSince = nil
        ambientOpenCandidateSince = nil
        if !ambientLinkEnabled, ambientTurnedLampOff {
            if !isAsleep { _ = lamp.setPower(on: true) }
            setAmbientLampLock(false)
            statusIndicator.restorePresenceAfterAmbientLock()
            log("环境联动已关闭，已释放环境关灯状态")
        }
        wasAmbientLinkEnabled = ambientLinkEnabled
    }

    if ambientLinkEnabled, !isAsleep, let displayAmbientProxy {
        if ambientTurnedLampOff {
            statusIndicator.maintainPresenceSuspendedForAmbientLock()
            ambientCloseCandidateSince = nil
            let reachedOpenPoint = statusIndicator.ambientOpenThreshold.map { displayAmbientProxy <= $0 } ?? false
            if reachedOpenPoint {
                if ambientOpenCandidateSince == nil { ambientOpenCandidateSince = Date() }
                if let since = ambientOpenCandidateSince, Date().timeIntervalSince(since) >= 15 {
                    if lamp.setPower(on: true) {
                        setAmbientLampLock(false)
                        ambientOpenCandidateSince = nil
                        statusIndicator.restorePresenceAfterAmbientLock()
                        log("环境已低于独立开灯点，已释放环境关灯锁定")
                    }
                } else if lamp.isPowerOn == true {
                    _ = lamp.setPower(on: false)
                }
            } else {
                ambientOpenCandidateSince = nil
                if lamp.isPowerOn == true, lamp.setPower(on: false) {
                    log("环境关灯优先级已压制灯体自动重新点亮")
                }
            }
        } else if lamp.isPowerOn == true {
            ambientOpenCandidateSince = nil
            if let closeThreshold = statusIndicator.ambientCloseThreshold,
               displayAmbientProxy >= closeThreshold {
                if ambientCloseCandidateSince == nil { ambientCloseCandidateSince = Date() }
                if let since = ambientCloseCandidateSince, Date().timeIntervalSince(since) >= 30 {
                    if statusIndicator.suspendPresenceForAmbientLock(), lamp.setPower(on: false) {
                        setAmbientLampLock(true)
                        ambientCloseCandidateSince = nil
                        log("环境已高于独立关灯点，已关闭 iScreenBar")
                    } else {
                        statusIndicator.restorePresenceAfterAmbientLock()
                    }
                }
            } else {
                ambientCloseCandidateSince = nil
            }
        } else {
            ambientCloseCandidateSince = nil
            if let closeThreshold = statusIndicator.ambientCloseThreshold,
               displayAmbientProxy >= closeThreshold {
                setAmbientLampLock(true)
                ambientOpenCandidateSince = nil
                _ = statusIndicator.suspendPresenceForAmbientLock()
                log("检测到灯已关闭且环境仍高于关灯点，已恢复关灯锁定")
            } else if let openThreshold = statusIndicator.ambientOpenThreshold,
               displayAmbientProxy <= openThreshold {
                if ambientOpenCandidateSince == nil { ambientOpenCandidateSince = Date() }
                if let since = ambientOpenCandidateSince, Date().timeIntervalSince(since) >= 15 {
                    if lamp.setPower(on: true) {
                        setAmbientLampLock(false)
                        ambientOpenCandidateSince = nil
                        log("环境已低于独立开灯点，已开启 iScreenBar")
                    }
                }
            } else {
                ambientOpenCandidateSince = nil
            }
        }
    } else {
        ambientCloseCandidateSince = nil
        ambientOpenCandidateSince = nil
    }

    if powerSyncEnabled != wasPowerSyncEnabled {
        if powerSyncEnabled, isAsleep {
            helperTurnedLampOff = lamp.setPower(on: false)
        } else if !powerSyncEnabled, helperTurnedLampOff {
            _ = lamp.setPower(on: true)
            helperTurnedLampOff = false
        }
        wasPowerSyncEnabled = powerSyncEnabled
        statusIndicator.update(isAsleep: isAsleep, healthy: true)
    }

    if brightnessFollowEnabled != wasBrightnessFollowEnabled {
        brightnessOffset = nil
        lastDisplayBrightness = nil
        if brightnessFollowEnabled {
            anchorStatusRevision = lamp.statusRevision
            lamp.requestStatus()
        } else {
            anchorStatusRevision = nil
        }
        wasBrightnessFollowEnabled = brightnessFollowEnabled
        statusIndicator.update(isAsleep: isAsleep, healthy: true)
    }

    if isAsleep != wasAsleep {
        if isAsleep {
            log("检测到 Studio Display 熄屏")
            if powerSyncEnabled {
                helperTurnedLampOff = lamp.setPower(on: false)
                statusIndicator.update(isAsleep: true, healthy: helperTurnedLampOff)
            } else {
                statusIndicator.update(isAsleep: true, healthy: true)
            }
        } else {
            log("检测到 Studio Display 唤醒")
            if helperTurnedLampOff, !ambientTurnedLampOff {
                let restored = lamp.setPower(on: true)
                statusIndicator.update(isAsleep: false, healthy: restored)
                helperTurnedLampOff = false
            } else {
                helperTurnedLampOff = false
                statusIndicator.update(isAsleep: false, healthy: true)
            }
        }
        wasAsleep = isAsleep
    }

    statusIndicator.applyScheduledTemperatureIfNeeded(isAsleep: isAsleep)

    if brightnessFollowEnabled, !isAsleep, let displayID,
       let displayBrightness = displayBrightnessReader.percent(for: displayID) {
        if let anchorRevision = anchorStatusRevision,
           lamp.statusRevision > anchorRevision,
           let lampBrightness = lamp.currentBrightness {
            if lamp.isAutoLightEnabled == true {
                log("检测到灯具自动感光仍在运行；亮度跟随将在关闭自动感光后生效")
                brightnessOffset = nil
                lastDisplayBrightness = displayBrightness
            } else {
                brightnessOffset = lampBrightness - displayBrightness
                lastDisplayBrightness = displayBrightness
                log("已锁定亮度差：iScreenBar \(lampBrightness)% / Studio Display \(displayBrightness)%")
            }
            anchorStatusRevision = nil
        } else if let brightnessOffset, displayBrightness != lastDisplayBrightness {
            let target = max(1, min(100, displayBrightness + brightnessOffset))
            if lamp.setBrightness(target) {
                lastDisplayBrightness = displayBrightness
            }
        }
    }

    if Date().timeIntervalSince(lastStatusRequest) >= 2 {
        let connected = lamp.checkConnection()
        if connected != wasLampConnected {
            if connected {
                log("检测到 iScreenBar 已恢复连接，正在恢复同步状态")
                if powerSyncEnabled {
                    if isAsleep {
                        helperTurnedLampOff = lamp.setPower(on: false)
                    } else if !ambientTurnedLampOff {
                        _ = lamp.setPower(on: true)
                    }
                }
                if brightnessFollowEnabled {
                    brightnessOffset = nil
                    lastDisplayBrightness = nil
                    anchorStatusRevision = lamp.statusRevision
                    lamp.requestStatus()
                }
            } else {
                log("检测到 iScreenBar 已断开")
                brightnessOffset = nil
                anchorStatusRevision = nil
            }
            wasLampConnected = connected
        }
        statusIndicator.update(isAsleep: isAsleep, healthy: connected && displayID != nil)
        lastStatusRequest = Date()
    }
}

let pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
    pollDisplayAndLamp()
}
pollingTimer.tolerance = 0.05
pollDisplayAndLamp()
NSApplication.shared.run()
