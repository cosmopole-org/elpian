// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Produced from the VM's own host-API list and capability mapping by:
//
//     cd rust && cargo run --bin gen-host-api-catalog -- \
//         ../native/ios/Sources/ElpianCore/VM/HostApiCatalog.swift
//
// The Swift twin of native/web/src/vm/host-api-catalog.ts;
// `cargo test -p elpian-vm --test host_api_catalog` fails when it is stale.

/// Every host API the Elpian VM forwards to the host, grouped the way the
/// host handler dispatches them, plus the capability that gates each.
public enum HostApiCatalog {
    /// Rendering, environment and diagnostics: the unprefixed names the
    /// Flutter engine has always spoken.
    public static let coreApiNames: Set<String> = [
        "log",
        "println",
        "stringify",
        "render",
        "updateApp",
        "env.get",
    ]

    /// Deferred work on the host clock.
    public static let timerApiNames: Set<String> = [
        "setTimeout",
        "setInterval",
        "clearTimeout",
        "clearInterval",
    ]

    /// The host document tree.
    public static let domApiNames: Set<String> = [
        "dom.getElementById",
        "dom.getElementsByClassName",
        "dom.getElementsByTagName",
        "dom.querySelector",
        "dom.querySelectorAll",
        "dom.createElement",
        "dom.removeElement",
        "dom.clear",
        "dom.setTextContent",
        "dom.setInnerHtml",
        "dom.setAttribute",
        "dom.getAttribute",
        "dom.removeAttribute",
        "dom.hasAttribute",
        "dom.setStyle",
        "dom.getStyle",
        "dom.setStyleObject",
        "dom.addClass",
        "dom.removeClass",
        "dom.hasClass",
        "dom.toggleClass",
        "dom.appendChild",
        "dom.insertBefore",
        "dom.removeChild",
        "dom.replaceChild",
        "dom.addEventListener",
        "dom.removeEventListener",
        "dom.dispatchEvent",
        "dom.toJson",
        "dom.getAllElements",
    ]

    /// The 2D drawing surface.
    public static let canvasApiNames: Set<String> = [
        "canvas.ctx.create",
        "canvas.ctx.dispose",
        "canvas.ctx.clear",
        "canvas.ctx.setSize",
        "canvas.ctx.addCommand",
        "canvas.ctx.addCommands",
        "canvas.addCommand",
        "canvas.addCommands",
        "canvas.clear",
        "canvas.getCommands",
        "canvas.beginPath",
        "canvas.closePath",
        "canvas.moveTo",
        "canvas.lineTo",
        "canvas.quadraticCurveTo",
        "canvas.bezierCurveTo",
        "canvas.arc",
        "canvas.arcTo",
        "canvas.ellipse",
        "canvas.rect",
        "canvas.roundRect",
        "canvas.circle",
        "canvas.fillRect",
        "canvas.strokeRect",
        "canvas.clearRect",
        "canvas.fillCircle",
        "canvas.strokeCircle",
        "canvas.fillPolygon",
        "canvas.strokePolygon",
        "canvas.fillText",
        "canvas.strokeText",
        "canvas.drawImage",
        "canvas.drawImageRect",
        "canvas.fill",
        "canvas.stroke",
        "canvas.clip",
        "canvas.save",
        "canvas.restore",
        "canvas.translate",
        "canvas.rotate",
        "canvas.scale",
        "canvas.transform",
        "canvas.setTransform",
        "canvas.resetTransform",
        "canvas.setFillStyle",
        "canvas.setStrokeStyle",
        "canvas.setLineWidth",
        "canvas.setLineCap",
        "canvas.setLineJoin",
        "canvas.setMiterLimit",
        "canvas.setLineDash",
        "canvas.setLineDashOffset",
        "canvas.setShadowBlur",
        "canvas.setShadowColor",
        "canvas.setShadowOffsetX",
        "canvas.setShadowOffsetY",
        "canvas.setGlobalAlpha",
        "canvas.setGlobalCompositeOperation",
        "canvas.setFont",
        "canvas.setTextAlign",
        "canvas.setTextBaseline",
        "canvas.createLinearGradient",
        "canvas.createRadialGradient",
        "canvas.addColorStop",
        "canvas.createPattern",
        "canvas.putImageData",
        "canvas.getImageData",
        "canvas.createImageData",
    ]

    /// Outbound and inbound networking.
    public static let netApiNames: Set<String> = [
        "net.fetch",
        "net.open",
        "net.send",
        "net.recv",
        "net.close",
    ]

    /// The fabricated filesystem.
    public static let fsApiNames: Set<String> = [
        "fs.read",
        "fs.write",
        "fs.append",
        "fs.delete",
        "fs.list",
        "fs.exists",
        "fs.stat",
        "fs.mkdir",
    ]

    /// GPU command submission and resources.
    public static let gpuApiNames: Set<String> = [
        "gpu.submit",
        "gpu.writeBuffer",
        "gpu.writeTexture",
        "gpu.readBuffer",
        "gpu.surfaceInfo",
        "gpu.define",
        "gpu.undefine",
    ]

    /// Wall-clock and monotonic time.
    public static let timeApiNames: Set<String> = [
        "time.now",
        "time.monotonic",
    ]

    /// Non-deterministic randomness.
    public static let randomApiNames: Set<String> = [
        "random.next",
        "random.bytes",
    ]

    /// Guest compute offloaded onto the host's worker pool.
    public static let taskApiNames: Set<String> = [
        "task.init",
        "task.spawn",
        "task.poll",
        "task.join",
        "task.relay",
        "task.stats",
    ]

    /// The embedder-defined message pipe.
    public static let hostMessagingApiNames: Set<String> = [
        "host.send",
        "host.request",
    ]

    /// The host's drawing surface — the op seams a guest submits UI
    /// through, whichever host is underneath.
    public static let surfaceApiNames: Set<String> = [
        "godot.op",
        "godot.batch",
        "flutter.op",
        "flutter.batch",
    ]

    /// A mini app calling its own server functions. Separate from the
    /// network: an app in a closed posture holds no network at all and
    /// still reaches its own backend through these.
    public static let serverApiNames: Set<String> = [
        "server.call",
        "server.render",
        "stream.emit",
    ]

    /// Durable per-app key/value state, and the secrets a server
    /// function may read.
    public static let stateApiNames: Set<String> = [
        "kv.get",
        "kv.set",
        "kv.delete",
        "kv.list",
        "secret.get",
        "cache.revalidate",
        "ctx.user",
    ]

    /// Module import and management of other VM instances.
    public static let vmApiNames: Set<String> = [
        "vm.import",
        "vm.spawn",
        "vm.pause",
        "vm.resume",
        "vm.terminate",
        "vm.state",
        "vm.usage",
        "vm.usageTree",
        "vm.limits",
        "vm.setLimits",
        "vm.permissions",
        "vm.setPermission",
        "vm.list",
        "vm.info",
        "vm.send",
        "vm.grant",
    ]

    /// The complete advertised surface.
    public static let allHostApiNames: Set<String> = Set<String>()
        .union(coreApiNames)
        .union(timerApiNames)
        .union(domApiNames)
        .union(canvasApiNames)
        .union(netApiNames)
        .union(fsApiNames)
        .union(gpuApiNames)
        .union(timeApiNames)
        .union(randomApiNames)
        .union(taskApiNames)
        .union(hostMessagingApiNames)
        .union(surfaceApiNames)
        .union(serverApiNames)
        .union(stateApiNames)
        .union(vmApiNames)

    /// The capability that gates each API (`Capability::for_api`).
    public static let capabilityOf: [String: String] = [
        "cache.revalidate": "state",
        "canvas.addColorStop": "canvas",
        "canvas.addCommand": "canvas",
        "canvas.addCommands": "canvas",
        "canvas.arc": "canvas",
        "canvas.arcTo": "canvas",
        "canvas.beginPath": "canvas",
        "canvas.bezierCurveTo": "canvas",
        "canvas.circle": "canvas",
        "canvas.clear": "canvas",
        "canvas.clearRect": "canvas",
        "canvas.clip": "canvas",
        "canvas.closePath": "canvas",
        "canvas.createImageData": "canvas",
        "canvas.createLinearGradient": "canvas",
        "canvas.createPattern": "canvas",
        "canvas.createRadialGradient": "canvas",
        "canvas.ctx.addCommand": "canvas",
        "canvas.ctx.addCommands": "canvas",
        "canvas.ctx.clear": "canvas",
        "canvas.ctx.create": "canvas",
        "canvas.ctx.dispose": "canvas",
        "canvas.ctx.setSize": "canvas",
        "canvas.drawImage": "canvas",
        "canvas.drawImageRect": "canvas",
        "canvas.ellipse": "canvas",
        "canvas.fill": "canvas",
        "canvas.fillCircle": "canvas",
        "canvas.fillPolygon": "canvas",
        "canvas.fillRect": "canvas",
        "canvas.fillText": "canvas",
        "canvas.getCommands": "canvas",
        "canvas.getImageData": "canvas",
        "canvas.lineTo": "canvas",
        "canvas.moveTo": "canvas",
        "canvas.putImageData": "canvas",
        "canvas.quadraticCurveTo": "canvas",
        "canvas.rect": "canvas",
        "canvas.resetTransform": "canvas",
        "canvas.restore": "canvas",
        "canvas.rotate": "canvas",
        "canvas.roundRect": "canvas",
        "canvas.save": "canvas",
        "canvas.scale": "canvas",
        "canvas.setFillStyle": "canvas",
        "canvas.setFont": "canvas",
        "canvas.setGlobalAlpha": "canvas",
        "canvas.setGlobalCompositeOperation": "canvas",
        "canvas.setLineCap": "canvas",
        "canvas.setLineDash": "canvas",
        "canvas.setLineDashOffset": "canvas",
        "canvas.setLineJoin": "canvas",
        "canvas.setLineWidth": "canvas",
        "canvas.setMiterLimit": "canvas",
        "canvas.setShadowBlur": "canvas",
        "canvas.setShadowColor": "canvas",
        "canvas.setShadowOffsetX": "canvas",
        "canvas.setShadowOffsetY": "canvas",
        "canvas.setStrokeStyle": "canvas",
        "canvas.setTextAlign": "canvas",
        "canvas.setTextBaseline": "canvas",
        "canvas.setTransform": "canvas",
        "canvas.stroke": "canvas",
        "canvas.strokeCircle": "canvas",
        "canvas.strokePolygon": "canvas",
        "canvas.strokeRect": "canvas",
        "canvas.strokeText": "canvas",
        "canvas.transform": "canvas",
        "canvas.translate": "canvas",
        "clearInterval": "timers",
        "clearTimeout": "timers",
        "ctx.user": "state",
        "dom.addClass": "dom",
        "dom.addEventListener": "dom",
        "dom.appendChild": "dom",
        "dom.clear": "dom",
        "dom.createElement": "dom",
        "dom.dispatchEvent": "dom",
        "dom.getAllElements": "dom",
        "dom.getAttribute": "dom",
        "dom.getElementById": "dom",
        "dom.getElementsByClassName": "dom",
        "dom.getElementsByTagName": "dom",
        "dom.getStyle": "dom",
        "dom.hasAttribute": "dom",
        "dom.hasClass": "dom",
        "dom.insertBefore": "dom",
        "dom.querySelector": "dom",
        "dom.querySelectorAll": "dom",
        "dom.removeAttribute": "dom",
        "dom.removeChild": "dom",
        "dom.removeClass": "dom",
        "dom.removeElement": "dom",
        "dom.removeEventListener": "dom",
        "dom.replaceChild": "dom",
        "dom.setAttribute": "dom",
        "dom.setInnerHtml": "dom",
        "dom.setStyle": "dom",
        "dom.setStyleObject": "dom",
        "dom.setTextContent": "dom",
        "dom.toJson": "dom",
        "dom.toggleClass": "dom",
        "env.get": "environment",
        "flutter.batch": "surface",
        "flutter.op": "surface",
        "fs.append": "storage",
        "fs.delete": "storage",
        "fs.exists": "storage",
        "fs.list": "storage",
        "fs.mkdir": "storage",
        "fs.read": "storage",
        "fs.stat": "storage",
        "fs.write": "storage",
        "godot.batch": "surface",
        "godot.op": "surface",
        "gpu.define": "gpu",
        "gpu.readBuffer": "gpu",
        "gpu.submit": "gpu",
        "gpu.surfaceInfo": "gpu",
        "gpu.undefine": "gpu",
        "gpu.writeBuffer": "gpu",
        "gpu.writeTexture": "gpu",
        "host.request": "host_messaging",
        "host.send": "host_messaging",
        "kv.delete": "state",
        "kv.get": "state",
        "kv.list": "state",
        "kv.set": "state",
        "log": "logging",
        "net.close": "network",
        "net.fetch": "network",
        "net.open": "network",
        "net.recv": "network",
        "net.send": "network",
        "println": "logging",
        "random.bytes": "randomness",
        "random.next": "randomness",
        "render": "render",
        "secret.get": "state",
        "server.call": "server_call",
        "server.render": "server_call",
        "setInterval": "timers",
        "setTimeout": "timers",
        "stream.emit": "server_call",
        "stringify": "other",
        "task.init": "tasks",
        "task.join": "tasks",
        "task.poll": "tasks",
        "task.relay": "tasks",
        "task.spawn": "tasks",
        "task.stats": "tasks",
        "time.monotonic": "clock",
        "time.now": "clock",
        "updateApp": "render",
        "vm.grant": "vm_manage",
        "vm.import": "module_import",
        "vm.info": "vm_manage",
        "vm.limits": "vm_manage",
        "vm.list": "vm_manage",
        "vm.pause": "vm_manage",
        "vm.permissions": "vm_manage",
        "vm.resume": "vm_manage",
        "vm.send": "vm_manage",
        "vm.setLimits": "vm_manage",
        "vm.setPermission": "vm_manage",
        "vm.spawn": "vm_manage",
        "vm.state": "vm_manage",
        "vm.terminate": "vm_manage",
        "vm.usage": "vm_manage",
        "vm.usageTree": "vm_manage",
    ]

    /// The capability gating `apiName`, or `"other"` for a name the VM does
    /// not advertise — the fail-safe gate, never a pass.
    public static func capabilityFor(_ apiName: String) -> String {
        capabilityOf[apiName] ?? "other"
    }
}
