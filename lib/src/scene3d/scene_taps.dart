/// Global hook for taps on interactive 3D scene nodes.
///
/// The game server marks tappable nodes (buildings, empty construction slots)
/// with `props: {clickable: true, panelHref: "/buildings/<id>", ...}`.
/// [GameSceneWidget] hit-tests those nodes on tap and, on a successful pick,
/// invokes [ElpianSceneTaps.handler] with the node's raw `props` map.
///
/// The hook is process-global on purpose: the scene widget is mounted deep
/// inside server-rendered UI trees with no practical way to thread a callback
/// down to it. Integrations that want default behaviour (e.g.
/// `NextjsServerWidget` navigating to `panelHref`) install a handler only when
/// none is set, so an app-provided handler is never clobbered.
library;

/// See library docs. Set [handler] to receive the `props` of tapped scene
/// nodes; set it back to null to uninstall.
class ElpianSceneTaps {
  ElpianSceneTaps._();

  /// Called with the tapped node's raw `props` map (e.g.
  /// `{clickable: true, panelHref: '/buildings/12', buildingId: 12}`).
  static void Function(Map<String, dynamic> props)? handler;
}
