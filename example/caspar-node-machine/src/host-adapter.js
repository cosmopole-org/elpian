export function createCasparVmHostFromGlobals() {
  const pointSignal = globalThis.casparPointSignal;
  const registerMachineWidget = globalThis.casparRegisterMachineWidget;

  if (typeof pointSignal !== 'function') {
    throw new Error(
      'Missing host import casparPointSignal(pointId, packet). Run this program inside Caspar VM with imported host functions.',
    );
  }

  return {
    pointSignal,
    registerMachineWidget: typeof registerMachineWidget === 'function' ? registerMachineWidget : undefined,
  };
}

export function createStdoutHost() {
  return {
    pointSignal(pointId, packet) {
      process.stdout.write(JSON.stringify({ kind: 'point-signal', pointId, packet }) + '\n');
    },
    registerMachineWidget(payload) {
      process.stdout.write(JSON.stringify({ kind: 'register-widget', payload }) + '\n');
    },
  };
}
