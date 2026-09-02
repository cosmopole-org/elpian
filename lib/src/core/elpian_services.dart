/// The host-side state one mini app owns.
///
/// # Why this exists
///
/// The widget registry, event dispatcher, event bus, stylesheet manager and
/// canvas store were all process-wide singletons. `ElpianEngine()` constructed
/// what looked like an isolated engine, but every instance shared the same
/// five objects, so in a super app hosting several mini apps:
///
///   * one mini app could overwrite another's custom widget builders;
///   * a global event handler received every other mini app's events;
///   * CSS rules loaded by one applied to all of them;
///   * and a canvas context created under a guessable id could be handed to
///     whoever asked for that id next.
///
/// None of that was reachable from the guest sandbox — the VM gates `askHost`
/// — but all of it was reachable through the host APIs the Flutter path
/// services, which had no gate of their own. There was no unit of isolation in
/// the host to enforce anything *against*.
///
/// [ElpianServices] is that unit. Each mini app host owns one; nothing is
/// shared unless a host deliberately shares it.
///
/// # How widgets reach it
///
/// Widget builders have the signature `Widget Function(ElpianNode, List<Widget>)`
/// — no `BuildContext`, so an `InheritedWidget` cannot be looked up from
/// inside one. Instead the engine installs its services as [current] for the
/// duration of a render, and builders capture what they need **at build time**
/// into their callbacks:
///
/// ```dart
/// // Right: bound to the mini app that built this widget.
/// final events = ElpianServices.current.events;
/// onChanged: (v) => events.dispatchChange(id, v),
///
/// // Wrong: resolved when the user taps, in whatever scope happens to be
/// // current then.
/// onChanged: (v) => ElpianServices.current.events.dispatchChange(id, v),
/// ```
///
/// Capture-at-build is what makes this correct: a Flutter callback fires long
/// after the render that created it, in the root zone, so anything resolved at
/// dispatch time would find the wrong mini app — or the shared fallback.
library;

import '../canvas/canvas_context_store.dart';
import '../css/stylesheet.dart';
import 'event_dispatcher.dart';
import 'event_system.dart';
import 'widget_registry.dart';

/// The services one mini app owns.
class ElpianServices {
  ElpianServices({
    String? appId,
    WidgetRegistry? registry,
    EventDispatcher? events,
    EventBus? eventBus,
    GlobalStylesheetManager? stylesheets,
    CanvasContextStore? canvasContexts,
  })  : appId = appId ?? 'default',
        registry = registry ?? WidgetRegistry(),
        events = events ?? EventDispatcher(),
        eventBus = eventBus ?? EventBus(),
        stylesheets = stylesheets ?? GlobalStylesheetManager(),
        canvasContexts = canvasContexts ?? CanvasContextStore();

  /// Which mini app these services belong to. Used to namespace host-side
  /// resources so an id collision cannot cross an app boundary.
  final String appId;

  /// Widget builders, including any this mini app registered itself.
  final WidgetRegistry registry;

  /// DOM-style event delivery for this mini app's tree.
  final EventDispatcher events;

  /// This mini app's pub/sub bus.
  final EventBus eventBus;

  /// This mini app's stylesheets and computed-style cache.
  final GlobalStylesheetManager stylesheets;

  /// This mini app's 2D drawing contexts.
  final CanvasContextStore canvasContexts;

  /// The services every un-scoped caller sees.
  ///
  /// Built from each service's own `shared` instance, so "the shared set" and
  /// "the shared dispatcher" are the same object rather than two rivals — code
  /// reaching for `EventDispatcher.shared` directly and code going through
  /// `ElpianServices.current` must land on the same place.
  ///
  /// A single-app embedder never has to think about this: the default
  /// [ElpianEngine] uses it, and behaviour is exactly what it was when these
  /// were singletons. A super app gives each mini app its own set instead.
  static final ElpianServices shared = ElpianServices(
    appId: 'shared',
    registry: WidgetRegistry.shared,
    events: EventDispatcher.shared,
    eventBus: EventBus.shared,
    stylesheets: GlobalStylesheetManager.shared,
    canvasContexts: CanvasContextStore.shared,
  );

  static ElpianServices _current = shared;

  /// The services in scope right now.
  ///
  /// Set for the duration of a render by [runScoped]. Outside a render this is
  /// [shared], which is what makes the single-app path work unchanged.
  static ElpianServices get current => _current;

  /// Run [body] with these services installed as [current].
  ///
  /// Restores the previous scope on the way out, including when [body] throws,
  /// so one mini app failing to render cannot leave its services installed for
  /// the next one.
  T runScoped<T>(T Function() body) {
    final previous = _current;
    _current = this;
    try {
      return body();
    } finally {
      _current = previous;
    }
  }

  /// Namespace a host-supplied resource id to this mini app.
  ///
  /// Guests choose their own ids (`canvas.ctx.create(id: "main")`), so two mini
  /// apps will collide on the obvious names. Prefixing with [appId] means a
  /// collision stays inside one app instead of handing it another's pixels.
  String scopeId(String id) => '$appId::$id';

  /// Release everything this mini app holds. Called when it is torn down.
  void dispose() {
    registry.clear();
    events.clear();
    eventBus.removeAllEventListeners();
    stylesheets.clear();
    canvasContexts.clearAll();
  }

  @override
  String toString() => 'ElpianServices($appId)';
}
