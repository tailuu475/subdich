// Thay noi dung file SampleHandler.swift do Xcode tao trong target "broadcast".
import ReplayKit
import CoreImage
import ImageIO
import UIKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let ctx = CIContext()
    private let translator = Translator()
    private let lock = NSLock()

    private let interval = 0.3      // giay giua cac lan kiem tra
    private let settle = 0.15       // chu phai dung yen bay nhieu giay thi moi dich
    private let maxWait = 2.0       // nen dong: toi da cho bay nhieu giay
    private let minGap = 0.4        // khoang cach toi thieu giua 2 lan dich
    private let threshold = 4.0     // do nhay phat hien chu doi

    private var lastCheck = Date.distantPast
    private var prevSig: [UInt8]?
    private var pending = false
    private var pendingSince = Date.distantPast
    private var lastChange = Date.distantPast
    private var lastSent = Date.distantPast
    private var inflight = 0
    private var seq = 0
    private var applied = 0
    private var curText = ""

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        Shared.writeState(text: "", ttl: 0)
        if Settings.load().apiKey.isEmpty {
            finishBroadcastWithError(NSError(domain: "SubDich", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Chua nhap Gemini API key trong app SubDich."]))
        }
    }

    override func broadcastFinished() {
        Shared.writeState(text: "", ttl: 0)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = Date()
        if now.timeIntervalSince(lastCheck) < interval { return }
        lastCheck = now
        autoreleasepool { process(sampleBuffer, now) }
    }

    private func process(_ sb: CMSampleBuffer, _ now: Date) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let st = Settings.load()
        if st.apiKey.isEmpty { return }

        var img = CIImage(cvPixelBuffer: pb)
        if let o = CMGetAttachment(sb, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
           let ori = CGImagePropertyOrientation(rawValue: o.uint32Value) {
            img = img.oriented(ori)     // man hinh xoay ngang -> dua ve dung chieu
        }
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.origin.x, y: -img.extent.origin.y))
        let W = img.extent.width, H = img.extent.height
        // CIImage goc toa do o duoi-trai
        let rect = CGRect(x: st.x * W, y: H - (st.y + st.h) * H, width: st.w * W, height: st.h * H)
            .intersection(img.extent)
        guard rect.width > 16, rect.height > 16 else { return }
        var crop = img.cropped(to: rect)
        crop = crop.transformed(by: CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))

        let sig = signature(of: crop)
        let d = prevSig.map { meanAbsDiff(sig, $0) } ?? 999.0
        prevSig = sig
        if d > threshold {
            if !pending { pending = true; pendingSince = now }
            lastChange = now
        }
        guard pending,
              now.timeIntervalSince(lastSent) >= minGap,
              now.timeIntervalSince(lastChange) >= settle || now.timeIntervalSince(pendingSince) >= maxWait
        else { return }

        lock.lock()
        let busy = inflight >= 2
        if !busy { inflight += 1; seq += 1 }
        let mySeq = seq
        lock.unlock()
        if busy { return }
        pending = false
        lastSent = now

        let scale = min(1.0, 1000.0 / crop.extent.width)
        let scaled = crop.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let opts: [CIImageRepresentationOption: Any] =
            [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.8]
        guard let jpeg = ctx.jpegRepresentation(of: scaled, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: opts) else {
            lock.lock(); inflight -= 1; lock.unlock()
            return
        }
        translator.translate(jpeg: jpeg, settings: st) { [weak self] vi in
            self?.finish(seq: mySeq, vi: vi, settings: st)
        }
    }

    private func finish(seq: Int, vi: String?, settings st: Settings) {
        lock.lock()
        inflight -= 1
        guard let vi = vi, seq >= applied else { lock.unlock(); return }   // loi hoac ket qua cu den tre
        applied = seq
        let cur = curText
        lock.unlock()

        if vi.isEmpty {
            lock.lock(); curText = ""; lock.unlock()
            Shared.writeState(text: "", ttl: 0)
            return
        }
        let ttl = st.hideAfter + 0.05 * Double(vi.count)
        if !cur.isEmpty, similarity(cur, vi) > 0.9 {      // cung cau: chi keo dai thoi gian hien
            Shared.writeState(text: cur, ttl: ttl)
            return
        }
        lock.lock(); curText = vi; lock.unlock()
        translator.remember(vi)
        Shared.writeState(text: vi, ttl: ttl)
    }

    // MARK: - tien ich
    private func signature(of crop: CIImage) -> [UInt8] {
        let w = 64, h = 16
        let sc = crop.transformed(by: CGAffineTransform(scaleX: CGFloat(w) / crop.extent.width,
                                                        y: CGFloat(h) / crop.extent.height))
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(sc, toBitmap: &buf, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var out = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            out[i] = UInt8((Int(buf[i * 4]) + Int(buf[i * 4 + 1]) + Int(buf[i * 4 + 2])) / 3)
        }
        return out
    }

    private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 999 }
        var s = 0
        for i in 0..<a.count { s += abs(Int(a[i]) - Int(b[i])) }
        return Double(s) / Double(a.count)
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a.lowercased().prefix(200)), y = Array(b.lowercased().prefix(200))
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + [Int](repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return 1.0 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }
}
