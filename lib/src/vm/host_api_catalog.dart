// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Produced from the VM's own host-API list and capability mapping by:
//
//     cd rust && cargo run --bin gen-host-api-catalog -- \
//         ../lib/src/vm/host_api_catalog.dart
//
// The Rust sources are `api::all_host_apis()` (which names the VM treats
// as native askHost targets) and `Capability::for_api` (which gate each
// sits behind). Editing this file by hand reintroduces the drift it was
// written to prevent — `cargo test -p elpian-vm --test host_api_catalog`
// fails when it is stale.

/// Every host API the Elpian VM will forward to the Dart side, grouped the
/// way [HostHandler] dispatches them, plus the capability that gates each.
class VmHostApiCatalog {
  /// Rendering, environment and diagnostics: the unprefixed names the
  /// Flutter engine has always spoken.
  static const coreApiNames = <String>{
    'log',
    'println',
    'stringify',
    'render',
    'updateApp',
    'env.get',
  };

  /// Deferred work on the host clock.
  static const timerApiNames = <String>{
    'setTimeout',
    'setInterval',
    'clearTimeout',
    'clearInterval',
  };

  /// The host document tree.
  static const domApiNames = <String>{
    'dom.getElementById',
    'dom.getElementsByClassName',
    'dom.getElementsByTagName',
    'dom.querySelector',
    'dom.querySelectorAll',
    'dom.createElement',
    'dom.removeElement',
    'dom.clear',
    'dom.setTextContent',
    'dom.setInnerHtml',
    'dom.setAttribute',
    'dom.getAttribute',
    'dom.removeAttribute',
    'dom.hasAttribute',
    'dom.setStyle',
    'dom.getStyle',
    'dom.setStyleObject',
    'dom.addClass',
    'dom.removeClass',
    'dom.hasClass',
    'dom.toggleClass',
    'dom.appendChild',
    'dom.insertBefore',
    'dom.removeChild',
    'dom.replaceChild',
    'dom.addEventListener',
    'dom.removeEventListener',
    'dom.dispatchEvent',
    'dom.toJson',
    'dom.getAllElements',
  };

  /// The 2D drawing surface.
  static const canvasApiNames = <String>{
    'canvas.ctx.create',
    'canvas.ctx.dispose',
    'canvas.ctx.clear',
    'canvas.ctx.setSize',
    'canvas.ctx.addCommand',
    'canvas.ctx.addCommands',
    'canvas.addCommand',
    'canvas.addCommands',
    'canvas.clear',
    'canvas.getCommands',
    'canvas.beginPath',
    'canvas.closePath',
    'canvas.moveTo',
    'canvas.lineTo',
    'canvas.quadraticCurveTo',
    'canvas.bezierCurveTo',
    'canvas.arc',
    'canvas.arcTo',
    'canvas.ellipse',
    'canvas.rect',
    'canvas.roundRect',
    'canvas.circle',
    'canvas.fillRect',
    'canvas.strokeRect',
    'canvas.clearRect',
    'canvas.fillCircle',
    'canvas.strokeCircle',
    'canvas.fillPolygon',
    'canvas.strokePolygon',
    'canvas.fillText',
    'canvas.strokeText',
    'canvas.drawImage',
    'canvas.drawImageRect',
    'canvas.fill',
    'canvas.stroke',
    'canvas.clip',
    'canvas.save',
    'canvas.restore',
    'canvas.translate',
    'canvas.rotate',
    'canvas.scale',
    'canvas.transform',
    'canvas.setTransform',
    'canvas.resetTransform',
    'canvas.setFillStyle',
    'canvas.setStrokeStyle',
    'canvas.setLineWidth',
    'canvas.setLineCap',
    'canvas.setLineJoin',
    'canvas.setMiterLimit',
    'canvas.setLineDash',
    'canvas.setLineDashOffset',
    'canvas.setShadowBlur',
    'canvas.setShadowColor',
    'canvas.setShadowOffsetX',
    'canvas.setShadowOffsetY',
    'canvas.setGlobalAlpha',
    'canvas.setGlobalCompositeOperation',
    'canvas.setFont',
    'canvas.setTextAlign',
    'canvas.setTextBaseline',
    'canvas.createLinearGradient',
    'canvas.createRadialGradient',
    'canvas.addColorStop',
    'canvas.createPattern',
    'canvas.putImageData',
    'canvas.getImageData',
    'canvas.createImageData',
  };

  /// Outbound and inbound networking.
  static const netApiNames = <String>{
    'net.fetch',
    'net.open',
    'net.send',
    'net.recv',
    'net.close',
  };

  /// The fabricated filesystem.
  static const fsApiNames = <String>{
    'fs.read',
    'fs.write',
    'fs.append',
    'fs.delete',
    'fs.list',
    'fs.exists',
    'fs.stat',
    'fs.mkdir',
  };

  /// GPU command submission and resources.
  static const gpuApiNames = <String>{
    'gpu.submit',
    'gpu.writeBuffer',
    'gpu.writeTexture',
    'gpu.readBuffer',
    'gpu.surfaceInfo',
    'gpu.define',
    'gpu.undefine',
  };

  /// Wall-clock and monotonic time.
  static const timeApiNames = <String>{
    'time.now',
    'time.monotonic',
  };

  /// Non-deterministic randomness.
  static const randomApiNames = <String>{
    'random.next',
    'random.bytes',
  };

  /// Guest compute offloaded onto the host's worker pool.
  static const taskApiNames = <String>{
    'task.init',
    'task.spawn',
    'task.poll',
    'task.join',
    'task.relay',
    'task.stats',
  };

  /// The embedder-defined message pipe.
  static const hostMessagingApiNames = <String>{
    'host.send',
    'host.request',
  };

  /// The host's drawing surface — the op seams a guest submits UI
  /// through, whichever host is underneath.
  static const surfaceApiNames = <String>{
    'godot.op',
    'godot.batch',
    'flutter.op',
    'flutter.batch',
  };

  /// Module import and management of other VM instances.
  static const vmApiNames = <String>{
    'vm.import',
    'vm.spawn',
    'vm.pause',
    'vm.resume',
    'vm.terminate',
    'vm.state',
    'vm.usage',
    'vm.usageTree',
    'vm.limits',
    'vm.setLimits',
    'vm.permissions',
    'vm.setPermission',
    'vm.list',
    'vm.info',
    'vm.send',
    'vm.grant',
  };

  /// The complete advertised surface.
  static const allHostApiNames = <String>{
    ...coreApiNames,
    ...timerApiNames,
    ...domApiNames,
    ...canvasApiNames,
    ...netApiNames,
    ...fsApiNames,
    ...gpuApiNames,
    ...timeApiNames,
    ...randomApiNames,
    ...taskApiNames,
    ...hostMessagingApiNames,
    ...surfaceApiNames,
    ...vmApiNames,
  };

  /// The capability that gates each API, keyed by name. Mirrors
  /// `Capability::for_api` in rust/src/sdk/capabilities.rs, so the Dart
  /// host can refuse a call for the same reason the VM would.
  static const capabilityOf = <String, String>{
    'canvas.addColorStop': 'canvas',
    'canvas.addCommand': 'canvas',
    'canvas.addCommands': 'canvas',
    'canvas.arc': 'canvas',
    'canvas.arcTo': 'canvas',
    'canvas.beginPath': 'canvas',
    'canvas.bezierCurveTo': 'canvas',
    'canvas.circle': 'canvas',
    'canvas.clear': 'canvas',
    'canvas.clearRect': 'canvas',
    'canvas.clip': 'canvas',
    'canvas.closePath': 'canvas',
    'canvas.createImageData': 'canvas',
    'canvas.createLinearGradient': 'canvas',
    'canvas.createPattern': 'canvas',
    'canvas.createRadialGradient': 'canvas',
    'canvas.ctx.addCommand': 'canvas',
    'canvas.ctx.addCommands': 'canvas',
    'canvas.ctx.clear': 'canvas',
    'canvas.ctx.create': 'canvas',
    'canvas.ctx.dispose': 'canvas',
    'canvas.ctx.setSize': 'canvas',
    'canvas.drawImage': 'canvas',
    'canvas.drawImageRect': 'canvas',
    'canvas.ellipse': 'canvas',
    'canvas.fill': 'canvas',
    'canvas.fillCircle': 'canvas',
    'canvas.fillPolygon': 'canvas',
    'canvas.fillRect': 'canvas',
    'canvas.fillText': 'canvas',
    'canvas.getCommands': 'canvas',
    'canvas.getImageData': 'canvas',
    'canvas.lineTo': 'canvas',
    'canvas.moveTo': 'canvas',
    'canvas.putImageData': 'canvas',
    'canvas.quadraticCurveTo': 'canvas',
    'canvas.rect': 'canvas',
    'canvas.resetTransform': 'canvas',
    'canvas.restore': 'canvas',
    'canvas.rotate': 'canvas',
    'canvas.roundRect': 'canvas',
    'canvas.save': 'canvas',
    'canvas.scale': 'canvas',
    'canvas.setFillStyle': 'canvas',
    'canvas.setFont': 'canvas',
    'canvas.setGlobalAlpha': 'canvas',
    'canvas.setGlobalCompositeOperation': 'canvas',
    'canvas.setLineCap': 'canvas',
    'canvas.setLineDash': 'canvas',
    'canvas.setLineDashOffset': 'canvas',
    'canvas.setLineJoin': 'canvas',
    'canvas.setLineWidth': 'canvas',
    'canvas.setMiterLimit': 'canvas',
    'canvas.setShadowBlur': 'canvas',
    'canvas.setShadowColor': 'canvas',
    'canvas.setShadowOffsetX': 'canvas',
    'canvas.setShadowOffsetY': 'canvas',
    'canvas.setStrokeStyle': 'canvas',
    'canvas.setTextAlign': 'canvas',
    'canvas.setTextBaseline': 'canvas',
    'canvas.setTransform': 'canvas',
    'canvas.stroke': 'canvas',
    'canvas.strokeCircle': 'canvas',
    'canvas.strokePolygon': 'canvas',
    'canvas.strokeRect': 'canvas',
    'canvas.strokeText': 'canvas',
    'canvas.transform': 'canvas',
    'canvas.translate': 'canvas',
    'clearInterval': 'timers',
    'clearTimeout': 'timers',
    'dom.addClass': 'dom',
    'dom.addEventListener': 'dom',
    'dom.appendChild': 'dom',
    'dom.clear': 'dom',
    'dom.createElement': 'dom',
    'dom.dispatchEvent': 'dom',
    'dom.getAllElements': 'dom',
    'dom.getAttribute': 'dom',
    'dom.getElementById': 'dom',
    'dom.getElementsByClassName': 'dom',
    'dom.getElementsByTagName': 'dom',
    'dom.getStyle': 'dom',
    'dom.hasAttribute': 'dom',
    'dom.hasClass': 'dom',
    'dom.insertBefore': 'dom',
    'dom.querySelector': 'dom',
    'dom.querySelectorAll': 'dom',
    'dom.removeAttribute': 'dom',
    'dom.removeChild': 'dom',
    'dom.removeClass': 'dom',
    'dom.removeElement': 'dom',
    'dom.removeEventListener': 'dom',
    'dom.replaceChild': 'dom',
    'dom.setAttribute': 'dom',
    'dom.setInnerHtml': 'dom',
    'dom.setStyle': 'dom',
    'dom.setStyleObject': 'dom',
    'dom.setTextContent': 'dom',
    'dom.toJson': 'dom',
    'dom.toggleClass': 'dom',
    'env.get': 'environment',
    'flutter.batch': 'surface',
    'flutter.op': 'surface',
    'fs.append': 'storage',
    'fs.delete': 'storage',
    'fs.exists': 'storage',
    'fs.list': 'storage',
    'fs.mkdir': 'storage',
    'fs.read': 'storage',
    'fs.stat': 'storage',
    'fs.write': 'storage',
    'godot.batch': 'surface',
    'godot.op': 'surface',
    'gpu.define': 'gpu',
    'gpu.readBuffer': 'gpu',
    'gpu.submit': 'gpu',
    'gpu.surfaceInfo': 'gpu',
    'gpu.undefine': 'gpu',
    'gpu.writeBuffer': 'gpu',
    'gpu.writeTexture': 'gpu',
    'host.request': 'host_messaging',
    'host.send': 'host_messaging',
    'log': 'logging',
    'net.close': 'network',
    'net.fetch': 'network',
    'net.open': 'network',
    'net.recv': 'network',
    'net.send': 'network',
    'println': 'logging',
    'random.bytes': 'randomness',
    'random.next': 'randomness',
    'render': 'render',
    'setInterval': 'timers',
    'setTimeout': 'timers',
    'stringify': 'other',
    'task.init': 'tasks',
    'task.join': 'tasks',
    'task.poll': 'tasks',
    'task.relay': 'tasks',
    'task.spawn': 'tasks',
    'task.stats': 'tasks',
    'time.monotonic': 'clock',
    'time.now': 'clock',
    'updateApp': 'render',
    'vm.grant': 'vm_manage',
    'vm.import': 'module_import',
    'vm.info': 'vm_manage',
    'vm.limits': 'vm_manage',
    'vm.list': 'vm_manage',
    'vm.pause': 'vm_manage',
    'vm.permissions': 'vm_manage',
    'vm.resume': 'vm_manage',
    'vm.send': 'vm_manage',
    'vm.setLimits': 'vm_manage',
    'vm.setPermission': 'vm_manage',
    'vm.spawn': 'vm_manage',
    'vm.state': 'vm_manage',
    'vm.terminate': 'vm_manage',
    'vm.usage': 'vm_manage',
    'vm.usageTree': 'vm_manage',
  };

  /// The capability gating [apiName], or `'other'` for a name the VM does
  /// not advertise — the fail-safe gate, never a pass.
  static String capabilityFor(String apiName) =>
      capabilityOf[apiName] ?? 'other';
}
