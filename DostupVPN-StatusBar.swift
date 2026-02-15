import Cocoa

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var restartMenuItem: NSMenuItem!
    private var updateProvidersMenuItem: NSMenuItem!
    private var healthcheckMenuItem: NSMenuItem!
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
        let statusbarDir = homeDir + "/dostup/statusbar"
        let size = NSSize(width: 18, height: 18)

        if let on = NSImage(contentsOfFile: statusbarDir + "/icon_on.png") {
            on.size = size
            on.isTemplate = false
            colorIcon = on
        }
        if let off = NSImage(contentsOfFile: statusbarDir + "/icon_off.png") {
            off.size = size
            off.isTemplate = false
            grayIcon = off
        }
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
        menu.autoenablesItems = false

        // Status line (disabled, info only)
        statusMenuItem = NSMenuItem(title: "\u{25CF} VPN \u{0440}\u{0430}\u{0431}\u{043E}\u{0442}\u{0430}\u{0435}\u{0442}", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Toggle VPN
        toggleMenuItem = NSMenuItem(title: "\u{041E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} VPN", action: #selector(toggleVPN), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        // Restart VPN
        restartMenuItem = NSMenuItem(title: "\u{041F}\u{0435}\u{0440}\u{0435}\u{0437}\u{0430}\u{043F}\u{0443}\u{0441}\u{0442}\u{0438}\u{0442}\u{044C}", action: #selector(restartVPN), keyEquivalent: "")
        restartMenuItem.target = self
        menu.addItem(restartMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Update providers
        updateProvidersMenuItem = NSMenuItem(title: "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} \u{043F}\u{0440}\u{043E}\u{043A}\u{0441}\u{0438} \u{0438} \u{043F}\u{0440}\u{0430}\u{0432}\u{0438}\u{043B}\u{0430}", action: #selector(updateProviders), keyEquivalent: "")
        updateProvidersMenuItem.target = self
        menu.addItem(updateProvidersMenuItem)

        // Healthcheck
        healthcheckMenuItem = NSMenuItem(title: "\u{041F}\u{0440}\u{043E}\u{0432}\u{0435}\u{0440}\u{043A}\u{0430} \u{043D}\u{043E}\u{0434}", action: #selector(healthcheckProviders), keyEquivalent: "")
        healthcheckMenuItem.target = self
        menu.addItem(healthcheckMenuItem)

        // Check access
        checkMenuItem = NSMenuItem(title: "\u{041F}\u{0440}\u{043E}\u{0432}\u{0435}\u{0440}\u{0438}\u{0442}\u{044C} \u{0434}\u{043E}\u{0441}\u{0442}\u{0443}\u{043F}", action: #selector(checkAccess), keyEquivalent: "")
        checkMenuItem.target = self
        menu.addItem(checkMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Exit
        let exitMenuItem = NSMenuItem(title: "\u{0412}\u{044B}\u{0445}\u{043E}\u{0434}", action: #selector(exitApp), keyEquivalent: "q")
        exitMenuItem.target = self
        menu.addItem(exitMenuItem)

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
        restartMenuItem.isEnabled = running
        updateProvidersMenuItem.isEnabled = running
        healthcheckMenuItem.isEnabled = running
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

            let shellCommand: String
            if running {
                let escapedPath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
                shellCommand = "'" + escapedPath + "' stop"
            } else {
                // Запуск mihomo напрямую (без control script) — Apple TN2065 паттерн
                let dostupDir = self.homeDir + "/dostup"
                let mihomoBin = dostupDir + "/mihomo"
                let logFile = dostupDir + "/logs/mihomo.log"
                let eBin = mihomoBin.replacingOccurrences(of: "'", with: "'\\''")
                let eDir = dostupDir.replacingOccurrences(of: "'", with: "'\\''")
                let eLog = logFile.replacingOccurrences(of: "'", with: "'\\''")
                let escapedPath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
                shellCommand = "/usr/libexec/ApplicationFirewall/socketfilterfw --add '\(eBin)' 2>/dev/null; " +
                    "/usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp '\(eBin)' 2>/dev/null; " +
                    "'\(eBin)' -d '\(eDir)' > '\(eLog)' 2>&1 & " +
                    "sleep 4; bash '\(escapedPath)' dns-set"
            }
            let source = "do shell script \"" + shellCommand + "\" with administrator privileges"
            var errorDict: NSDictionary? = nil
            let script = NSAppleScript(source: source)
            script?.executeAndReturnError(&errorDict)

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
            } else if running {
                DispatchQueue.main.async {
                    self.showNotification(title: "Dostup VPN",
                                          text: "Dostup VPN \u{043E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}")
                    self.updateStatus()
                }
            } else {
                // Mihomo нужно время на запуск — ждём 5 сек и проверяем
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

    @objc private func restartVPN() {
        runInTerminal(argument: "restart")
    }

    @objc private func updateProviders() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let api = "http://127.0.0.1:9090"
            var allOk = true
            let semaphore = DispatchSemaphore(value: 0)

            // Update proxy providers dynamically
            if let url = URL(string: "\(api)/providers/proxies"),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let providers = json["providers"] as? [String: Any] {
                for name in providers.keys {
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                    var request = URLRequest(url: URL(string: "\(api)/providers/proxies/\(encoded)")!)
                    request.httpMethod = "PUT"
                    request.timeoutInterval = 15
                    URLSession.shared.dataTask(with: request) { _, response, _ in
                        if let http = response as? HTTPURLResponse, !(200...204).contains(http.statusCode) {
                            allOk = false
                        }
                        semaphore.signal()
                    }.resume()
                    semaphore.wait()
                }
            } else {
                allOk = false
            }

            // Update rule providers dynamically
            if let url = URL(string: "\(api)/providers/rules"),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let providers = json["providers"] as? [String: Any] {
                for name in providers.keys {
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                    var request = URLRequest(url: URL(string: "\(api)/providers/rules/\(encoded)")!)
                    request.httpMethod = "PUT"
                    request.timeoutInterval = 15
                    URLSession.shared.dataTask(with: request) { _, response, _ in
                        if let http = response as? HTTPURLResponse, !(200...204).contains(http.statusCode) {
                            allOk = false
                        }
                        semaphore.signal()
                    }.resume()
                    semaphore.wait()
                }
            }

            DispatchQueue.main.async {
                self?.showNotification(
                    title: "Dostup VPN",
                    text: allOk ? "\u{041F}\u{0440}\u{043E}\u{0432}\u{0430}\u{0439}\u{0434}\u{0435}\u{0440}\u{044B} \u{043E}\u{0431}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}\u{044B}" : "\u{041E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430} \u{043E}\u{0431}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}\u{0438}\u{044F} \u{043F}\u{0440}\u{043E}\u{0432}\u{0430}\u{0439}\u{0434}\u{0435}\u{0440}\u{043E}\u{0432}"
                )
            }
        }
    }

    @objc private func healthcheckProviders() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let api = "http://127.0.0.1:9090"
            var summaryLines: [String] = []
            var hasErrors = false
            let semaphore = DispatchSemaphore(value: 0)

            if let url = URL(string: "\(api)/providers/proxies"),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let providers = json["providers"] as? [String: Any] {
                for name in providers.keys {
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                    // Run healthcheck
                    var request = URLRequest(url: URL(string: "\(api)/providers/proxies/\(encoded)/healthcheck")!)
                    request.httpMethod = "GET"
                    request.timeoutInterval = 30
                    URLSession.shared.dataTask(with: request) { _, _, _ in
                        semaphore.signal()
                    }.resume()
                    semaphore.wait()

                    // Get detailed results
                    if let detailUrl = URL(string: "\(api)/providers/proxies/\(encoded)"),
                       let detailData = try? Data(contentsOf: detailUrl),
                       let detailJson = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                       let proxies = detailJson["proxies"] as? [[String: Any]] {
                        var alive = 0
                        var totalDelay = 0
                        let total = proxies.count
                        for proxy in proxies {
                            if let history = proxy["history"] as? [[String: Any]],
                               let last = history.last,
                               let delay = last["delay"] as? Int,
                               delay > 0 {
                                alive += 1
                                totalDelay += delay
                            }
                        }
                        let avg = alive > 0 ? totalDelay / alive : 0
                        if alive > 0 {
                            summaryLines.append("\(name): \(alive)/\(total) (avg \(avg)ms)")
                        } else {
                            summaryLines.append("\(name): 0/\(total)")
                            hasErrors = true
                        }
                    } else {
                        summaryLines.append("\(name): \u{043E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430}")
                        hasErrors = true
                    }
                }
            } else {
                hasErrors = true
                summaryLines.append("\u{041D}\u{0435}\u{0442} \u{0434}\u{0430}\u{043D}\u{043D}\u{044B}\u{0445}")
            }

            let text = summaryLines.joined(separator: "\n")
            DispatchQueue.main.async {
                self?.showNotification(
                    title: "\u{041F}\u{0440}\u{043E}\u{0432}\u{0435}\u{0440}\u{043A}\u{0430} \u{043D}\u{043E}\u{0434}",
                    text: text
                )
            }
        }
    }

    @objc private func checkAccess() {
        runInTerminal(argument: "check")
    }

    @objc private func exitApp() {
        let running = isMihomoRunning()
        if !running {
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let escapedPath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
            let shellCommand = "'" + escapedPath + "' stop"
            let source = "do shell script \"" + shellCommand + "\" with administrator privileges"
            var errorDict: NSDictionary? = nil
            let script = NSAppleScript(source: source)
            script?.executeAndReturnError(&errorDict)

            if let error = errorDict {
                let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
                if errorNumber == -128 {
                    return // User cancelled
                }
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
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
