// Hien phu de tieng Viet trong cua so Picture-in-Picture noi len tren moi app.
import AVKit
import UIKit
import SwiftUI

final class LayerHostView: UIView {
    var hosted: CALayer? { didSet { if let l = hosted { layer.addSublayer(l) } } }
    override func layoutSubviews() {
        super.layoutSubviews()
        hosted?.frame = bounds
    }
}

struct PiPHostView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    func makeUIView(context: Context) -> LayerHostView {
        let v = LayerHostView()
        v.backgroundColor = .black
        layer.videoGravity = .resizeAspect
        v.hosted = layer
        return v
    }
    func updateUIView(_ uiView: LayerHostView, context: Context) {}
}

final class PiPManager: NSObject, ObservableObject,
                        AVPictureInPictureControllerDelegate,
                        AVPictureInPictureSampleBufferPlaybackDelegate {
    let displayLayer = AVSampleBufferDisplayLayer()
    @Published var status = "Chua bat"
    @Published var lastText = ""

    private var pip: AVPictureInPictureController?
    private var timer: Timer?
    private var cached: CVPixelBuffer?
    private var renderedText: String?
    private let size = CGSize(width: 1280, height: 320)

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
    }

    func start() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            status = "May nay khong ho tro Picture-in-Picture"; return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            status = "Loi audio session: \(error.localizedDescription)"
        }
        if pip == nil {
            let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
            let c = AVPictureInPictureController(contentSource: source)
            c.delegate = self
            c.canStartPictureInPictureAutomaticallyFromInline = true
            pip = c
        }
        timer?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
        // cho khung hinh dau tien len roi moi bat PiP
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, let pip = self.pip else { return }
            if pip.isPictureInPicturePossible {
                pip.startPictureInPicture()
            } else {
                self.status = "Chua bat duoc PiP. Thu bam lai sau 1-2 giay."
            }
        }
    }

    func stop() {
        pip?.stopPictureInPicture()
        timer?.invalidate(); timer = nil
        status = "Da tat"
    }

    // MARK: - ve khung hinh
    private func tick() {
        let text = Shared.currentText()
        if text != renderedText || cached == nil {
            cached = render(text: text)
            renderedText = text
            DispatchQueue.main.async { self.lastText = text }
        }
        guard let pb = cached, let sb = makeSampleBuffer(pb) else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sb)
    }

    private func render(text: String) -> CVPixelBuffer? {
        let w = Int(size.width), h = Int(size.height)
        var pbOut: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pbOut)
        guard let pb = pbOut else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let cg = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                 bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        UIGraphicsPushContext(cg)
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        UIColor(white: 0.05, alpha: 1).setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        let shown = text.isEmpty ? "(cho phu de...)" : text
        let color: UIColor = text.isEmpty ? UIColor(white: 0.4, alpha: 1) : .white
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let maxW = size.width - 80, maxH = size.height - 40
        var fontSize: CGFloat = text.isEmpty ? 40 : 76
        var attr = NSAttributedString()
        var box = CGRect.zero
        while fontSize >= 24 {
            attr = NSAttributedString(string: shown, attributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: color, .paragraphStyle: para])
            box = attr.boundingRect(with: CGSize(width: maxW, height: .greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            if box.height <= maxH { break }
            fontSize -= 4
        }
        let drawRect = CGRect(x: 40, y: (size.height - box.height) / 2, width: maxW, height: ceil(box.height))
        attr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        UIGraphicsPopContext()
        return pb
    }

    private func makeSampleBuffer(_ pb: CVPixelBuffer) -> CMSampleBuffer? {
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fmt)
        guard let f = fmt else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sbOut: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb,
                                                 formatDescription: f, sampleTiming: &timing, sampleBufferOut: &sbOut)
        guard let sb = sbOut,
              let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true),
              CFArrayGetCount(arr) > 0 else { return nil }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(dict,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        return sb
    }

    // MARK: - AVPictureInPictureControllerDelegate
    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { self.status = "Dang hien cua so chu Viet (PiP)" }
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { self.status = "Cua so PiP da dong" }
    }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async { self.status = "Loi PiP: \(error.localizedDescription)" }
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) { completionHandler() }
}
