import Cocoa

// Персональный установщик Dostup VPN.
//
// Слаг подписки берётся из имени бандла:
//     «Установить Dostup VPN [a_abdrashitova].app»
// Это позволяет нотаризовать приложение ОДИН раз, а персонализировать
// переименованием: имя папки бандла не входит в подпись, а тикет нотаризации
// лежит внутри Contents/ и переименование переживает.
//
// Сам установщик не дублируется и не вшивается — качается свежий с GitHub.
// Так пользователь всегда получает актуальную версию, а пересобирать
// персональные файлы при каждом релизе не нужно.

// База URL подписки НЕ хранится в исходнике: репозиторий публичный, а слаги
// предсказуемы (обычно фамилия), поэтому опубликованный шаблон позволил бы
// перебирать чужие подписки. Значение подставляется при сборке в Info.plist
// ключом DostupSubscriptionBase — см. make-installer-app.sh.
let subscriptionBase = Bundle.main.object(forInfoDictionaryKey: "DostupSubscriptionBase") as? String

let installerURL = "https://raw.githubusercontent.com/RichardMoor75/dostup_vpn/master/dostup-install.command"

// MARK: - UI

func showAlert(_ message: String, _ informative: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = informative
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

// MARK: - Слаг из имени бандла

// Выборка по скобкам переживает суффиксы, которые добавляют браузер и мессенджеры
// при повторном скачивании: «… [slug] 2.app», «… [slug]-2.app».
func slugFromBundleName() -> String? {
    let name = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
    guard let open = name.firstIndex(of: "[") else { return nil }
    let rest = name[name.index(after: open)...]
    guard let close = rest.firstIndex(of: "]") else { return nil }

    let slug = String(rest[rest.startIndex..<close])
    guard !slug.isEmpty else { return nil }

    // Белый список: слаг подставляется в URL, посторонним символам там делать нечего
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    guard slug.allSatisfy({ allowed.contains($0) }) else { return nil }
    return slug
}

// MARK: - Запуск установщика в Терминале

// Через временный .command, а не через AppleScript-автоматизацию Terminal:
// автоматизация требует отдельного разрешения в «Конфиденциальности».
// Файл создаётся локально, значит карантина на нём нет и Gatekeeper не мешает.
func launchInstaller(subscription: String?) -> String? {
    let argument = subscription.map { " '\($0)'" } ?? ""
    let script = """
    #!/bin/bash
    clear
    echo "Установка Dostup VPN"
    echo ""
    TMP=$(mktemp -t dostup-install) || exit 1
    if ! curl -fsSL --connect-timeout 10 "\(installerURL)" -o "$TMP"; then
        echo "Не удалось скачать установщик."
        echo "Проверьте подключение к интернету и попробуйте ещё раз."
        read -p "Нажмите Enter для закрытия..." < /dev/tty || true
        rm -f "$TMP"
        exit 1
    fi
    if ! head -1 "$TMP" | grep -q '^#!/bin/bash'; then
        echo "Скачанный файл повреждён. Попробуйте позже."
        read -p "Нажмите Enter для закрытия..." < /dev/tty || true
        rm -f "$TMP"
        exit 1
    fi
    bash "$TMP"\(argument)
    rm -f "$TMP"

    """

    let path = NSTemporaryDirectory() + "dostup-launch-\(UUID().uuidString).command"
    do {
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: path)
    } catch {
        return "Не удалось подготовить запуск: \(error.localizedDescription)"
    }

    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-a", "Terminal", path]
    do {
        try open.run()
    } catch {
        return "Не удалось открыть Терминал: \(error.localizedDescription)"
    }
    return nil
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        var subscription: String? = nil

        if let base = subscriptionBase, let slug = slugFromBundleName() {
            subscription = "\(base)/\(slug).yaml"
        }
        // Слага нет — не ошибка: установщик сам спросит ссылку, как при обычной
        // установке с GitHub. Так же ведёт себя файл, переименованный пользователем.

        if let error = launchInstaller(subscription: subscription) {
            showAlert("Не удалось запустить установку", error)
        }
        NSApp.terminate(nil)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
