import 'package:elpian_ui/elpian_ui.dart';
// flutter_test also exports an `EventDispatcher` (its pointer-event helper),
// so Elpian's is reached through a prefix here.
import 'package:elpian_ui/src/core/event_dispatcher.dart' as ed;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Per-mini-app isolation and the nesting rules.
///
/// The host used to have no unit of isolation at all: the widget registry,
/// event dispatcher, event bus, stylesheet manager and canvas store were
/// process-wide singletons that every `ElpianEngine` shared, so mini apps could
/// read and overwrite each other's state through the ordinary host APIs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('services are per mini app', () {
    test('two mini apps do not share a widget registry', () {
      final a = ElpianServices(appId: 'app-a');
      final b = ElpianServices(appId: 'app-b');

      a.registry.register('custom', (node, children) => const SizedBox());

      expect(a.registry.has('custom'), isTrue);
      expect(b.registry.has('custom'), isFalse,
          reason:
              'one mini app must not be able to define widgets for another');
    });

    test('two mini apps do not share stylesheets', () {
      final a = ElpianServices(appId: 'app-a');
      final b = ElpianServices(appId: 'app-b');

      a.stylesheets.global.addRule('.card', {'color': '#ff0000'});

      expect(
          a.stylesheets.getComputedStyleMap(tagName: 'div', classes: ['card']),
          isNotEmpty);
      expect(
          b.stylesheets.getComputedStyleMap(tagName: 'div', classes: ['card']),
          isEmpty,
          reason: "one mini app's CSS must not restyle another's tree");
    });

    test('two mini apps do not share an event dispatcher', () {
      final a = ElpianServices(appId: 'app-a');
      final b = ElpianServices(appId: 'app-b');

      ElpianEvent? sawInA;
      ElpianEvent? sawInB;
      a.events.globalEventHandler = (e) => sawInA = e;
      b.events.globalEventHandler = (e) => sawInB = e;

      a.events.dispatchChange('field', 'secret');

      expect(sawInA, isNotNull);
      expect(sawInB, isNull,
          reason: "a global handler must not receive another app's events");

      a.events.globalEventHandler = null;
      b.events.globalEventHandler = null;
    });

    test('a canvas id chosen by one app cannot fetch another app’s context',
        () {
      // The leak this closes: the store was global and keyed by an id the
      // *guest* supplies, and `create` returned the existing context when the
      // id was taken. Asking for an obvious name got you someone else's pixels.
      final a = ElpianServices(appId: 'app-a');
      final b = ElpianServices(appId: 'app-b');

      a.canvasContexts.create(id: a.scopeId('main'), width: 100, height: 100);

      expect(a.canvasContexts.get(a.scopeId('main')), isNotNull);
      expect(b.canvasContexts.get(b.scopeId('main')), isNull);
      expect(a.canvasContexts.get(b.scopeId('main')), isNull,
          reason: 'namespacing keeps a collision inside one app');
    });

    test('an engine renders against its own services', () {
      final services = ElpianServices(appId: 'app-a');
      final engine = ElpianEngine(services: services);

      engine.loadStylesheet({
        'rules': [
          {
            'selector': '.tinted',
            'styles': {'color': '#00ff00'}
          },
        ],
      });

      expect(
        services.stylesheets
            .getComputedStyleMap(tagName: 'div', classes: ['tinted']),
        isNotEmpty,
      );
      expect(
        ElpianServices.shared.stylesheets
            .getComputedStyleMap(tagName: 'div', classes: ['tinted']),
        isEmpty,
        reason: 'a scoped engine must not write into the shared set',
      );
    });

    test('the default engine still uses the shared services', () {
      // The single-app path must behave exactly as it did when these were
      // singletons, or every existing embedder breaks.
      expect(ElpianEngine().services, same(ElpianServices.shared));
      expect(ElpianServices.shared.events, same(ed.EventDispatcher.shared));
      expect(ElpianServices.shared.stylesheets,
          same(GlobalStylesheetManager.shared));
    });

    test('a scope is restored even when a render throws', () {
      final services = ElpianServices(appId: 'app-a');
      expect(
        () => services.runScoped(() => throw StateError('render blew up')),
        throwsStateError,
      );
      expect(ElpianServices.current, same(ElpianServices.shared),
          reason: 'a failed render must not leave its scope installed');
    });
  });

  group('policy resolution', () {
    const manifest = MiniAppManifest(
      id: 'weather',
      name: 'Weather',
      requestedCapabilities: {
        ElpianCapability.render,
        ElpianCapability.network,
        ElpianCapability.storage,
      },
    );

    test('an app gets no more than it was granted', () {
      final policy = MiniAppPolicy.resolve(manifest, MiniAppGrant.untrusted);

      expect(policy.capabilities, contains(ElpianCapability.render));
      expect(policy.capabilities, isNot(contains(ElpianCapability.network)));
      expect(policy.deniedRequests,
          containsAll([ElpianCapability.network, ElpianCapability.storage]));
    });

    test('an app gets no more than it asked for', () {
      // Least privilege: a generous grant does not silently widen an app that
      // only asked to draw itself.
      const modest = MiniAppManifest(
        id: 'clock',
        name: 'Clock',
        requestedCapabilities: {ElpianCapability.render},
      );
      final policy = MiniAppPolicy.resolve(modest, MiniAppGrant.trusted);

      expect(policy.capabilities, {ElpianCapability.render});
      expect(policy.capabilities, isNot(contains(ElpianCapability.network)));
      expect(policy.deniedRequests, isEmpty);
    });

    test('an app that requests nothing gets what it was granted', () {
      // Omitting the field is not the same as asking for nothing — that would
      // launch every simple app with no capabilities and fail confusingly.
      const silent = MiniAppManifest(id: 'blank', name: 'Blank');
      final policy = MiniAppPolicy.resolve(silent, MiniAppGrant.untrusted);
      expect(policy.capabilities, MiniAppGrant.untrusted.capabilities);
    });

    test('the tighter budget wins on every axis', () {
      const greedy = MiniAppManifest(
        id: 'greedy',
        name: 'Greedy',
        requestedLimits: ElpianLimits(
          maxInstructions: 999999999,
          maxMemoryBytes: 1024,
        ),
      );
      final policy = MiniAppPolicy.resolve(greedy, MiniAppGrant.untrusted);

      expect(
          policy.limits.maxInstructions, ElpianLimits.sandboxed.maxInstructions,
          reason: 'the grant is tighter here');
      expect(policy.limits.maxMemoryBytes, 1024,
          reason: 'the request is tighter here');
    });

    test('an API allowlist narrows further than a capability', () {
      const grant = MiniAppGrant(
        capabilities: {ElpianCapability.network},
        limits: ElpianLimits.sandboxed,
        allowedApis: {'net.fetch'},
      );
      const netApp = MiniAppManifest(
        id: 'net',
        name: 'Net',
        requestedCapabilities: {ElpianCapability.network},
      );
      final policy = MiniAppPolicy.resolve(netApp, grant);

      expect(policy.allowsApi('net.fetch', ElpianCapability.network), isTrue);
      expect(policy.allowsApi('net.open', ElpianCapability.network), isFalse,
          reason:
              'holding the capability is not the same as holding every API');
    });

    test('nesting needs the manifest, the grant and the capability', () {
      const wantsChildren = MiniAppManifest(
        id: 'shell',
        name: 'Shell',
        allowsChildren: true,
        requestedCapabilities: {ElpianCapability.vmManage},
      );

      expect(
        MiniAppPolicy.resolve(wantsChildren, MiniAppGrant.trusted)
            .mayHostChildren,
        isTrue,
      );
      expect(
        MiniAppPolicy.resolve(wantsChildren, MiniAppGrant.untrusted)
            .mayHostChildren,
        isFalse,
        reason: 'an untrusted app may not spend the parent budget on children',
      );

      const noDeclare = MiniAppManifest(
        id: 'shell2',
        name: 'Shell',
        requestedCapabilities: {ElpianCapability.vmManage},
      );
      expect(
        MiniAppPolicy.resolve(noDeclare, MiniAppGrant.trusted).mayHostChildren,
        isFalse,
        reason: 'an app that never declared nesting does not get it implicitly',
      );
    });

    test('a manifest that could forge a namespace is rejected', () {
      const forger = MiniAppManifest(id: 'a::b', name: 'Forger');
      expect(forger.validate(), isNotNull);
      expect(const MiniAppManifest(id: '', name: 'Nameless').validate(),
          isNotNull);
      expect(const MiniAppManifest(id: 'ok', name: 'Fine').validate(), isNull);
    });

    test('a manifest round-trips through JSON', () {
      final json = manifest.toJson();
      final parsed = MiniAppManifest.fromJson(json);
      expect(parsed.id, manifest.id);
      expect(parsed.requestedCapabilities, manifest.requestedCapabilities);
    });

    test('an unknown capability name in a manifest is dropped, not fatal', () {
      final parsed = MiniAppManifest.fromJson({
        'id': 'future',
        'name': 'Future',
        'requestedCapabilities': ['render', 'quantum_entanglement'],
      });
      expect(parsed.requestedCapabilities, {ElpianCapability.render},
          reason: 'dropping can only narrow, which is the safe direction');
    });
  });
}
