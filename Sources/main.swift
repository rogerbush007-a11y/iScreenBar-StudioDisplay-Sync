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

private final class StatusIndicator: NSObject {
    private let item: NSStatusItem
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let brightnessMenuItem = NSMenuItem(title: "亮度同步", action: #selector(toggleBrightnessFollow), keyEquivalent: "")
    private(set) var isBrightnessFollowEnabled: Bool

    init(isAsleep: Bool) {
        isBrightnessFollowEnabled = UserDefaults.standard.bool(forKey: "brightnessFollowEnabled")
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        item.button?.title = ""
        item.button?.imagePosition = .imageOnly

        statusMenuItem.isEnabled = false
        brightnessMenuItem.target = self
        brightnessMenuItem.state = isBrightnessFollowEnabled ? .on : .off

        let menu = NSMenu()
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(brightnessMenuItem)
        item.menu = menu
        update(isAsleep: isAsleep, healthy: true)
    }

    func update(isAsleep: Bool, healthy: Bool) {
        updateIcon(healthy: healthy)
        let displayState = isAsleep ? "Studio Display 已熄屏" : "Studio Display 已唤醒"
        let brightnessStatus = isBrightnessFollowEnabled ? "亮度跟随已开启" : "亮度跟随已关闭"
        let status = healthy ? "同步正常" : "同步异常"
        statusMenuItem.title = "\(status) · \(displayState) · \(brightnessStatus)"
        item.button?.toolTip = "iScreenBar：\(status) · \(displayState)"
        item.button?.setAccessibilityLabel("iScreenBar \(status)")
    }

    @objc private func toggleBrightnessFollow() {
        isBrightnessFollowEnabled.toggle()
        UserDefaults.standard.set(isBrightnessFollowEnabled, forKey: "brightnessFollowEnabled")
        brightnessMenuItem.state = isBrightnessFollowEnabled ? .on : .off
        updateIcon(healthy: true)
        log(isBrightnessFollowEnabled ? "已开启 Studio Display 亮度跟随" : "已关闭 Studio Display 亮度跟随")
    }

    private func updateIcon(healthy: Bool) {
        let color: NSColor = healthy
            ? (isBrightnessFollowEnabled ? .systemYellow : .secondaryLabelColor)
            : .systemRed
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        let symbol = NSImage(systemSymbolName: "sun.min.fill", accessibilityDescription: "亮度同步")?
            .withSymbolConfiguration(configuration)
        symbol?.isTemplate = false
        item.button?.image = symbol
    }

}

private final class LampController {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private(set) var currentBrightness: Int?
    private(set) var statusRevision = 0

    init?() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: benqVendorID,
            kIOHIDProductIDKey as String: iScreenBarProductID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let first = devices.first else {
            log("无法打开 iScreenBar USB HID 设备")
            return nil
        }
        device = first
        configureInputCallback(for: first)
        requestStatus()
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
            log("灯已\(on ? "开启" : "关闭")")
            return true
        }

        log("USB HID 连接已失效，正在重新连接")
        guard reconnect(), sendPowerReport(on: on) else {
            log("USB HID 重连后指令仍失败")
            return false
        }

        log("重连成功，灯已\(on ? "开启" : "关闭")")
        return true
    }

    func setBrightness(_ brightness: Int) -> Bool {
        let value = UInt8(clamping: brightness)
        var report = [UInt8](repeating: 0, count: 33)
        report[0] = 0x01
        report[1] = 0xF0
        report[2] = 0x04
        report[3] = 0x06
        report[4] = UInt8(truncatingIfNeeded: 0xF0 + 0x04 + 0x06 + Int(value) * 2)
        report[5] = value
        report[6] = value
        guard send(report) else { return false }
        log("灯亮度已调整为 \(brightness)%")
        return true
    }

    func requestStatus() {
        var report = [UInt8](repeating: 0, count: 33)
        report[0] = 0x01
        report[1] = 0xF0
        report[2] = 0x20
        report[3] = 0x04
        report[4] = 0x14
        _ = send(report)
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
                   report[3] == 0x0D, (report[4] == 0x7D || report[4] == 0x7E), reportLength >= 15 {
                    controller.currentBrightness = Int(report[10])
                    controller.statusRevision += 1
                }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func reconnect() -> Bool {
        device = nil
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let first = devices.first else {
            return false
        }
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
    log("未找到外接显示器")
    exit(2)
}
guard let lamp = LampController() else { exit(3) }
private let displayBrightnessReader = DisplayBrightnessReader()

log("开始监听 Studio Display ID=\(displayID)，分辨率=\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))")
var wasAsleep = CGDisplayIsAsleep(displayID) != 0
var helperTurnedLampOff = false
private let statusIndicator = StatusIndicator(isAsleep: wasAsleep)
var wasBrightnessFollowEnabled = statusIndicator.isBrightnessFollowEnabled
var brightnessOffset: Int?
var anchorStatusRevision: Int?
var lastDisplayBrightness: Int?
var lastStatusRequest = Date.distantPast
if wasBrightnessFollowEnabled {
    anchorStatusRevision = lamp.statusRevision
    lamp.requestStatus()
    log("Studio Display 亮度跟随已开启，正在锁定当前亮度差")
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
            log("检测到 Studio Display 熄屏")
            helperTurnedLampOff = lamp.setPower(on: false)
            statusIndicator.update(isAsleep: true, healthy: helperTurnedLampOff)
        } else {
            log("检测到 Studio Display 唤醒")
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
            brightnessOffset = lampBrightness - displayBrightness
            lastDisplayBrightness = displayBrightness
            anchorStatusRevision = nil
            log("已锁定亮度差：iScreenBar \(lampBrightness)% / Studio Display \(displayBrightness)%")
        } else if let brightnessOffset, displayBrightness != lastDisplayBrightness {
            let target = max(1, min(100, displayBrightness + brightnessOffset))
            if lamp.setBrightness(target) {
                lastDisplayBrightness = displayBrightness
            }
        }
    }

    if Date().timeIntervalSince(lastStatusRequest) >= 2 {
        lamp.requestStatus()
        lastStatusRequest = Date()
    }
}

let pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
    pollDisplayAndLamp()
}
pollingTimer.tolerance = 0.05
pollDisplayAndLamp()
NSApplication.shared.run()
