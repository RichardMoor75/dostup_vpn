import Cocoa

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var restartMenuItem: NSMenuItem!
    private var updateProvidersMenuItem: NSMenuItem!
    private var healthcheckMenuItem: NSMenuItem!
    private var checkMenuItem: NSMenuItem!
    private var updateScriptMenuItem: NSMenuItem!
    private var timer: Timer?

    // Пока идёт перезапуск, таймер не трогает заголовок статуса —
    // иначе через 5 секунд «Перезапуск...» сменяется на «VPN остановлен»
    // и пользователь считает, что перезапуск не сработал.
    private var isRestarting = false

    private var colorIcon: NSImage?
    private var grayIcon: NSImage?

    private let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    private var controlScript: String {
        return homeDir + "/dostup/Dostup_VPN.command"
    }
    // Флаг наличия обновления ставит планировщик (control script)
    private var scriptUpdateFlag: String {
        return homeDir + "/dostup/.script-update"
    }
    // Очередь уведомлений от фоновых bash-задач
    private var notifyFile: String {
        return homeDir + "/dostup/.notify"
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Устанавливаем иконку приложения для уведомлений
        if let appIcon = NSImage(contentsOfFile: homeDir + "/dostup/icon_app.png") {
            NSApplication.shared.applicationIconImage = appIcon
        }
        // Без делегата клики по уведомлениям никуда не приходят
        NSUserNotificationCenter.default.delegate = self
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

        // Update script (виден только когда планировщик нашёл обновление)
        updateScriptMenuItem = NSMenuItem(title: "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C} \u{0441}\u{043A}\u{0440}\u{0438}\u{043F}\u{0442}", action: #selector(updateScript), keyEquivalent: "")
        updateScriptMenuItem.target = self
        updateScriptMenuItem.isHidden = true
        menu.addItem(updateScriptMenuItem)

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

        drainPendingNotifications()
        updateScriptMenuItem.isHidden = !FileManager.default.fileExists(atPath: scriptUpdateFlag)

        // Во время перезапуска состоянием меню управляет restartVPN()
        if isRestarting { return }

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

    // MARK: - Pending Notifications

    // Фоновые задачи (планировщик ru.dostup.vpn.updater) складывают текст сюда,
    // чтобы уведомление ушло от приложения — с иконкой и в едином стиле.
    private func drainPendingNotifications() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: notifyFile) else { return }
        let content = (try? String(contentsOfFile: notifyFile, encoding: .utf8)) ?? ""
        try? fm.removeItem(atPath: notifyFile)

        var actionable = false
        var texts: [String] = []
        for raw in content.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("@ACTION@") {
                actionable = true
                texts.append(String(line.dropFirst(8)))
            } else {
                texts.append(line)
            }
        }
        guard !texts.isEmpty else { return }
        showNotification(title: "Dostup VPN",
                         text: texts.joined(separator: "\n"),
                         actionable: actionable)
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

            let task = Process()

            if running {
                // Stop: через control script (обрабатывает DNS restore)
                task.executableURL = URL(fileURLWithPath: "/bin/bash")
                let ePath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
                task.arguments = ["-c", "'" + ePath + "' stop"]
            } else {
                // Start: напрямую через launchctl (без пароля, через sudoers)
                task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                task.arguments = ["-n", "/bin/launchctl", "start", "ru.dostup.vpn.mihomo"]
            }

            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.showNotification(title: "Dostup VPN",
                                          text: "\u{041E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430}: \(error.localizedDescription)")
                    self.updateStatus()
                }
                return
            }

            if running {
                DispatchQueue.main.async {
                    self.showNotification(title: "Dostup VPN",
                                          text: "Dostup VPN \u{043E}\u{0441}\u{0442}\u{0430}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}")
                    self.updateStatus()
                }
            } else {
                // Mihomo нужно время на запуск — ждём 5 сек и проверяем
                Thread.sleep(forTimeInterval: 5.0)
                let started = self.isMihomoRunning()
                if started {
                    // Переключаем DNS на публичные (fail-safe)
                    let dnsTask = Process()
                    dnsTask.executableURL = URL(fileURLWithPath: "/bin/bash")
                    let ePath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
                    dnsTask.arguments = ["-c", "'" + ePath + "' dns-set"]
                    dnsTask.standardOutput = FileHandle.nullDevice
                    dnsTask.standardError = FileHandle.nullDevice
                    try? dnsTask.run()
                    dnsTask.waitUntilExit()
                }
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
        isRestarting = true
        restartMenuItem.isEnabled = false
        updateProvidersMenuItem.isEnabled = false
        statusMenuItem.title = "\u{21BB} \u{041F}\u{0435}\u{0440}\u{0435}\u{0437}\u{0430}\u{043F}\u{0443}\u{0441}\u{043A}..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let output = self.runControlScript("restart-silent")
            let text = output.isEmpty ? "VPN \u{043F}\u{0435}\u{0440}\u{0435}\u{0437}\u{0430}\u{043F}\u{0443}\u{0449}\u{0435}\u{043D}" : output

            DispatchQueue.main.async {
                self.isRestarting = false
                self.showNotification(title: "Dostup VPN", text: text)
                self.updateStatus()
            }
        }
    }

    @objc private func updateProviders() {
        updateProvidersMenuItem.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // Профиль по ссылке подписки + провайдеры прокси и правил.
            // Логика целиком в control script: её можно менять без пересборки бинарника.
            let output = self.runControlScript("update-profile-silent")
            let text = output.isEmpty ? "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{043B}\u{0435}\u{043D}\u{0438}\u{0435} \u{0437}\u{0430}\u{0432}\u{0435}\u{0440}\u{0448}\u{0435}\u{043D}\u{043E}" : output
            DispatchQueue.main.async {
                self.showNotification(title: "Dostup VPN", text: text)
                self.updateStatus()
            }
        }
    }

    @objc private func healthcheckProviders() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let api = "http://127.0.0.1:9090"
            var summaryLines: [String] = []
            let semaphore = DispatchSemaphore(value: 0)

            if let url = URL(string: "\(api)/providers/proxies"),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let providers = json["providers"] as? [String: Any] {
                for name in providers.keys where name != "default" {
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
                        }
                    } else {
                        summaryLines.append("\(name): \u{043E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430}")
                    }
                }
            } else {
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

    // Установщику нужны пароль и ответы пользователя — только в Терминале
    @objc private func updateScript() {
        runInTerminal(argument: "self-update")
    }

    @objc private func exitApp() {
        let running = isMihomoRunning()
        if !running {
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            let ePath = self.controlScript.replacingOccurrences(of: "'", with: "'\\''")
            task.arguments = ["-c", "'" + ePath + "' stop"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Helpers

    // Синхронный вызов control script с чтением stdout.
    // Читаем ДО waitUntilExit: иначе при выводе больше размера буфера пайпа
    // дочерний процесс заблокируется на записи, а мы — в ожидании его выхода.
    private func runControlScript(_ argument: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [controlScript, argument]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

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

    // MARK: - Notifications

    private func showNotification(title: String, text: String, actionable: Bool = false) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = text
        notification.contentImage = NSImage(contentsOfFile: homeDir + "/dostup/icon_app.png")
        if actionable {
            notification.hasActionButton = true
            notification.actionButtonTitle = "\u{041E}\u{0431}\u{043D}\u{043E}\u{0432}\u{0438}\u{0442}\u{044C}"
            notification.userInfo = ["action": "self-update"]
        }
        NSUserNotificationCenter.default.deliver(notification)
    }

    // Приложение живёт в статусбаре и формально почти всегда «активно» —
    // без этого системa решит не показывать уведомление.
    func userNotificationCenter(_ center: NSUserNotificationCenter,
                                shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter,
                                didActivate notification: NSUserNotification) {
        guard let action = notification.userInfo?["action"] as? String else { return }
        // Кнопка действия видна только в стиле «Предупреждения»; в «Баннерах»
        // работает клик по телу уведомления — обрабатываем оба случая.
        switch notification.activationType {
        case .actionButtonClicked, .contentsClicked:
            runInTerminal(argument: action)
        default:
            break
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
