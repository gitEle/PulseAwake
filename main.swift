import Cocoa
import IOKit.pwr_mgt
import CoreGraphics
import ApplicationServices
import ServiceManagement

private let kJiggleEnabled  = "jiggleEnabled"
private let kJiggleInterval = "jiggleInterval"
private let kPreventSleep   = "preventSleep"
private let kPreventDisplay = "preventDisplaySleep"
private let kAssertionName  = "PulseAwake" as CFString

private enum MenuTag: Int {
    case status      = 100
    case permission  = 101
    case jiggle      = 102
    case sleep       = 103
    case display     = 104
    case launchLogin = 105
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var monitorTimer: Timer?
    private var idleSleepID: IOPMAssertionID = 0
    private var displaySleepID: IOPMAssertionID = 0
    private var jiggleCount = 0
    private var lastJiggle: Date?
    private var lastTrusted = false
    private let defaults = UserDefaults.standard

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func applicationDidFinishLaunching(_ note: Notification) {
        defaults.register(defaults: [
            kJiggleEnabled: true,
            kJiggleInterval: 90,
            kPreventSleep: true,
            kPreventDisplay: true
        ])

        lastTrusted = AXIsProcessTrusted()
        if defaults.bool(forKey: kJiggleEnabled) && !lastTrusted {
            promptAccessibility(openSettings: false)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        applyState()
    }

    func applicationWillTerminate(_ note: Notification) {
        stopMonitor()
        releaseAllAssertions()
    }

    // MARK: - 空闲巡检与微抖动

    private func startMonitor() {
        stopMonitor()
        let t = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 1.5
        RunLoop.main.add(t, forMode: .common)
        monitorTimer = t
    }

    private func stopMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func tick() {
        let trusted = AXIsProcessTrusted()
        if trusted != lastTrusted {
            lastTrusted = trusted
            updateIcon()
        }

        guard defaults.bool(forKey: kJiggleEnabled), trusted else { return }

        let threshold = Double(max(15, defaults.integer(forKey: kJiggleInterval)))
        let idle = currentIdleSeconds()
        if idle >= threshold && !isMouseButtonDown() {
            performJiggle()
        }
    }

    private func currentIdleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }

    private func isMouseButtonDown() -> Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left) ||
        CGEventSource.buttonState(.combinedSessionState, button: .right) ||
        CGEventSource.buttonState(.combinedSessionState, button: .center)
    }

    private func performJiggle() {
        guard AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        let cur = CGEvent(source: nil)?.location ?? CGPoint(x: 500, y: 500)
        let dx: CGFloat = cur.x > 10 ? -1 : 1
        let away = CGPoint(x: cur.x + dx, y: cur.y)

        CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                mouseCursorPosition: away, mouseButton: .left)?.post(tap: .cghidEventTap)

        jiggleCount += 1
        lastJiggle = Date()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let nowPos = CGEvent(source: nil)?.location ?? away
            if hypot(nowPos.x - away.x, nowPos.y - away.y) < 3 {
                CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                        mouseCursorPosition: cur, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        }
    }

    private func promptAccessibility(openSettings: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if openSettings, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 电源防休眠断言（独立状态同步）

    private func syncSleepAssertions() {
        let wantIdle = defaults.bool(forKey: kPreventSleep)
        if wantIdle && idleSleepID == 0 {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           kAssertionName, &id) == kIOReturnSuccess {
                idleSleepID = id
            }
        } else if !wantIdle && idleSleepID != 0 {
            IOPMAssertionRelease(idleSleepID)
            idleSleepID = 0
        }

        let wantDisplay = defaults.bool(forKey: kPreventDisplay)
        if wantDisplay && displaySleepID == 0 {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           kAssertionName, &id) == kIOReturnSuccess {
                displaySleepID = id
            }
        } else if !wantDisplay && displaySleepID != 0 {
            IOPMAssertionRelease(displaySleepID)
            displaySleepID = 0
        }
    }

    private func releaseAllAssertions() {
        if idleSleepID != 0 { IOPMAssertionRelease(idleSleepID); idleSleepID = 0 }
        if displaySleepID != 0 { IOPMAssertionRelease(displaySleepID); displaySleepID = 0 }
    }

    private func applyState() {
        if defaults.bool(forKey: kJiggleEnabled) { startMonitor() } else { stopMonitor() }
        syncSleepAssertions()
        updateIcon()
    }

    // MARK: - 状态栏菜单与图标

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let status = NSMenuItem(title: "状态：加载中", action: nil, keyEquivalent: "")
        status.tag = MenuTag.status.rawValue
        status.isEnabled = false
        menu.addItem(status)

        let permItem = NSMenuItem(title: "授权辅助功能权限…", action: #selector(requestAccessibility), keyEquivalent: "")
        permItem.target = self
        permItem.tag = MenuTag.permission.rawValue
        menu.addItem(permItem)

        menu.addItem(.separator())

        let jiggleItem = NSMenuItem(title: "空闲保活（防自动离开）", action: #selector(toggleJiggle), keyEquivalent: "")
        jiggleItem.target = self
        jiggleItem.tag = MenuTag.jiggle.rawValue
        menu.addItem(jiggleItem)

        let intervalMenu = NSMenu()
        for v in [30, 60, 90, 120, 180, 300] {
            let it = NSMenuItem(title: "\(v) 秒", action: #selector(setInterval(_:)), keyEquivalent: "")
            it.target = self
            it.tag = v
            intervalMenu.addItem(it)
        }
        let intervalItem = NSMenuItem(title: "空闲触发阈值", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        menu.addItem(.separator())

        let sleepItem = NSMenuItem(title: "阻止系统休眠", action: #selector(toggleSleep), keyEquivalent: "")
        sleepItem.target = self
        sleepItem.tag = MenuTag.sleep.rawValue
        menu.addItem(sleepItem)

        let displayItem = NSMenuItem(title: "阻止屏幕休眠", action: #selector(toggleDisplay), keyEquivalent: "")
        displayItem.target = self
        displayItem.tag = MenuTag.display.rawValue
        menu.addItem(displayItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = MenuTag.launchLogin.rawValue
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 PulseAwake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        refreshMenuState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        lastTrusted = AXIsProcessTrusted()
        updateIcon()
        refreshMenuState()
    }

    private func refreshMenuState() {
        guard let menu = statusItem.menu else { return }
        let jiggleOn = defaults.bool(forKey: kJiggleEnabled)
        let sleepOn = defaults.bool(forKey: kPreventSleep)
        let displayOn = defaults.bool(forKey: kPreventDisplay)
        let interval = defaults.integer(forKey: kJiggleInterval)
        let trusted = AXIsProcessTrusted()

        if let status = menu.item(withTag: MenuTag.status.rawValue) {
            if jiggleOn && !trusted {
                status.title = "⚠️ 缺少辅助功能权限（保活未生效）"
            } else if jiggleOn {
                let idle = Int(currentIdleSeconds())
                var text = "运行中 · 空闲 \(idle)s/\(interval)s · 触发 \(jiggleCount) 次"
                if let d = lastJiggle {
                    text += " · 最近 \(timeFormatter.string(from: d))"
                }
                status.title = text
            } else if sleepOn || displayOn {
                status.title = "仅防休眠运行中"
            } else {
                status.title = "已暂停"
            }
        }

        menu.item(withTag: MenuTag.permission.rawValue)?.isHidden = trusted
        menu.item(withTag: MenuTag.jiggle.rawValue)?.state = jiggleOn ? .on : .off
        menu.item(withTag: MenuTag.sleep.rawValue)?.state = sleepOn ? .on : .off
        menu.item(withTag: MenuTag.display.rawValue)?.state = displayOn ? .on : .off
        menu.item(withTag: MenuTag.launchLogin.rawValue)?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off

        if let intervalSubmenu = menu.items.first(where: { $0.submenu != nil })?.submenu {
            for item in intervalSubmenu.items {
                item.state = (item.tag == interval) ? .on : .off
            }
        }
    }

    private func updateIcon() {
        let jiggleOn = defaults.bool(forKey: kJiggleEnabled)
        let anySleepGuard = defaults.bool(forKey: kPreventSleep) || defaults.bool(forKey: kPreventDisplay)
        let trusted = AXIsProcessTrusted()

        let symbolName: String
        if jiggleOn && !trusted {
            symbolName = "exclamationmark.triangle"
        } else if jiggleOn || anySleepGuard {
            symbolName = "waveform.path.ecg.rectangle.fill"
        } else {
            symbolName = "waveform.path.ecg.rectangle"
        }

        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "PulseAwake") {
            img.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.title = ""
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = (jiggleOn || anySleepGuard) ? "保活" : "暂停"
        }
    }

    // MARK: - 菜单交互动作

    @objc private func requestAccessibility() {
        promptAccessibility(openSettings: true)
    }

    @objc private func toggleJiggle() {
        let next = !defaults.bool(forKey: kJiggleEnabled)
        defaults.set(next, forKey: kJiggleEnabled)
        if next && !AXIsProcessTrusted() {
            promptAccessibility(openSettings: false)
        }
        applyState()
        refreshMenuState()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        defaults.set(sender.tag, forKey: kJiggleInterval)
        applyState()
        refreshMenuState()
    }

    @objc private func toggleSleep() {
        defaults.set(!defaults.bool(forKey: kPreventSleep), forKey: kPreventSleep)
        applyState()
        refreshMenuState()
    }

    @objc private func toggleDisplay() {
        defaults.set(!defaults.bool(forKey: kPreventDisplay), forKey: kPreventDisplay)
        applyState()
        refreshMenuState()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置开机自动启动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshMenuState()
    }
}

if CommandLine.arguments.contains("--enable-login") {
    do {
        if SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
        }
        print("LaunchAtLogin status=\(SMAppService.mainApp.status.rawValue)")
        exit(0)
    } catch {
        fputs("Failed to enable LaunchAtLogin: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
