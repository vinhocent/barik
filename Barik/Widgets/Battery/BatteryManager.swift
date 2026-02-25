import Combine
import Foundation
import IOKit
import IOKit.ps

/// This class monitors the battery status using event-driven IOKit notifications.
/// Uses a singleton pattern to ensure only one system-level listener.
class BatteryManager: ObservableObject {
    static let shared = BatteryManager()

    @Published var batteryLevel: Int = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false

    private var runLoopSource: CFRunLoopSource?

    private init() {
        // Fetch initial battery state
        updatePowerState()

        // Register for power source change notifications
        let context = Unmanaged.passUnretained(self).toOpaque()
        runLoopSource = IOPSNotificationCreateRunLoopSource(
            BatteryManager.powerSourceChanged,
            context
        )?.takeRetainedValue()

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        }
    }

    deinit {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        }
    }

    /// C-style callback triggered by IOKit on battery state changes
    private static let powerSourceChanged: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
        guard let context = context else { return }
        let manager = Unmanaged<BatteryManager>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async {
            manager.updatePowerState()
        }
    }

    /// Updates the battery level and charging state from IOKit
    private func updatePowerState() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?
                .takeRetainedValue() as? [CFTypeRef]
        else {
            return
        }

        for source in sources {
            if let description = IOPSGetPowerSourceDescription(
                snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let currentCapacity = description[
                kIOPSCurrentCapacityKey as String] as? Int,
               let maxCapacity = description[kIOPSMaxCapacityKey as String]
                as? Int,
               let charging = description[kIOPSIsChargingKey as String]
                as? Bool,
               let powerSourceState = description[
                kIOPSPowerSourceStateKey as String] as? String
            {
                let isAC = (powerSourceState == kIOPSACPowerValue)

                self.batteryLevel = (currentCapacity * 100) / maxCapacity
                self.isCharging = charging
                self.isPluggedIn = isAC
            }
        }
    }
}
