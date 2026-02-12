import Cocoa

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var checkMenuItem: NSMenuItem!
    private var timer: Timer?

    private var colorIcon: NSImage?
    private var grayIcon: NSImage?

    private let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    private var controlScript: String {
        return homeDir + "/dostup/Dostup_VPN.command"
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadIcons()
        setupStatusItem()
        setupMenu()
        startTimer()
        updateStatus()
    }

    // MARK: - Icons

    private func loadIcons() {
        let iconPath = homeDir + "/dostup/icon.icns"
        if let image = NSImage(contentsOfFile: iconPath) {
            let size = NSSize(width: 18, height: 18)
            let rendered = renderImage(image, to: size)
            colorIcon = tintImage(rendered, with: NSColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1.0))
            grayIcon = tintImage(rendered, with: NSColor(white: 0.55, alpha: 1.0))
        }
    }

    private func renderImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let pixelSize = NSSize(width: size.width * 2, height: size.height * 2)
        let rendered = NSImage(size: size)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixelSize.width), pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        rendered.addRepresentation(rep)
        rendered.isTemplate = false
        return rendered
    }

    private func tintImage(_ image: NSImage, with color: NSColor) -> NSImage {
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size),
                   from: .zero, operation: .copy, fraction: 1.0)
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    // MARK: - StatusItem & Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let icon = colorIcon {
                button.image = icon
            } else {
                button.title = "VPN"
            }
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Status line (disabled, info only)
        statusMenuItem = NSMenuItem(title: "\u{25CF} VPN \u{0440}\u{0430}\u{0431}\u{043E}\u{0442}\u{0430}\u{0435}\u{0442}", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Toggle VPN
        toggleMenuItem = NSMenuItem(title: "\u{041E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} VPN", action: #selector(toggleVPN), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Check access
        checkMenuItem = NSMenuItem(title: "\u{041F}\u{0440}\u{043E}\u{0432}\u{0435}\u{0440}\u{0438}\u{0442}\u{044C} \u{0434}\u{043E}\u{0441}\u{0442}\u{0443}\u{043F}", action: #selector(checkAccess), keyEquivalent: "")
        checkMenuItem.target = self
        menu.addItem(checkMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Update core
        let updateCoreItem = NSMenuItem(title: "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} \u{044F}\u{0434}\u{0440}\u{043E}", action: #selector(updateCore), keyEquivalent: "")
        updateCoreItem.target = self
        menu.addItem(updateCoreItem)

        // Update config
        let updateConfigItem = NSMenuItem(title: "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} \u{043A}\u{043E}\u{043D}\u{0444}\u{0438}\u{0433}", action: #selector(updateConfig), keyEquivalent: "")
        updateConfigItem.target = self
        menu.addItem(updateConfigItem)

        menu.addItem(NSMenuItem.separator())

        // Quit (only the menu bar app, NOT the VPN)
        let quitItem = NSMenuItem(title: "\u{0412}\u{044B}\u{0439}\u{0442}\u{0438}", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Timer & Status

    private func startTimer() {
        timer = Timer.scheduledTimer(timeInterval: 5.0, target: self,
                                     selector: #selector(updateStatus),
                                     userInfo: nil, repeats: true)
        RunLoop.current.add(timer!, forMode: .common)
    }

    @objc private func updateStatus() {
        let running = isMihomoRunning()

        // Update icon
        if let button = statusItem.button {
            if colorIcon != nil {
                button.image = running ? colorIcon : grayIcon
                button.title = ""
            } else {
                button.title = "VPN"
            }
        }

        // Update menu items
        checkMenuItem.isEnabled = running
        if running {
            statusMenuItem.title = "\u{25CF} VPN \u{0440}\u{0430}\u{0431}\u{043E}\u{0442}\u{0430}\u{0435}\u{0442}"
            toggleMenuItem.title = "\u{041E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} VPN"
        } else {
            statusMenuItem.title = "\u{25CB} VPN \u{043E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}"
            toggleMenuItem.title = "\u{0417}\u{0430}\u{043F}\u{0443}\u{0441}\u{0442}\u{0438}\u{0442}\u{044C} VPN"
        }
    }

    // MARK: - Process Check

    private func isMihomoRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "mihomo"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    // MARK: - Actions

    @objc private func toggleVPN() {
        let running = isMihomoRunning()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let escapedPath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
            let shellCommand: String
            if running {
                shellCommand = "'" + escapedPath + "' stop"
            } else {
                // & в конце — чтобы do shell script не ждал фоновые процессы mihomo
                shellCommand = "'" + escapedPath + "' start </dev/null >/dev/null 2>&1 &"
            }
            let source = "do shell script \"" + shellCommand + "\" with administrator privileges"
            var errorDict: NSDictionary? = nil
            let script = NSAppleScript(source: source)
            script?.executeAndReturnError(&errorDict)

            if running {
                // Stop — результат известен сразу
                DispatchQueue.main.async {
                    if let error = errorDict {
                        let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
                        if errorNumber != -128 {
                            let msg = error[NSAppleScript.errorMessage] as? String ?? ""
                            self.showNotification(title: "Dostup VPN",
                                                  text: "\u{041E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430}: " + msg)
                        }
                    } else {
                        self.showNotification(title: "Dostup VPN",
                                              text: "Dostup VPN \u{043E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}")
                    }
                    self.updateStatus()
                }
            } else {
                // Start — команда фоновая, ждём 5 сек и проверяем
                if let error = errorDict {
                    let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
                    DispatchQueue.main.async {
                        if errorNumber != -128 {
                            let msg = error[NSAppleScript.errorMessage] as? String ?? ""
                            self.showNotification(title: "Dostup VPN",
                                                  text: "\u{041E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430}: " + msg)
                        }
                        self.updateStatus()
                    }
                } else {
                    Thread.sleep(forTimeInterval: 5.0)
                    let started = self.isMihomoRunning()
                    DispatchQueue.main.async {
                        if started {
                            self.showNotification(title: "Dostup VPN",
                                                  text: "Dostup VPN \u{0437}\u{0430}\u{043F}\u{0443}\u{0449}\u{0435}\u{043D}")
                        } else {
                            self.showNotification(title: "Dostup VPN",
                                                  text: "\u{041D}\u{0435} \u{0443}\u{0434}\u{0430}\u{043B}\u{043E}\u{0441}\u{044C} \u{0437}\u{0430}\u{043F}\u{0443}\u{0441}\u{0442}\u{0438}\u{0442}\u{044C} VPN")
                        }
                        self.updateStatus()
                    }
                }
            }
        }
    }

    @objc private func checkAccess() {
        runInTerminal(argument: "check")
    }

    @objc private func updateCore() {
        runInTerminal(argument: "update-core")
    }

    @objc private func updateConfig() {
        runInTerminal(argument: "update-config")
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func runInTerminal(argument: String) {
        // Используем временный .command файл вместо AppleScript automation Terminal
        // (AppleScript automation блокируется macOS без подписи приложения)
        let escapedPath = controlScript.replacingOccurrences(of: "'", with: "'\\''")
        let escapedArg = argument.replacingOccurrences(of: "'", with: "'\\''")
        let tempScript = homeDir + "/dostup/statusbar/run_command.command"
        let content = "#!/bin/bash\nbash '\(escapedPath)' '\(escapedArg)'\n"
        try? content.write(toFile: tempScript, atomically: true, encoding: .utf8)

        // chmod +x
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", tempScript]
        try? chmod.run()
        chmod.waitUntilExit()

        // open -a Terminal (не требует Automation permissions)
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Terminal", tempScript]
        try? open.run()
    }

    private func showNotification(title: String, text: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = text
        NSUserNotificationCenter.default.deliver(notification)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
