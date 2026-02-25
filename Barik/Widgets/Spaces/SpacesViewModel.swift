import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    @Published var spaces: [AnySpace] = []
    private var provider: AnySpacesProvider?
    private var observers: [NSObjectProtocol] = []
    private var updateWorkItem: DispatchWorkItem?

    init() {
        let runningApps = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        if runningApps.contains("yabai") {
            provider = AnySpacesProvider(YabaiSpacesProvider())
        } else if runningApps.contains("aerospace") {
            provider = AnySpacesProvider(AerospaceSpacesProvider())
        } else {
            provider = nil
        }
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()

        // Register for workspace change notifications
        let spaceChangeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: workspace,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleUpdate()
        }
        observers.append(spaceChangeObserver)

        // Register for application activation (window focus changes)
        let appActivateObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: workspace,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleUpdate()
        }
        observers.append(appActivateObserver)

        // Register for application launch/termination
        let appLaunchObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: workspace,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleUpdate()
        }
        observers.append(appLaunchObserver)

        let appTerminateObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: workspace,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleUpdate()
        }
        observers.append(appTerminateObserver)

        // Register for distributed notifications (works with AeroSpace callbacks)
        let aerospaceUpdateObserver = distributedCenter.addObserver(
            forName: NSNotification.Name("aerospace_workspace_change"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleUpdate()
        }
        observers.append(aerospaceUpdateObserver)

        // Initial load
        loadSpaces()
    }

    private func stopMonitoring() {
        for observer in observers {
            if let name = (observer as? NSNotification).flatMap({ $0.name }) {
                DistributedNotificationCenter.default().removeObserver(observer, name: name, object: nil)
            } else {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
        }
        observers.removeAll()
        updateWorkItem?.cancel()
    }

    /// Debounce rapid updates to avoid excessive processing
    private func scheduleUpdate() {
        updateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.loadSpaces()
        }
        updateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func loadSpaces() {
        DispatchQueue.global(qos: .background).async {
            guard let provider = self.provider,
                let spaces = provider.getSpacesWithWindows()
            else {
                DispatchQueue.main.async {
                    self.spaces = []
                }
                return
            }
            let sortedSpaces = spaces.sorted {
                // Try to sort numerically first, fall back to lexicographic if not numbers
                if let num1 = Int($0.id), let num2 = Int($1.id) {
                    return num1 < num2
                }
                return $0.id < $1.id
            }
            DispatchQueue.main.async {
                self.spaces = sortedSpaces
            }
        }
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusSpace(
                spaceId: space.id, needWindowFocus: needWindowFocus)
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusWindow(windowId: String(window.id))
        }
    }
}

class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {}
    func icon(for appName: String) -> NSImage? {
        if let cached = cache.object(forKey: appName as NSString) {
            return cached
        }
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: {
            $0.localizedName == appName
        }),
            let bundleURL = app.bundleURL
        {
            let icon = workspace.icon(forFile: bundleURL.path)
            cache.setObject(icon, forKey: appName as NSString)
            return icon
        }
        return nil
    }
}
