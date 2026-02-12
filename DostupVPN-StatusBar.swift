import Cocoa

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
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
        // NSImage нативно поддерживает .icns — конвертация через sips не нужна
        let iconPath = homeDir + "/dostup/icon.icns"
        if let image = NSImage(contentsOfFile: iconPath) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            colorIcon = image
            grayIcon = makeGrayscale(image)
        }
    }

    private func makeGrayscale(_ image: NSImage) -> NSImage {
        guard let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData),
              let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return image }
        let rep = NSCIImageRep(ciImage: output)
        let gray = NSImage(size: rep.size)
        gray.addRepresentation(rep)
        gray.size = NSSize(width: 18, height: 18)
        gray.isTemplate = false
        return gray
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
        let checkItem = NSMenuItem(title: "\u{041F}\u{0440}\u{043E}\u{0432}\u{0435}\u{0440}\u{0438}\u{0442}\u{044C} \u{0434}\u{043E}\u{0441}\u{0442}\u{0443}\u{043F}", action: #selector(checkAccess), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)

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
        let command = running ? "stop" : "start"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let escapedPath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
            // Оборачиваем в подоболочку с </dev/null чтобы do shell script не ждал фоновые процессы
            let shellCommand = "bash -c '\\\"\\(escapedPath)\\\" " + command + " </dev/null'"
            let source = "do shell script \"" + shellCommand + "\" with administrator privileges"
            var errorDict: NSDictionary? = nil
            let script = NSAppleScript(source: source)
            script?.executeAndReturnError(&errorDict)

            DispatchQueue.main.async {
                if let error = errorDict {
                    let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
                    if errorNumber != -128 {
                        let msg = error[NSAppleScript.errorMessage] as? String ?? ""
                        self.showNotification(title: "Dostup VPN",
                                              text: "\u{041E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430}: " + msg)
                    }
                } else {
                    let text = running
                        ? "Dostup VPN \u{043E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}"
                        : "Dostup VPN \u{0437}\u{0430}\u{043F}\u{0443}\u{0449}\u{0435}\u{043D}"
                    self.showNotification(title: "Dostup VPN", text: text)
                }
                self.updateStatus()
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
