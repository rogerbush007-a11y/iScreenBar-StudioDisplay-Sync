import Foundation
import IOKit.hid

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDVendorIDKey as String: 0x05AC,
    kIOHIDProductIDKey as String: 0x1118,
    kIOHIDPrimaryUsagePageKey as String: 0x20,
    kIOHIDPrimaryUsageKey as String: 0x41
]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
      let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
      let device = devices.first else {
    fatalError("Studio Display ALS device not found")
}

print("device=\(device)")
let elements = (IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
for element in elements {
    var rawValue: Unmanaged<IOHIDValue> = .fromOpaque(UnsafeRawPointer(bitPattern: 1)!)
    let result = IOHIDDeviceGetValue(device, element, &rawValue)
    let integer = result == kIOReturnSuccess ? IOHIDValueGetIntegerValue(rawValue.takeUnretainedValue()) : nil
    let resultText = String(format: "0x%08X", result)
    let valueText = integer.map(String.init) ?? "nil"
    print("page=\(IOHIDElementGetUsagePage(element)) usage=\(IOHIDElementGetUsage(element)) type=\(IOHIDElementGetType(element).rawValue) report=\(IOHIDElementGetReportID(element)) min=\(IOHIDElementGetLogicalMin(element)) max=\(IOHIDElementGetLogicalMax(element)) result=\(resultText) value=\(valueText)")
}

IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
