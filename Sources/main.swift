import AppKit
import CoreGraphics
import Foundation
import IOKit.hid

private let benqVendorID = 0x04A5
private let iScreenBarProductID = 0x2501
private let pollInterval: TimeInterval = 1.0

private func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    print("[\(formatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

private final class StatusIndicator: NSObject {
    private let item: NSStatusItem
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let syncMenuItem = NSMenuItem(title: "自动同步开关灯", action: #selector(toggleSync), keyEquivalent: "")
    private(set) var isSyncEnabled: Bool

    init(isAsleep: Bool) {
        isSyncEnabled = UserDefaults.standard.object(forKey: "syncEnabled") as? Bool ?? true
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusMenuItem.isEnabled = false
        syncMenuItem.target = self
        syncMenuItem.state = isSyncEnabled ? .on : .off

        let menu = NSMenu()
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(syncMenuItem)
        item.menu = menu
        update(isAsleep: isAsleep, healthy: true)
    }

    func update(isAsleep: Bool, healthy: Bool) {
        let color: NSColor = healthy ? (isSyncEnabled ? .systemGreen : .systemGray) : .systemRed
        item.button?.image = Self.dotImage(color: color)
        let displayState = isAsleep ? "Studio Display 已熄屏" : "Studio Display 已唤醒"
        let status = healthy ? (isSyncEnabled ? "同步正常" : "同步已暂停") : "同步异常"
        statusMenuItem.title = "\(status) · \(displayState)"
        item.button?.toolTip = "iScreenBar：\(status) · \(displayState)"
        item.button?.setAccessibilityLabel("iScreenBar \(status)")
    }

    @objc private func toggleSync() {
        isSyncEnabled.toggle()
        UserDefaults.standard.set(isSyncEnabled, forKey: "syncEnabled")
        syncMenuItem.state = isSyncEnabled ? .on : .off
        log(isSyncEnabled ? "已开启自动同步开关灯" : "已暂停自动同步开关灯")
    }

    private static func dotImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 8, height: 8)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

private final class LampController {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?

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
    }

    deinit {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
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

    private func sendPowerReport(on: Bool) -> Bool {
        guard let device else { return false }
        var report = [UInt8](repeating: 0, count: 33)
        report[0] = 0x01
        report[1] = 0xF0
        report[2] = 0x07
        report[3] = 0x05
        report[4] = on ? 0xFD : 0xFC
        report[5] = on ? 0x01 : 0x00
        let result = report.withUnsafeBytes { bytes in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 1,
                                 bytes.bindMemory(to: UInt8.self).baseAddress!, report.count)
        }
        if result != kIOReturnSuccess {
            log(String(format: "USB HID 指令失败：0x%08X", result))
        }
        return result == kIOReturnSuccess
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

guard let displayID = studioDisplayID() else {
    log("未找到外接显示器")
    exit(2)
}
guard let lamp = LampController() else { exit(3) }

log("开始监听 Studio Display ID=\(displayID)，分辨率=\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))")
var wasAsleep = CGDisplayIsAsleep(displayID) != 0
var helperTurnedLampOff = false
private let statusIndicator = StatusIndicator(isAsleep: wasAsleep)
var wasSyncEnabled = statusIndicator.isSyncEnabled
log(wasSyncEnabled ? "自动同步开关灯已开启" : "自动同步开关灯已暂停")

while true {
    let isAsleep = CGDisplayIsAsleep(displayID) != 0
    let syncEnabled = statusIndicator.isSyncEnabled

    if syncEnabled != wasSyncEnabled {
        if syncEnabled, isAsleep {
            helperTurnedLampOff = lamp.setPower(on: false)
            statusIndicator.update(isAsleep: true, healthy: helperTurnedLampOff)
        } else if syncEnabled, helperTurnedLampOff {
            let restored = lamp.setPower(on: true)
            helperTurnedLampOff = !restored
            statusIndicator.update(isAsleep: false, healthy: restored)
        } else {
            statusIndicator.update(isAsleep: isAsleep, healthy: true)
        }
        wasSyncEnabled = syncEnabled
        wasAsleep = isAsleep
    } else if syncEnabled, isAsleep != wasAsleep {
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
    } else if !syncEnabled, isAsleep != wasAsleep {
        wasAsleep = isAsleep
        statusIndicator.update(isAsleep: isAsleep, healthy: true)
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: pollInterval))
}
