const SUPPORTED_MODES = new Set(['nextjs_server', 'streaming_server', 'fully_client_side']);

function normalizeMode(mode) {
  return SUPPORTED_MODES.has(mode) ? mode : 'fully_client_side';
}

function scriptingLanguageFor(mode) {
  return mode === 'streaming_server' ? 'n/a' : 'quickjs';
}

function nowIso() {
  return new Date().toISOString();
}

function packetEnvelope({ pointId, machineId, packetType, sequence, data }) {
  return {
    protocol: 'caspar.point.signal.v1',
    packetId: crypto.randomUUID(),
    sequence,
    pointId,
    machineId,
    packetType,
    timestamp: nowIso(),
    data,
  };
}

export function createMachineProgram(host) {
  if (!host?.pointSignal) {
    throw new Error('host.pointSignal(pointId, packet) must be provided by Caspar VM host imports');
  }

  let sequence = 0;
  let streamVersion = 0;

  function nextSequence() {
    sequence += 1;
    return sequence;
  }

  function send(pointId, machineId, packetType, data) {
    const packet = packetEnvelope({
      pointId,
      machineId,
      packetType,
      sequence: nextSequence(),
      data,
    });

    host.pointSignal(pointId, packet);
    return packet;
  }

  return {
    bootstrapWidget({ pointId, machineId, widgetId = 'elpian-mini-app', integrationMode }) {
      const mode = normalizeMode(integrationMode);
      const scriptingLanguage = scriptingLanguageFor(mode);

      if (host.registerMachineWidget) {
        host.registerMachineWidget({
          pointId,
          machineId,
          widgetId,
          engine: 'elpian',
          integrationMode: mode,
          scriptingLanguage,
        });
      }

      return send(pointId, machineId, 'machine.widget.attached', {
        widgetId,
        engine: 'elpian',
        integration: {
          mode,
          scriptingLanguage,
        },
        capabilities: {
          supportsUiInit: true,
          supportsUiPatch: true,
          supportsUiReplace: true,
        },
      });
    },

    initUi({ pointId, machineId, component, stylesheet = null }) {
      streamVersion += 1;
      return send(pointId, machineId, 'ui.init', {
        streamVersion,
        component,
        stylesheet,
      });
    },

    patchUi({ pointId, machineId, operations = [] }) {
      return send(pointId, machineId, 'ui.patch', {
        streamVersion,
        operations,
      });
    },

    replaceUi({ pointId, machineId, component, stylesheet = null }) {
      streamVersion += 1;
      return send(pointId, machineId, 'ui.replace', {
        streamVersion,
        component,
        stylesheet,
      });
    },
  };
}
