import Flutter
import UIKit

/// The platform view Flutter composites where a `Scene3D` sits on iOS.
///
/// A `CADisplayLink` drains the op queue each frame and hands each batch to the
/// linked Godot iOS runtime — the iOS analogue of the Android `OpSink.gd` pulling
/// through `ElpianGodotBridge.pollOps()`. The direction differs (push here, pull
/// there) because the Android engine owns its own render thread while the iOS
/// runtime is driven from the host's run loop; the *protocol* is identical.
///
/// ## Graceful degradation
///
/// Hosting Godot's Metal layer needs `libgodot.ios` plus the `elpian_godot`
/// GDExtension built for iOS — binary artifacts (see ios/README.md). Until they
/// are linked, [GodotRuntimeHost.opSink] is nil: this view shows a labelled
/// placeholder and drops drained ops, so a partial install renders a blank 3D
/// box rather than crashing. This matches Android, and it is why `Scene3D` is
/// safe to place in any tree.
final class GodotSurfaceView: NSObject, FlutterPlatformView {
    private let container = UIView()
    private let placeholder = UILabel()
    private let surfaceId: Int
    private var displayLink: CADisplayLink?

    init(frame: CGRect, surfaceId: Int) {
        self.surfaceId = surfaceId
        super.init()

        container.frame = frame
        container.backgroundColor = UIColor(
            red: 0.043, green: 0.071, blue: 0.125, alpha: 1) // #0b1220
        container.clipsToBounds = true

        placeholder.text = "3D unavailable — Godot iOS runtime not linked"
        placeholder.textColor = UIColor(white: 0.42, alpha: 1)
        placeholder.font = .systemFont(ofSize: 12)
        placeholder.textAlignment = .center
        placeholder.numberOfLines = 0
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            placeholder.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
            placeholder.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -8),
        ])

        attachRuntimeIfAvailable()
        start()
    }

    func view() -> UIView { container }

    /// Hand the container to a linked runtime so it can render into it.
    private func attachRuntimeIfAvailable() {
        guard let host = GodotRuntimeHost.attach else {
            placeholder.isHidden = false
            return
        }
        placeholder.isHidden = true
        host(container, surfaceId)
    }

    private func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(drain))
        // .common so the drain keeps running during scrolling and other tracking
        // run-loop modes — a 3D scene must not freeze because a list is moving.
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func drain() {
        let json = GodotOpQueue.shared.drain()
        guard !json.isEmpty else { return }
        // With no runtime linked the ops are dropped: the Dart side already
        // allocated every handle, so nothing is waiting on them.
        GodotRuntimeHost.opSink?(json)
    }

    deinit { stop() }
}

/// The seam a linked Godot iOS runtime plugs into.
///
/// Kept as plain function hooks rather than a protocol so the runtime can be
/// linked in by the host app (or a future `elpian_godot_ios` pod) without this
/// package taking a build dependency on it.
public enum GodotRuntimeHost {
    /// Receives each drained op batch as a JSON array string.
    public static var opSink: ((String) -> Void)?

    /// Called when a surface appears, so the runtime can render into the view.
    public static var attach: ((UIView, Int) -> Void)?

    /// Called when a surface is released.
    public static var release: ((Int) -> Void)?

    /// A linked runtime calls this to answer an awaited batch.
    public static func reply(_ requestId: Int, _ payload: String) {
        GodotOpQueue.shared.putReply(requestId, payload)
    }

    /// A linked runtime calls this when a connected signal fires.
    public static var onSignal: ((Int, String) -> Void)?
}

/// Creates the platform view for each `Scene3D`.
final class GodotSurfaceFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let params = args as? [String: Any] ?? [:]
        let surfaceId = (params["surfaceId"] as? NSNumber)?.intValue ?? 0
        return GodotSurfaceView(frame: frame, surfaceId: surfaceId)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}
