#if canImport(UIKit)
import UIKit
import AVFoundation
import WebKit
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

// ---------------------------------------------------------------------------
// Native islands and the Godot surface
// ---------------------------------------------------------------------------

/** A live host-registered component (`native` views / server-component islands). */
public protocol NativeComponentInstance: AnyObject {
    var view: UIView { get }
    func update(_ props: JSONObject)
    func dispose()
}

public extension NativeComponentInstance {
    func update(_ props: JSONObject) {}
    func dispose() {}
}

/** Creates a native component; `emit` reports `(type, value)` events for the view. */
public typealias NativeComponentFactory = (_ props: JSONObject, _ emit: @escaping (_ type: String, _ value: Any?) -> Void) -> NativeComponentInstance

/** Intrinsic size (logical px) of a native component, or nil for the core default. */
public typealias NativeComponentMeasurer = (_ props: JSONObject, _ maxWidth: Double) -> Size?

public enum NativeComponents {
    private static var factories: [String: NativeComponentFactory] = [:]
    private static var measurers: [String: NativeComponentMeasurer] = [:]

    public static func register(_ name: String, factory: @escaping NativeComponentFactory, measurer: NativeComponentMeasurer? = nil) {
        factories[name] = factory
        measurers[name] = measurer
    }

    public static func factory(_ name: String) -> NativeComponentFactory? { factories[name] }
    public static func measurer(_ name: String) -> NativeComponentMeasurer? { measurers[name] }
}

/** Register a native island component (`ServerComponent` native islands, `native` views). */
public func registerNativeComponent(_ name: String, factory: @escaping NativeComponentFactory, measurer: NativeComponentMeasurer? = nil) {
    NativeComponents.register(name, factory: factory, measurer: measurer)
}

/**
 * Hands out the view a Godot engine renders surface `surfaceId` into; the
 * Godot binding implements it and the `scene3d` view hosts the result.
 */
public protocol GodotSurfaceProvider: AnyObject {
    func surfaceView(_ surfaceId: Int) -> UIView?
    func releaseSurface(_ surfaceId: Int, _ view: UIView)
}

/** The `scene3d` view kind: a host the Godot binding attaches its surface view to. */
final class Scene3dLeaf: UIView {
    private(set) var surfaceId: Int?
    private var surface: UIView?
    private let provider: () -> GodotSurfaceProvider?

    init(provider: @escaping () -> GodotSurfaceProvider?) {
        self.provider = provider
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSurface(_ id: Int?) {
        if id == surfaceId && surface != nil { return }
        release()
        surfaceId = id
        guard let id = id, let v = provider()?.surfaceView(id) else { return }
        v.removeFromSuperview()
        v.frame = bounds
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        insertSubview(v, at: 0)
        surface = v
    }

    func release() {
        guard let v = surface else { return }
        v.removeFromSuperview()
        if let id = surfaceId { provider()?.releaseSurface(id, v) }
        surface = nil
    }
}

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

/** The `image` view kind: a bitmap with BoxFit, alignment and an srcIn tint. */
final class ImageLeafView: UIView {
    private weak var owner: ElpianView?
    private var src: String?
    private var image: UIImage?
    private let onResult: (String, UIImage?) -> Void
    var fit: String? = "contain" {
        didSet { setNeedsDisplay() }
    }
    var alignment: Alignment = .center {
        didSet { setNeedsDisplay() }
    }
    var tint: Color? {
        didSet { setNeedsDisplay() }
    }

    init(owner: ElpianView, onResult: @escaping (String, UIImage?) -> Void) {
        self.owner = owner
        self.onResult = onResult
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSrc(_ s: String?) {
        if s == src { return }
        src = s
        image = nil
        setNeedsDisplay()
        guard let s = s, !s.isEmpty, let images = owner?.host?.images else { return }
        images.load(s) { [weak self] img in
            guard let self = self, self.src == s else { return }
            self.image = img
            self.setNeedsDisplay()
            self.onResult(s, img)
        }
    }

    override func draw(_ rect: CGRect) {
        guard let img = image, let cg = img.cgImage, let ctx = UIGraphicsGetCurrentContext() else { return }
        let iw = Double(cg.width), ih = Double(cg.height)
        if iw <= 0 || ih <= 0 || bounds.width <= 0 || bounds.height <= 0 { return }
        // One image pixel is one logical px (Android scales natural sizes by density).
        let r = PaintMath.fitRect(fit, iw, ih, Double(bounds.width), Double(bounds.height), alignment, 1)
        let dst = CGRect(x: r.x, y: r.y, width: r.w, height: r.h)
        ctx.saveGState()
        ctx.clip(to: bounds)
        ctx.interpolationQuality = .high
        img.draw(in: dst)
        if let t = tint {
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(Paints.cgColor(t))
            ctx.fill(dst)
        }
        ctx.restoreGState()
    }
}

// ---------------------------------------------------------------------------
// Video and audio
// ---------------------------------------------------------------------------

/** One timed text cue. */
struct Cue {
    let start: Double
    let end: Double
    let text: String
}

/** WebVTT / SRT cues (MediaLeaf's subtitle tracks). */
enum Subtitles {
    static func parseTime(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let parts = t.replacingOccurrences(of: ",", with: ".").split(separator: ":").map(String.init)
        guard !parts.isEmpty else { return nil }
        var total = 0.0
        for p in parts {
            guard let v = Double(p) else { return nil }
            total = total * 60 + v
        }
        return total
    }

    static func parse(_ raw: String) -> [Cue] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var cues: [Cue] = []
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = lines[ti].components(separatedBy: "-->")
            guard times.count >= 2, let a = parseTime(times[0]), let b = parseTime(times[1]) else { continue }
            let body = lines[(ti + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            cues.append(Cue(start: a, end: b, text: body))
        }
        return cues
    }
}

/**
 * The `video` / `audio` view kinds on AVPlayer (MediaLeaf in Leaves.kt): an
 * AVPlayerLayer for video (so transforms, opacity and clips apply), BoxFit,
 * poster, loop, muted, autoplay, tap-to-show controls, WebVTT/SRT text tracks
 * and load / play / pause / ended / error / volumechange / seeked /
 * timeupdate events.
 */
final class MediaLeaf: UIView {
    private weak var owner: ElpianView?
    private let video: Bool
    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private let playerLayer = AVPlayerLayer()
    private var prepared = false
    private var src: String?
    private let poster: ImageLeafView
    private let caption = PaddedLabel()
    private let controlsBar = UIView()
    private let playButton = UIButton(type: .system)
    private let scrubber = UISlider()
    private let timeLabel = UILabel()
    private var hideControls: DispatchWorkItem?
    private var observers: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var cues: [Cue] = []
    private var tracks: [JSONObject] = []
    private var lastTick = 0.0
    var autoplay = false
    var loop = false
    var muted = false {
        didSet {
            player?.isMuted = muted
            if oldValue != muted && prepared { emitState("volumechange") }
        }
    }
    var controls = true
    var fit = "contain" {
        didSet { updateGeometry() }
    }

    init(owner: ElpianView, video: Bool) {
        self.owner = owner
        self.video = video
        poster = ImageLeafView(owner: owner) { _, _ in }
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = video ? .black : .clear
        clipsToBounds = true
        if video {
            layer.addSublayer(playerLayer)
            poster.frame = bounds
            addSubview(poster)
        }
        caption.textColor = .white
        caption.backgroundColor = UIColor(white: 0, alpha: 0.6)
        caption.font = UIFont.systemFont(ofSize: 14)
        caption.textAlignment = .center
        caption.numberOfLines = 0
        caption.isHidden = true
        addSubview(caption)
        buildControls()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildControls() {
        controlsBar.backgroundColor = UIColor(white: 0, alpha: 0.55)
        controlsBar.isHidden = true
        playButton.tintColor = .white
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        scrubber.minimumValue = 0
        scrubber.maximumValue = 1
        scrubber.addTarget(self, action: #selector(scrubbed), for: .valueChanged)
        timeLabel.textColor = .white
        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        controlsBar.addSubview(playButton)
        controlsBar.addSubview(scrubber)
        controlsBar.addSubview(timeLabel)
        addSubview(controlsBar)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        poster.frame = bounds
        updateGeometry()
        let barH: CGFloat = 44
        controlsBar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
        playButton.frame = CGRect(x: 4, y: 0, width: 40, height: barH)
        timeLabel.frame = CGRect(x: bounds.width - 96, y: 0, width: 92, height: barH)
        scrubber.frame = CGRect(x: 48, y: 0, width: max(0, bounds.width - 148), height: barH)
        let size = caption.sizeThatFits(CGSize(width: bounds.width - 32, height: .greatestFiniteMagnitude))
        caption.frame = CGRect(x: (bounds.width - size.width) / 2, y: bounds.height - 24 - size.height, width: size.width, height: size.height)
    }

    private func duration() -> Double {
        guard prepared, let d = item?.duration, d.isNumeric else { return .nan }
        return d.seconds
    }

    private func currentTime() -> Double { prepared ? (player?.currentTime().seconds ?? 0) : 0 }

    private func emit(_ type: String, _ value: Any?) {
        guard let o = owner else { return }
        o.host?.emit(ViewEvent(id: o.viewId, type: type, value: value))
    }

    private func emitState(_ type: String) {
        emit(type, JSONObject([("currentTime", currentTime()), ("duration", duration()), ("volume", muted ? 0.0 : 1.0), ("muted", muted)]))
    }

    func setPoster(_ url: String?) {
        poster.fit = fit
        poster.setSrc(url)
    }

    func setTracks(_ list: [JSONObject]) {
        tracks = list
        if prepared { loadTracks() }
    }

    private func url(for s: String) -> URL? {
        if s.hasPrefix("asset:") {
            let path = String(s.dropFirst("asset:".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return IOSPlatform.bundleURL(path)
        }
        if s.hasPrefix("/") { return URL(fileURLWithPath: s) }
        if let u = URL(string: s), u.scheme != nil { return u }
        return IOSPlatform.bundleURL(s)
    }

    func setSrc(_ s: String?) {
        if s == src { return }
        src = s
        release()
        guard let s = s, !s.isEmpty else { return }
        guard let u = url(for: s) else {
            emit("error", JSONObject([("message", "unsupported media source: \(s)")]))
            return
        }
        let it = AVPlayerItem(url: u)
        let p = AVPlayer(playerItem: it)
        p.isMuted = muted
        p.actionAtItemEnd = .pause
        item = it
        player = p
        prepared = false
        if video {
            playerLayer.player = p
            observers.append(playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] l, _ in
                DispatchQueue.main.async { if l.isReadyForDisplay && self?.player?.rate ?? 0 > 0 { self?.poster.isHidden = true } }
            })
        }
        observers.append(it.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async { self?.statusChanged(item) }
        })
        observers.append(it.observe(\.presentationSize, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateGeometry() }
        })
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: it, queue: .main) { [weak self] _ in
            self?.ended()
        }
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
            self?.tick(t.seconds)
        }
    }

    private func statusChanged(_ it: AVPlayerItem) {
        guard it === item else { return }
        switch it.status {
        case .readyToPlay:
            if prepared { return }
            prepared = true
            updateGeometry()
            let size = it.presentationSize
            emit("load", JSONObject([("width", Double(size.width)), ("height", Double(size.height)), ("duration", duration())]))
            loadTracks()
            if autoplay { play() }
        case .failed:
            emit("error", JSONObject([("message", it.error?.localizedDescription ?? "media failed to load")]))
        default:
            break
        }
    }

    private func ended() {
        emitState("ended")
        if loop {
            player?.seek(to: .zero)
            player?.play()
        } else {
            emitState("pause")
            updateControls()
        }
    }

    private func tick(_ seconds: Double) {
        if !cues.isEmpty {
            let cue = cues.first { seconds >= $0.start && seconds < $0.end }
            caption.text = cue?.text
            caption.isHidden = cue == nil
            setNeedsLayout()
        }
        guard let p = player, prepared, p.rate > 0 else { return }
        updateControls()
        if seconds - lastTick >= 0.25 || seconds < lastTick {
            lastTick = seconds
            emit("timeupdate", JSONObject([("currentTime", seconds), ("duration", duration())]))
        }
    }

    private func updateGeometry() {
        guard video else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = item?.presentationSize ?? .zero
        switch fit {
        case "cover": playerLayer.videoGravity = .resizeAspectFill; playerLayer.frame = bounds
        case "fill": playerLayer.videoGravity = .resize; playerLayer.frame = bounds
        case "contain": playerLayer.videoGravity = .resizeAspect; playerLayer.frame = bounds
        default:
            if size.width > 0 && size.height > 0 {
                let r = PaintMath.fitRect(fit, Double(size.width), Double(size.height), Double(bounds.width), Double(bounds.height), .center, 1)
                playerLayer.videoGravity = .resize
                playerLayer.frame = CGRect(x: r.x, y: r.y, width: r.w, height: r.h)
            } else {
                playerLayer.videoGravity = .resizeAspect
                playerLayer.frame = bounds
            }
        }
        CATransaction.commit()
    }

    private func loadTracks() {
        let list = tracks.filter { ["subtitles", "captions"].contains(HostProps.str($0["kind"]) ?? "subtitles") }
        guard let chosen = list.first(where: { HostProps.bool($0["default"]) }), let s = HostProps.str(chosen["src"]), let u = url(for: s) else { return }
        let current = item
        if u.isFileURL {
            DispatchQueue.global().async { [weak self] in
                let text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
                DispatchQueue.main.async { if self?.item === current { self?.cues = Subtitles.parse(text) } }
            }
            return
        }
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            DispatchQueue.main.async { if self?.item === current { self?.cues = Subtitles.parse(text) } }
        }.resume()
    }

    func play() {
        guard let p = player else { return }
        if !prepared {
            autoplay = true
            return
        }
        if p.rate == 0 {
            p.play()
            if video && playerLayer.isReadyForDisplay { poster.isHidden = true }
            emitState("play")
            updateControls()
        }
    }

    func pause() {
        guard let p = player, prepared, p.rate > 0 else { return }
        p.pause()
        emitState("pause")
        updateControls()
    }

    func seek(_ seconds: Double) {
        guard let p = player, prepared else { return }
        p.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] done in
            if done { DispatchQueue.main.async { self?.emitState("seeked") } }
        }
    }

    // ---------------------------------------------------------------------
    // Controls
    // ---------------------------------------------------------------------

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if controls { showControls() }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !controls { return nil }
        return super.hitTest(point, with: event)
    }

    private func showControls() {
        controlsBar.isHidden = false
        updateControls()
        hideControls?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.controlsBar.isHidden = true }
        hideControls = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    private func updateControls() {
        let playing = (player?.rate ?? 0) > 0
        playButton.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
        let d = duration()
        let c = currentTime()
        if d.isFinite && d > 0 && !scrubber.isTracking { scrubber.value = Float(c / d) }
        func fmt(_ s: Double) -> String {
            guard s.isFinite else { return "--:--" }
            let t = Int(s)
            return String(format: "%d:%02d", t / 60, t % 60)
        }
        timeLabel.text = "\(fmt(c)) / \(fmt(d))"
    }

    @objc private func togglePlay() {
        if (player?.rate ?? 0) > 0 { pause() } else { play() }
        showControls()
    }

    @objc private func scrubbed() {
        let d = duration()
        if d.isFinite && d > 0 { seek(Double(scrubber.value) * d) }
        showControls()
    }

    func release() {
        hideControls?.cancel()
        controlsBar.isHidden = true
        if let t = timeObserver { player?.removeTimeObserver(t) }
        timeObserver = nil
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        endObserver = nil
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        player?.pause()
        playerLayer.player = nil
        player = nil
        item = nil
        prepared = false
        cues = []
        caption.isHidden = true
        if video { poster.isHidden = false }
    }

    deinit { release() }
}

// ---------------------------------------------------------------------------
// Web
// ---------------------------------------------------------------------------

/** The `web` view kind: a WKWebView showing `src` or inline `html`. */
final class WebLeaf: UIView, WKNavigationDelegate {
    private weak var owner: ElpianView?
    private let web: WKWebView
    private var loaded: String?

    init(owner: ElpianView) {
        self.owner = owner
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        web = WKWebView(frame: .zero, configuration: cfg)
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.frame = bounds
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = .clear
        addSubview(web)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ all: JSONObject, _ patch: JSONObject) {
        if patch.has("javascript") {
            web.configuration.defaultWebpagePreferences.allowsContentJavaScript = !HostProps.isFalse(all["javascript"])
        }
        let html = HostProps.str(all["html"])
        if patch.has("html"), let h = html {
            loaded = nil
            web.loadHTMLString(h, baseURL: nil)
        } else if patch.has("src"), let s = HostProps.str(all["src"]), !s.isEmpty, s != loaded {
            loaded = s
            if s.hasPrefix("asset:") {
                let path = String(s.dropFirst("asset:".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let u = IOSPlatform.bundleURL(path) { web.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent()) }
            } else if let u = URL(string: s) {
                web.load(URLRequest(url: u))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let o = owner else { return }
        o.host?.emit(ViewEvent(id: o.viewId, type: "load"))
    }

    func release() {
        web.stopLoading()
        web.navigationDelegate = nil
    }
}
#endif
