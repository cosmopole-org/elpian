#if canImport(UIKit)
import UIKit
import ImageIO
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * Decodes images off the main thread and caches them (ImageLoader.kt):
 * `http(s):` (URLSession), `asset:` (the app bundle), `file:` and absolute
 * paths and `data:` URIs. Relative paths resolve against the app's bundle.
 * Natural sizes are the encoded image's pixel size, even when a huge image is
 * decoded downsampled.
 */
public final class ImageLoader: ImageSource {
    private let maxDimension: Int
    private let cache = NSCache<NSString, UIImage>()
    private var sizes: [String: (Int, Int)] = [:]
    private var failed = Set<String>()
    private var waiting: [String: [(UIImage?) -> Void]] = [:]
    private var listeners: [Int: (String, Int, Int) -> Void] = [:]
    private var nextListener = 1
    private let queue = DispatchQueue(label: "dev.elpian.images", qos: .userInitiated, attributes: .concurrent)
    private let session: URLSession

    public init(maxDimension: Int = 4096, session: URLSession = .shared) {
        self.maxDimension = maxDimension
        self.session = session
        cache.totalCostLimit = Int(min(Double(ProcessInfo.processInfo.physicalMemory) / 8, Double(Int32.max)))
    }

    /** Listen for natural sizes (0×0 = failed); returns an unsubscriber. */
    public func onImageLoaded(_ listener: @escaping (_ src: String, _ width: Int, _ height: Int) -> Void) -> () -> Void {
        let id = nextListener
        nextListener += 1
        listeners[id] = listener
        return { [weak self] in self?.listeners.removeValue(forKey: id) }
    }

    /** The natural pixel size once known. */
    public func size(_ src: String) -> (Int, Int)? { sizes[src] }

    public func isFailed(_ src: String) -> Bool { failed.contains(src) }

    /** Report a size learned elsewhere (e.g. a view decoded it). */
    public func reportSize(_ src: String, _ width: Int, _ height: Int) {
        if width > 0 && height > 0 {
            if let prev = sizes[src], prev.0 == width && prev.1 == height { return }
            sizes[src] = (width, height)
            failed.remove(src)
        } else {
            if failed.contains(src) { return }
            failed.insert(src)
        }
        for l in listeners.keys.sorted().compactMap({ listeners[$0] }) { l(src, width, height) }
    }

    /** Load [src]; [callback] runs on the main thread. */
    public func load(_ src: String, _ callback: @escaping (UIImage?) -> Void) {
        if let hit = cache.object(forKey: src as NSString) {
            callback(hit)
            return
        }
        if waiting[src] != nil {
            waiting[src]?.append(callback)
            return
        }
        waiting[src] = [callback]
        bytes(src) { [weak self] data in
            guard let self = self else { return }
            self.queue.async {
                var natural = (0, 0)
                let img = data.flatMap { self.decode($0) { natural = ($0, $1) } }
                DispatchQueue.main.async {
                    if let img = img {
                        let cost = Int(img.size.width * img.scale * img.size.height * img.scale * 4)
                        self.cache.setObject(img, forKey: src as NSString, cost: cost)
                        let px = img.cgImage.map { ($0.width, $0.height) } ?? (0, 0)
                        self.reportSize(src, natural.0 > 0 ? natural.0 : px.0, natural.1 > 0 ? natural.1 : px.1)
                    } else {
                        self.reportSize(src, 0, 0)
                    }
                    let cbs = self.waiting.removeValue(forKey: src) ?? []
                    for cb in cbs { cb(img) }
                }
            }
        }
    }

    /** Start loading [src] (the core's preloadImage). */
    public func preload(_ src: String) {
        if cache.object(forKey: src as NSString) != nil || waiting[src] != nil { return }
        load(src) { _ in }
    }

    public func clear() { cache.removeAllObjects() }

    /** Memory pressure: drop the cache (NSCache also evicts on its own). */
    public func trim() { cache.removeAllObjects() }

    private func bytes(_ src: String, _ done: @escaping (Data?) -> Void) {
        let s = src.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("data:") {
            queue.async {
                guard let comma = s.firstIndex(of: ",") else { return done(nil) }
                let meta = s[s.index(s.startIndex, offsetBy: 5)..<comma]
                let payload = String(s[s.index(after: comma)...])
                if meta.hasSuffix(";base64") {
                    done(Data(base64Encoded: payload, options: .ignoreUnknownCharacters))
                } else {
                    done(payload.removingPercentEncoding.flatMap { $0.data(using: .utf8) })
                }
            }
            return
        }
        if s.hasPrefix("http://") || s.hasPrefix("https://") {
            guard let u = URL(string: s) else { return done(nil) }
            var req = URLRequest(url: u)
            req.timeoutInterval = 30
            session.dataTask(with: req) { data, response, _ in
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return done(nil) }
                done(data)
            }.resume()
            return
        }
        queue.async {
            if s.hasPrefix("asset:") {
                let path = String(s.dropFirst("asset:".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                done(IOSPlatform.bundleURL(path).flatMap { try? Data(contentsOf: $0) })
            } else if s.hasPrefix("file://") {
                done(URL(string: s).flatMap { try? Data(contentsOf: $0) })
            } else if s.hasPrefix("/") {
                done(try? Data(contentsOf: URL(fileURLWithPath: s)))
            } else {
                done(IOSPlatform.bundleURL(s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).flatMap { try? Data(contentsOf: $0) })
            }
        }
    }

    private func decode(_ data: Data, _ natural: (Int, Int) -> Void) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        var h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if orientation >= 5 { swap(&w, &h) }
        guard w > 0, h > 0 else { return nil }
        natural(w, h)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxDimension, max(w, h)),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }
}
#endif
