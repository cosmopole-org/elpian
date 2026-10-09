import { createMachineProgram } from './machine-program.js';
import { createCasparVmHostFromGlobals, createStdoutHost } from './host-adapter.js';

function env(name, fallback) {
  return process.env[name] || fallback;
}

const pointId = env('CASPAR_POINT_ID', 'point-alpha');
const machineId = env('CASPAR_MACHINE_ID', 'machine-1');
const widgetId = env('CASPAR_WIDGET_ID', 'elpian-mini-app');
const integrationMode = env('ELPIAN_INTEGRATION_MODE', 'fully_client_side');
const hostMode = env('CASPAR_HOST_MODE', 'stdout');

const host = hostMode === 'vm-imports' ? createCasparVmHostFromGlobals() : createStdoutHost();
const machine = createMachineProgram(host);

machine.bootstrapWidget({ pointId, machineId, widgetId, integrationMode });

machine.initUi({
  pointId,
  machineId,
  component: {
    type: 'div',
    style: { padding: 16 },
    children: [
      { type: 'h1', props: { text: 'Caspar VM-hosted machine' } },
      {
        type: 'p',
        props: {
          text: `Runtime mode: ${integrationMode}`,
        },
      },
    ],
  },
});

machine.patchUi({
  pointId,
  machineId,
  operations: [
    {
      op: 'add',
      path: '/children/-',
      value: {
        type: 'p',
        props: { text: 'Incremental UI patch from VM machine.' },
      },
    },
  ],
});
