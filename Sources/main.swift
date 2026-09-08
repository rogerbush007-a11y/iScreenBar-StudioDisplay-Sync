import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit.hid

private let benqVendorID = 0x04A5
private let iScreenBarProductID = 0x2501
private let pollInterval: TimeInterval = 0.25

private func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    print("[\(formatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

private enum InterfaceLanguage {
    case simplifiedChinese
    case traditionalChinese
    case english

    /// Picks the interface language from the user's first preferred system language.
    static let current: InterfaceLanguage = {
        guard let identifier = Locale.preferredLanguages.first else { return .english }
        let language = Locale.Language(identifier: identifier)
        guard language.languageCode?.identifier == "zh" else { return .english }
        return language.maximalIdentifier.contains("Hant") ? .traditionalChinese : .simplifiedChinese
    }()
}

/// Returns the string matching the current interface language.
private func L(_ simplified: String, _ traditional: String, _ english: String) -> String {
    switch InterfaceLanguage.current {
    case .simplifiedChinese: return simplified
    case .traditionalChinese: return traditional
    case .english: return english
    }
}

private final class StatusIndicator: NSObject {
    private let item: NSStatusItem
    private let lamp: LampController
    private let popover = NSPopover()
    private let powerSwitch = NSButton(checkboxWithTitle: L("开灯", "開燈", "Lamp On"), target: nil, action: nil)
    private let brightnessSlider = NSSlider(value: 50, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let brightnessValueLabel = NSTextField(labelWithString: "50%")
    private let temperatureSlider = NSSlider(value: 5000, minValue: 2700, maxValue: 6500, target: nil, action: nil)
    private let temperatureValueLabel = NSTextField(labelWithString: "5000K")
    private let autoLightSwitch = NSButton(checkboxWithTitle: L("自动感光", "自動感光", "Auto Ambient Light"), target: nil, action: nil)
    private let brightnessFollowSwitch = NSButton(checkboxWithTitle: L("跟随 Studio Display 亮度", "跟隨 Studio Display 亮度", "Follow Studio Display Brightness"), target: nil, action: nil)
    private(set) var isBrightnessFollowEnabled: Bool
    private var isHealthy = true
    private var isAsleep: Bool

    init(isAsleep: Bool, lamp: LampController) {
        self.lamp = lamp
        self.isAsleep = isAsleep
        isBrightnessFollowEnabled = UserDefaults.standard.bool(forKey: "brightnessFollowEnabled")
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        configurePanel()
        update(isAsleep: isAsleep, healthy: true)
    }

    func update(isAsleep: Bool, healthy: Bool) {
        self.isAsleep = isAsleep
        isHealthy = healthy
        updateIcon(healthy: healthy)
        let displayState = isAsleep
            ? L("Studio Display 已熄屏", "Studio Display 已休眠", "Studio Display asleep")
            : L("Studio Display 已唤醒", "Studio Display 已喚醒", "Studio Display awake")
        let brightnessStatus = isBrightnessFollowEnabled
            ? L("亮度跟随已开启", "亮度跟隨已開啟", "brightness following on")
            : L("亮度跟随已关闭", "亮度跟隨已關閉", "brightness following off")
        let status = healthy ? L("同步正常", "同步正常", "sync healthy") : L("同步异常", "同步異常", "sync failed")
        item.button?.toolTip = L("iScreenBar：", "iScreenBar：", "iScreenBar: ") + "\(status) · \(displayState) · \(brightnessStatus)"
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
        lamp.requestStatus()
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

    @objc private func autoLightChanged() {
        let requested = autoLightSwitch.state == .on
        if lamp.setAutoLight(enabled: requested) {
            if requested, isBrightnessFollowEnabled {
                isBrightnessFollowEnabled = false
                brightnessFollowSwitch.state = .off
                UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
                update(isAsleep: isAsleep, healthy: isHealthy)
                log(L("自动感光已开启，同时关闭 Studio Display 亮度跟随", "自動感光已開啟，同時關閉 Studio Display 亮度跟隨", "Auto ambient light enabled; Studio Display brightness following disabled"))
            }
        } else {
            autoLightSwitch.state = requested ? .off : .on
        }
        lamp.requestStatus()
    }

    @objc private func brightnessFollowChanged() {
        isBrightnessFollowEnabled = brightnessFollowSwitch.state == .on
        if isBrightnessFollowEnabled, lamp.isAutoLightEnabled == true {
            _ = lamp.setAutoLight(enabled: false)
            autoLightSwitch.state = .off
            log(L("Studio Display 亮度跟随已开启，同时关闭灯具自动感光", "Studio Display 亮度跟隨已開啟，同時關閉燈具自動感光", "Studio Display brightness following enabled; lamp auto ambient light disabled"))
        }
        UserDefaults.standard.set(isBrightnessFollowEnabled, forKey: "brightnessFollowEnabled")
        update(isAsleep: isAsleep, healthy: isHealthy)
        log(isBrightnessFollowEnabled
            ? L("已开启 Studio Display 亮度跟随", "已開啟 Studio Display 亮度跟隨", "Studio Display brightness following enabled")
            : L("已关闭 Studio Display 亮度跟随", "已關閉 Studio Display 亮度跟隨", "Studio Display brightness following disabled"))
    }

    private func configurePanel() {
        powerSwitch.setButtonType(.switch)
        autoLightSwitch.setButtonType(.switch)
        brightnessFollowSwitch.setButtonType(.switch)
        powerSwitch.target = self
        powerSwitch.action = #selector(powerChanged)
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        brightnessSlider.isContinuous = false
        temperatureSlider.target = self
        temperatureSlider.action = #selector(temperatureChanged)
        temperatureSlider.isContinuous = false
        autoLightSwitch.target = self
        autoLightSwitch.action = #selector(autoLightChanged)
        brightnessFollowSwitch.target = self
        brightnessFollowSwitch.action = #selector(brightnessFollowChanged)

        let title = NSTextField(labelWithString: L("iScreenBar 控制", "iScreenBar 控制", "iScreenBar Controls"))
        title.font = .boldSystemFont(ofSize: 15)
        let brightnessRow = controlRow(title: L("亮度", "亮度", "Brightness"), slider: brightnessSlider, valueLabel: brightnessValueLabel)
        let temperatureRow = controlRow(title: L("色温", "色溫", "Color Temp"), slider: temperatureSlider, valueLabel: temperatureValueLabel)
        let divider = NSBox()
        divider.boxType = .separator

        let stack = NSStackView(views: [title, powerSwitch, brightnessRow, temperatureRow, autoLightSwitch, divider, brightnessFollowSwitch])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        brightnessRow.widthAnchor.constraint(equalToConstant: 288).isActive = true
        temperatureRow.widthAnchor.constraint(equalToConstant: 288).isActive = true

        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 250))
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: controller.view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: controller.view.bottomAnchor)
        ])
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 320, height: 250)
        popover.behavior = .transient
    }

    private func controlRow(title: String, slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        let titleWidth: CGFloat = InterfaceLanguage.current == .english ? 78 : 34
        titleLabel.widthAnchor.constraint(equalToConstant: titleWidth).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 214 - titleWidth).isActive = true
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 58).isActive = true
        let row = NSStackView(views: [titleLabel, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func refreshControls() {
        powerSwitch.state = lamp.isPowerOn == true ? .on : .off
        autoLightSwitch.state = lamp.isAutoLightEnabled == true ? .on : .off
        brightnessFollowSwitch.state = isBrightnessFollowEnabled ? .on : .off
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
        brightnessSlider.isEnabled = enabled
        temperatureSlider.isEnabled = enabled
        autoLightSwitch.isEnabled = enabled
    }

    private func updateIcon(healthy: Bool) {
        let color: NSColor = healthy
            ? (isBrightnessFollowEnabled ? .systemYellow : .secondaryLabelColor)
            : .systemRed
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        let symbol = NSImage(systemSymbolName: "sun.min.fill", accessibilityDescription: L("亮度同步", "亮度同步", "Brightness sync"))?
            .withSymbolConfiguration(configuration)
        symbol?.isTemplate = false
        item.button?.image = symbol
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
    private(set) var statusRevision = 0

    var isConnected: Bool { device != nil }

    init() {
        manager = Self.makeManager()
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            log(L("无法打开 iScreenBar USB HID 设备", "無法開啟 iScreenBar USB HID 裝置", "Failed to open iScreenBar USB HID device"))
            return
        }
        guard attachFirstDevice() else {
            log(L("未检测到 iScreenBar USB HID 设备，等待重新连接", "未偵測到 iScreenBar USB HID 裝置，等待重新連接", "iScreenBar USB HID device not found; waiting for reconnection"))
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
            log(on ? L("灯已开启", "燈已開啟", "Lamp turned on") : L("灯已关闭", "燈已關閉", "Lamp turned off"))
            return true
        }

        log(L("USB HID 连接已失效，正在重新连接", "USB HID 連線已失效，正在重新連接", "USB HID connection lost; reconnecting"))
        guard reconnect(), sendPowerReport(on: on) else {
            log(L("USB HID 重连后指令仍失败", "USB HID 重新連接後指令仍失敗", "Command still failed after USB HID reconnection"))
            return false
        }

        isPowerOn = on
        log(on
            ? L("重连成功，灯已开启", "重新連接成功，燈已開啟", "Reconnected; lamp turned on")
            : L("重连成功，灯已关闭", "重新連接成功，燈已關閉", "Reconnected; lamp turned off"))
        return true
    }

    func setBrightness(_ brightness: Int) -> Bool {
        let value = UInt8(clamping: max(1, min(100, brightness)))
        guard sendCommand(0x04, payload: [value, value]) else { return false }
        currentBrightness = Int(value)
        log(L("灯亮度已调整为 \(brightness)%", "燈亮度已調整為 \(brightness)%", "Lamp brightness set to \(brightness)%"))
        return true
    }

    func setTemperature(_ temperature: Int) -> Bool {
        let value = max(2700, min(6500, temperature))
        let payload = [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        guard sendCommand(0x03, payload: payload) else { return false }
        currentTemperature = value
        log(L("灯色温已调整为 \(value)K", "燈色溫已調整為 \(value)K", "Lamp color temperature set to \(value)K"))
        return true
    }

    func setAutoLight(enabled: Bool) -> Bool {
        guard sendCommand(0x06, payload: [enabled ? 1 : 0]) else { return false }
        isAutoLightEnabled = enabled
        log(enabled
            ? L("已开启灯具自动感光", "已開啟燈具自動感光", "Lamp auto ambient light enabled")
            : L("已关闭灯具自动感光", "已關閉燈具自動感光", "Lamp auto ambient light disabled"))
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
        log(L("USB HID 已重新连接", "USB HID 已重新連接", "USB HID reconnected"))
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
            log(String(format: L("USB HID 指令失败：0x%08X", "USB HID 指令失敗：0x%08X", "USB HID command failed: 0x%08X"), result))
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
                    if controller.isPowerOn == nil {
                        controller.isPowerOn = (report[6] & 0x10) != 0
                    }
                    controller.isAutoLightEnabled = (report[6] & 0x20) != 0
                    controller.currentTemperature = (Int(report[8]) << 8) | Int(report[9])
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

private func studioDisplayID() -> CGDirectDisplayID? {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
    return displays.prefix(Int(count))
        .filter { CGDisplayIsBuiltin($0) == 0 }
        .max { CGDisplayPixelsWide($0) < CGDisplayPixelsWide($1) }
}

guard let displayID = studioDisplayID() else {
    log(L("未找到外接显示器", "未找到外接顯示器", "No external display found"))
    exit(2)
}
private let lamp = LampController()
private let displayBrightnessReader = DisplayBrightnessReader()

log(L("开始监听 Studio Display ID=\(displayID)，分辨率=\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))",
      "開始監聽 Studio Display ID=\(displayID)，解析度=\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))",
      "Monitoring Studio Display ID=\(displayID), resolution=\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))"))
var wasAsleep = CGDisplayIsAsleep(displayID) != 0
var helperTurnedLampOff = false
private let statusIndicator = StatusIndicator(isAsleep: wasAsleep, lamp: lamp)
var wasBrightnessFollowEnabled = statusIndicator.isBrightnessFollowEnabled
var brightnessOffset: Int?
var anchorStatusRevision: Int?
var lastDisplayBrightness: Int?
var lastStatusRequest = Date.distantPast
var wasLampConnected = lamp.isConnected
if wasBrightnessFollowEnabled {
    anchorStatusRevision = lamp.statusRevision
    lamp.requestStatus()
    log(L("Studio Display 亮度跟随已开启，正在锁定当前亮度差", "Studio Display 亮度跟隨已開啟，正在鎖定目前亮度差", "Studio Display brightness following enabled; locking current brightness offset"))
}

private func pollDisplayAndLamp() {
    let isAsleep = CGDisplayIsAsleep(displayID) != 0
    let brightnessFollowEnabled = statusIndicator.isBrightnessFollowEnabled

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
            log(L("检测到 Studio Display 熄屏", "偵測到 Studio Display 休眠", "Studio Display went to sleep"))
            helperTurnedLampOff = lamp.setPower(on: false)
            statusIndicator.update(isAsleep: true, healthy: helperTurnedLampOff)
        } else {
            log(L("检测到 Studio Display 唤醒", "偵測到 Studio Display 喚醒", "Studio Display woke up"))
            if helperTurnedLampOff {
                let restored = lamp.setPower(on: true)
                statusIndicator.update(isAsleep: false, healthy: restored)
                helperTurnedLampOff = false
            } else {
                statusIndicator.update(isAsleep: false, healthy: true)
            }
        }
        wasAsleep = isAsleep
    }

    if brightnessFollowEnabled, !isAsleep,
       let displayBrightness = displayBrightnessReader.percent(for: displayID) {
        if let anchorRevision = anchorStatusRevision,
           lamp.statusRevision > anchorRevision,
           let lampBrightness = lamp.currentBrightness {
            if lamp.isAutoLightEnabled == true {
                _ = lamp.setAutoLight(enabled: false)
                log(L("Studio Display 亮度跟随生效，同时关闭灯具自动感光", "Studio Display 亮度跟隨生效，同時關閉燈具自動感光", "Studio Display brightness following active; lamp auto ambient light disabled"))
            }
            brightnessOffset = lampBrightness - displayBrightness
            lastDisplayBrightness = displayBrightness
            anchorStatusRevision = nil
            log(L("已锁定亮度差：iScreenBar \(lampBrightness)% / Studio Display \(displayBrightness)%",
                  "已鎖定亮度差：iScreenBar \(lampBrightness)% / Studio Display \(displayBrightness)%",
                  "Brightness offset locked: iScreenBar \(lampBrightness)% / Studio Display \(displayBrightness)%"))
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
                log(L("检测到 iScreenBar 已恢复连接，正在恢复同步状态", "偵測到 iScreenBar 已恢復連接，正在恢復同步狀態", "iScreenBar reconnected; restoring synchronization state"))
                if isAsleep {
                    helperTurnedLampOff = lamp.setPower(on: false)
                } else {
                    _ = lamp.setPower(on: true)
                }
                if brightnessFollowEnabled {
                    brightnessOffset = nil
                    lastDisplayBrightness = nil
                    anchorStatusRevision = lamp.statusRevision
                    lamp.requestStatus()
                }
            } else {
                log(L("检测到 iScreenBar 已断开", "偵測到 iScreenBar 已斷開", "iScreenBar disconnected"))
                brightnessOffset = nil
                anchorStatusRevision = nil
            }
            wasLampConnected = connected
        }
        statusIndicator.update(isAsleep: isAsleep, healthy: connected)
        lastStatusRequest = Date()
    }
}

let pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
    pollDisplayAndLamp()
}
pollingTimer.tolerance = 0.05
pollDisplayAndLamp()
NSApplication.shared.run()
