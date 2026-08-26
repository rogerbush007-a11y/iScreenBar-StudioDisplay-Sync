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

private final class StatusIndicator {
    private let item: NSStatusItem

    init(isAsleep: Bool) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        update(isAsleep: isAsleep, healthy: true)
    }

    func update(isAsleep: Bool, healthy: Bool) {
        let color: NSColor = healthy ? .systemGreen : .systemRed
        item.button?.image = Self.dotImage(color: color)
        let displayState = isAsleep ? "Studio Display 已熄屏" : "Studio Display 已唤醒"
        let status = healthy ? "同步正常" : "同步异常"
        item.button?.toolTip = "iScreenBar：\(status) · \(displayState)"
        item.button?.setAccessibilityLabel("iScreenBar \(status)")
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
        if result == kIOReturnSuccess {
            log("灯已\(on ? "开启" : "关闭")")
            return true
        }
        log(String(format: "USB HID 指令失败：0x%08X", result))
        return false
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

while true {
    let isAsleep = CGDisplayIsAsleep(displayID) != 0
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
    RunLoop.current.run(until: Date(timeIntervalSinceNow: pollInterval))
}
