// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Produced from the VM's own host-API list and capability mapping by:
//
//     cd rust && cargo run --bin gen-host-api-catalog -- \
//         ../native/android/elpian-core/src/main/kotlin/dev/elpian/core/vm/HostApiCatalog.kt
//
// The Kotlin twin of native/web/src/vm/host-api-catalog.ts;
// `cargo test -p elpian-vm --test host_api_catalog` fails when it is stale.

package dev.elpian.core.vm

/** Rendering, environment and diagnostics: the unprefixed names the
 * Flutter engine has always spoken. */
val coreApiNames: Set<String> = linkedSetOf(
  "log",
  "println",
  "stringify",
  "render",
  "updateApp",
  "env.get",
)

/** Deferred work on the host clock. */
val timerApiNames: Set<String> = linkedSetOf(
  "setTimeout",
  "setInterval",
  "clearTimeout",
  "clearInterval",
)

/** The host document tree. */
val domApiNames: Set<String> = linkedSetOf(
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
)

/** The 2D drawing surface. */
val canvasApiNames: Set<String> = linkedSetOf(
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
)

/** Outbound and inbound networking. */
val netApiNames: Set<String> = linkedSetOf(
  "net.fetch",
  "net.open",
  "net.send",
  "net.recv",
  "net.close",
)

/** The fabricated filesystem. */
val fsApiNames: Set<String> = linkedSetOf(
  "fs.read",
  "fs.write",
  "fs.append",
  "fs.delete",
  "fs.list",
  "fs.exists",
  "fs.stat",
  "fs.mkdir",
)

/** GPU command submission and resources. */
val gpuApiNames: Set<String> = linkedSetOf(
  "gpu.submit",
  "gpu.writeBuffer",
  "gpu.writeTexture",
  "gpu.readBuffer",
  "gpu.surfaceInfo",
  "gpu.define",
  "gpu.undefine",
)

/** Wall-clock and monotonic time. */
val timeApiNames: Set<String> = linkedSetOf(
  "time.now",
  "time.monotonic",
)

/** Non-deterministic randomness. */
val randomApiNames: Set<String> = linkedSetOf(
  "random.next",
  "random.bytes",
)

/** Guest compute offloaded onto the host's worker pool. */
val taskApiNames: Set<String> = linkedSetOf(
  "task.init",
  "task.spawn",
  "task.poll",
  "task.join",
  "task.relay",
  "task.stats",
)

/** The embedder-defined message pipe. */
val hostMessagingApiNames: Set<String> = linkedSetOf(
  "host.send",
  "host.request",
)

/** The host's drawing surface — the op seams a guest submits UI
 * through, whichever host is underneath. */
val surfaceApiNames: Set<String> = linkedSetOf(
  "godot.op",
  "godot.batch",
  "flutter.op",
  "flutter.batch",
)

/** A mini app calling its own server functions. Separate from the
 * network: an app in a closed posture holds no network at all and
 * still reaches its own backend through these. */
val serverApiNames: Set<String> = linkedSetOf(
  "server.call",
  "server.render",
  "stream.emit",
)

/** Durable per-app key/value state, and the secrets a server
 * function may read. */
val stateApiNames: Set<String> = linkedSetOf(
  "kv.get",
  "kv.set",
  "kv.delete",
  "kv.list",
  "secret.get",
  "cache.revalidate",
  "ctx.user",
)

/** Module import and management of other VM instances. */
val vmApiNames: Set<String> = linkedSetOf(
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
)

/** The complete advertised surface. */
val allHostApiNames: Set<String> = LinkedHashSet<String>().apply {
  addAll(coreApiNames)
  addAll(timerApiNames)
  addAll(domApiNames)
  addAll(canvasApiNames)
  addAll(netApiNames)
  addAll(fsApiNames)
  addAll(gpuApiNames)
  addAll(timeApiNames)
  addAll(randomApiNames)
  addAll(taskApiNames)
  addAll(hostMessagingApiNames)
  addAll(surfaceApiNames)
  addAll(serverApiNames)
  addAll(stateApiNames)
  addAll(vmApiNames)
}

/** The capability that gates each API (`Capability::for_api`). */
val capabilityOf: Map<String, String> = linkedMapOf(
  "cache.revalidate" to "state",
  "canvas.addColorStop" to "canvas",
  "canvas.addCommand" to "canvas",
  "canvas.addCommands" to "canvas",
  "canvas.arc" to "canvas",
  "canvas.arcTo" to "canvas",
  "canvas.beginPath" to "canvas",
  "canvas.bezierCurveTo" to "canvas",
  "canvas.circle" to "canvas",
  "canvas.clear" to "canvas",
  "canvas.clearRect" to "canvas",
  "canvas.clip" to "canvas",
  "canvas.closePath" to "canvas",
  "canvas.createImageData" to "canvas",
  "canvas.createLinearGradient" to "canvas",
  "canvas.createPattern" to "canvas",
  "canvas.createRadialGradient" to "canvas",
  "canvas.ctx.addCommand" to "canvas",
  "canvas.ctx.addCommands" to "canvas",
  "canvas.ctx.clear" to "canvas",
  "canvas.ctx.create" to "canvas",
  "canvas.ctx.dispose" to "canvas",
  "canvas.ctx.setSize" to "canvas",
  "canvas.drawImage" to "canvas",
  "canvas.drawImageRect" to "canvas",
  "canvas.ellipse" to "canvas",
  "canvas.fill" to "canvas",
  "canvas.fillCircle" to "canvas",
  "canvas.fillPolygon" to "canvas",
  "canvas.fillRect" to "canvas",
  "canvas.fillText" to "canvas",
  "canvas.getCommands" to "canvas",
  "canvas.getImageData" to "canvas",
  "canvas.lineTo" to "canvas",
  "canvas.moveTo" to "canvas",
  "canvas.putImageData" to "canvas",
  "canvas.quadraticCurveTo" to "canvas",
  "canvas.rect" to "canvas",
  "canvas.resetTransform" to "canvas",
  "canvas.restore" to "canvas",
  "canvas.rotate" to "canvas",
  "canvas.roundRect" to "canvas",
  "canvas.save" to "canvas",
  "canvas.scale" to "canvas",
  "canvas.setFillStyle" to "canvas",
  "canvas.setFont" to "canvas",
  "canvas.setGlobalAlpha" to "canvas",
  "canvas.setGlobalCompositeOperation" to "canvas",
  "canvas.setLineCap" to "canvas",
  "canvas.setLineDash" to "canvas",
  "canvas.setLineDashOffset" to "canvas",
  "canvas.setLineJoin" to "canvas",
  "canvas.setLineWidth" to "canvas",
  "canvas.setMiterLimit" to "canvas",
  "canvas.setShadowBlur" to "canvas",
  "canvas.setShadowColor" to "canvas",
  "canvas.setShadowOffsetX" to "canvas",
  "canvas.setShadowOffsetY" to "canvas",
  "canvas.setStrokeStyle" to "canvas",
  "canvas.setTextAlign" to "canvas",
  "canvas.setTextBaseline" to "canvas",
  "canvas.setTransform" to "canvas",
  "canvas.stroke" to "canvas",
  "canvas.strokeCircle" to "canvas",
  "canvas.strokePolygon" to "canvas",
  "canvas.strokeRect" to "canvas",
  "canvas.strokeText" to "canvas",
  "canvas.transform" to "canvas",
  "canvas.translate" to "canvas",
  "clearInterval" to "timers",
  "clearTimeout" to "timers",
  "ctx.user" to "state",
  "dom.addClass" to "dom",
  "dom.addEventListener" to "dom",
  "dom.appendChild" to "dom",
  "dom.clear" to "dom",
  "dom.createElement" to "dom",
  "dom.dispatchEvent" to "dom",
  "dom.getAllElements" to "dom",
  "dom.getAttribute" to "dom",
  "dom.getElementById" to "dom",
  "dom.getElementsByClassName" to "dom",
  "dom.getElementsByTagName" to "dom",
  "dom.getStyle" to "dom",
  "dom.hasAttribute" to "dom",
  "dom.hasClass" to "dom",
  "dom.insertBefore" to "dom",
  "dom.querySelector" to "dom",
  "dom.querySelectorAll" to "dom",
  "dom.removeAttribute" to "dom",
  "dom.removeChild" to "dom",
  "dom.removeClass" to "dom",
  "dom.removeElement" to "dom",
  "dom.removeEventListener" to "dom",
  "dom.replaceChild" to "dom",
  "dom.setAttribute" to "dom",
  "dom.setInnerHtml" to "dom",
  "dom.setStyle" to "dom",
  "dom.setStyleObject" to "dom",
  "dom.setTextContent" to "dom",
  "dom.toJson" to "dom",
  "dom.toggleClass" to "dom",
  "env.get" to "environment",
  "flutter.batch" to "surface",
  "flutter.op" to "surface",
  "fs.append" to "storage",
  "fs.delete" to "storage",
  "fs.exists" to "storage",
  "fs.list" to "storage",
  "fs.mkdir" to "storage",
  "fs.read" to "storage",
  "fs.stat" to "storage",
  "fs.write" to "storage",
  "godot.batch" to "surface",
  "godot.op" to "surface",
  "gpu.define" to "gpu",
  "gpu.readBuffer" to "gpu",
  "gpu.submit" to "gpu",
  "gpu.surfaceInfo" to "gpu",
  "gpu.undefine" to "gpu",
  "gpu.writeBuffer" to "gpu",
  "gpu.writeTexture" to "gpu",
  "host.request" to "host_messaging",
  "host.send" to "host_messaging",
  "kv.delete" to "state",
  "kv.get" to "state",
  "kv.list" to "state",
  "kv.set" to "state",
  "log" to "logging",
  "net.close" to "network",
  "net.fetch" to "network",
  "net.open" to "network",
  "net.recv" to "network",
  "net.send" to "network",
  "println" to "logging",
  "random.bytes" to "randomness",
  "random.next" to "randomness",
  "render" to "render",
  "secret.get" to "state",
  "server.call" to "server_call",
  "server.render" to "server_call",
  "setInterval" to "timers",
  "setTimeout" to "timers",
  "stream.emit" to "server_call",
  "stringify" to "other",
  "task.init" to "tasks",
  "task.join" to "tasks",
  "task.poll" to "tasks",
  "task.relay" to "tasks",
  "task.spawn" to "tasks",
  "task.stats" to "tasks",
  "time.monotonic" to "clock",
  "time.now" to "clock",
  "updateApp" to "render",
  "vm.grant" to "vm_manage",
  "vm.import" to "module_import",
  "vm.info" to "vm_manage",
  "vm.limits" to "vm_manage",
  "vm.list" to "vm_manage",
  "vm.pause" to "vm_manage",
  "vm.permissions" to "vm_manage",
  "vm.resume" to "vm_manage",
  "vm.send" to "vm_manage",
  "vm.setLimits" to "vm_manage",
  "vm.setPermission" to "vm_manage",
  "vm.spawn" to "vm_manage",
  "vm.state" to "vm_manage",
  "vm.terminate" to "vm_manage",
  "vm.usage" to "vm_manage",
  "vm.usageTree" to "vm_manage",
)

/** The capability gating [apiName], or `"other"` for a name the VM does not
 * advertise — the fail-safe gate, never a pass. */
fun capabilityFor(apiName: String): String = capabilityOf[apiName] ?: "other"
