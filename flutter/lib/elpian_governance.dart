/// Elpian's control plane: what a mini app may do, how much it may spend, and
/// whether it runs at all.
///
/// Import this on its own when you are writing the *super app* — the shell that
/// decides policy — rather than rendering UI:
///
/// ```dart
/// import 'package:elpian_ui/elpian_governance.dart';
///
/// final host = await MiniAppHost.launch(
///   manifest: MiniAppManifest.fromJson(manifestJson),
///   grant: MiniAppGrant.untrusted,
///   source: program,
/// );
/// final pressure = await host.pressure();
/// ```
///
/// Everything here is also exported from `elpian_ui.dart`; this entrypoint
/// exists so a policy layer does not have to pull in 200 widget classes to
/// reach a capability enum.
library;

// What a mini app is, what it may be granted, and what it actually gets.
export 'src/superapp/mini_app.dart';
export 'src/superapp/mini_app_host.dart';

// The governance model itself: limits, meters, capabilities, lifecycle, tree.
export 'src/vm/governance/models.dart';
export 'src/vm/governance/governor.dart';
export 'src/vm/governance/elpian_governor.dart';
export 'src/vm/governance/host_side_governor.dart';

// Which host APIs exist and which capability gates each.
export 'src/vm/host_api_catalog.dart';

// Per-mini-app host state — the unit of isolation policy is enforced against.
export 'src/core/elpian_services.dart';
