// Dung chung cho CA HAI target: app chinh (SubDich) va extension (broadcast).
import Foundation

enum Shared {
    /// Bundle ID cua app chinh (neu dang chay trong extension thi bo duoi ".broadcast").
    static var mainBundleID: String {
        var id = Bundle.main.bundleIdentifier ?? "com.example.subdich"
        if id.hasSuffix(".broadcast") { id = String(id.dropLast(".broadcast".count)) }
        return id
    }
    /// App Group phai tao dung ten: "group." + bundle ID app chinh
    static var appGroup: String { "group." + mainBundleID }
    static var extensionBundleID: String { mainBundleID + ".broadcast" }
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static var stateURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("state.json")
    }
}

struct AppState: Codable {
    var text: String
    var expire: Double   // epoch giay
}

extension Shared {
    static func writeState(text: String, ttl: Double) {
        guard let url = stateURL else { return }
        let st = AppState(text: text, expire: text.isEmpty ? 0 : Date().timeIntervalSince1970 + ttl)
        if let data = try? JSONEncoder().encode(st) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Phu de dang hien (rong neu da het han)
    static func currentText() -> String {
        guard let url = stateURL,
              let data = try? Data(contentsOf: url),
              let st = try? JSONDecoder().decode(AppState.self, from: data),
              Date().timeIntervalSince1970 < st.expire else { return "" }
        return st.text
    }
}

struct Settings: Equatable {
    var apiKey = ""
    var model = "gemini-3.5-flash-lite"
    var fallbacks = "gemini-3.1-flash-lite,gemini-3.5-flash"
    var title = ""
    var style = "tu nhien, doi thoai doi thuong, giu ten rieng"
    var sourceLang = "tieng Anh"
    var thinking = "minimal"          // de trong neu model khong ho tro thinkingLevel
    // vung phu de, ti le 0-1 cua man hinh (goc tren-trai)
    var x = 0.05
    var y = 0.70
    var w = 0.90
    var h = 0.25
    var hideAfter = 5.0

    var fallbackList: [String] {
        fallbacks.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func load() -> Settings {
        let d = Shared.defaults
        var s = Settings()
        s.apiKey = d.string(forKey: "apiKey") ?? s.apiKey
        s.model = d.string(forKey: "model") ?? s.model
        s.fallbacks = d.string(forKey: "fallbacks") ?? s.fallbacks
        s.title = d.string(forKey: "title") ?? s.title
        s.style = d.string(forKey: "style") ?? s.style
        s.sourceLang = d.string(forKey: "sourceLang") ?? s.sourceLang
        s.thinking = d.string(forKey: "thinking") ?? s.thinking
        func num(_ k: String, _ def: Double) -> Double { d.object(forKey: k) != nil ? d.double(forKey: k) : def }
        s.x = num("x", s.x); s.y = num("y", s.y); s.w = num("w", s.w); s.h = num("h", s.h)
        s.hideAfter = num("hideAfter", s.hideAfter)
        return s
    }

    func save() {
        let d = Shared.defaults
        d.set(apiKey, forKey: "apiKey"); d.set(model, forKey: "model"); d.set(fallbacks, forKey: "fallbacks")
        d.set(title, forKey: "title"); d.set(style, forKey: "style"); d.set(sourceLang, forKey: "sourceLang")
        d.set(thinking, forKey: "thinking")
        d.set(x, forKey: "x"); d.set(y, forKey: "y"); d.set(w, forKey: "w"); d.set(h, forKey: "h")
        d.set(hideAfter, forKey: "hideAfter")
    }
}
