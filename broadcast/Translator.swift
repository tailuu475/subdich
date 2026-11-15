// Chi thuoc target extension (broadcast). Goi Gemini qua REST.
import Foundation

final class Translator {
    private let lock = NSLock()
    private var history: [String] = []

    func remember(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        history = Array((history + [s]).suffix(8))
    }

    private func systemPrompt(_ st: Settings) -> String {
        lock.lock(); let hist = history.suffix(4); lock.unlock()
        var s = "Ban la dich gia phu de, dich tu \(st.sourceLang) sang tieng Viet.\n"
        s += "Noi dung: \(st.title.isEmpty ? "khong ro" : st.title). Phong cach: \(st.style).\n"
        s += "Quy tac: giu nguyen ten rieng (nhan vat, dia danh); xung ho tu nhien theo ngu canh; dich ngan gon, de doc; khong giai thich them.\n"
        s += "Anh la vung phu de cua man hinh dien thoai. Chi doc va dich phu de / loi thoai. "
        s += "Neu anh KHONG co phu de (chi hinh canh, menu, so, gio) thi tra ve chuoi rong.\n"
        if !hist.isEmpty { s += "Cac cau truoc (de nhat quan xung ho): " + hist.joined(separator: " | ") + "\n" }
        s += "Tra ve JSON: {\"vi\": \"<ban dich>\"} (chuoi rong neu khong co phu de)"
        return s
    }

    /// done(nil) = loi; done("") = khong co phu de; done("...") = ban dich
    func translate(jpeg: Data, settings st: Settings, done: @escaping (String?) -> Void) {
        let models = ([st.model] + st.fallbackList).filter { !$0.isEmpty }
        attempt(models: models, index: 0, useThinking: !st.thinking.isEmpty, jpeg: jpeg, st: st, done: done)
    }

    private func attempt(models: [String], index: Int, useThinking: Bool, jpeg: Data, st: Settings,
                         done: @escaping (String?) -> Void) {
        guard index < models.count else { done(nil); return }
        let model = models[index]
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            done(nil); return
        }
        var gen: [String: Any] = ["responseMimeType": "application/json", "temperature": 0.3, "maxOutputTokens": 400]
        if useThinking { gen["thinkingConfig"] = ["thinkingLevel": st.thinking] }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt(st)]]],
            "contents": [["parts": [
                ["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]],
                ["text": "Doc va dich phu de."]
            ]]],
            "generationConfig": gen
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(st.apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            guard let self = self else { return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if err == nil, code == 200, let data = data, let vi = Self.parse(data) {
                done(vi); return
            }
            if code == 400 && useThinking {   // model khong ho tro thinkingLevel -> thu lai khong co
                self.attempt(models: models, index: index, useThinking: false, jpeg: jpeg, st: st, done: done)
            } else {                          // loi / het luot / model khong ton tai -> model ke tiep
                self.attempt(models: models, index: index + 1, useThinking: useThinking, jpeg: jpeg, st: st, done: done)
            }
        }.resume()
    }

    private static func parse(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cands = root["candidates"] as? [[String: Any]],
              let content = cands.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return nil }
        var text = ""
        for p in parts where (p["thought"] as? Bool) != true {
            if let t = p["text"] as? String { text += t }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let d = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) else {
            return text   // model tra ve chu thuong
        }
        if let dict = obj as? [String: Any] { return (dict["vi"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        if let arr = obj as? [[String: Any]], let first = arr.first {
            return (first["vi"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
