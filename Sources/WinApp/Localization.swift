import Foundation

// The app's text in the language the Mac is set to, with English for any other language.
//
// Every string in the code is its own English text, so `T("Quit PC Mode")` is also what an
// English Mac shows. The tables below map that English text to a translation. A string a
// table doesn't have stays English. Templates take {0}, {1}.
//
// To add a language or a string, add it here by hand, keeping the key identical to the
// English text used in the code. The text is shared with ServerHat's tables.

/// The text for `english` in the current language, with {0}, {1} filled from `args`.
func T(_ english: String, _ args: Any...) -> String {
    Loc.fill(Loc.table[english] ?? english, args)
}

enum Loc {
    /// "en", or the code of a language with a table below.
    static let code: String = {
        if let forced = ProcessInfo.processInfo.environment["PCMODE_LANGUAGE"] {
            return match(forced) ?? "en"
        }
        return pick(from: Locale.preferredLanguages)
    }()

    static let table: [String: String] = tables[code] ?? [:]

    /// The first language in the user's list that PC Mode has. Someone who lists English
    /// first gets English, even if a language further down is translated.
    static func pick(from preferred: [String]) -> String {
        for id in preferred {
            if let code = match(id) { return code }
        }
        return "en"
    }

    /// "de-AT" is German, "zh-Hans-CN" is Simplified Chinese, "en-GB" is English.
    /// Traditional Chinese has no translation yet, so it is skipped.
    static func match(_ id: String) -> String? {
        let parts = id.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
        guard let language = parts.first else { return nil }
        if language == "en" { return "en" }
        if language == "zh" {
            let traditional = parts.contains { ["hant", "tw", "hk", "mo"].contains($0) }
            return traditional ? nil : "zh-Hans"
        }
        return tables[language] == nil ? nil : language
    }

    /// Replaces {0}, {1}… in one pass, so a value that contains "{1}" is left alone.
    static func fill(_ template: String, _ args: [Any]) -> String {
        guard !args.isEmpty, template.contains("{") else { return template }
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let after = rest[rest.index(after: open)...]
            if let close = after.firstIndex(of: "}"), let index = Int(after[..<close]), args.indices.contains(index) {
                result += String(describing: args[index])
                rest = after[after.index(after: close)...]
            } else {
                result += "{"
                rest = after
            }
        }
        return result + rest
    }

    // MARK: Text that was already put together in English

    /// Translates a sentence the app built in English, such as a status `detail` like
    /// "Port 3000 is already in use.": an exact match, then a match on a template with
    /// {0}, {1}, then one sentence at a time. Anything it doesn't know stays English.
    static func auto(_ text: String) -> String { translate(text, to: code) }

    static func translate(_ text: String, to code: String) -> String {
        guard let table = tables[code], !text.isEmpty else { return text }
        if let exact = table[text] { return exact }
        if let translated = fromTemplate(text, table: table, code: code) { return translated }
        let sentences = splitSentences(text)
        if sentences.count > 1 { return sentences.map { translate($0, to: code) }.joined(separator: " ") }
        return text
    }

    private static func splitSentences(_ text: String) -> [String] {
        let pieces = text.components(separatedBy: ". ")
        return pieces.enumerated().map { $0.offset < pieces.count - 1 ? $0.element + "." : $0.element }
    }

    private typealias Template = (regex: NSRegularExpression, translation: String)
    private static let templateLock = NSLock()
    nonisolated(unsafe) private static var templateCache: [String: [Template]] = [:]

    /// A {0} never reaches across a sentence: "1. Automatic restart…" is two sentences, not a value.
    /// A language's templates, the longest English text first so a specific sentence wins
    /// over "in {0}". Built once per language.
    private static func templates(_ table: [String: String], code: String) -> [Template] {
        templateLock.lock()
        defer { templateLock.unlock() }
        if let cached = templateCache[code] { return cached }
        var found: [(key: String, template: Template)] = []
        for (key, translation) in table where key.contains("{0}") {
            var pattern = NSRegularExpression.escapedPattern(for: key)
            for index in 0...3 { pattern = pattern.replacingOccurrences(of: "\\{\(index)\\}", with: "((?:(?!\\. ).)+?)") }
            guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$", options: [.dotMatchesLineSeparators]) else { continue }
            found.append((key, (regex, translation)))
        }
        let sorted = found.sorted { $0.key.count > $1.key.count }.map(\.template)
        templateCache[code] = sorted
        return sorted
    }

    private static func fromTemplate(_ text: String, table: [String: String], code: String) -> String? {
        let whole = NSRange(text.startIndex..., in: text)
        for (regex, translation) in templates(table, code: code) {
            guard let match = regex.firstMatch(in: text, range: whole) else { continue }
            let captured: [Any] = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
            return fill(translation, captured)
        }
        return nil
    }

    // MARK: Translations

    private static let spanish: [String: String] = [
        "Features": "Funciones",
        "General": "General",
        "A GuruHat open-source tool": "Una herramienta de código abierto de GuruHat",
        "About": "Acerca de",
        "Accessibility": "Accesibilidad",
        "Allow PC Mode in System Settings → General → Login Items.": "Permite PC Mode en Configuración del Sistema → General → Ítems de inicio.",
        "App": "App",
        "Checking permissions…": "Comprobando permisos…",
        "Could not update Login Items: {0}": "No se pudieron actualizar los ítems de inicio: {0}",
        "Cut and move with ⌘X / ⌘V": "Cortar y mover con ⌘X / ⌘V",
        "Delete key moves items to Trash": "La tecla de borrar mueve elementos a la Papelera",
        "Donations keep GuruHat apps free. Thank you!": "Las donaciones mantienen gratis las apps de GuruHat. ¡Gracias!",
        "Download": "Descargar",
        "Download PC Mode {0} ›": "Descargar PC Mode {0} ›",
        "Enable permissions, then restart PC Mode.": "Activa los permisos y reinicia PC Mode.",
        "Finder": "Finder",
        "Hidden": "Oculta",
        "Hidden app": "App oculta",
        "Later": "Más tarde",
        "Manage": "Administrar",
        "Minimized": "Minimizada",
        "Move PC Mode to Applications to enable this.": "Mueve PC Mode a Aplicaciones para activar esto.",
        "Not working? ›": "¿No funciona? ›",
        "Open PC Mode at login": "Abrir PC Mode al iniciar sesión",
        "PC Mode Settings": "Configuración de PC Mode",
        "Permissions": "Permisos",
        "Put on your PC hat.": "Ponte tu sombrero de PC.",
        "Quit PC Mode": "Salir de PC Mode",
        "Ready": "Listo",
        "Select files, press ⌘X, then open a destination folder and press ⌘V.": "Selecciona archivos, pulsa ⌘X, abre una carpeta de destino y pulsa ⌘V.",
        "Settings": "Configuración",
        "Shortcut key": "Tecla de atajo",
        "Show PC Mode in the menu bar": "Mostrar PC Mode en la barra de menús",
        "Support GuruHat": "Apoyar a GuruHat",
        "Switch between individual windows, including minimized and hidden windows.": "Cambia entre ventanas individuales, incluidas las minimizadas y ocultas.",
        "Switch individual windows with ⌘Tab": "Cambiar entre ventanas individuales con ⌘Tab",
        "Tab: next   Release ⌘: open": "Tab: siguiente   Suelta ⌘: abrir",
        "Troubleshooting ›": "Solución de problemas ›",
        "Turn on PC Mode in {0} and Input Monitoring, then restart.": "Activa PC Mode en {0} y en Monitorización de entrada, y reinicia.",
        "Uses this key instead of its normal Finder action.": "Usa esta tecla en lugar de su acción normal en el Finder.",
        "Version {0}": "Versión {0}",
        "View on GitHub ↗": "Ver en GitHub ↗",
        "Window": "Ventana",
        "Windows": "Ventanas",
        "Windows & Apps": "Ventanas y apps",
        "Windows is a trademark of Microsoft.\nGuruHat is not affiliated with or endorsed by Microsoft.": "Windows es una marca comercial de Microsoft.\nGuruHat no está afiliada ni respaldada por Microsoft.",
        "You have version {0}. Download the new version from GitHub?": "Tienes la versión {0}. ¿Quieres descargar la nueva versión desde GitHub?",
        "{0} {1} is available": "{0} {1} está disponible",
    ]

    private static let german: [String: String] = [
        "Features": "Funktionen",
        "General": "Allgemein",
        "A GuruHat open-source tool": "Ein Open-Source-Tool von GuruHat",
        "About": "Über",
        "Accessibility": "Bedienungshilfen",
        "Allow PC Mode in System Settings → General → Login Items.": "Erlaube PC Mode in Systemeinstellungen → Allgemein → Anmeldeobjekte.",
        "App": "App",
        "Checking permissions…": "Berechtigungen werden geprüft …",
        "Could not update Login Items: {0}": "Anmeldeobjekte konnten nicht aktualisiert werden: {0}",
        "Cut and move with ⌘X / ⌘V": "Ausschneiden und Bewegen mit ⌘X / ⌘V",
        "Delete key moves items to Trash": "Löschtaste bewegt Objekte in den Papierkorb",
        "Donations keep GuruHat apps free. Thank you!": "Spenden halten die GuruHat-Apps kostenlos. Vielen Dank!",
        "Download": "Herunterladen",
        "Download PC Mode {0} ›": "PC Mode {0} laden ›",
        "Enable permissions, then restart PC Mode.": "Aktiviere die Berechtigungen und starte PC Mode dann neu.",
        "Finder": "Finder",
        "Hidden": "Ausgeblendet",
        "Hidden app": "Ausgeblendete App",
        "Later": "Später",
        "Manage": "Verwalten",
        "Minimized": "Minimiert",
        "Move PC Mode to Applications to enable this.": "Bewege PC Mode in „Programme“, um dies zu aktivieren.",
        "Not working? ›": "Funktioniert nicht? ›",
        "Open PC Mode at login": "PC Mode beim Anmelden öffnen",
        "PC Mode Settings": "PC-Mode-Einstellungen",
        "Permissions": "Berechtigungen",
        "Put on your PC hat.": "Setz deinen PC-Hut auf.",
        "Quit PC Mode": "PC Mode beenden",
        "Ready": "Bereit",
        "Select files, press ⌘X, then open a destination folder and press ⌘V.": "Dateien auswählen, ⌘X drücken, dann einen Zielordner öffnen und ⌘V drücken.",
        "Settings": "Einstellungen",
        "Shortcut key": "Tastenkürzel",
        "Show PC Mode in the menu bar": "PC Mode in der Menüleiste anzeigen",
        "Support GuruHat": "GuruHat unterstützen",
        "Switch between individual windows, including minimized and hidden windows.": "Wechselt zwischen einzelnen Fenstern, auch minimierten und ausgeblendeten.",
        "Switch individual windows with ⌘Tab": "Einzelne Fenster mit ⌘Tab wechseln",
        "Tab: next   Release ⌘: open": "Tab: weiter   ⌘ loslassen: öffnen",
        "Troubleshooting ›": "Fehlerbehebung ›",
        "Turn on PC Mode in {0} and Input Monitoring, then restart.": "Aktiviere PC Mode unter {0} und Eingabeüberwachung und starte dann neu.",
        "Uses this key instead of its normal Finder action.": "Verwendet diese Taste anstelle ihrer normalen Finder-Funktion.",
        "Version {0}": "Version {0}",
        "View on GitHub ↗": "Auf GitHub ansehen ↗",
        "Window": "Fenster",
        "Windows": "Fenster",
        "Windows & Apps": "Fenster & Apps",
        "Windows is a trademark of Microsoft.\nGuruHat is not affiliated with or endorsed by Microsoft.": "Windows ist eine Marke von Microsoft.\nGuruHat steht in keiner Verbindung zu Microsoft und wird von Microsoft nicht unterstützt.",
        "You have version {0}. Download the new version from GitHub?": "Sie haben Version {0}. Möchten Sie die neue Version von GitHub herunterladen?",
        "{0} {1} is available": "{0} {1} ist verfügbar",
    ]

    private static let french: [String: String] = [
        "Features": "Fonctions",
        "General": "Général",
        "A GuruHat open-source tool": "Un outil open source de GuruHat",
        "About": "À propos",
        "Accessibility": "Accessibilité",
        "Allow PC Mode in System Settings → General → Login Items.": "Autorisez PC Mode dans Réglages Système → Général → Éléments de connexion.",
        "App": "App",
        "Checking permissions…": "Vérification des autorisations…",
        "Could not update Login Items: {0}": "Impossible de mettre à jour les éléments d'ouverture : {0}",
        "Cut and move with ⌘X / ⌘V": "Couper et déplacer avec ⌘X / ⌘V",
        "Delete key moves items to Trash": "La touche Supprimer place les éléments dans la corbeille",
        "Donations keep GuruHat apps free. Thank you!": "Les dons gardent les apps GuruHat gratuites. Merci !",
        "Download": "Télécharger",
        "Download PC Mode {0} ›": "Télécharger PC Mode {0} ›",
        "Enable permissions, then restart PC Mode.": "Activez les autorisations, puis redémarrez PC Mode.",
        "Finder": "Finder",
        "Hidden": "Masquée",
        "Hidden app": "App masquée",
        "Later": "Plus tard",
        "Manage": "Gérer",
        "Minimized": "Réduite",
        "Move PC Mode to Applications to enable this.": "Déplacez PC Mode dans Applications pour activer cette option.",
        "Not working? ›": "Ça ne marche pas ? ›",
        "Open PC Mode at login": "Ouvrir PC Mode à l'ouverture de session",
        "PC Mode Settings": "Réglages de PC Mode",
        "Permissions": "Autorisations",
        "Put on your PC hat.": "Mettez votre chapeau de PC.",
        "Quit PC Mode": "Quitter PC Mode",
        "Ready": "Prêt",
        "Select files, press ⌘X, then open a destination folder and press ⌘V.": "Sélectionnez des fichiers, appuyez sur ⌘X, ouvrez un dossier de destination, puis appuyez sur ⌘V.",
        "Settings": "Réglages",
        "Shortcut key": "Touche de raccourci",
        "Show PC Mode in the menu bar": "Afficher PC Mode dans la barre des menus",
        "Support GuruHat": "Soutenir GuruHat",
        "Switch between individual windows, including minimized and hidden windows.": "Passe d'une fenêtre à l'autre, y compris les fenêtres réduites et masquées.",
        "Switch individual windows with ⌘Tab": "Changer de fenêtre individuelle avec ⌘Tab",
        "Tab: next   Release ⌘: open": "Tab : suivant   Relâcher ⌘ : ouvrir",
        "Troubleshooting ›": "Dépannage ›",
        "Turn on PC Mode in {0} and Input Monitoring, then restart.": "Activez PC Mode dans {0} et Surveillance de l'entrée, puis redémarrez.",
        "Uses this key instead of its normal Finder action.": "Utilise cette touche à la place de son action habituelle dans le Finder.",
        "Version {0}": "Version {0}",
        "View on GitHub ↗": "Voir sur GitHub ↗",
        "Window": "Fenêtre",
        "Windows": "Fenêtres",
        "Windows & Apps": "Fenêtres et apps",
        "Windows is a trademark of Microsoft.\nGuruHat is not affiliated with or endorsed by Microsoft.": "Windows est une marque de Microsoft.\nGuruHat n'est ni affiliée à Microsoft ni approuvée par Microsoft.",
        "You have version {0}. Download the new version from GitHub?": "Vous avez la version {0}. Télécharger la nouvelle version depuis GitHub ?",
        "{0} {1} is available": "{0} {1} est disponible",
    ]

    private static let portuguese: [String: String] = [
        "Features": "Recursos",
        "General": "Geral",
        "A GuruHat open-source tool": "Uma ferramenta de código aberto da GuruHat",
        "About": "Sobre",
        "Accessibility": "Acessibilidade",
        "Allow PC Mode in System Settings → General → Login Items.": "Permita o PC Mode em Ajustes do Sistema → Geral → Itens de Login.",
        "App": "App",
        "Checking permissions…": "Verificando permissões…",
        "Could not update Login Items: {0}": "Não foi possível atualizar os itens de login: {0}",
        "Cut and move with ⌘X / ⌘V": "Recortar e mover com ⌘X / ⌘V",
        "Delete key moves items to Trash": "A tecla de apagar move itens para o Lixo",
        "Donations keep GuruHat apps free. Thank you!": "As doações mantêm os apps do GuruHat gratuitos. Obrigado!",
        "Download": "Baixar",
        "Download PC Mode {0} ›": "Baixar o PC Mode {0} ›",
        "Enable permissions, then restart PC Mode.": "Ative as permissões e reinicie o PC Mode.",
        "Finder": "Finder",
        "Hidden": "Oculta",
        "Hidden app": "App oculto",
        "Later": "Mais tarde",
        "Manage": "Gerenciar",
        "Minimized": "Minimizada",
        "Move PC Mode to Applications to enable this.": "Mova o PC Mode para Aplicativos para ativar isso.",
        "Not working? ›": "Não funciona? ›",
        "Open PC Mode at login": "Abrir o PC Mode ao iniciar sessão",
        "PC Mode Settings": "Ajustes do PC Mode",
        "Permissions": "Permissões",
        "Put on your PC hat.": "Coloque seu chapéu de PC.",
        "Quit PC Mode": "Encerrar o PC Mode",
        "Ready": "Pronto",
        "Select files, press ⌘X, then open a destination folder and press ⌘V.": "Selecione arquivos, pressione ⌘X, abra uma pasta de destino e pressione ⌘V.",
        "Settings": "Configurações",
        "Shortcut key": "Tecla de atalho",
        "Show PC Mode in the menu bar": "Mostrar o PC Mode na barra de menus",
        "Support GuruHat": "Apoiar o GuruHat",
        "Switch between individual windows, including minimized and hidden windows.": "Alterna entre janelas individuais, inclusive minimizadas e ocultas.",
        "Switch individual windows with ⌘Tab": "Alternar entre janelas individuais com ⌘Tab",
        "Tab: next   Release ⌘: open": "Tab: próxima   Solte ⌘: abrir",
        "Troubleshooting ›": "Solução de problemas ›",
        "Turn on PC Mode in {0} and Input Monitoring, then restart.": "Ative o PC Mode em {0} e em Monitoramento de Entrada e reinicie.",
        "Uses this key instead of its normal Finder action.": "Usa esta tecla em vez da ação normal dela no Finder.",
        "Version {0}": "Versão {0}",
        "View on GitHub ↗": "Ver no GitHub ↗",
        "Window": "Janela",
        "Windows": "Janelas",
        "Windows & Apps": "Janelas e apps",
        "Windows is a trademark of Microsoft.\nGuruHat is not affiliated with or endorsed by Microsoft.": "Windows é uma marca registrada da Microsoft.\nA GuruHat não é afiliada nem endossada pela Microsoft.",
        "You have version {0}. Download the new version from GitHub?": "Você tem a versão {0}. Baixar a nova versão no GitHub?",
        "{0} {1} is available": "O {0} {1} está disponível",
    ]

    private static let japanese: [String: String] = [
        "Features": "機能",
        "General": "一般",
        "A GuruHat open-source tool": "GuruHatのオープンソースツール",
        "About": "情報",
        "Accessibility": "アクセシビリティ",
        "Allow PC Mode in System Settings → General → Login Items.": "システム設定 → 一般 → ログイン項目 で PC Mode を許可してください。",
        "App": "App",
        "Checking permissions…": "権限を確認しています…",
        "Could not update Login Items: {0}": "ログイン項目を更新できませんでした: {0}",
        "Cut and move with ⌘X / ⌘V": "⌘X / ⌘Vで切り取りと移動",
        "Delete key moves items to Trash": "削除キーで項目をゴミ箱に入れる",
        "Donations keep GuruHat apps free. Thank you!": "寄付のおかげで GuruHat のアプリは無料で提供されています。ありがとうございます!",
        "Download": "ダウンロード",
        "Download PC Mode {0} ›": "PC Mode {0}をダウンロード ›",
        "Enable permissions, then restart PC Mode.": "権限を有効にしてから、PC Modeを再起動してください。",
        "Finder": "Finder",
        "Hidden": "非表示",
        "Hidden app": "非表示のApp",
        "Later": "後で",
        "Manage": "管理",
        "Minimized": "最小化",
        "Move PC Mode to Applications to enable this.": "これを有効にするには、PC Modeを「アプリケーション」フォルダに移動してください。",
        "Not working? ›": "うまく動作しない場合 ›",
        "Open PC Mode at login": "ログイン時にPC Modeを開く",
        "PC Mode Settings": "PC Modeの設定",
        "Permissions": "権限",
        "Put on your PC hat.": "PCハットをかぶろう。",
        "Quit PC Mode": "PC Modeを終了",
        "Ready": "準備完了",
        "Select files, press ⌘X, then open a destination folder and press ⌘V.": "ファイルを選択して⌘Xを押し、移動先のフォルダを開いて⌘Vを押します。",
        "Settings": "設定",
        "Shortcut key": "ショートカットキー",
        "Show PC Mode in the menu bar": "メニューバーにPC Modeを表示",
        "Support GuruHat": "GuruHat を支援",
        "Switch between individual windows, including minimized and hidden windows.": "最小化されたウインドウや非表示のウインドウを含め、個別のウインドウを切り替えます。",
        "Switch individual windows with ⌘Tab": "⌘Tabで個別のウインドウを切り替える",
        "Tab: next   Release ⌘: open": "Tab: 次へ   ⌘を離す: 開く",
        "Troubleshooting ›": "トラブルシューティング ›",
        "Turn on PC Mode in {0} and Input Monitoring, then restart.": "{0}と入力監視でPC Modeをオンにしてから、再起動してください。",
        "Uses this key instead of its normal Finder action.": "このキーを、Finderでの通常の動作の代わりに使います。",
        "Version {0}": "バージョン {0}",
        "View on GitHub ↗": "GitHubで見る ↗",
        "Window": "ウインドウ",
        "Windows": "ウインドウ",
        "Windows & Apps": "ウインドウとApp",
        "Windows is a trademark of Microsoft.\nGuruHat is not affiliated with or endorsed by Microsoft.": "Windowsは Microsoft の商標です。\nGuruHatは Microsoft とは提携しておらず、Microsoft の承認も受けていません。",
        "You have version {0}. Download the new version from GitHub?": "現在のバージョンは {0} です。GitHub から新しいバージョンをダウンロードしますか?",
        "{0} {1} is available": "{0} {1} が利用可能です",
    ]

    private static let chineseSimplified: [String: String] = [
        "Features": "功能",
        "General": "通用",
        "A GuruHat open-source tool": "GuruHat 开源工具",
        "About": "关于",
        "Accessibility": "辅助功能",
        "Allow PC Mode in System Settings → General → Login Items.": "请在“系统设置 → 通用 → 登录项”中允许 PC Mode。",
        "App": "App",
        "Checking permissions…": "正在检查权限…",
        "Could not update Login Items: {0}": "无法更新登录项：{0}",
        "Cut and move with ⌘X / ⌘V": "使用 ⌘X / ⌘V 剪切并移动",
        "Delete key moves items to Trash": "删除键将项目移到废纸篓",
        "Donations keep GuruHat apps free. Thank you!": "捐款让 GuruHat 应用保持免费。谢谢！",
        "Download": "下载",
        "Download PC Mode {0} ›": "下载 PC Mode {0} ›",
        "Enable permissions, then restart PC Mode.": "请启用权限，然后重新启动 PC Mode。",
        "Finder": "访达",
        "Hidden": "已隐藏",
        "Hidden app": "已隐藏的 App",
        "Later": "稍后",
        "Manage": "管理",
        "Minimized": "已最小化",
        "Move PC Mode to Applications to enable this.": "请将 PC Mode 移到“应用程序”文件夹以启用此功能。",
        "Not working? ›": "无法使用？›",
        "Open PC Mode at login": "登录时打开 PC Mode",
        "PC Mode Settings": "PC Mode 设置",
        "Permissions": "权限",
        "Put on your PC hat.": "戴上你的 PC 帽子。",
        "Quit PC Mode": "退出 PC Mode",
        "Ready": "已就绪",
        "Select files, press ⌘X, then open a destination folder and press ⌘V.": "选择文件，按 ⌘X，然后打开目标文件夹并按 ⌘V。",
        "Settings": "设置",
        "Shortcut key": "快捷键",
        "Show PC Mode in the menu bar": "在菜单栏中显示 PC Mode",
        "Support GuruHat": "支持 GuruHat",
        "Switch between individual windows, including minimized and hidden windows.": "在单个窗口之间切换，包括已最小化和已隐藏的窗口。",
        "Switch individual windows with ⌘Tab": "使用 ⌘Tab 切换单个窗口",
        "Tab: next   Release ⌘: open": "Tab：下一个   松开 ⌘：打开",
        "Troubleshooting ›": "疑难解答 ›",
        "Turn on PC Mode in {0} and Input Monitoring, then restart.": "在“{0}”和“输入监控”中打开 PC Mode，然后重新启动。",
        "Uses this key instead of its normal Finder action.": "使用此按键代替其在访达中的常规功能。",
        "Version {0}": "版本 {0}",
        "View on GitHub ↗": "在 GitHub 上查看 ↗",
        "Window": "窗口",
        "Windows": "窗口",
        "Windows & Apps": "窗口和 App",
        "Windows is a trademark of Microsoft.\nGuruHat is not affiliated with or endorsed by Microsoft.": "Windows 是 Microsoft 的商标。\nGuruHat 与 Microsoft 无关联，也未获得 Microsoft 认可。",
        "You have version {0}. Download the new version from GitHub?": "你的版本是 {0}。要从 GitHub 下载新版本吗？",
        "{0} {1} is available": "{0} {1} 现已推出",
    ]

    private static let korean: [String: String] = [
        "Features": "기능",
        "General": "일반",
        "A GuruHat open-source tool": "GuruHat의 오픈 소스 도구",
        "About": "정보",
        "Accessibility": "손쉬운 사용",
        "Allow PC Mode in System Settings → General → Login Items.": "시스템 설정 → 일반 → 로그인 항목에서 PC Mode을 허용하세요.",
        "App": "앱",
        "Checking permissions…": "권한 확인 중…",
        "Could not update Login Items: {0}": "로그인 항목을 업데이트할 수 없습니다: {0}",
        "Cut and move with ⌘X / ⌘V": "⌘X / ⌘V로 잘라내기 및 이동",
        "Delete key moves items to Trash": "삭제 키로 항목을 휴지통으로 이동",
        "Donations keep GuruHat apps free. Thank you!": "후원 덕분에 GuruHat 앱이 무료로 유지됩니다. 감사합니다!",
        "Download": "다운로드",
        "Download PC Mode {0} ›": "PC Mode {0} 다운로드 ›",
        "Enable permissions, then restart PC Mode.": "권한을 활성화한 다음 PC Mode를 다시 시작하세요.",
        "Finder": "Finder",
        "Hidden": "가려짐",
        "Hidden app": "가려진 앱",
        "Later": "나중에",
        "Manage": "관리",
        "Minimized": "최소화됨",
        "Move PC Mode to Applications to enable this.": "이 기능을 사용하려면 PC Mode를 응용 프로그램 폴더로 옮기세요.",
        "Not working? ›": "작동하지 않나요? ›",
        "Open PC Mode at login": "로그인 시 PC Mode 열기",
        "PC Mode Settings": "PC Mode 설정",
        "Permissions": "권한",
        "Put on your PC hat.": "PC 모자를 써 보세요.",
        "Quit PC Mode": "PC Mode 종료",
        "Ready": "준비됨",
        "Select files, press ⌘X, then open a destination folder and press ⌘V.": "파일을 선택하고 ⌘X를 누른 다음, 대상 폴더를 열고 ⌘V를 누르세요.",
        "Settings": "설정",
        "Shortcut key": "단축키",
        "Show PC Mode in the menu bar": "메뉴 막대에 PC Mode 표시",
        "Support GuruHat": "GuruHat 후원하기",
        "Switch between individual windows, including minimized and hidden windows.": "최소화되거나 가려진 윈도우를 포함해 개별 윈도우 간에 전환합니다.",
        "Switch individual windows with ⌘Tab": "⌘Tab으로 개별 윈도우 전환",
        "Tab: next   Release ⌘: open": "Tab: 다음   ⌘ 놓기: 열기",
        "Troubleshooting ›": "문제 해결 ›",
        "Turn on PC Mode in {0} and Input Monitoring, then restart.": "{0} 및 입력 모니터링에서 PC Mode를 켠 다음 다시 시작하세요.",
        "Uses this key instead of its normal Finder action.": "이 키를 Finder의 기본 동작 대신 사용합니다.",
        "Version {0}": "버전 {0}",
        "View on GitHub ↗": "GitHub에서 보기 ↗",
        "Window": "윈도우",
        "Windows": "윈도우",
        "Windows & Apps": "윈도우 및 앱",
        "Windows is a trademark of Microsoft.\nGuruHat is not affiliated with or endorsed by Microsoft.": "Windows는 Microsoft의 상표입니다.\nGuruHat은 Microsoft와 제휴하거나 Microsoft의 보증을 받지 않았습니다.",
        "You have version {0}. Download the new version from GitHub?": "현재 버전은 {0}입니다. GitHub에서 새 버전을 다운로드할까요?",
        "{0} {1} is available": "{0} {1} 업데이트가 있습니다",
    ]

    static let tables: [String: [String: String]] = [
        "es": spanish,
        "de": german,
        "fr": french,
        "pt": portuguese,
        "ja": japanese,
        "zh-Hans": chineseSimplified,
        "ko": korean
    ]
}
