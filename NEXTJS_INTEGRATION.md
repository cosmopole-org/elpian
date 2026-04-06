# Next.js + Elpian Integration (Black-Box Client)

Elpian now includes a **black-box Next.js client**: developers only provide a Next.js server base URL and route, then `NextjsServerWidget` handles:

- route requests
- Next.js payload loading
- client-side navigation between child routes
- server redirect/back/refresh commands
- rendering of returned Elpian component/style payloads

## Minimal usage (no extra config)

```dart
import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';

class MiniAppShell extends StatelessWidget {
  const MiniAppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const NextjsServerWidget(
      serverBaseUrl: 'https://mini.example.com',
      route: '/',
    );
  }
}
```

Default behavior uses route-path requests (normal Next.js style): route `/profile` -> `GET https://your-server/profile`.

## Request modes

`NextjsServerWidget` supports two request styles:

1. `NextjsServerRequestMode.routePath` (default): fetch each route directly as a normal Next.js route.
2. `NextjsServerRequestMode.apiEndpoint`: use one API endpoint (legacy/fallback).

```dart
const NextjsServerWidget(
  serverBaseUrl: 'https://mini.example.com',
  route: '/',
  requestMode: NextjsServerRequestMode.apiEndpoint,
  endpoint: '/api/elpian-render',
);
```

## Payload contract

```json
{
  "component": {
    "type": "div",
    "style": {"padding": 20},
    "children": [
      {"type": "h1", "props": {"text": "Hello"}},
      {
        "type": "NextjsLink",
        "props": {"text": "Go profile", "href": "/profile"}
      }
    ]
  },
  "stylesheet": {
    "rules": [
      {"selector": "h1", "styles": {"color": "#3366FF"}}
    ]
  },
  "meta": {
    "route": "/"
  },
  "navigation": {
    "redirectTo": "/auth/login",
    "replace": true
  },
  "jsCode": "function MainComponent(){ const ui={type:\"div\",children:[{type:\"h1\",props:{text:\"JS Component\"}}]}; askHost(\"render\", JSON.stringify(ui)); return JSON.stringify(ui); }",
  "jsEntryFunction": "MainComponent",
  "vmAstJson": "{\"type\":\"program\",\"body\":[]}"
}
```

### Fields

- `component` **(required)**: Elpian UI JSON node tree.
- `stylesheet` *(optional)*: Elpian JSON stylesheet.
- `meta` *(optional)*: metadata.
- `navigation` *(optional)*: server-side navigation command.
  - `redirectTo: string`
  - `replace: bool`
  - `back: bool`
  - `refresh: bool`
- `jsCode` *(optional)*: JavaScript source executed on client via QuickJS.
- `jsEntryFunction` *(optional)*: JS function called after load (default: `MainComponent`).
- `vmAstJson` *(optional)*: Elpian VM AST JSON executed on client VM.

## Server-side navigation commands

The server can control navigation by returning `navigation`:

- redirect to new route: `{ "redirectTo": "/home" }`
- replace current route: `{ "redirectTo": "/login", "replace": true }`
- go back: `{ "back": true }`
- refresh current route: `{ "refresh": true }`


## `clientComp` pattern with inline `jsCode`

Instead of sending a path, return `clientComp` nodes with JS source inline:

```json
{
  "component": {
    "type": "clientComp",
    "jsCode": "function MainComponent(props){ const ui={type:'div',children:[{type:'h1',props:{text:'Hello '+props.userName}}]}; askHost('render', JSON.stringify(ui)); return JSON.stringify(ui); }",
    "props": {
      "userName": "Elpian"
    }
  }
}
```

`NextjsServerWidget` executes the provided JS text and calls `MainComponent(props)` (or `jsEntryFunction`).

## Client script execution


Example JS file at `/components/ProfileHeader.js`:

```js
function MainComponent(props) {
  const ui = {
    type: "div",
    children: [
      { type: "h1", props: { text: `Hello ${props.userName}` } }
    ]
  };

  // Trigger Elpian host render
  askHost("render", JSON.stringify(ui));

  // Optional extra JS logic can run here
  return JSON.stringify(ui);
}
```

If a response includes `jsCode`, `NextjsServerWidget` first loads that JS into QuickJS, then calls `MainComponent` (or `jsEntryFunction` if provided). Inside that function, call `askHost("render", JSON.stringify(uiJson))` to push UI DSL to Elpian rendering, and you can still run any additional JS logic.

If a response includes `vmAstJson`, the Elpian VM AST is executed similarly, and host `render` calls are also captured for UI rendering.

You can observe outputs with `onScriptExecuted` and errors with `onScriptError`.

```dart
NextjsServerWidget(
  serverBaseUrl: 'https://mini.example.com',
  route: '/',
  onScriptExecuted: (result) {
    debugPrint('script [\${result.kind}] => \${result.output}');
  },
  onScriptError: (error, stack) {
    debugPrint('script error: \$error');
  },
);
```

## Built-in navigation component

`NextjsBridge` auto-registers `NextjsLink` / `next-link` widgets. Example in payload:

```json
{
  "type": "NextjsLink",
  "props": {
    "text": "Settings",
    "href": "/settings",
    "replace": false
  }
}
```

When tapped, the widget asks `NextjsServerWidget` to load that route from Next.js.

## Suggested Next.js route behavior (normal mode)

In normal mode, you can keep **multiple route handlers/components** instead of one central POST API.

```ts
// app/profile/route.ts
import { NextResponse } from 'next/server';

export async function GET() {
  return NextResponse.json({
    component: {
      type: 'div',
      children: [
        { type: 'h1', props: { text: 'Profile' } },
        { type: 'NextjsLink', props: { text: 'Settings', href: '/settings' } }
      ]
    }
  });
}
```

```ts
// app/settings/route.ts
import { NextResponse } from 'next/server';

export async function GET() {
  return NextResponse.json({
    component: {
      type: 'div',
      children: [
        { type: 'h1', props: { text: 'Settings' } },
        { type: 'NextjsLink', props: { text: 'Back profile', href: '/profile' } }
      ]
    }
  });
}
```

This lets each route own its own server logic like a regular Next.js app.

## Advanced override (optional)

For custom auth/proxy transport, pass `loader` and keep same envelope contract.


## Optional single-endpoint API mode

If you still want one POST endpoint, set `requestMode: NextjsServerRequestMode.apiEndpoint` and expose `/api/elpian-render`.
