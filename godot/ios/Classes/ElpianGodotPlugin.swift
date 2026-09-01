import Flutter
import UIKit

/// The iOS side of the embedded-Godot seam.
///
/// Registers the same three things as the Android plugin, against the same
/// channel names in `godot_binding.dart` — so the Dart side is entirely
/// platform-agnostic:
///
///  * method channel `elpian/godot/ops` — `post` / `batch` / `mountSurface` /
///    `releaseSurface` / `stats`;
///  * event channel `elpian/godot/events` — signal callbacks back to Dart;
///  * platform view factory `elpian/godot/surface` — the viewport.
public class ElpianGodotPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private static let opsChannel = "elpian/godot/ops"
    private static let eventsChannel = "elpian/godot/events"
    private static let viewType = "elpian/godot/surface"

    private static let replyTimeout: TimeInterval = 2.0
    private static let replyPoll: TimeInterval = 0.016

    private var eventSink: FlutterEventSink?
    private var nextRequestId = 1

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ElpianGodotPlugin()

        let methods = FlutterMethodChannel(
            name: opsChannel, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methods)

        let events = FlutterEventChannel(
            name: eventsChannel, binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance)

        registrar.register(
            GodotSurfaceFactory(messenger: registrar.messenger()),
            withId: viewType)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let queue = GodotOpQueue.shared

        switch call.method {
        // Fire-and-forget: the overwhelmingly common path.
        case "post":
            if let json = call.arguments as? String {
                queue.push("{\"ops\":\(json)}")
            }
            result(nil)

        // A batch whose replies the caller awaits. The runtime answers on its
        // next frame, so park the request and poll for the reply.
        case "batch":
            guard let json = call.arguments as? String else {
                result("[]")
                return
            }
            let id = nextRequestId
            nextRequestId += 1
            queue.push("{\"ops\":\(json),\"req\":\(id)}")
            awaitReply(id, result)

        case "mountSurface":
            let args = call.arguments as? [String: Any] ?? [:]
            let surfaceId = (args["surfaceId"] as? NSNumber)?.intValue ?? 0
            let mountNode = (args["mountNode"] as? NSNumber)?.intValue ?? 0
            queue.push("{\"mount\":\(surfaceId),\"node\":\(mountNode)}")
            result(nil)

        case "releaseSurface":
            let args = call.arguments as? [String: Any] ?? [:]
            let surfaceId = (args["surfaceId"] as? NSNumber)?.intValue ?? 0
            queue.push("{\"release\":\(surfaceId)}")
            GodotRuntimeHost.release?(surfaceId)
            result(nil)

        case "stats":
            var stats = queue.stats()
            stats["runtimeLinked"] = GodotRuntimeHost.opSink != nil
            result(stats)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Poll for a reply the runtime will produce, then answer the Dart call.
    ///
    /// Reads are rare — creates and writes need no reply — so a short poll is
    /// simpler and cheaper than threading a completion through the runtime.
    /// Gives up after [replyTimeout] rather than wedging the caller when no
    /// runtime is linked at all.
    private func awaitReply(_ requestId: Int, _ result: @escaping FlutterResult) {
        let deadline = Date().addingTimeInterval(ElpianGodotPlugin.replyTimeout)

        func poll() {
            if let reply = GodotOpQueue.shared.takeReply(requestId) {
                result(reply)
                return
            }
            if Date() > deadline {
                // Not an error: the surface may simply have no runtime yet.
                result("[]")
                return
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + ElpianGodotPlugin.replyPoll, execute: poll)
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + ElpianGodotPlugin.replyPoll, execute: poll)
    }

    // MARK: - FlutterStreamHandler

    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        GodotRuntimeHost.onSignal = { [weak self] callbackId, argsJson in
            self?.emitSignal(callbackId, argsJson)
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        GodotRuntimeHost.onSignal = nil
        return nil
    }

    private func emitSignal(_ callbackId: Int, _ argsJson: String) {
        guard let sink = eventSink else { return }
        var args: [Any] = []
        if let data = argsJson.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            args = decoded
        }
        // Channel replies must be delivered on the platform thread.
        DispatchQueue.main.async {
            sink(["cb": callbackId, "args": args])
        }
    }
}
