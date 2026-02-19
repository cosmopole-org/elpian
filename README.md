# Elpian UI

A high-performance Flutter UI engine that renders HTML, CSS, Flutter DSL, and 3D scene graphs from JSON and markup formats into native Flutter 2D/3D widgets.

## Features

### Rendering Engines
- **Flutter DSL** - 60+ Flutter widgets rendered from JSON definitions
- **HTML Rendering** - 70+ HTML5 elements with semantic tag support
- **CSS Engine** - 150+ CSS properties including flexbox, grid, transforms, animations, and filters
- **Canvas 2D** - Full 2D graphics API with 50+ drawing commands
- **3D Scene Graphs** - Define 3D scenes in JSON, rendered via Bevy (Rust/GPU) or pure-Dart canvas
- **Elpian VM** - Sandboxed Rust VM with FFI/WASM for scripting UI logic

### Core Capabilities
- **JSON Stylesheet Parser** - Define CSS stylesheets in JSON with media queries, variables, and keyframe animations
- **DOM API** - Full DOM manipulation API (getElementById, querySelector, appendChild, etc.)
- **Event System** - 40+ event types with bubbling, capturing, delegation, and custom events
- **Extensible Architecture** - Register custom widgets and host handlers

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  elpian_ui:
    path: ./path/to/elpian_ui
```

## Quick Start

```dart
import 'package:elpian_ui/elpian_ui.dart';

final engine = ElpianEngine();

final widget = engine.renderFromJson({
  'type': 'div',
  'style': {
    'padding': '20',
    'backgroundColor': '#2196F3',
    'borderRadius': 12,
    'boxShadow': [{
      'color': 'rgba(0,0,0,0.2)',
      'offset': {'x': 0, 'y': 4},
      'blur': 8
    }]
  },
  'children': [
    {
      'type': 'h1',
      'props': {'text': 'Hello World'},
      'style': {
        'color': 'white',
        'fontSize': 32,
        'fontWeight': 'bold'
      }
    }
  ]
});
```

### JSON Stylesheet

```dart
final engine = ElpianEngine();

engine.loadStylesheet({
  'rules': [
    {
      'selector': '.card',
      'styles': {
        'backgroundColor': '#FFFFFF',
        'padding': '20',
        'borderRadius': 12,
        'boxShadow': [
          {
            'color': 'rgba(0,0,0,0.1)',
            'offset': {'x': 0, 'y': 2},
            'blur': 8,
          }
        ],
      }
    },
    {
      'selector': '.btn-primary',
      'styles': {
        'backgroundColor': '#2196F3',
        'color': '#FFFFFF',
        'padding': '12 24',
      }
    }
  ],
  'mediaQueries': [
    {
      'query': 'min-width: 768',
      'rules': [
        {
          'selector': '.card',
          'styles': {'padding': '40'}
        }
      ]
    }
  ]
});

final ui = engine.renderFromJson({
  'type': 'div',
  'props': {'className': 'card'},
  'children': [
    {
      'type': 'Button',
      'props': {'text': 'Click Me', 'className': 'btn-primary'}
    }
  ]
});
```

### Event Handling

```dart
final engine = ElpianEngine();

engine.setGlobalEventHandler((event) {
  print('Event: ${event.type}');
  print('Target: ${event.target}');
  if (event is ElpianPointerEvent) {
    print('Position: ${event.position}');
  }
});

final widget = engine.renderFromJson({
  'type': 'Button',
  'key': 'my-button',
  'props': {'text': 'Click Me'},
  'events': {
    'click': (event) { /* handle click */ },
    'longpress': (event) { /* handle long press */ }
  }
});
```

### DOM API

```dart
final dom = ElpianDOM();
final container = dom.createElement('div', id: 'main', classes: ['container']);
final title = dom.createElement('h1');
title.textContent = 'Dynamic Content';
title.setStyle('color', '#2196F3');
container.appendChild(title);

final element = dom.getElementById('main');
element?.addClass('active');
element?.addEventListener('click', () => print('Clicked!'));

final node = element?.toElpianNode();
```

### 3D Scene Rendering

```json
{
  "world": [
    {
      "type": "mesh3d",
      "mesh": {"Box": {"width": 2.0, "height": 2.0, "depth": 2.0}},
      "material": {"color": [0.2, 0.6, 1.0, 1.0]},
      "transform": {"translation": [0.0, 1.0, 0.0]}
    },
    {
      "type": "light",
      "light_type": "Point",
      "intensity": 1500.0,
      "transform": {"translation": [4.0, 8.0, 4.0]}
    },
    {
      "type": "camera",
      "transform": {"translation": [0.0, 5.0, 10.0]}
    }
  ]
}
```

### VM-Driven UI

The Elpian VM executes AST programs (JSON) in a sandboxed Rust VM and renders
the resulting UI via `ElpianEngine`. The VM communicates with Flutter through
typed host calls — the most important being `render`, which sends a view tree
to Flutter for display.

**Basic — render a styled heading:**

```dart
import 'dart:convert';
import 'package:elpian_ui/elpian_ui.dart';

ElpianVmWidget.fromAst(
  machineId: 'hello',
  astJson: jsonEncode({
    "type": "program",
    "body": [
      // def view = { type: "Text", props: { data: "Hello …", style: { … } } }
      {
        "type": "definition",
        "data": {
          "leftSide": {"type": "identifier", "data": {"name": "view"}},
          "rightSide": {
            "type": "object",
            "data": {
              "value": {
                "type": {"type": "string", "data": {"value": "Text"}},
                "props": {
                  "type": "object",
                  "data": {
                    "value": {
                      "data": {"type": "string", "data": {"value": "Hello from Elpian VM!"}},
                      "style": {
                        "type": "object",
                        "data": {
                          "value": {
                            "fontSize": {"type": "i16", "data": {"value": 24}},
                            "fontWeight": {"type": "string", "data": {"value": "bold"}},
                            "color": {"type": "string", "data": {"value": "#2196F3"}}
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      // askHost("render", view)
      {
        "type": "host_call",
        "data": {
          "name": "render",
          "args": [
            {"type": "identifier", "data": {"name": "view"}}
          ]
        }
      }
    ]
  }),
)
```

**Styled card layout — Column with heading, subtitle, and button:**

```dart
// Helper to keep the AST readable
Map<String, dynamic> str(String v) =>
    {"type": "string", "data": {"value": v}};
Map<String, dynamic> num16(int v) =>
    {"type": "i16", "data": {"value": v}};
Map<String, dynamic> obj(Map<String, dynamic> fields) =>
    {"type": "object", "data": {"value": fields}};
Map<String, dynamic> arr(List<dynamic> items) =>
    {"type": "array", "data": {"value": items}};

final cardAst = {
  "type": "program",
  "body": [
    {
      "type": "definition",
      "data": {
        "leftSide": {"type": "identifier", "data": {"name": "card"}},
        "rightSide": obj({
          "type": str("Container"),
          "style": obj({
            "padding": str("24"),
            "backgroundColor": str("#FFFFFF"),
            "borderRadius": num16(16),
            "boxShadow": arr([
              obj({
                "color": str("rgba(0,0,0,0.12)"),
                "offset": obj({"x": num16(0), "y": num16(4)}),
                "blur": num16(12),
              })
            ]),
          }),
          "children": arr([
            // Heading
            obj({
              "type": str("Text"),
              "props": obj({
                "data": str("Welcome"),
                "style": obj({
                  "fontSize": num16(28),
                  "fontWeight": str("bold"),
                  "color": str("#1A1A2E"),
                }),
              }),
            }),
            // Subtitle
            obj({
              "type": str("Text"),
              "props": obj({
                "data": str("This card is rendered by the Elpian VM."),
                "style": obj({
                  "fontSize": num16(14),
                  "color": str("#666666"),
                  "marginTop": str("8"),
                }),
              }),
            }),
            // Button
            obj({
              "type": str("Button"),
              "props": obj({
                "text": str("Get Started"),
              }),
              "style": obj({
                "marginTop": str("20"),
                "backgroundColor": str("#6C63FF"),
                "color": str("#FFFFFF"),
                "padding": str("12 32"),
                "borderRadius": num16(8),
              }),
            }),
          ]),
        }),
      }
    },
    {
      "type": "host_call",
      "data": {
        "name": "render",
        "args": [{"type": "identifier", "data": {"name": "card"}}]
      }
    }
  ]
};

ElpianVmWidget.fromAst(
  machineId: 'card-demo',
  astJson: jsonEncode(cardAst),
)
```

**Interactive counter — VM state + Dart-driven re-render:**

The VM keeps a `count` variable. An `increment` function mutates it and
re-renders. Dart calls that function via `entryFunction` or the controller.

```dart
final counterAst = {
  "type": "program",
  "body": [
    // def count = 0
    {
      "type": "definition",
      "data": {
        "leftSide": {"type": "identifier", "data": {"name": "count"}},
        "rightSide": {"type": "i16", "data": {"value": 0}}
      }
    },
    // function buildView() — creates the view tree from current state
    {
      "type": "functionDefinition",
      "data": {
        "name": "buildView",
        "params": [],
        "body": [
          {
            "type": "definition",
            "data": {
              "leftSide": {"type": "identifier", "data": {"name": "label"}},
              "rightSide": {
                "type": "arithmetic",
                "data": {
                  "operation": "+",
                  "operand1": {"type": "string", "data": {"value": "Count: "}},
                  "operand2": {
                    "type": "cast",
                    "data": {
                      "value": {"type": "identifier", "data": {"name": "count"}},
                      "targetType": "string"
                    }
                  }
                }
              }
            }
          },
          {
            "type": "host_call",
            "data": {
              "name": "render",
              "args": [
                {"type": "object", "data": {"value": {
                  "type": {"type": "string", "data": {"value": "Column"}},
                  "props": {"type": "object", "data": {"value": {
                    "mainAxisAlignment": {"type": "string", "data": {"value": "center"}},
                    "children": {"type": "array", "data": {"value": [
                      {"type": "object", "data": {"value": {
                        "type": {"type": "string", "data": {"value": "Text"}},
                        "props": {"type": "object", "data": {"value": {
                          "data": {"type": "identifier", "data": {"name": "label"}},
                          "style": {"type": "object", "data": {"value": {
                            "fontSize": {"type": "i16", "data": {"value": 32}},
                            "fontWeight": {"type": "string", "data": {"value": "bold"}}
                          }}}
                        }}}
                      }}},
                      {"type": "object", "data": {"value": {
                        "type": {"type": "string", "data": {"value": "Button"}},
                        "props": {"type": "object", "data": {"value": {
                          "text": {"type": "string", "data": {"value": "+1"}}
                        }}},
                        "style": {"type": "object", "data": {"value": {
                          "marginTop": {"type": "string", "data": {"value": "16"}},
                          "padding": {"type": "string", "data": {"value": "12 40"}},
                          "backgroundColor": {"type": "string", "data": {"value": "#4CAF50"}},
                          "borderRadius": {"type": "i16", "data": {"value": 8}}
                        }}}
                      }}}
                    ]}}
                  }}}
                }}}
              ]
            }
          }
        ]
      }
    },
    // function increment() — mutate state and re-render
    {
      "type": "functionDefinition",
      "data": {
        "name": "increment",
        "params": [],
        "body": [
          {
            "type": "assignment",
            "data": {
              "leftSide": {"type": "identifier", "data": {"name": "count"}},
              "rightSide": {
                "type": "arithmetic",
                "data": {
                  "operation": "+",
                  "operand1": {"type": "identifier", "data": {"name": "count"}},
                  "operand2": {"type": "i16", "data": {"value": 1}}
                }
              }
            }
          },
          {
            "type": "functionCall",
            "data": {
              "callee": {"type": "identifier", "data": {"name": "buildView"}},
              "args": []
            }
          }
        ]
      }
    },
    // Initial render
    {
      "type": "functionCall",
      "data": {
        "callee": {"type": "identifier", "data": {"name": "buildView"}},
        "args": []
      }
    }
  ]
};

// Use ElpianVmScope + controller so Dart can call VM functions
final controller = ElpianVmController();

ElpianVmScope(
  controller: controller,
  machineId: 'counter',
  astJson: jsonEncode(counterAst),
  onPrintln: (msg) => debugPrint('VM: $msg'),
)

// Later, from a button press in Dart:
// await controller.callFunction('increment');
```

**Custom host handlers — bridge VM logic to native platform APIs:**

```dart
ElpianVmWidget.fromAst(
  machineId: 'api-bridge',
  astJson: jsonEncode({
    "type": "program",
    "body": [
      // def user = askHost("fetchUser", { id: 42 })
      {
        "type": "definition",
        "data": {
          "leftSide": {"type": "identifier", "data": {"name": "user"}},
          "rightSide": {
            "type": "functionCall",
            "data": {
              "callee": {"type": "identifier", "data": {"name": "askHost"}},
              "args": [
                {"type": "string", "data": {"value": "fetchUser"}},
                {"type": "array", "data": {"value": [
                  {"type": "object", "data": {"value": {
                    "id": {"type": "i16", "data": {"value": 42}}
                  }}}
                ]}}
              ]
            }
          }
        }
      },
      // def greeting = "Welcome, " + user.name
      {
        "type": "definition",
        "data": {
          "leftSide": {"type": "identifier", "data": {"name": "greeting"}},
          "rightSide": {
            "type": "arithmetic",
            "data": {
              "operation": "+",
              "operand1": {"type": "string", "data": {"value": "Welcome, "}},
              "operand2": {
                "type": "indexer",
                "data": {
                  "target": {"type": "identifier", "data": {"name": "user"}},
                  "index": {"type": "string", "data": {"value": "name"}}
                }
              }
            }
          }
        }
      },
      // render a personalized card
      {
        "type": "host_call",
        "data": {
          "name": "render",
          "args": [
            {"type": "object", "data": {"value": {
              "type": {"type": "string", "data": {"value": "div"}},
              "style": {"type": "object", "data": {"value": {
                "padding": {"type": "string", "data": {"value": "24"}},
                "backgroundColor": {"type": "string", "data": {"value": "#F5F5F5"}},
                "borderRadius": {"type": "i16", "data": {"value": 12}}
              }}},
              "children": {"type": "array", "data": {"value": [
                {"type": "object", "data": {"value": {
                  "type": {"type": "string", "data": {"value": "h1"}},
                  "props": {"type": "object", "data": {"value": {
                    "text": {"type": "identifier", "data": {"name": "greeting"}}
                  }}},
                  "style": {"type": "object", "data": {"value": {
                    "color": {"type": "string", "data": {"value": "#1A1A2E"}}
                  }}}
                }}},
                {"type": "object", "data": {"value": {
                  "type": {"type": "string", "data": {"value": "p"}},
                  "props": {"type": "object", "data": {"value": {
                    "text": {"type": "string", "data": {"value": "Your profile was loaded by the VM."}}
                  }}},
                  "style": {"type": "object", "data": {"value": {
                    "color": {"type": "string", "data": {"value": "#666"}}
                  }}}
                }}}
              ]}}
            }}}
          ]
        }
      }
    ]
  }),
  // Register a custom host handler the VM can call
  hostHandlers: {
    'fetchUser': (apiName, payload) async {
      // In a real app, call your backend or local DB here
      return jsonEncode({
        "type": "object",
        "data": {
          "value": {
            "name": {"type": "string", "data": {"value": "Alice"}},
            "email": {"type": "string", "data": {"value": "alice@example.com"}}
          }
        }
      });
    },
  },
  onPrintln: (msg) => debugPrint('VM: $msg'),
  errorBuilder: (error) => Center(child: Text('Oops: $error')),
)
```

**Automatic event handling — UI events call VM functions directly:**

When the VM renders a view tree whose nodes contain an `"events"` map with
**string values** (VM function names), the engine automatically calls the
corresponding VM function when that event fires. No manual piping needed.

The VM function receives a typed event object with `type`, `target`, and
event-specific fields (`x`/`y` for pointer events, `key`/`keyCode` for
keyboard events, `value` for input events, `scale`/`rotation` for gestures).

```dart
final toggleAst = {
  "type": "program",
  "body": [
    // def isOn = false
    {
      "type": "definition",
      "data": {
        "leftSide": {"type": "identifier", "data": {"name": "isOn"}},
        "rightSide": {"type": "bool", "data": {"value": false}}
      }
    },
    // function renderUI(evt) — rebuild the view from current state
    {
      "type": "functionDefinition",
      "data": {
        "name": "renderUI",
        "params": ["evt"],
        "body": [
          // Toggle: isOn = not isOn
          {
            "type": "assignment",
            "data": {
              "leftSide": {"type": "identifier", "data": {"name": "isOn"}},
              "rightSide": {
                "type": "not",
                "data": {
                  "value": {"type": "identifier", "data": {"name": "isOn"}}
                }
              }
            }
          },
          // Choose label based on state
          {
            "type": "definition",
            "data": {
              "leftSide": {"type": "identifier", "data": {"name": "label"}},
              "rightSide": {"type": "string", "data": {"value": "ON"}}
            }
          },
          {
            "type": "ifStmt",
            "data": {
              "condition": {
                "type": "not",
                "data": {
                  "value": {"type": "identifier", "data": {"name": "isOn"}}
                }
              },
              "body": [
                {
                  "type": "assignment",
                  "data": {
                    "leftSide": {"type": "identifier", "data": {"name": "label"}},
                    "rightSide": {"type": "string", "data": {"value": "OFF"}}
                  }
                }
              ]
            }
          },
          // Render a button — "events" maps event names to VM function names
          {
            "type": "host_call",
            "data": {
              "name": "render",
              "args": [
                {"type": "object", "data": {"value": {
                  "type": {"type": "string", "data": {"value": "Column"}},
                  "props": {"type": "object", "data": {"value": {
                    "mainAxisAlignment": {"type": "string", "data": {"value": "center"}},
                    "children": {"type": "array", "data": {"value": [
                      {"type": "object", "data": {"value": {
                        "type": {"type": "string", "data": {"value": "Text"}},
                        "props": {"type": "object", "data": {"value": {
                          "data": {"type": "identifier", "data": {"name": "label"}},
                          "style": {"type": "object", "data": {"value": {
                            "fontSize": {"type": "i16", "data": {"value": 48}},
                            "fontWeight": {"type": "string", "data": {"value": "bold"}}
                          }}}
                        }}}
                      }}},
                      {"type": "object", "data": {"value": {
                        "type": {"type": "string", "data": {"value": "Button"}},
                        "key": {"type": "string", "data": {"value": "toggle-btn"}},
                        "props": {"type": "object", "data": {"value": {
                          "text": {"type": "string", "data": {"value": "Toggle"}}
                        }}},
                        "style": {"type": "object", "data": {"value": {
                          "marginTop": {"type": "string", "data": {"value": "24"}},
                          "padding": {"type": "string", "data": {"value": "16 48"}},
                          "backgroundColor": {"type": "string", "data": {"value": "#6C63FF"}},
                          "borderRadius": {"type": "i16", "data": {"value": 12}}
                        }}},
                        "events": {"type": "object", "data": {"value": {
                          "click": {"type": "string", "data": {"value": "renderUI"}}
                        }}}
                      }}}
                    ]}}
                  }}}
                }}}
              ]
            }
          }
        ]
      }
    },
    // Initial render (call renderUI with a dummy event)
    {
      "type": "functionCall",
      "data": {
        "callee": {"type": "identifier", "data": {"name": "renderUI"}},
        "args": [{"type": "object", "data": {"value": {
          "type": {"type": "string", "data": {"value": "init"}}
        }}}]
      }
    }
  ]
};

// Just drop it in — events are wired up automatically
ElpianVmWidget.fromAst(
  machineId: 'toggle',
  astJson: jsonEncode(toggleAst),
)
```

**Multi-event form — input, focus, and submit handled by the VM:**

```dart
final formAst = {
  "type": "program",
  "body": [
    // def username = ""
    {
      "type": "definition",
      "data": {
        "leftSide": {"type": "identifier", "data": {"name": "username"}},
        "rightSide": {"type": "string", "data": {"value": ""}}
      }
    },
    // function onInput(evt) — store input value
    {
      "type": "functionDefinition",
      "data": {
        "name": "onInput",
        "params": ["evt"],
        "body": [
          {
            "type": "assignment",
            "data": {
              "leftSide": {"type": "identifier", "data": {"name": "username"}},
              "rightSide": {
                "type": "indexer",
                "data": {
                  "target": {"type": "identifier", "data": {"name": "evt"}},
                  "index": {"type": "string", "data": {"value": "value"}}
                }
              }
            }
          }
        ]
      }
    },
    // function onSubmit(evt) — greet the user
    {
      "type": "functionDefinition",
      "data": {
        "name": "onSubmit",
        "params": ["evt"],
        "body": [
          {
            "type": "definition",
            "data": {
              "leftSide": {"type": "identifier", "data": {"name": "greeting"}},
              "rightSide": {
                "type": "arithmetic",
                "data": {
                  "operation": "+",
                  "operand1": {"type": "string", "data": {"value": "Hello, "}},
                  "operand2": {"type": "identifier", "data": {"name": "username"}}
                }
              }
            }
          },
          {
            "type": "host_call",
            "data": {
              "name": "render",
              "args": [
                {"type": "object", "data": {"value": {
                  "type": {"type": "string", "data": {"value": "div"}},
                  "style": {"type": "object", "data": {"value": {
                    "padding": {"type": "string", "data": {"value": "32"}},
                    "backgroundColor": {"type": "string", "data": {"value": "#E8F5E9"}},
                    "borderRadius": {"type": "i16", "data": {"value": 12}}
                  }}},
                  "children": {"type": "array", "data": {"value": [
                    {"type": "object", "data": {"value": {
                      "type": {"type": "string", "data": {"value": "h1"}},
                      "props": {"type": "object", "data": {"value": {
                        "text": {"type": "identifier", "data": {"name": "greeting"}}
                      }}},
                      "style": {"type": "object", "data": {"value": {
                        "color": {"type": "string", "data": {"value": "#2E7D32"}}
                      }}}
                    }}}
                  ]}}
                }}}
              ]
            }
          }
        ]
      }
    },
    // Initial render — a form with input + submit button
    {
      "type": "host_call",
      "data": {
        "name": "render",
        "args": [
          {"type": "object", "data": {"value": {
            "type": {"type": "string", "data": {"value": "div"}},
            "style": {"type": "object", "data": {"value": {
              "padding": {"type": "string", "data": {"value": "32"}}
            }}},
            "children": {"type": "array", "data": {"value": [
              {"type": "object", "data": {"value": {
                "type": {"type": "string", "data": {"value": "h2"}},
                "props": {"type": "object", "data": {"value": {
                  "text": {"type": "string", "data": {"value": "Sign In"}}
                }}}
              }}},
              {"type": "object", "data": {"value": {
                "type": {"type": "string", "data": {"value": "input"}},
                "key": {"type": "string", "data": {"value": "name-input"}},
                "props": {"type": "object", "data": {"value": {
                  "placeholder": {"type": "string", "data": {"value": "Enter your name"}}
                }}},
                "style": {"type": "object", "data": {"value": {
                  "marginTop": {"type": "string", "data": {"value": "16"}},
                  "padding": {"type": "string", "data": {"value": "12"}},
                  "borderRadius": {"type": "i16", "data": {"value": 8}}
                }}},
                "events": {"type": "object", "data": {"value": {
                  "change": {"type": "string", "data": {"value": "onInput"}}
                }}}
              }}},
              {"type": "object", "data": {"value": {
                "type": {"type": "string", "data": {"value": "Button"}},
                "key": {"type": "string", "data": {"value": "submit-btn"}},
                "props": {"type": "object", "data": {"value": {
                  "text": {"type": "string", "data": {"value": "Submit"}}
                }}},
                "style": {"type": "object", "data": {"value": {
                  "marginTop": {"type": "string", "data": {"value": "16"}},
                  "backgroundColor": {"type": "string", "data": {"value": "#2196F3"}},
                  "padding": {"type": "string", "data": {"value": "12 32"}},
                  "borderRadius": {"type": "i16", "data": {"value": 8}}
                }}},
                "events": {"type": "object", "data": {"value": {
                  "click": {"type": "string", "data": {"value": "onSubmit"}}
                }}}
              }}}
            ]}}
          }}}
        ]
      }
    }
  ]
};

ElpianVmWidget.fromAst(
  machineId: 'form-demo',
  astJson: jsonEncode(formAst),
)
```

## Custom Widget Registration

```dart
final engine = ElpianEngine();

engine.registerWidget('MyCustomCard', (node, children) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(children: children),
  );
});
```

## Project Structure

```
elpian/
├── lib/
│   ├── elpian_ui.dart            # Main library export
│   ├── src/
│   │   ├── core/                 # ElpianEngine, widget registry, event system
│   │   ├── models/               # ElpianNode, CSSStyle data models
│   │   ├── parser/               # JSON parser
│   │   ├── css/                  # CSS parser, stylesheet, JSON stylesheet
│   │   ├── canvas/               # 2D Canvas API
│   │   ├── widgets/              # 60+ Flutter widget builders
│   │   ├── html_widgets/         # 70+ HTML element builders
│   │   ├── bevy/                 # Bevy 3D scene integration (Rust FFI)
│   │   ├── scene3d/              # Pure-Dart 3D renderer
│   │   └── vm/                   # Elpian VM (Rust FFI/WASM)
│   └── example/                  # Demo applications
├── rust/                         # Rust VM + Bevy crate
├── rust_builder/                 # Flutter FFI plugin
├── test/                         # Unit tests
├── web/                          # Web assets + Bevy WASM demo
└── pubspec.yaml
```

## Documentation

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](QUICKSTART.md) | Getting started guide |
| [FEATURES.md](FEATURES.md) | Complete feature set reference |
| [EVENT_SYSTEM.md](EVENT_SYSTEM.md) | Event handling documentation |
| [JSON_STYLESHEET.md](JSON_STYLESHEET.md) | JSON stylesheet system |
| [CANVAS_API.md](CANVAS_API.md) | 2D Canvas drawing API |
| [VM_INTEGRATION.md](VM_INTEGRATION.md) | Rust VM and FFI integration |
| [2d_graphics.md](2d_graphics.md) | 2D UI element reference |
| [3d_graphics.md](3d_graphics.md) | 3D scene graph reference |
| [logic_vm.md](logic_vm.md) | VM AST and API reference |

## Testing

```bash
flutter test
```

## License

MIT License
