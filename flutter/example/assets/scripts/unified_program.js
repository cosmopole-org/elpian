
// ─────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────
let activeTab = 0;
let activeSubTab = 0;

// Counter demo
let count = 0;

// Clock demo
let clockTime = new Date().toISOString();

// Theme demo
let isDark = false;

// Host data demo
let profile = null;

// DOM + Canvas demo
let domCanvasCount = 0;
let domCanvasColors = ['#4f46e5', '#059669', '#dc2626', '#d97706'];
let domCanvasColorIdx = 0;
let clockTimerId = null;
let wbStrokes = [];
let wbCurrentStroke = null;
let wbColor = '#0f172a';
let wbBrush = 3;
let wbEraser = false;
let wbIsDrawing = false;
let wbCommands = null;
let wbRenderPending = false;
let wbLastRenderAt = 0;
let wbRenderTimerId = null;
let wbContextId = null;
const wbPalette = ['#0f172a', '#2563eb', '#16a34a', '#dc2626', '#9333ea', '#f59e0b'];

// 3D demos
let bevyInteractive = true;
let bevyFps = 60;
let gameInteractive = true;
let gameFps = 60;

// Real-world demo state
let rwSearch = '';
let rwFilter = 'all';
let rwTickets = [
  { id: 'T-101', title: 'Login latency spikes', owner: 'SRE', status: 'open', priority: 'high' },
  { id: 'T-102', title: 'Billing email mismatch', owner: 'Support', status: 'open', priority: 'med' },
  { id: 'T-103', title: 'Checkout retry bug', owner: 'Payments', status: 'closed', priority: 'low' },
  { id: 'T-104', title: 'Push notification delays', owner: 'Mobile', status: 'open', priority: 'med' }
];

let rwCart = [
  { id: 'SKU-01', name: 'Pro Plan', price: 24, qty: 1 },
  { id: 'SKU-02', name: 'Analytics Add-on', price: 12, qty: 2 }
];
let rwPromoCode = '';
let rwDiscount = 0;

let rwChatDraft = '';
let rwChatMessages = [
  { id: 1, from: 'Ava', text: 'Customer reported an outage in EU-West.' },
  { id: 2, from: 'You', text: 'Looking into it now. Can you pull logs?' }
];

let rwPipeline = {
  todo: [
    { id: 'P-1', title: 'Onboarding flow', owner: 'Design' },
    { id: 'P-2', title: 'Usage-based billing', owner: 'Eng' }
  ],
  doing: [
    { id: 'P-3', title: 'Realtime audit logs', owner: 'Platform' }
  ],
  done: [
    { id: 'P-4', title: 'SLA dashboard', owner: 'Data' }
  ]
};

function safeJsonParse(name, raw) {
  try {
    return JSON.parse(raw);
  } catch (e) {
    try {
      askHost('println', 'JSON parse failed for ' + name + ': ' + e);
    } catch (_) {}
    if (!parseErrors) parseErrors = {};
    parseErrors[name] = String(e);
    return { type: 'Text', props: { text: 'Failed to load ' + name } };
  }
}

let parseErrors = {};

const TABS = [
  'UI Widgets',
  'Canvas',
  'VM Demos',
  'DOM + Canvas',
  'Landing Page',
  'Bevy 3D',
  'Game 3D',
  'Real World'
];

const LANDING_PAGE_JSON = {
  "type": "div",
  "key": "landing-root",
  "style": {
    "backgroundColor": "#0F172A"
  },
  "children": [
    {
      "type": "header",
      "key": "main-header",
      "style": {
        "backgroundColor": "rgba(15,23,42,0.95)",
        "padding": "16 24",
        "display": "flex",
        "flexDirection": "row",
        "justifyContent": "space-between",
        "alignItems": "center"
      },
      "children": [
        {
          "type": "div",
          "style": {
            "display": "flex",
            "flexDirection": "row",
            "alignItems": "center",
            "gap": 12
          },
          "children": [
            {
              "type": "Icon",
              "props": { "icon": "rocket_launch" },
              "style": { "fontSize": 28, "color": "#818CF8" }
            },
            {
              "type": "span",
              "props": { "text": "Elpian" },
              "style": {
                "color": "white",
                "fontSize": 22,
                "fontWeight": "bold",
                "letterSpacing": 1.2
              }
            }
          ]
        },
        {
          "type": "nav",
          "style": {
            "gap": 32,
            "justifyContent": "center",
            "alignItems": "center"
          },
          "children": [
            {
              "type": "a",
              "props": { "text": "Features", "href": "#features" },
              "style": { "color": "#94A3B8", "fontSize": 14 }
            },
            {
              "type": "a",
              "props": { "text": "Pricing", "href": "#pricing" },
              "style": { "color": "#94A3B8", "fontSize": 14 }
            },
            {
              "type": "a",
              "props": { "text": "Docs", "href": "#docs" },
              "style": { "color": "#94A3B8", "fontSize": 14 }
            },
            {
              "type": "a",
              "props": { "text": "Blog", "href": "#blog" },
              "style": { "color": "#94A3B8", "fontSize": 14 }
            }
          ]
        },
        {
          "type": "div",
          "style": {
            "display": "flex",
            "flexDirection": "row",
            "gap": 12,
            "alignItems": "center"
          },
          "children": [
            {
              "type": "Button",
              "props": { "text": "Sign In" },
              "style": {
                "backgroundColor": "rgba(255,255,255,0.08)",
                "color": "#E2E8F0",
                "padding": "8 20",
                "borderRadius": 8
              }
            },
            {
              "type": "Button",
              "props": { "text": "Get Started" },
              "style": {
                "backgroundColor": "#6366F1",
                "color": "white",
                "padding": "8 20",
                "borderRadius": 8
              }
            }
          ]
        }
      ]
    },

    {
      "type": "section",
      "key": "hero-section",
      "style": {
        "padding": "80 24 60 24",
        "alignItems": "center"
      },
      "children": [
        {
          "type": "div",
          "style": {
            "backgroundColor": "rgba(99,102,241,0.15)",
            "padding": "6 16",
            "borderRadius": 20,
            "margin": "0 0 24 0"
          },
          "children": [
            {
              "type": "span",
              "props": { "text": "v2.0 - Now with Server-Driven UI" },
              "style": { "color": "#818CF8", "fontSize": 13, "fontWeight": "w500" }
            }
          ]
        },
        {
          "type": "h1",
          "props": { "text": "Build Beautiful UIs" },
          "style": {
            "color": "white",
            "fontSize": 52,
            "fontWeight": "bold",
            "textAlign": "center",
            "margin": "0 0 8 0",
            "letterSpacing": -1.5
          }
        },
        {
          "type": "h1",
          "props": { "text": "From JSON & HTML" },
          "style": {
            "fontSize": 52,
            "fontWeight": "bold",
            "textAlign": "center",
            "margin": "0 0 24 0",
            "letterSpacing": -1.5,
            "color": "#818CF8"
          }
        },
        {
          "type": "p",
          "props": {
            "text": "A high-performance Flutter rendering engine that transforms JSON definitions and HTML+CSS into native Flutter widgets. Ship UI updates without app releases."
          },
          "style": {
            "color": "#94A3B8",
            "fontSize": 18,
            "textAlign": "center",
            "lineHeight": 1.6,
            "margin": "0 0 40 0",
            "padding": "0 60 0 60"
          }
        },
        {
          "type": "div",
          "style": {
            "display": "flex",
            "flexDirection": "row",
            "gap": 16,
            "justifyContent": "center"
          },
          "children": [
            {
              "type": "Button",
              "props": { "text": "Start Building Free" },
              "style": {
                "backgroundColor": "#6366F1",
                "color": "white",
                "padding": "14 32",
                "borderRadius": 10,
                "fontSize": 16
              }
            },
            {
              "type": "Button",
              "props": { "text": "View Documentation" },
              "style": {
                "backgroundColor": "rgba(255,255,255,0.06)",
                "color": "#E2E8F0",
                "padding": "14 32",
                "borderRadius": 10,
                "fontSize": 16
              }
            }
          ]
        },
        {
          "type": "div",
          "style": {
            "display": "flex",
            "flexDirection": "row",
            "gap": 24,
            "justifyContent": "center",
            "margin": "32 0 0 0"
          },
          "children": [
            {
              "type": "div",
              "style": {
                "display": "flex",
                "flexDirection": "row",
                "gap": 6,
                "alignItems": "center"
              },
              "children": [
                {
                  "type": "Icon",
                  "props": { "icon": "check_circle" },
                  "style": { "fontSize": 16, "color": "#34D399" }
                },
                {
                  "type": "span",
                  "props": { "text": "76+ Widgets" },
                  "style": { "color": "#94A3B8", "fontSize": 13 }
                }
              ]
            },
            {
              "type": "div",
              "style": {
                "display": "flex",
                "flexDirection": "row",
                "gap": 6,
                "alignItems": "center"
              },
              "children": [
                {
                  "type": "Icon",
                  "props": { "icon": "check_circle" },
                  "style": { "fontSize": 16, "color": "#34D399" }
                },
                {
                  "type": "span",
                  "props": { "text": "150+ CSS Properties" },
                  "style": { "color": "#94A3B8", "fontSize": 13 }
                }
              ]
            },
            {
              "type": "div",
              "style": {
                "display": "flex",
                "flexDirection": "row",
                "gap": 6,
                "alignItems": "center"
              },
              "children": [
                {
                  "type": "Icon",
                  "props": { "icon": "check_circle" },
                  "style": { "fontSize": 16, "color": "#34D399" }
                },
                {
                  "type": "span",
                  "props": { "text": "40+ Event Types" },
                  "style": { "color": "#94A3B8", "fontSize": 13 }
                }
              ]
            }
          ]
        }
      ]
    },

    {
      "type": "section",
      "key": "features-section",
      "style": {
        "padding": "60 24",
        "backgroundColor": "#1E293B"
      },
      "children": [
        {
          "type": "h2",
          "props": { "text": "Everything you need to build dynamic UIs" },
          "style": {
            "color": "white",
            "fontSize": 36,
            "textAlign": "center",
            "margin": "0 0 8 0",
            "letterSpacing": -0.8
          }
        },
        {
          "type": "p",
          "props": { "text": "A complete toolkit for server-driven Flutter interfaces" },
          "style": {
            "color": "#94A3B8",
            "fontSize": 16,
            "textAlign": "center",
            "margin": "0 0 48 0"
          }
        },
        {
          "type": "Row",
          "style": {
            "justifyContent": "center",
            "gap": 20
          },
          "children": [
            {
              "type": "Card",
              "key": "feature-1",
              "style": {
                "backgroundColor": "#0F172A",
                "borderRadius": 16,
                "padding": "28",
                "flex": 1,
                "minWidth": 200
              },
              "children": [
                {
                  "type": "Container",
                  "children": [
                    {
                      "type": "div",
                      "style": {
                        "backgroundColor": "rgba(99,102,241,0.15)",
                        "width": 48,
                        "height": 48,
                        "borderRadius": 12,
                        "display": "flex",
                        "justifyContent": "center",
                        "alignItems": "center",
                        "margin": "0 0 16 0"
                      },
                      "children": [
                        {
                          "type": "Icon",
                          "props": { "icon": "code" },
                          "style": { "fontSize": 24, "color": "#818CF8" }
                        }
                      ]
                    },
                    {
                      "type": "h3",
                      "props": { "text": "JSON & HTML DSL" },
                      "style": {
                        "color": "white",
                        "fontSize": 18,
                        "margin": "0 0 8 0"
                      }
                    },
                    {
                      "type": "p",
                      "props": { "text": "Define UIs declaratively using JSON or HTML+CSS. Full semantic HTML support with div, section, nav, form elements and more." },
                      "style": { "color": "#94A3B8", "fontSize": 14, "lineHeight": 1.5 }
                    }
                  ]
                }
              ]
            },
            {
              "type": "Card",
              "key": "feature-2",
              "style": {
                "backgroundColor": "#0F172A",
                "borderRadius": 16,
                "padding": "28",
                "flex": 1,
                "minWidth": 200
              },
              "children": [
                {
                  "type": "Container",
                  "children": [
                    {
                      "type": "div",
                      "style": {
                        "backgroundColor": "rgba(52,211,153,0.15)",
                        "width": 48,
                        "height": 48,
                        "borderRadius": 12,
                        "display": "flex",
                        "justifyContent": "center",
                        "alignItems": "center",
                        "margin": "0 0 16 0"
                      },
                      "children": [
                        {
                          "type": "Icon",
                          "props": { "icon": "palette" },
                          "style": { "fontSize": 24, "color": "#34D399" }
                        }
                      ]
                    },
                    {
                      "type": "h3",
                      "props": { "text": "Full CSS Styling" },
                      "style": {
                        "color": "white",
                        "fontSize": 18,
                        "margin": "0 0 8 0"
                      }
                    },
                    {
                      "type": "p",
                      "props": { "text": "150+ CSS properties including flexbox, grid, transforms, animations, gradients, shadows, and responsive media queries." },
                      "style": { "color": "#94A3B8", "fontSize": 14, "lineHeight": 1.5 }
                    }
                  ]
                }
              ]
            },
            {
              "type": "Card",
              "key": "feature-3",
              "style": {
                "backgroundColor": "#0F172A",
                "borderRadius": 16,
                "padding": "28",
                "flex": 1,
                "minWidth": 200
              },
              "children": [
                {
                  "type": "Container",
                  "children": [
                    {
                      "type": "div",
                      "style": {
                        "backgroundColor": "rgba(251,191,36,0.15)",
                        "width": 48,
                        "height": 48,
                        "borderRadius": 12,
                        "display": "flex",
                        "justifyContent": "center",
                        "alignItems": "center",
                        "margin": "0 0 16 0"
                      },
                      "children": [
                        {
                          "type": "Icon",
                          "props": { "icon": "bolt" },
                          "style": { "fontSize": 24, "color": "#FBBF24" }
                        }
                      ]
                    },
                    {
                      "type": "h3",
                      "props": { "text": "High Performance" },
                      "style": {
                        "color": "white",
                        "fontSize": 18,
                        "margin": "0 0 8 0"
                      }
                    },
                    {
                      "type": "p",
                      "props": { "text": "Native Flutter rendering with efficient widget tree construction. Canvas API for custom 2D graphics with 50+ drawing commands." },
                      "style": { "color": "#94A3B8", "fontSize": 14, "lineHeight": 1.5 }
                    }
                  ]
                }
              ]
            }
          ]
        },
        {
          "type": "Row",
          "style": {
            "justifyContent": "center",
            "gap": 20,
            "margin": "20 0 0 0"
          },
          "children": [
            {
              "type": "Card",
              "key": "feature-4",
              "style": {
                "backgroundColor": "#0F172A",
                "borderRadius": 16,
                "padding": "28",
                "flex": 1,
                "minWidth": 200
              },
              "children": [
                {
                  "type": "Container",
                  "children": [
                    {
                      "type": "div",
                      "style": {
                        "backgroundColor": "rgba(248,113,113,0.15)",
                        "width": 48,
                        "height": 48,
                        "borderRadius": 12,
                        "display": "flex",
                        "justifyContent": "center",
                        "alignItems": "center",
                        "margin": "0 0 16 0"
                      },
                      "children": [
                        {
                          "type": "Icon",
                          "props": { "icon": "touch_app" },
                          "style": { "fontSize": 24, "color": "#F87171" }
                        }
                      ]
                    },
                    {
                      "type": "h3",
                      "props": { "text": "Rich Event System" },
                      "style": {
                        "color": "white",
                        "fontSize": 18,
                        "margin": "0 0 8 0"
                      }
                    },
                    {
                      "type": "p",
                      "props": { "text": "40+ event types with full DOM event propagation: bubbling, capturing, tap, drag, swipe, keyboard, and custom events." },
                      "style": { "color": "#94A3B8", "fontSize": 14, "lineHeight": 1.5 }
                    }
                  ]
                }
              ]
            },
            {
              "type": "Card",
              "key": "feature-5",
              "style": {
                "backgroundColor": "#0F172A",
                "borderRadius": 16,
                "padding": "28",
                "flex": 1,
                "minWidth": 200
              },
              "children": [
                {
                  "type": "Container",
                  "children": [
                    {
                      "type": "div",
                      "style": {
                        "backgroundColor": "rgba(168,85,247,0.15)",
                        "width": 48,
                        "height": 48,
                        "borderRadius": 12,
                        "display": "flex",
                        "justifyContent": "center",
                        "alignItems": "center",
                        "margin": "0 0 16 0"
                      },
                      "children": [
                        {
                          "type": "Icon",
                          "props": { "icon": "auto_awesome" },
                          "style": { "fontSize": 24, "color": "#A855F7" }
                        }
                      ]
                    },
                    {
                      "type": "h3",
                      "props": { "text": "20+ Animations" },
                      "style": {
                        "color": "white",
                        "fontSize": 18,
                        "margin": "0 0 8 0"
                      }
                    },
                    {
                      "type": "p",
                      "props": { "text": "Built-in implicit & explicit animations: fade, slide, scale, rotation, shimmer, pulse, staggered animations, and hero transitions." },
                      "style": { "color": "#94A3B8", "fontSize": 14, "lineHeight": 1.5 }
                    }
                  ]
                }
              ]
            },
            {
              "type": "Card",
              "key": "feature-6",
              "style": {
                "backgroundColor": "#0F172A",
                "borderRadius": 16,
                "padding": "28",
                "flex": 1,
                "minWidth": 200
              },
              "children": [
                {
                  "type": "Container",
                  "children": [
                    {
                      "type": "div",
                      "style": {
                        "backgroundColor": "rgba(56,189,248,0.15)",
                        "width": 48,
                        "height": 48,
                        "borderRadius": 12,
                        "display": "flex",
                        "justifyContent": "center",
                        "alignItems": "center",
                        "margin": "0 0 16 0"
                      },
                      "children": [
                        {
                          "type": "Icon",
                          "props": { "icon": "extension" },
                          "style": { "fontSize": 24, "color": "#38BDF8" }
                        }
                      ]
                    },
                    {
                      "type": "h3",
                      "props": { "text": "DOM API & Canvas" },
                      "style": {
                        "color": "white",
                        "fontSize": 18,
                        "margin": "0 0 8 0"
                      }
                    },
                    {
                      "type": "p",
                      "props": { "text": "Full DOM manipulation API with querySelector, element creation, and 2D Canvas drawing for custom graphics and charts." },
                      "style": { "color": "#94A3B8", "fontSize": 14, "lineHeight": 1.5 }
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    },

    {
      "type": "section",
      "key": "stats-section",
      "style": {
        "padding": "60 24",
        "backgroundColor": "#0F172A"
      },
      "children": [
        {
          "type": "Row",
          "style": {
            "justifyContent": "space-evenly",
            "gap": 16
          },
          "children": [
            {
              "type": "Container",
              "style": { "padding": "20", "alignItems": "center" },
              "children": [
                {
                  "type": "Text",
                  "props": { "text": "76+" },
                  "style": { "fontSize": 42, "fontWeight": "bold", "color": "#818CF8" }
                },
                {
                  "type": "Text",
                  "props": { "text": "Flutter Widgets" },
                  "style": { "fontSize": 14, "color": "#94A3B8", "margin": "4 0 0 0" }
                }
              ]
            },
            {
              "type": "Container",
              "style": { "padding": "20", "alignItems": "center" },
              "children": [
                {
                  "type": "Text",
                  "props": { "text": "76+" },
                  "style": { "fontSize": 42, "fontWeight": "bold", "color": "#34D399" }
                },
                {
                  "type": "Text",
                  "props": { "text": "HTML Elements" },
                  "style": { "fontSize": 14, "color": "#94A3B8", "margin": "4 0 0 0" }
                }
              ]
            },
            {
              "type": "Container",
              "style": { "padding": "20", "alignItems": "center" },
              "children": [
                {
                  "type": "Text",
                  "props": { "text": "150+" },
                  "style": { "fontSize": 42, "fontWeight": "bold", "color": "#FBBF24" }
                },
                {
                  "type": "Text",
                  "props": { "text": "CSS Properties" },
                  "style": { "fontSize": 14, "color": "#94A3B8", "margin": "4 0 0 0" }
                }
              ]
            },
            {
              "type": "Container",
              "style": { "padding": "20", "alignItems": "center" },
              "children": [
                {
                  "type": "Text",
                  "props": { "text": "50+" },
                  "style": { "fontSize": 42, "fontWeight": "bold", "color": "#F87171" }
                },
                {
                  "type": "Text",
                  "props": { "text": "Canvas Commands" },
                  "style": { "fontSize": 14, "color": "#94A3B8", "margin": "4 0 0 0" }
                }
              ]
            }
          ]
        }
      ]
    },

    {
      "type": "section",
      "key": "pricing-section",
      "style": {
        "padding": "60 24",
        "backgroundColor": "#1E293B"
      },
      "children": [
        {
          "type": "h2",
          "props": { "text": "Simple, transparent pricing" },
          "style": {
            "color": "white",
            "fontSize": 36,
            "textAlign": "center",
            "margin": "0 0 8 0",
            "letterSpacing": -0.8
          }
        },
        {
          "type": "p",
          "props": { "text": "Start free and scale as your application grows" },
          "style": {
            "color": "#94A3B8",
            "fontSize": 16,
            "textAlign": "center",
            "margin": "0 0 48 0"
          }
        },
        {
          "type": "Row",
          "style": {
            "justifyContent": "center",
            "gap": 24
          },
          "children": [
            {
              "type": "Card",
              "key": "plan-free",
              "style": {
                "backgroundColor": "#0F172A",
                "borderRadius": 16,
                "padding": "32",
                "flex": 1,
                "minWidth": 240,
                "borderWidth": 1,
                "borderColor": "#334155"
              },
              "children": [
                {
                  "type": "Container",
                  "children": [
                    {
                      "type": "h3",
                      "props": { "text": "Starter" },
                      "style": { "color": "#94A3B8", "fontSize": 16, "fontWeight": "w500", "margin": "0 0 8 0" }
                    },
                    {
                      "type": "div",
                      "style": { "display": "flex", "flexDirection": "row", "alignItems": "flex-end", "gap": 4, "margin": "0 0 24 0" },
                      "children": [
                        { "type": "Text", "props": { "text": "$0" }, "style": { "fontSize": 40, "fontWeight": "bold", "color": "white" } },
                        { "type": "Text", "props": { "text": "/month" }, "style": { "fontSize": 14, "color": "#64748B", "margin": "0 0 8 0" } }
                      ]
                    },
                    {
                      "type": "Button",
                      "props": { "text": "Get Started" },
                      "style": { "backgroundColor": "rgba(255,255,255,0.08)", "color": "white", "padding": "12 0", "borderRadius": 10, "width": 220 }
                    },
                    { "type": "hr", "style": { "margin": "24 0", "color": "#334155" } },
                    {
                      "type": "Column",
                      "style": { "gap": 12 },
                      "children": [
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#34D399" } },
                            { "type": "span", "props": { "text": "Up to 10 UI templates" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        },
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#34D399" } },
                            { "type": "span", "props": { "text": "All HTML elements" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        },
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#34D399" } },
                            { "type": "span", "props": { "text": "CSS styling engine" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        },
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#34D399" } },
                            { "type": "span", "props": { "text": "Community support" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            },
            {
              "type": "Card",
              "key": "plan-pro",
              "style": {
                "backgroundColor": "#0F172A",
                "borderRadius": 16,
                "padding": "32",
                "flex": 1,
                "minWidth": 240,
                "borderWidth": 2,
                "borderColor": "#6366F1"
              },
              "children": [
                {
                  "type": "Container",
                  "children": [
                    {
                      "type": "div",
                      "style": { "display": "flex", "flexDirection": "row", "justifyContent": "space-between", "alignItems": "center", "margin": "0 0 8 0" },
                      "children": [
                        { "type": "h3", "props": { "text": "Pro" }, "style": { "color": "#818CF8", "fontSize": 16, "fontWeight": "w500", "margin": "0" } },
                        {
                          "type": "div",
                          "style": { "backgroundColor": "rgba(99,102,241,0.15)", "padding": "4 10", "borderRadius": 12 },
                          "children": [
                            { "type": "span", "props": { "text": "Popular" }, "style": { "color": "#818CF8", "fontSize": 11, "fontWeight": "bold" } }
                          ]
                        }
                      ]
                    },
                    {
                      "type": "div",
                      "style": { "display": "flex", "flexDirection": "row", "alignItems": "flex-end", "gap": 4, "margin": "0 0 24 0" },
                      "children": [
                        { "type": "Text", "props": { "text": "$29" }, "style": { "fontSize": 40, "fontWeight": "bold", "color": "white" } },
                        { "type": "Text", "props": { "text": "/month" }, "style": { "fontSize": 14, "color": "#64748B", "margin": "0 0 8 0" } }
                      ]
                    },
                    {
                      "type": "Button",
                      "props": { "text": "Start Free Trial" },
                      "style": { "backgroundColor": "#6366F1", "color": "white", "padding": "12 0", "borderRadius": 10, "width": 220 }
                    },
                    { "type": "hr", "style": { "margin": "24 0", "color": "#334155" } },
                    {
                      "type": "Column",
                      "style": { "gap": 12 },
                      "children": [
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#818CF8" } },
                            { "type": "span", "props": { "text": "Unlimited templates" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        },
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#818CF8" } },
                            { "type": "span", "props": { "text": "Animation engine" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        },
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#818CF8" } },
                            { "type": "span", "props": { "text": "Canvas 2D graphics" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        },
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#818CF8" } },
                            { "type": "span", "props": { "text": "Priority support" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        },
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#818CF8" } },
                            { "type": "span", "props": { "text": "Event system & DOM API" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            },
            {
              "type": "Card",
              "key": "plan-enterprise",
              "style": {
                "backgroundColor": "#0F172A",
                "borderRadius": 16,
                "padding": "32",
                "flex": 1,
                "minWidth": 240,
                "borderWidth": 1,
                "borderColor": "#334155"
              },
              "children": [
                {
                  "type": "Container",
                  "children": [
                    {
                      "type": "h3",
                      "props": { "text": "Enterprise" },
                      "style": { "color": "#94A3B8", "fontSize": 16, "fontWeight": "w500", "margin": "0 0 8 0" }
                    },
                    {
                      "type": "div",
                      "style": { "display": "flex", "flexDirection": "row", "alignItems": "flex-end", "gap": 4, "margin": "0 0 24 0" },
                      "children": [
                        { "type": "Text", "props": { "text": "Custom" }, "style": { "fontSize": 40, "fontWeight": "bold", "color": "white" } }
                      ]
                    },
                    {
                      "type": "Button",
                      "props": { "text": "Contact Sales" },
                      "style": { "backgroundColor": "rgba(255,255,255,0.08)", "color": "white", "padding": "12 0", "borderRadius": 10, "width": 220 }
                    },
                    { "type": "hr", "style": { "margin": "24 0", "color": "#334155" } },
                    {
                      "type": "Column",
                      "style": { "gap": 12 },
                      "children": [
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#34D399" } },
                            { "type": "span", "props": { "text": "Everything in Pro" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        },
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#34D399" } },
                            { "type": "span", "props": { "text": "Custom widget registry" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        },
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#34D399" } },
                            { "type": "span", "props": { "text": "SLA & dedicated support" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        },
                        {
                          "type": "div",
                          "style": { "display": "flex", "flexDirection": "row", "gap": 8, "alignItems": "center" },
                          "children": [
                            { "type": "Icon", "props": { "icon": "check" }, "style": { "fontSize": 16, "color": "#34D399" } },
                            { "type": "span", "props": { "text": "Multi-tenant UI system" }, "style": { "color": "#CBD5E1", "fontSize": 14 } }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    },

    {
      "type": "section",
      "key": "cta-section",
      "style": {
        "padding": "80 24",
        "backgroundColor": "#0F172A"
      },
      "children": [
        {
          "type": "div",
          "style": {
            "backgroundColor": "rgba(99,102,241,0.08)",
            "borderRadius": 24,
            "padding": "60 40",
            "borderWidth": 1,
            "borderColor": "rgba(99,102,241,0.2)"
          },
          "children": [
            {
              "type": "h2",
              "props": { "text": "Ready to build dynamic UIs?" },
              "style": {
                "color": "white",
                "fontSize": 36,
                "textAlign": "center",
                "margin": "0 0 12 0",
                "letterSpacing": -0.8
              }
            },
            {
              "type": "p",
              "props": { "text": "Join thousands of developers building server-driven Flutter applications with Elpian's powerful rendering engine." },
              "style": {
                "color": "#94A3B8",
                "fontSize": 16,
                "textAlign": "center",
                "margin": "0 0 32 0"
              }
            },
            {
              "type": "div",
              "style": {
                "display": "flex",
                "flexDirection": "row",
                "gap": 16,
                "justifyContent": "center"
              },
              "children": [
                {
                  "type": "Button",
                  "props": { "text": "Get Started Free" },
                  "style": {
                    "backgroundColor": "#6366F1",
                    "color": "white",
                    "padding": "14 32",
                    "borderRadius": 10,
                    "fontSize": 16
                  }
                },
                {
                  "type": "Button",
                  "props": { "text": "Schedule Demo" },
                  "style": {
                    "backgroundColor": "rgba(255,255,255,0.06)",
                    "color": "#E2E8F0",
                    "padding": "14 32",
                    "borderRadius": 10,
                    "fontSize": 16
                  }
                }
              ]
            }
          ]
        }
      ]
    },

    {
      "type": "footer",
      "key": "main-footer",
      "style": {
        "backgroundColor": "#0F172A",
        "padding": "40 24 24 24",
        "borderWidth": 1,
        "borderColor": "#1E293B"
      },
      "children": [
        {
          "type": "Row",
          "style": {
            "justifyContent": "space-between",
            "gap": 40,
            "margin": "0 0 32 0"
          },
          "children": [
            {
              "type": "Column",
              "style": { "gap": 12 },
              "children": [
                {
                  "type": "div",
                  "style": { "display": "flex", "flexDirection": "row", "alignItems": "center", "gap": 8, "margin": "0 0 8 0" },
                  "children": [
                    { "type": "Icon", "props": { "icon": "rocket_launch" }, "style": { "fontSize": 22, "color": "#818CF8" } },
                    { "type": "span", "props": { "text": "Elpian" }, "style": { "color": "white", "fontSize": 18, "fontWeight": "bold" } }
                  ]
                },
                {
                  "type": "p",
                  "props": { "text": "High-performance server-driven\nUI engine for Flutter." },
                  "style": { "color": "#64748B", "fontSize": 13, "lineHeight": 1.5, "margin": "0" }
                }
              ]
            },
            {
              "type": "Column",
              "style": { "gap": 10 },
              "children": [
                { "type": "span", "props": { "text": "Product" }, "style": { "color": "white", "fontSize": 13, "fontWeight": "w600" } },
                { "type": "a", "props": { "text": "Features", "href": "#" }, "style": { "color": "#64748B", "fontSize": 13 } },
                { "type": "a", "props": { "text": "Pricing", "href": "#" }, "style": { "color": "#64748B", "fontSize": 13 } },
                { "type": "a", "props": { "text": "Changelog", "href": "#" }, "style": { "color": "#64748B", "fontSize": 13 } }
              ]
            },
            {
              "type": "Column",
              "style": { "gap": 10 },
              "children": [
                { "type": "span", "props": { "text": "Resources" }, "style": { "color": "white", "fontSize": 13, "fontWeight": "w600" } },
                { "type": "a", "props": { "text": "Documentation", "href": "#" }, "style": { "color": "#64748B", "fontSize": 13 } },
                { "type": "a", "props": { "text": "API Reference", "href": "#" }, "style": { "color": "#64748B", "fontSize": 13 } },
                { "type": "a", "props": { "text": "Examples", "href": "#" }, "style": { "color": "#64748B", "fontSize": 13 } }
              ]
            },
            {
              "type": "Column",
              "style": { "gap": 10 },
              "children": [
                { "type": "span", "props": { "text": "Company" }, "style": { "color": "white", "fontSize": 13, "fontWeight": "w600" } },
                { "type": "a", "props": { "text": "About", "href": "#" }, "style": { "color": "#64748B", "fontSize": 13 } },
                { "type": "a", "props": { "text": "Blog", "href": "#" }, "style": { "color": "#64748B", "fontSize": 13 } },
                { "type": "a", "props": { "text": "Contact", "href": "#" }, "style": { "color": "#64748B", "fontSize": 13 } }
              ]
            }
          ]
        },
        {
          "type": "hr",
          "style": { "color": "#1E293B", "margin": "0 0 20 0" }
        },
        {
          "type": "p",
          "props": { "text": "2026 Elpian. All rights reserved. Built with STAC Flutter UI." },
          "style": {
            "color": "#475569",
            "fontSize": 12,
            "textAlign": "center",
            "margin": "0"
          }
        }
      ]
    }
  ]
};

const BEVY_SCENE_JSON = safeJsonParse('bevy_scene.json', `
{
  "world": [
    {
      "type": "environment",
      "ambient_light": {"r": 0.4, "g": 0.4, "b": 0.5, "a": 1.0},
      "ambient_intensity": 0.3,
      "fog_enabled": true,
      "fog_color": {"r": 0.1, "g": 0.1, "b": 0.15, "a": 1.0},
      "fog_distance": 50.0
    },
    {
      "type": "camera",
      "camera_type": "Perspective",
      "fov": 60.0,
      "near": 0.1,
      "far": 1000.0,
      "transform": {
        "position": {"x": 3.0, "y": 4.0, "z": 8.0},
        "rotation": {"x": -20.0, "y": 15.0, "z": 0.0}
      }
    },
    {
      "type": "light",
      "light_type": "Directional",
      "color": {"r": 1.0, "g": 0.95, "b": 0.9, "a": 1.0},
      "intensity": 1.2,
      "transform": {
        "position": {"x": 5.0, "y": 10.0, "z": 5.0},
        "rotation": {"x": -45.0, "y": 30.0, "z": 0.0}
      }
    },
    {
      "type": "light",
      "light_type": "Point",
      "color": {"r": 0.3, "g": 0.5, "b": 1.0, "a": 1.0},
      "intensity": 0.8,
      "transform": {
        "position": {"x": -3.0, "y": 3.0, "z": 2.0}
      }
    },
    {
      "type": "mesh3d",
      "mesh": "Cube",
      "material": {
        "base_color": {"r": 0.8, "g": 0.2, "b": 0.2, "a": 1.0},
        "metallic": 0.3,
        "roughness": 0.5
      },
      "transform": {
        "position": {"x": 0.0, "y": 1.0, "z": 0.0},
        "rotation": {"x": 0.0, "y": 45.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 0.0, "y": 1.0, "z": 0.0}, "degrees": 360.0},
        "duration": 4.0,
        "looping": true,
        "easing": "Linear"
      }
    },
    {
      "type": "mesh3d",
      "mesh": {"shape": "Sphere", "radius": 0.8, "subdivisions": 16},
      "material": {
        "base_color": {"r": 0.2, "g": 0.6, "b": 0.9, "a": 1.0},
        "metallic": 0.8,
        "roughness": 0.2
      },
      "transform": {
        "position": {"x": 3.0, "y": 1.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Bounce", "height": 1.5},
        "duration": 2.0,
        "looping": true,
        "easing": "EaseInOut"
      }
    },
    {
      "type": "mesh3d",
      "mesh": {"shape": "Cylinder", "radius": 0.4, "height": 2.0},
      "material": {
        "base_color": {"r": 0.2, "g": 0.8, "b": 0.3, "a": 1.0},
        "metallic": 0.1,
        "roughness": 0.8
      },
      "transform": {
        "position": {"x": -3.0, "y": 1.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Pulse", "min_scale": 0.8, "max_scale": 1.2},
        "duration": 1.5,
        "looping": true,
        "easing": "EaseInOut"
      }
    },
    {
      "type": "mesh3d",
      "mesh": {"shape": "Plane", "size": 20.0},
      "material": {
        "base_color": {"r": 0.3, "g": 0.3, "b": 0.35, "a": 1.0},
        "metallic": 0.0,
        "roughness": 0.9
      },
      "transform": {
        "position": {"x": 0.0, "y": 0.0, "z": 0.0}
      }
    }
  ]
}
`);
const GAME_SCENE_JSON = safeJsonParse('game_scene.json', `
{
  "world": [
    {
      "type": "environment",
      "ambient_light": {"r": 0.35, "g": 0.35, "b": 0.45},
      "ambient_intensity": 0.25,
      "sky_color_top": {"r": 0.15, "g": 0.25, "b": 0.55},
      "sky_color_bottom": {"r": 0.6, "g": 0.7, "b": 0.9},
      "fog_type": "linear",
      "fog_color": {"r": 0.5, "g": 0.55, "b": 0.7},
      "fog_near": 15.0,
      "fog_distance": 60.0
    },
    {
      "type": "camera",
      "camera_type": "Perspective",
      "fov": 55.0,
      "near": 0.1,
      "far": 200.0,
      "transform": {
        "position": {"x": 6.0, "y": 5.0, "z": 12.0},
        "rotation": {"x": -18.0, "y": 20.0, "z": 0.0}
      }
    },
    {
      "type": "light",
      "light_type": "Directional",
      "color": {"r": 1.0, "g": 0.95, "b": 0.85},
      "intensity": 1.3,
      "transform": {
        "rotation": {"x": -50.0, "y": 35.0, "z": 0.0}
      }
    },
    {
      "type": "light",
      "light_type": "Point",
      "color": {"r": 1.0, "g": 0.6, "b": 0.2},
      "intensity": 1.5,
      "range": 12.0,
      "transform": {
        "position": {"x": 0.0, "y": 4.0, "z": 0.0}
      }
    },
    {
      "type": "light",
      "light_type": "Point",
      "color": {"r": 0.3, "g": 0.5, "b": 1.0},
      "intensity": 0.8,
      "range": 15.0,
      "transform": {
        "position": {"x": -5.0, "y": 3.0, "z": 4.0}
      }
    },

    {
      "type": "mesh3d",
      "name": "ground",
      "mesh": {"shape": "Plane", "size": 30.0},
      "material": {
        "base_color": {"r": 0.25, "g": 0.3, "b": 0.2},
        "roughness": 0.95,
        "metallic": 0.0,
        "texture": "checkerboard",
        "texture_color2": {"r": 0.2, "g": 0.25, "b": 0.18},
        "texture_scale": 4.0
      },
      "transform": {
        "position": {"x": 0.0, "y": 0.0, "z": 0.0}
      }
    },

    {
      "type": "mesh3d",
      "name": "crystal_tower",
      "mesh": {"shape": "Cylinder", "radius": 0.3, "height": 4.0, "segments": 6},
      "material": {
        "base_color": {"r": 0.4, "g": 0.7, "b": 0.9, "a": 0.85},
        "metallic": 0.9,
        "roughness": 0.1,
        "emissive": {"r": 0.1, "g": 0.2, "b": 0.4},
        "emissive_strength": 2.0,
        "alpha_mode": "blend"
      },
      "transform": {
        "position": {"x": 0.0, "y": 2.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 0.0, "y": 1.0, "z": 0.0}, "degrees": 360.0},
        "duration": 8.0,
        "looping": true,
        "easing": "Linear"
      }
    },

    {
      "type": "mesh3d",
      "name": "floating_sphere",
      "mesh": {"shape": "Sphere", "radius": 0.7, "subdivisions": 20},
      "material": {
        "base_color": {"r": 0.9, "g": 0.3, "b": 0.15},
        "metallic": 0.7,
        "roughness": 0.2,
        "emissive": {"r": 0.3, "g": 0.05, "b": 0.0},
        "emissive_strength": 1.5
      },
      "transform": {
        "position": {"x": 0.0, "y": 5.5, "z": 0.0}
      },
      "animation": [
        {
          "animation_type": {"type": "Bounce", "height": 0.8},
          "duration": 3.0,
          "looping": true,
          "easing": "EaseInOut"
        },
        {
          "animation_type": {"type": "Rotate", "axis": {"x": 0.3, "y": 1.0, "z": 0.1}, "degrees": 360.0},
          "duration": 5.0,
          "looping": true,
          "easing": "Linear"
        }
      ]
    },

    {
      "type": "group",
      "name": "stone_ring",
      "transform": {
        "position": {"x": 0.0, "y": 0.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 0.0, "y": 1.0, "z": 0.0}, "degrees": 360.0},
        "duration": 20.0,
        "looping": true,
        "easing": "Linear"
      },
      "children": [
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.5, "g": 0.5, "b": 0.55},
            "roughness": 0.8,
            "metallic": 0.1
          },
          "transform": {
            "position": {"x": 5.0, "y": 0.75, "z": 0.0},
            "scale": {"x": 0.8, "y": 1.5, "z": 0.8}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.55, "g": 0.5, "b": 0.5},
            "roughness": 0.85,
            "metallic": 0.05
          },
          "transform": {
            "position": {"x": -5.0, "y": 0.6, "z": 0.0},
            "scale": {"x": 0.7, "y": 1.2, "z": 0.7}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.5, "g": 0.52, "b": 0.5},
            "roughness": 0.82,
            "metallic": 0.08
          },
          "transform": {
            "position": {"x": 0.0, "y": 0.9, "z": 5.0},
            "scale": {"x": 0.9, "y": 1.8, "z": 0.9}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.48, "g": 0.48, "b": 0.52},
            "roughness": 0.9,
            "metallic": 0.05
          },
          "transform": {
            "position": {"x": 0.0, "y": 0.5, "z": -5.0},
            "scale": {"x": 0.6, "y": 1.0, "z": 0.6}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.52, "g": 0.5, "b": 0.48},
            "roughness": 0.87,
            "metallic": 0.06
          },
          "transform": {
            "position": {"x": 3.54, "y": 0.65, "z": 3.54},
            "scale": {"x": 0.75, "y": 1.3, "z": 0.75}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.5, "g": 0.48, "b": 0.52},
            "roughness": 0.88,
            "metallic": 0.07
          },
          "transform": {
            "position": {"x": -3.54, "y": 0.7, "z": -3.54},
            "scale": {"x": 0.7, "y": 1.4, "z": 0.7}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.53, "g": 0.51, "b": 0.5},
            "roughness": 0.83,
            "metallic": 0.09
          },
          "transform": {
            "position": {"x": 3.54, "y": 0.55, "z": -3.54},
            "scale": {"x": 0.65, "y": 1.1, "z": 0.65}
          }
        },
        {
          "type": "mesh3d",
          "mesh": "Cube",
          "material": {
            "base_color": {"r": 0.5, "g": 0.53, "b": 0.51},
            "roughness": 0.86,
            "metallic": 0.04
          },
          "transform": {
            "position": {"x": -3.54, "y": 0.8, "z": 3.54},
            "scale": {"x": 0.85, "y": 1.6, "z": 0.85}
          }
        }
      ]
    },

    {
      "type": "mesh3d",
      "name": "torus_portal",
      "mesh": {"shape": "Torus", "major_radius": 2.0, "tube_radius": 0.15, "radial_segments": 24, "tubular_segments": 32},
      "material": {
        "base_color": {"r": 0.8, "g": 0.7, "b": 0.2},
        "metallic": 0.95,
        "roughness": 0.1,
        "emissive": {"r": 0.3, "g": 0.25, "b": 0.05},
        "emissive_strength": 1.0
      },
      "transform": {
        "position": {"x": -6.0, "y": 3.0, "z": -2.0},
        "rotation": {"x": 90.0, "y": 0.0, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 0.0, "y": 0.0, "z": 1.0}, "degrees": 360.0},
        "duration": 6.0,
        "looping": true,
        "easing": "Linear"
      }
    },

    {
      "type": "mesh3d",
      "name": "pyramid_ancient",
      "mesh": {"shape": "Pyramid", "base": 3.0, "height": 2.5},
      "material": {
        "base_color": {"r": 0.7, "g": 0.6, "b": 0.4},
        "roughness": 0.7,
        "metallic": 0.05,
        "texture": "noise",
        "texture_scale": 3.0
      },
      "transform": {
        "position": {"x": 7.0, "y": 0.0, "z": -5.0}
      }
    },

    {
      "type": "mesh3d",
      "name": "capsule_pod",
      "mesh": {"shape": "Capsule", "radius": 0.5, "height": 1.2, "segments": 16},
      "material": {
        "base_color": {"r": 0.2, "g": 0.8, "b": 0.4},
        "metallic": 0.6,
        "roughness": 0.3
      },
      "transform": {
        "position": {"x": -4.0, "y": 1.5, "z": 5.0}
      },
      "animation": {
        "animation_type": {"type": "Pulse", "min_scale": 0.85, "max_scale": 1.15},
        "duration": 2.5,
        "looping": true,
        "easing": "Sine"
      }
    },

    {
      "type": "mesh3d",
      "name": "wedge_ramp",
      "mesh": {"shape": "Wedge", "width": 2.0, "height": 1.5, "depth": 3.0},
      "material": {
        "base_color": {"r": 0.6, "g": 0.35, "b": 0.2},
        "roughness": 0.6,
        "metallic": 0.15,
        "texture": "stripes",
        "texture_color2": {"r": 0.5, "g": 0.3, "b": 0.15},
        "texture_scale": 2.0
      },
      "transform": {
        "position": {"x": 5.0, "y": 0.0, "z": 6.0},
        "rotation": {"x": 0.0, "y": -30.0, "z": 0.0}
      }
    },

    {
      "type": "mesh3d",
      "name": "icosphere_gem",
      "mesh": {"shape": "IcoSphere", "radius": 0.6, "subdivisions": 3},
      "material": {
        "base_color": {"r": 0.3, "g": 0.1, "b": 0.8},
        "metallic": 1.0,
        "roughness": 0.05,
        "emissive": {"r": 0.1, "g": 0.0, "b": 0.3},
        "emissive_strength": 2.0
      },
      "transform": {
        "position": {"x": -7.0, "y": 2.0, "z": -6.0}
      },
      "animation": [
        {
          "animation_type": {"type": "Bounce", "height": 1.0},
          "duration": 2.0,
          "looping": true,
          "easing": "Bounce"
        },
        {
          "animation_type": {"type": "Rotate", "axis": {"x": 1.0, "y": 1.0, "z": 0.0}, "degrees": 360.0},
          "duration": 3.0,
          "looping": true,
          "easing": "Linear"
        }
      ]
    },

    {
      "type": "mesh3d",
      "name": "wireframe_sphere",
      "mesh": {"shape": "Sphere", "radius": 1.5, "subdivisions": 8},
      "material": {
        "base_color": {"r": 0.0, "g": 1.0, "b": 0.5, "a": 0.6},
        "wireframe": true,
        "unlit": true,
        "alpha_mode": "blend"
      },
      "transform": {
        "position": {"x": 0.0, "y": 5.5, "z": 0.0}
      },
      "animation": {
        "animation_type": {"type": "Rotate", "axis": {"x": 0.2, "y": 1.0, "z": 0.3}, "degrees": 360.0},
        "duration": 12.0,
        "looping": true,
        "easing": "Linear"
      }
    },

    {
      "type": "mesh3d",
      "name": "cone_spire",
      "mesh": {"shape": "Cone", "radius": 0.6, "height": 3.0, "segments": 12},
      "material": {
        "base_color": {"r": 0.7, "g": 0.2, "b": 0.5},
        "metallic": 0.4,
        "roughness": 0.4
      },
      "transform": {
        "position": {"x": 8.0, "y": 0.0, "z": 3.0}
      }
    },

    {
      "type": "particles",
      "name": "fire_particles",
      "transform": {
        "position": {"x": 0.0, "y": 4.2, "z": 0.0}
      },
      "emitter": {
        "shape": "point",
        "emit_rate": 30,
        "lifetime": 1.5,
        "start_color": {"r": 1.0, "g": 0.8, "b": 0.2},
        "end_color": {"r": 1.0, "g": 0.2, "b": 0.0},
        "start_size": 0.15,
        "end_size": 0.02,
        "start_alpha": 0.9,
        "end_alpha": 0.0,
        "gravity": {"x": 0.0, "y": 1.5, "z": 0.0},
        "spread": 25.0,
        "speed": 1.5,
        "speed_variance": 0.5,
        "max_particles": 100
      }
    },

    {
      "type": "particles",
      "name": "sparkle_ring",
      "transform": {
        "position": {"x": -6.0, "y": 3.0, "z": -2.0}
      },
      "emitter": {
        "shape": "ring",
        "emit_rate": 15,
        "lifetime": 2.0,
        "start_color": {"r": 1.0, "g": 0.9, "b": 0.5},
        "end_color": {"r": 0.5, "g": 0.3, "b": 1.0},
        "start_size": 0.08,
        "end_size": 0.0,
        "start_alpha": 1.0,
        "end_alpha": 0.0,
        "gravity": {"x": 0.0, "y": 0.5, "z": 0.0},
        "spread": 60.0,
        "speed": 0.8,
        "max_particles": 60
      }
    }
  ]
}
`);


// ─────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────
function text(t, style) {
  return { type: 'Text', props: { text: String(t), style: style || {} } };
}

function heading(t, size) {
  return text(t, { fontSize: String(size || 22), fontWeight: 'bold', color: '#1e293b' });
}

function subheading(t) {
  return text(t, { fontSize: '17', fontWeight: '600', color: '#475569' });
}

function spacer(h) {
  return { type: 'SizedBox', props: { style: { height: String(h || 12) } } };
}

function card(children, extraStyle) {
  const base = {
    padding: '16',
    backgroundColor: '#ffffff',
    borderRadius: '12',
    border: '1px solid #e2e8f0'
  };
  return {
    type: 'Container',
    props: { style: Object.assign(base, extraStyle || {}) },
    children: children
  };
}

function btn(label, handler, style) {
  const base = {
    backgroundColor: '#6366f1',
    color: '#ffffff',
    padding: '10 20',
    borderRadius: '8',
    fontSize: '14',
    fontWeight: '600'
  };
  return {
    type: 'Button',
    props: { text: label, style: Object.assign(base, style || {}) },
    events: { tap: handler }
  };
}

function col(children, style) {
  return { type: 'Column', props: { style: style || {} }, children: children };
}

function row(children, style) {
  return { type: 'Row', props: { style: style || {} }, children: children };
}

function divider() {
  return { type: 'Container', props: { style: { height: '1', backgroundColor: '#e2e8f0', margin: '8 0' } } };
}

function scope(child, key) {
  return {
    type: 'Scope',
    key: key,
    children: [child]
  };
}

const SHELL_TABS_SCOPE_KEY = 'scope-shell-tabs';
const SHELL_BODY_SCOPE_KEY = 'scope-shell-body';
const SHELL_CONTENT_SCOPE_KEY = 'scope-shell-content';
const VM_PANEL_SCOPE_KEY = 'scope-vm-panel';
const TAB_SCOPE_KEYS = [
  'scope-tab-ui',
  'scope-tab-canvas',
  'scope-tab-vm',
  'scope-tab-dom-canvas',
  'scope-tab-landing',
  'scope-tab-bevy',
  'scope-tab-game',
  'scope-tab-real-world'
];

function tabBuilders() {
  return [
    buildUiWidgetsTab,
    buildCanvasTab,
    buildVmDemosTab,
    buildDomCanvasTab,
    buildLandingPageTab,
    buildBevyTab,
    buildGameTab,
    buildRealWorldTab
  ];
}

function vmSubTabVisible(index) {
  return activeTab === 2 && activeSubTab === index;
}

function realWorldSubTabVisible(index) {
  return activeTab === 7 && activeSubTab === index;
}

function buildVmPanel() {
  const content = [buildCounterDemo, buildClockDemo, buildAnalogClockDemo, buildWhiteboardDemo, buildThemeDemo, buildHostDataDemo];
  const idx = Math.min(activeSubTab, content.length - 1);
  return content[idx]();
}

function buildActiveTabScope() {
  const builders = tabBuilders();
  const idx = Math.min(activeTab, builders.length - 1);
  return scope(builders[idx](), TAB_SCOPE_KEYS[idx]);
}

function buildShellBody() {
  return {
    type: 'Expanded',
    children: [
      {
        type: 'ListView',
        props: { scrollable: !wbIsDrawing, style: { backgroundColor: '#f8fafc' } },
        children: [
          scope(buildActiveTabScope(), SHELL_CONTENT_SCOPE_KEY)
        ]
      }
    ]
  };
}

function renderScoped(scopeKey, node) {
  askHost('render', JSON.stringify(node), scopeKey);
}

function rerenderShellTabs() {
  renderScoped(
    SHELL_TABS_SCOPE_KEY,
    scope(buildTabBar(), SHELL_TABS_SCOPE_KEY)
  );
}

function rerenderShellContent() {
  renderScoped(
    SHELL_CONTENT_SCOPE_KEY,
    scope(buildActiveTabScope(), SHELL_CONTENT_SCOPE_KEY)
  );
}

function rerenderShellBody() {
  renderScoped(
    SHELL_BODY_SCOPE_KEY,
    scope(buildShellBody(), SHELL_BODY_SCOPE_KEY)
  );
}

function rerenderActiveTab() {
  const builders = tabBuilders();
  const idx = Math.min(activeTab, builders.length - 1);
  renderScoped(
    TAB_SCOPE_KEYS[idx],
    scope(builders[idx](), TAB_SCOPE_KEYS[idx])
  );
}

function rerenderVmPanel() {
  if (activeTab !== 2) return;
  renderScoped(
    VM_PANEL_SCOPE_KEY,
    scope(buildVmPanel(), VM_PANEL_SCOPE_KEY)
  );
}

function money(v) {
  return '$' + Number(v).toFixed(2);
}

function rwCartSubtotal() {
  let sum = 0;
  for (let i = 0; i < rwCart.length; i += 1) {
    sum += rwCart[i].price * rwCart[i].qty;
  }
  return sum;
}

function rwCartTotal() {
  const sub = rwCartSubtotal();
  return Math.max(0, sub - rwDiscount);
}

function hostTimerCall(apiName, payload) {
  try {
    const response = askHost(apiName, JSON.stringify(payload || {}));
    const parsed = JSON.parse(response);
    return parsed && parsed.data ? parsed.data.value : null;
  } catch (_) {
    return null;
  }
}

function wbEnsureContext() {
  if (wbContextId) return wbContextId;
  wbContextId = hostTimerCall('canvas.ctx.create', {
    id: 'whiteboard_ctx',
    width: 420,
    height: 260
  });
  wbInitContext();
  return wbContextId;
}

function wbInitContext() {
  if (!wbContextId) return;
  hostTimerCall('canvas.ctx.clear', { id: wbContextId });
  hostTimerCall('canvas.ctx.addCommands', {
    id: wbContextId,
    commands: [
      { type: 'setFillStyle', params: { color: '#ffffff' } },
      { type: 'fillRect', params: { x: 0, y: 0, width: 420, height: 260 } },
      { type: 'setStrokeStyle', params: { color: '#e2e8f0' } },
      { type: 'setLineWidth', params: { width: 1 } },
      { type: 'beginPath', params: {} },
      { type: 'moveTo', params: { x: 0, y: 0 } },
      { type: 'lineTo', params: { x: 420, y: 0 } },
      { type: 'lineTo', params: { x: 420, y: 260 } },
      { type: 'lineTo', params: { x: 0, y: 260 } },
      { type: 'closePath', params: {} },
      { type: 'stroke', params: {} },
      { type: 'setLineCap', params: { cap: 'round' } },
      { type: 'setLineJoin', params: { join: 'round' } }
    ]
  });
}

function wbScheduleRender() {
  const now = Date.now();
  if (now - wbLastRenderAt >= 16) {
    wbLastRenderAt = now;
    if (vmSubTabVisible(3)) rerenderVmPanel();
    return;
  }
  if (wbRenderPending) return;
  wbRenderPending = true;
  if (wbRenderTimerId !== null) {
    hostTimerCall('clearTimeout', { id: wbRenderTimerId });
  }
  wbRenderTimerId = hostTimerCall('setTimeout', {
    handler: 'wbRenderTick',
    delay: 16
  });
}

function wbRenderTick() {
  wbRenderPending = false;
  wbLastRenderAt = Date.now();
  if (vmSubTabVisible(3)) rerenderVmPanel();
}

function startClockTimer() {
  if (clockTimerId !== null) {
    hostTimerCall('clearInterval', { id: clockTimerId });
    clockTimerId = null;
  }
  clockTimerId = hostTimerCall('setInterval', {
    handler: 'tickClock',
    delay: 1000
  });
}

// ─────────────────────────────────────────────────────────
// Tab bar (rendered as part of the QuickJS view tree)
// ─────────────────────────────────────────────────────────
function buildTabBar() {
  const tabs = TABS.map((label, i) => {
    const isActive = i === activeTab;
    return {
      type: 'Container',
      props: {
        style: {
          padding: '12 20',
          backgroundColor: isActive ? '#6366f1' : '#f1f5f9',
          borderRadius: '8 8 0 0',
          margin: '0 2 0 0'
        }
      },
      events: { tap: 'switchTab_' + i },
      children: [
        text(label, {
          fontSize: '14',
          fontWeight: isActive ? 'bold' : '500',
          color: isActive ? '#ffffff' : '#64748b'
        })
      ]
    };
  });

  return {
    type: 'Container',
    props: {
      style: {
        backgroundColor: '#f8fafc',
        padding: '12 16 0 16',
        borderRadius: '0',
        border: '0 0 1px 0 solid #e2e8f0'
      }
    },
    children: [
      row([
        text('Elpian', { fontSize: '20', fontWeight: 'bold', color: '#6366f1', margin: '0 16 0 0' }),
        text('Unified QuickJS Example', { fontSize: '14', color: '#94a3b8' })
      ], { alignItems: 'center', margin: '0 0 12 0' }),
      { type: 'Wrap', props: { style: { gap: '6' } }, children: tabs }
    ]
  };
}

// ─────────────────────────────────────────────────────────
// Sub-tab builder
// ─────────────────────────────────────────────────────────
function buildSubTabs(labels) {
  const chips = labels.map((label, i) => {
    const isActive = i === activeSubTab;
    return {
      type: 'Container',
      props: {
        style: {
          padding: '8 16',
          backgroundColor: isActive ? '#e0e7ff' : '#f8fafc',
          borderRadius: '20',
          border: isActive ? '1px solid #6366f1' : '1px solid #e2e8f0'
        }
      },
      events: { tap: 'switchSubTab_' + i },
      children: [
        text(label, {
          fontSize: '13',
          fontWeight: isActive ? '600' : '400',
          color: isActive ? '#4338ca' : '#64748b'
        })
      ]
    };
  });
  return { type: 'Wrap', props: { style: { gap: '8', margin: '0 0 16 0' } }, children: chips };
}

// ─────────────────────────────────────────────────────────
// TAB 0 – UI Widgets
// ─────────────────────────────────────────────────────────
function buildUiWidgetsTab() {
  const subTabs = ['Flutter Widgets', 'HTML Elements', 'Dashboard'];
  const content = [buildFlutterWidgets, buildHtmlElements, buildDashboard];
  const idx = Math.min(activeSubTab, content.length - 1);
  return col([
    buildSubTabs(subTabs),
    content[idx]()
  ], { padding: '16' });
}

function buildFlutterWidgets() {
  return col([
    heading('Flutter Widgets'),
    spacer(8),
    card([
      text('This card is rendered entirely from QuickJS.', { fontSize: '15', color: '#475569' }),
      spacer(8),
      text('The engine supports all standard Flutter & HTML widgets.', { fontSize: '14', color: '#64748b' })
    ]),
    spacer(12),
    subheading('Buttons'),
    spacer(8),
    row([
      btn('Primary', 'noop', {}),
      btn('Success', 'noop', { backgroundColor: '#10b981' }),
      btn('Danger', 'noop', { backgroundColor: '#ef4444' }),
      btn('Warning', 'noop', { backgroundColor: '#f59e0b', color: '#1e293b' })
    ], { gap: '8', flexWrap: 'wrap' }),
    spacer(16),
    subheading('Cards Row'),
    spacer(8),
    row([
      card([
        text('1,234', { fontSize: '28', fontWeight: 'bold', color: '#ffffff' }),
        text('Users', { fontSize: '13', color: '#e2e8f0' })
      ], { backgroundColor: '#6366f1', flex: '1' }),
      card([
        text('567', { fontSize: '28', fontWeight: 'bold', color: '#ffffff' }),
        text('Sales', { fontSize: '13', color: '#e2e8f0' })
      ], { backgroundColor: '#10b981', flex: '1' }),
      card([
        text('89%', { fontSize: '28', fontWeight: 'bold', color: '#ffffff' }),
        text('Uptime', { fontSize: '13', color: '#e2e8f0' })
      ], { backgroundColor: '#f59e0b', flex: '1' })
    ], { gap: '12' }),
    spacer(16),
    subheading('Chips'),
    spacer(8),
    {
      type: 'Wrap',
      props: { style: { gap: '8' } },
      children: [
        { type: 'Chip', props: { label: 'Flutter' }, style: { backgroundColor: '#e0e7ff' } },
        { type: 'Chip', props: { label: 'Dart' }, style: { backgroundColor: '#fce7f3' } },
        { type: 'Chip', props: { label: 'QuickJS' }, style: { backgroundColor: '#d1fae5' } },
        { type: 'Chip', props: { label: 'Elpian' }, style: { backgroundColor: '#fef3c7' } }
      ]
    }
  ]);
}

function buildHtmlElements() {
  return col([
    heading('HTML Elements'),
    spacer(8),
    { type: 'h1', props: { text: 'Heading 1' }, style: { color: '#e11d48' } },
    { type: 'h2', props: { text: 'Heading 2' }, style: { color: '#7c3aed' } },
    { type: 'h3', props: { text: 'Heading 3' }, style: { color: '#2563eb' } },
    spacer(8),
    { type: 'p', props: { text: 'This is a paragraph rendered from the QuickJS runtime through the Elpian engine.' }, style: { fontSize: '16', color: '#475569', lineHeight: '1.6' } },
    spacer(8),
    {
      type: 'ul',
      children: [
        { type: 'li', props: { text: 'Unordered list item 1' } },
        { type: 'li', props: { text: 'Unordered list item 2' } },
        { type: 'li', props: { text: 'Unordered list item 3' } }
      ]
    },
    spacer(8),
    {
      type: 'details',
      children: [
        { type: 'summary', props: { text: 'Click to expand' } },
        { type: 'p', props: { text: 'Hidden content revealed by the <details> element!' } }
      ]
    },
    spacer(8),
    row([
      { type: 'kbd', props: { text: 'Ctrl' } },
      text(' + ', { fontSize: '14' }),
      { type: 'kbd', props: { text: 'C' } }
    ], { alignItems: 'center', gap: '4' }),
    spacer(8),
    { type: 'progress', props: { value: 0.7, max: 1.0 }, style: { margin: '8 0' } },
    spacer(8),
    {
      type: 'blockquote',
      children: [
        { type: 'p', props: { text: '"The best way to predict the future is to invent it." — Alan Kay' } }
      ]
    }
  ]);
}

function buildDashboard() {
  return col([
    heading('Dashboard'),
    spacer(8),
    {
      type: 'header',
      style: { backgroundColor: '#1e293b', padding: '16', borderRadius: '10', margin: '0 0 12 0' },
      children: [
        { type: 'h2', props: { text: 'Statistics Overview' }, style: { color: '#ffffff', margin: '0' } }
      ]
    },
    row([
      card([
        text('Revenue', { fontSize: '13', color: '#94a3b8' }),
        text('$42,580', { fontSize: '24', fontWeight: 'bold', color: '#10b981' })
      ], { flex: '1' }),
      card([
        text('Orders', { fontSize: '13', color: '#94a3b8' }),
        text('1,847', { fontSize: '24', fontWeight: 'bold', color: '#6366f1' })
      ], { flex: '1' }),
      card([
        text('Customers', { fontSize: '13', color: '#94a3b8' }),
        text('3,210', { fontSize: '24', fontWeight: 'bold', color: '#f59e0b' })
      ], { flex: '1' })
    ], { gap: '12' }),
    spacer(12),
    card([
      subheading('Recent Activity'),
      spacer(8),
      text('• New user signed up – john@example.com', { fontSize: '14', color: '#64748b' }),
      text('• Order #1847 completed', { fontSize: '14', color: '#64748b' }),
      text('• Server uptime: 99.98%', { fontSize: '14', color: '#64748b' }),
      text('• 12 new support tickets', { fontSize: '14', color: '#64748b' })
    ]),
    spacer(12),
    {
      type: 'footer',
      style: { padding: '14', backgroundColor: '#f1f5f9', borderRadius: '10' },
      children: [
        { type: 'p', props: { text: '© 2025 Elpian UI – QuickJS Unified Demo' }, style: { textAlign: 'center', color: '#94a3b8', margin: '0', fontSize: '13' } }
      ]
    }
  ]);
}

// ─────────────────────────────────────────────────────────
// TAB 1 – Canvas
// ─────────────────────────────────────────────────────────
function buildCanvasTab() {
  const subTabs = ['Shapes', 'Paths & Curves', 'Text', 'Gradients'];
  const content = [buildCanvasShapes, buildCanvasPaths, buildCanvasText, buildCanvasGradients];
  const idx = Math.min(activeSubTab, content.length - 1);
  return col([
    buildSubTabs(subTabs),
    content[idx]()
  ], { padding: '16' });
}

function buildCanvasShapes() {
  return col([
    heading('Basic Shapes'),
    spacer(8),
    subheading('Rectangles'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 160,
        commands: [
          { type: 'setFillStyle', params: { color: '#ef4444' } },
          { type: 'fillRect', params: { x: 20, y: 20, width: 100, height: 80 } },
          { type: 'setStrokeStyle', params: { color: '#3b82f6' } },
          { type: 'setLineWidth', params: { width: 3 } },
          { type: 'strokeRect', params: { x: 140, y: 20, width: 100, height: 80 } },
          { type: 'setFillStyle', params: { color: '#22c55e' } },
          { type: 'beginPath', params: {} },
          { type: 'roundRect', params: { x: 260, y: 20, width: 100, height: 80, radius: 12 } },
          { type: 'fill', params: {} }
        ]
      }
    },
    spacer(12),
    subheading('Circles'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 160,
        commands: [
          { type: 'setFillStyle', params: { color: '#8b5cf6' } },
          { type: 'fillCircle', params: { x: 70, y: 80, radius: 50 } },
          { type: 'setStrokeStyle', params: { color: '#f97316' } },
          { type: 'setLineWidth', params: { width: 4 } },
          { type: 'strokeCircle', params: { x: 200, y: 80, radius: 50 } },
          { type: 'setFillStyle', params: { color: '#06b6d4' } },
          { type: 'beginPath', params: {} },
          { type: 'ellipse', params: { x: 330, y: 80, radiusX: 55, radiusY: 40 } },
          { type: 'fill', params: {} }
        ]
      }
    }
  ]);
}

function buildCanvasPaths() {
  return col([
    heading('Paths & Curves'),
    spacer(8),
    subheading('Bezier Curves'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 160,
        commands: [
          { type: 'setStrokeStyle', params: { color: '#3b82f6' } },
          { type: 'setLineWidth', params: { width: 3 } },
          { type: 'beginPath', params: {} },
          { type: 'moveTo', params: { x: 50, y: 80 } },
          { type: 'bezierCurveTo', params: { cp1x: 100, cp1y: 10, cp2x: 150, cp2y: 150, x: 200, y: 80 } },
          { type: 'stroke', params: {} },
          { type: 'setStrokeStyle', params: { color: '#22c55e' } },
          { type: 'beginPath', params: {} },
          { type: 'moveTo', params: { x: 220, y: 80 } },
          { type: 'quadraticCurveTo', params: { cpx: 280, cpy: 10, x: 340, y: 80 } },
          { type: 'stroke', params: {} }
        ]
      }
    },
    spacer(12),
    subheading('Triangle'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 160,
        commands: [
          { type: 'setFillStyle', params: { color: '#f97316' } },
          { type: 'setStrokeStyle', params: { color: '#c2410c' } },
          { type: 'setLineWidth', params: { width: 3 } },
          { type: 'beginPath', params: {} },
          { type: 'moveTo', params: { x: 200, y: 20 } },
          { type: 'lineTo', params: { x: 280, y: 140 } },
          { type: 'lineTo', params: { x: 120, y: 140 } },
          { type: 'closePath', params: {} },
          { type: 'fill', params: {} },
          { type: 'stroke', params: {} }
        ]
      }
    }
  ]);
}

function buildCanvasText() {
  return col([
    heading('Text Rendering'),
    spacer(8),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 220,
        commands: [
          { type: 'setFillStyle', params: { color: '#1e293b' } },
          { type: 'setFont', params: { font: '24px Arial' } },
          { type: 'fillText', params: { text: 'Hello Canvas!', x: 40, y: 40 } },
          { type: 'setFont', params: { font: 'bold 28px Arial' } },
          { type: 'setFillStyle', params: { color: '#3b82f6' } },
          { type: 'fillText', params: { text: 'Bold Text', x: 40, y: 80 } },
          { type: 'setFont', params: { font: 'italic 20px Arial' } },
          { type: 'setFillStyle', params: { color: '#22c55e' } },
          { type: 'fillText', params: { text: 'Italic Text', x: 40, y: 120 } },
          { type: 'setStrokeStyle', params: { color: '#ef4444' } },
          { type: 'setLineWidth', params: { width: 1.5 } },
          { type: 'setFont', params: { font: 'bold 30px Arial' } },
          { type: 'strokeText', params: { text: 'Outlined', x: 40, y: 168 } },
          { type: 'setFillStyle', params: { color: '#fbbf24' } },
          { type: 'setFont', params: { font: 'bold 26px Arial' } },
          { type: 'fillText', params: { text: 'Golden', x: 40, y: 210 } }
        ]
      }
    }
  ]);
}

function buildCanvasGradients() {
  return col([
    heading('Gradients'),
    spacer(8),
    subheading('Linear Gradient'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 120,
        commands: [
          { type: 'createLinearGradient', params: { id: 'g1', x0: 40, y0: 60, x1: 360, y1: 60, colors: ['#ef4444', '#8b5cf6', '#3b82f6'] } },
          { type: 'setFillStyle', params: { gradientId: 'g1' } },
          { type: 'fillRect', params: { x: 40, y: 20, width: 320, height: 80 } }
        ]
      }
    },
    spacer(12),
    subheading('Radial Gradient'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 180,
        commands: [
          { type: 'createRadialGradient', params: { id: 'g2', x: 200, y: 90, r: 70, colors: ['#fbbf24', '#f97316', '#ef4444'] } },
          { type: 'setFillStyle', params: { gradientId: 'g2' } },
          { type: 'fillCircle', params: { x: 200, y: 90, radius: 70 } }
        ]
      }
    }
  ]);
}

// ─────────────────────────────────────────────────────────
// TAB 2 – VM Demos (all driven by QuickJS state)
// ─────────────────────────────────────────────────────────
function buildVmDemosTab() {
  const subTabs = ['Counter', 'Clock', 'Analog Clock', 'Whiteboard', 'Theme Toggle', 'Host Data'];
  return col([
    buildSubTabs(subTabs),
    scope(buildVmPanel(), VM_PANEL_SCOPE_KEY)
  ], { padding: '16' });
}

function buildCounterDemo() {
  return col([
    heading('Interactive Counter'),
    spacer(8),
    card([
      text('QuickJS Counter', { fontSize: '18', fontWeight: 'bold', color: '#1e293b' }),
      spacer(8),
      text(`Current value: ${count}`, { fontSize: '32', fontWeight: 'bold', color: '#6366f1' }),
      spacer(4),
      text('Tap the buttons below or the card to increment.', { fontSize: '14', color: '#94a3b8' })
    ], { border: '2px solid #e0e7ff' }),
    spacer(12),
    row([
      btn('− Decrement', 'decrement', { backgroundColor: '#64748b', flex: '1' }),
      btn('+ Increment', 'increment', { flex: '1' }),
    ], { gap: '8' }),
    spacer(8),
    btn('Reset', 'resetCounter', { backgroundColor: '#ef4444' })
  ]);
}

function buildClockDemo() {
  return col([
    heading('QuickJS Clock'),
    spacer(8),
    card([
      text('Current Time', { fontSize: '16', fontWeight: '600', color: '#94a3b8' }),
      spacer(8),
      text(clockTime, { fontSize: '22', fontWeight: 'bold', color: '#10b981' }),
      spacer(4),
      text('Press Refresh to update the timestamp from JS Date().', { fontSize: '13', color: '#94a3b8' })
    ], { backgroundColor: '#0f172a', border: 'none' }),
    spacer(12),
    btn('Refresh Clock', 'refreshClock', { backgroundColor: '#10b981' })
  ]);
}

function buildAnalogClockDemo() {
  const now = new Date(clockTime);
  const centerX = 140;
  const centerY = 140;
  const radius = 110;
  const second = now.getSeconds();
  const minute = now.getMinutes();
  const hour = now.getHours() % 12;

  const secAngle = (Math.PI * 2) * (second / 60) - Math.PI / 2;
  const minAngle = (Math.PI * 2) * ((minute + second / 60) / 60) - Math.PI / 2;
  const hourAngle = (Math.PI * 2) * ((hour + minute / 60) / 12) - Math.PI / 2;

  function hand(angle, length, width, color) {
    return [
      { type: 'setStrokeStyle', params: { color: color } },
      { type: 'setLineWidth', params: { width: width } },
      { type: 'beginPath', params: {} },
      { type: 'moveTo', params: { x: centerX, y: centerY } },
      { type: 'lineTo', params: { x: centerX + Math.cos(angle) * length, y: centerY + Math.sin(angle) * length } },
      { type: 'stroke', params: {} }
    ];
  }

  const tickMarks = [];
  for (let i = 0; i < 12; i += 1) {
    const a = (Math.PI * 2) * (i / 12) - Math.PI / 2;
    const inner = radius - 14;
    tickMarks.push(
      { type: 'setStrokeStyle', params: { color: '#1f2937' } },
      { type: 'setLineWidth', params: { width: 3 } },
      { type: 'beginPath', params: {} },
      { type: 'moveTo', params: { x: centerX + Math.cos(a) * inner, y: centerY + Math.sin(a) * inner } },
      { type: 'lineTo', params: { x: centerX + Math.cos(a) * radius, y: centerY + Math.sin(a) * radius } },
      { type: 'stroke', params: {} }
    );
  }

  const commands = [
    { type: 'setFillStyle', params: { color: '#f8fafc' } },
    { type: 'fillRect', params: { x: 0, y: 0, width: 280, height: 280 } },
    { type: 'setFillStyle', params: { color: '#ffffff' } },
    { type: 'fillCircle', params: { x: centerX, y: centerY, radius: radius } },
    { type: 'setStrokeStyle', params: { color: '#94a3b8' } },
    { type: 'setLineWidth', params: { width: 4 } },
    { type: 'strokeCircle', params: { x: centerX, y: centerY, radius: radius } },
    ...tickMarks,
    ...hand(hourAngle, radius * 0.5, 5, '#111827'),
    ...hand(minAngle, radius * 0.72, 3.5, '#334155'),
    ...hand(secAngle, radius * 0.82, 2, '#ef4444'),
    { type: 'setFillStyle', params: { color: '#111827' } },
    { type: 'fillCircle', params: { x: centerX, y: centerY, radius: 4 } }
  ];

  return col([
    heading('Analog Clock'),
    spacer(8),
    text('Live clock driven by QuickJS time state.', { fontSize: '14', color: '#64748b' }),
    spacer(8),
    { type: 'Canvas', props: { width: 280, height: 280, commands: commands } },
    spacer(12),
    btn('Sync Time', 'refreshClock', { backgroundColor: '#0ea5e9' })
  ]);
}

function buildThemeDemo() {
  const bg = isDark ? '#1e293b' : '#ffffff';
  const fg = isDark ? '#f8fafc' : '#1e293b';
  const sub = isDark ? '#94a3b8' : '#64748b';
  const label = isDark ? 'Dark Mode' : 'Light Mode';
  const icon = isDark ? '🌙' : '☀️';

  return col([
    heading('Theme Toggle'),
    spacer(8),
    {
      type: 'Container',
      props: {
        style: {
          padding: '24',
          backgroundColor: bg,
          borderRadius: '12',
          border: isDark ? '1px solid #334155' : '1px solid #e2e8f0'
        }
      },
      children: [
        text(`${icon}  ${label}`, { fontSize: '22', fontWeight: 'bold', color: fg }),
        spacer(8),
        text('This entire card adapts based on a single boolean toggled in JS.', { fontSize: '14', color: sub }),
        spacer(8),
        text(`isDark = ${isDark}`, { fontSize: '13', fontWeight: '600', color: isDark ? '#818cf8' : '#6366f1' })
      ]
    },
    spacer(12),
    btn('Toggle Theme', 'toggleTheme', { backgroundColor: isDark ? '#818cf8' : '#6366f1' })
  ]);
}

function buildWhiteboardDemo() {
  const controls = row([
    btn('Undo', 'wbUndo', { backgroundColor: '#64748b' }),
    btn('Clear', 'wbClear', { backgroundColor: '#ef4444' }),
    btn(wbEraser ? 'Eraser On' : 'Eraser Off', 'wbToggleEraser', { backgroundColor: wbEraser ? '#f59e0b' : '#0ea5e9' }),
  ], { gap: '8', flexWrap: 'wrap' });

  const paletteChips = wbPalette.map((c, i) => {
    const isActive = c === wbColor && !wbEraser;
    return {
      type: 'Container',
      props: {
        style: {
          width: '28',
          height: '28',
          backgroundColor: c,
          borderRadius: '999',
          border: isActive ? '2px solid #111827' : '1px solid #e2e8f0'
        }
      },
      events: { tap: 'wbColor_' + i }
    };
  });

  const brushButtons = row([
    btn('Small', 'wbBrushSmall', { backgroundColor: wbBrush === 2 ? '#0f172a' : '#94a3b8' }),
    btn('Medium', 'wbBrushMedium', { backgroundColor: wbBrush === 4 ? '#0f172a' : '#94a3b8' }),
    btn('Large', 'wbBrushLarge', { backgroundColor: wbBrush === 7 ? '#0f172a' : '#94a3b8' }),
  ], { gap: '8', flexWrap: 'wrap' });

  return col([
    heading('Interactive Whiteboard'),
    spacer(6),
    text('Draw with touch or mouse. Drag to draw, tap to place a dot.', { fontSize: '14', color: '#64748b' }),
    spacer(10),
    row(paletteChips, { gap: '8', flexWrap: 'wrap' }),
    spacer(10),
    brushButtons,
    spacer(10),
    controls,
    spacer(12),
    {
      type: 'Container',
      props: {
        style: {
          padding: '8',
          backgroundColor: '#ffffff',
          borderRadius: '12',
          border: '1px solid #e2e8f0'
        }
      },
      children: [
        {
          type: 'CachedCanvas',
          key: 'whiteboard-canvas',
          props: { width: 420, height: 260, contextId: wbEnsureContext() },
          events: {
            tap: 'wbTap',
            pointerdown: 'wbPointerDown',
            pointermove: 'wbPointerMove',
            pointerup: 'wbPointerUp'
          }
        }
      ]
    },
    spacer(6),
    text('Tip: Use Eraser to remove strokes. Undo removes the last stroke.', { fontSize: '12', color: '#94a3b8' })
  ]);
}

function buildWhiteboardCommands() {
  return [];
}

function buildHostDataDemo() {
  const items = [];
  items.push(heading('Host Data Roundtrip'));
  items.push(spacer(8));
  items.push(text('Calls askHost("getProfile") to fetch data from the Dart host, parses the typed response, and renders it.', { fontSize: '14', color: '#64748b' }));
  items.push(spacer(12));

  if (profile) {
    items.push(card([
      text('Profile Loaded', { fontSize: '16', fontWeight: 'bold', color: '#10b981' }),
      spacer(8),
      text(`Name: ${profile.name}`, { fontSize: '15', color: '#1e293b' }),
      text(`Role: ${profile.role}`, { fontSize: '15', color: '#1e293b' }),
      text(`Project: ${profile.project}`, { fontSize: '15', color: '#1e293b' })
    ]));
  } else {
    items.push(card([
      text('No profile loaded yet.', { fontSize: '15', color: '#94a3b8' })
    ]));
  }

  items.push(spacer(12));
  items.push(btn('Load Profile', 'loadProfile', { backgroundColor: '#0891b2' }));
  return col(items);
}

// ─────────────────────────────────────────────────────────
// TAB 3 – DOM + Canvas (host APIs)
// ─────────────────────────────────────────────────────────
function buildDomCanvasTab() {
  return col([
    heading('DOM + Canvas Host APIs'),
    spacer(4),
    text('Uses askHost("dom.*") and askHost("canvas.*") to interact with the Dart-side host APIs, then renders combined output.', { fontSize: '14', color: '#64748b' }),
    spacer(12),
    buildDomCanvasCard(),
    spacer(8),
    buildDomCanvasCanvas(),
    spacer(12),
    row([
      btn('− Decrement', 'domCanvasDec', { backgroundColor: '#64748b', flex: '1' }),
      btn('+ Increment', 'domCanvasInc', { flex: '1' })
    ], { gap: '8' })
  ], { padding: '16' });
}

function typedValueOf(response) {
  try {
    const parsed = JSON.parse(response);
    if (parsed && parsed.data) return parsed.data.value;
  } catch (_) {}
  return null;
}

function buildDomCanvasCard() {
  askHost('dom.clear', '{}');
  askHost('dom.createElement', JSON.stringify({ tagName: 'div', id: 'rootCard' }));
  askHost('dom.setStyleObject', JSON.stringify({
    id: 'rootCard',
    styles: { padding: '14', backgroundColor: '#ffffff', borderRadius: '12', border: '1px solid #dbe2ff' }
  }));
  askHost('dom.createElement', JSON.stringify({ tagName: 'h3', id: 'title' }));
  askHost('dom.setTextContent', JSON.stringify({ id: 'title', text: 'DOM API Card' }));
  askHost('dom.createElement', JSON.stringify({ tagName: 'p', id: 'desc' }));
  askHost('dom.setTextContent', JSON.stringify({
    id: 'desc',
    text: `Counter: ${domCanvasCount} | Color: ${domCanvasColors[domCanvasColorIdx]}`
  }));
  askHost('dom.appendChild', JSON.stringify({ parentId: 'rootCard', childId: 'title' }));
  askHost('dom.appendChild', JSON.stringify({ parentId: 'rootCard', childId: 'desc' }));
  const rootResponse = askHost('dom.toJson', JSON.stringify({ id: 'rootCard' }));
  return typedValueOf(rootResponse) || { type: 'Text', props: { text: 'DOM unavailable' } };
}

function buildDomCanvasCanvas() {
  askHost('canvas.clear', '{}');
  askHost('canvas.setFillStyle', JSON.stringify({ color: '#f8faff' }));
  askHost('canvas.fillRect', JSON.stringify({ x: 0, y: 0, width: 400, height: 140 }));
  askHost('canvas.setFillStyle', JSON.stringify({ color: domCanvasColors[domCanvasColorIdx] }));
  askHost('canvas.fillRect', JSON.stringify({ x: 20, y: 20, width: Math.max(40, 40 + domCanvasCount * 20), height: 36 }));
  askHost('canvas.setStrokeStyle', JSON.stringify({ color: '#111827' }));
  askHost('canvas.setLineWidth', JSON.stringify({ width: 2 }));
  askHost('canvas.strokeRect', JSON.stringify({ x: 20, y: 20, width: 300, height: 36 }));
  askHost('canvas.fillText', JSON.stringify({ text: `count=${domCanvasCount}`, x: 20, y: 88 }));
  const resp = askHost('canvas.getCommands', '{}');
  const cmds = typedValueOf(resp) || [];
  return {
    type: 'Canvas',
    props: { width: 400, height: 140, commands: cmds }
  };
}

// ─────────────────────────────────────────────────────────
// TAB 4 – Landing Page (JSON + logic wrapper)
// ─────────────────────────────────────────────────────────
function buildLandingPageTab() {
  const landingOk = LANDING_PAGE_JSON && LANDING_PAGE_JSON.type;
  const landingErr = parseErrors['landing_page.json'];
  return col([
    card([
      text('Landing Page (JSON Asset)', { fontSize: '16', fontWeight: 'bold', color: '#1e293b' }),
      spacer(6),
      text('This section renders the full landing_page.json while keeping live JS controls above it.', { fontSize: '13', color: '#64748b' }),
      spacer(8),
      row([
        btn('Toggle Theme', 'toggleTheme', { backgroundColor: isDark ? '#818cf8' : '#6366f1' }),
        btn('Refresh Clock', 'refreshClock', { backgroundColor: '#10b981' })
      ], { gap: '8', flexWrap: 'wrap' })
    ]),
    spacer(12),
    landingOk
      ? scope(LANDING_PAGE_JSON, 'scope-landing')
      : card([text('Landing page JSON failed: ' + (landingErr || 'unknown error'), { fontSize: '14', color: '#ef4444' })])
  ], { padding: '16' });
}

// ─────────────────────────────────────────────────────────
// TAB 5 – Bevy 3D Scene
// ─────────────────────────────────────────────────────────
function buildBevyTab() {
  return col([
    heading('Bevy 3D Scene'),
    spacer(6),
    text('Interactive Bevy scene embedded inside the JSON UI renderer.', { fontSize: '14', color: '#64748b' }),
    spacer(10),
    row([
      btn(bevyInteractive ? 'Interactive On' : 'Interactive Off', 'toggleBevyInteractive', { backgroundColor: bevyInteractive ? '#10b981' : '#64748b' }),
      btn(bevyFps === 60 ? '60 FPS' : '30 FPS', 'toggleBevyFps', { backgroundColor: '#6366f1' })
    ], { gap: '8', flexWrap: 'wrap' }),
    spacer(12),
    scope({
      type: 'BevyScene',
      props: {
        width: 820,
        height: 520,
        fps: bevyFps,
        interactive: bevyInteractive,
        scene: BEVY_SCENE_JSON
      }
    }, 'scope-bevy')
  ], { padding: '16' });
}

// ─────────────────────────────────────────────────────────
// TAB 6 – Game Scene
// ─────────────────────────────────────────────────────────
function buildGameTab() {
  return col([
    heading('Game Scene (Pure Dart 3D)'),
    spacer(6),
    text('Feature-rich 3D game scene with physics-ready layout and animations.', { fontSize: '14', color: '#64748b' }),
    spacer(10),
    row([
      btn(gameInteractive ? 'Interactive On' : 'Interactive Off', 'toggleGameInteractive', { backgroundColor: gameInteractive ? '#10b981' : '#64748b' }),
      btn(gameFps === 60 ? '60 FPS' : '30 FPS', 'toggleGameFps', { backgroundColor: '#6366f1' })
    ], { gap: '8', flexWrap: 'wrap' }),
    spacer(12),
    scope({
      type: 'GameScene',
      key: 'game-scene-main',
      props: {
        width: 820,
        height: 520,
        fps: gameFps,
        interactive: gameInteractive,
        sceneKey: 'game-scene-v1',
        scene: GAME_SCENE_JSON
      }
    }, 'scope-game')
  ], { padding: '16' });
}

// ─────────────────────────────────────────────────────────
// TAB 7 – Real World Demos
// ─────────────────────────────────────────────────────────
function buildRealWorldTab() {
  const subTabs = ['Ops Console', 'Checkout', 'Support Chat', 'Pipeline'];
  const content = [buildOpsConsole, buildCheckoutDemo, buildSupportChat, buildPipelineDemo];
  const idx = Math.min(activeSubTab, content.length - 1);
  return col([
    buildSubTabs(subTabs),
    content[idx]()
  ], { padding: '16' });
}

function buildOpsConsole() {
  const filtered = rwTickets.filter((t) => {
    const matchesStatus = rwFilter === 'all' || t.status === rwFilter;
    const matchesQuery = !rwSearch || t.title.toLowerCase().includes(rwSearch.toLowerCase());
    return matchesStatus && matchesQuery;
  });

  const list = filtered.map((t) => ({
    type: 'Container',
    key: 'ticket_' + t.id,
    props: {
      style: {
        padding: '12',
        backgroundColor: '#ffffff',
        borderRadius: '10',
        border: '1px solid #e2e8f0',
        margin: '0 0 8 0'
      }
    },
    events: { tap: 'rwToggleTicket' },
    children: [
      row([
        text(t.id, { fontSize: '12', color: '#94a3b8' }),
        text(t.status.toUpperCase(), { fontSize: '12', color: t.status === 'open' ? '#16a34a' : '#64748b' })
      ], { justifyContent: 'space-between' }),
      text(t.title, { fontSize: '15', fontWeight: '600', color: '#1e293b' }),
      text('Owner: ' + t.owner + ' • Priority: ' + t.priority, { fontSize: '12', color: '#64748b' })
    ]
  }));

  return scope(col([
    heading('Ops Console'),
    spacer(6),
    text('Live incident feed with filters and quick status updates.', { fontSize: '14', color: '#64748b' }),
    spacer(10),
    {
      type: 'TextField',
      key: 'rw_search',
      props: { hint: 'Search incidents...' },
      events: { input: 'rwSearchInput' }
    },
    spacer(8),
    row([
      btn('All', 'rwFilterAll', { backgroundColor: rwFilter === 'all' ? '#6366f1' : '#94a3b8' }),
      btn('Open', 'rwFilterOpen', { backgroundColor: rwFilter === 'open' ? '#16a34a' : '#94a3b8' }),
      btn('Closed', 'rwFilterClosed', { backgroundColor: rwFilter === 'closed' ? '#64748b' : '#94a3b8' })
    ], { gap: '8', flexWrap: 'wrap' }),
    spacer(10),
    ...list
  ]), 'scope-ops');
}

function buildCheckoutDemo() {
  const items = rwCart.map((item) => ({
    type: 'Container',
    props: { style: { padding: '10', borderBottom: '1px solid #e2e8f0' } },
    children: [
      row([
        text(item.name, { fontSize: '14', fontWeight: '600', color: '#1e293b' }),
        text(money(item.price * item.qty), { fontSize: '14', color: '#1e293b' })
      ], { justifyContent: 'space-between' }),
      row([
        text('Qty: ' + item.qty, { fontSize: '12', color: '#64748b' }),
        row([
          { type: 'Container', key: 'cart_dec_' + item.id, props: { style: { padding: '6 10', backgroundColor: '#f1f5f9', borderRadius: '6' } }, events: { tap: 'rwCartDec' }, children: [text('−', { fontSize: '14' })] },
          { type: 'Container', key: 'cart_inc_' + item.id, props: { style: { padding: '6 10', backgroundColor: '#e0e7ff', borderRadius: '6' } }, events: { tap: 'rwCartInc' }, children: [text('+', { fontSize: '14' })] }
        ], { gap: '6' })
      ], { justifyContent: 'space-between' })
    ]
  }));

  return scope(col([
    heading('Checkout'),
    spacer(6),
    text('Cart management with promo codes and dynamic totals.', { fontSize: '14', color: '#64748b' }),
    spacer(10),
    card(items),
    spacer(10),
    row([
      { type: 'Expanded', children: [
        { type: 'TextField', key: 'promo_input', props: { hint: 'Promo code' }, events: { input: 'rwPromoInput' } }
      ]},
      btn('Apply', 'rwPromoApply', { backgroundColor: '#0ea5e9' })
    ], { gap: '8', flexWrap: 'wrap' }),
    spacer(10),
    card([
      row([text('Subtotal', { fontSize: '13', color: '#64748b' }), text(money(rwCartSubtotal()), { fontSize: '13', color: '#1e293b' })], { justifyContent: 'space-between' }),
      row([text('Discount', { fontSize: '13', color: '#64748b' }), text(money(rwDiscount), { fontSize: '13', color: '#1e293b' })], { justifyContent: 'space-between' }),
      row([text('Total', { fontSize: '15', fontWeight: 'bold', color: '#1e293b' }), text(money(rwCartTotal()), { fontSize: '15', fontWeight: 'bold', color: '#1e293b' })], { justifyContent: 'space-between' })
    ])
  ]), 'scope-checkout');
}

function buildSupportChat() {
  const messages = rwChatMessages.map((m) => ({
    type: 'Container',
    props: {
      style: {
        padding: '8 10',
        backgroundColor: m.from === 'You' ? '#e0e7ff' : '#f1f5f9',
        borderRadius: '8',
        margin: '0 0 6 0'
      }
    },
    children: [
      text(m.from, { fontSize: '11', color: '#64748b' }),
      text(m.text, { fontSize: '14', color: '#1e293b' })
    ]
  }));

  return scope(col([
    heading('Support Chat'),
    spacer(6),
    text('Quick updates and status syncing for incident response.', { fontSize: '14', color: '#64748b' }),
    spacer(10),
    card(messages, { maxHeight: '260', overflow: 'scroll' }),
    spacer(10),
    { type: 'TextField', key: 'chat_input', props: { hint: 'Write a message...' }, events: { input: 'rwChatInput' } },
    spacer(8),
    btn('Send Update', 'rwChatSend', { backgroundColor: '#6366f1' })
  ]), 'scope-chat');
}

function buildPipelineDemo() {
  function column(title, items, status) {
    const cards = items.map((t) => ({
      type: 'Container',
      props: { style: { padding: '10', backgroundColor: '#ffffff', borderRadius: '8', border: '1px solid #e2e8f0', margin: '0 0 6 0' } },
      children: [
        text(t.title, { fontSize: '13', fontWeight: '600', color: '#1e293b' }),
        text('Owner: ' + t.owner, { fontSize: '11', color: '#64748b' }),
        row([
          { type: 'Container', key: 'pipe_left_' + status + '_' + t.id, props: { style: { padding: '4 8', backgroundColor: '#f1f5f9', borderRadius: '6' } }, events: { tap: 'rwPipeLeft' }, children: [text('←', { fontSize: '12' })] },
          { type: 'Container', key: 'pipe_right_' + status + '_' + t.id, props: { style: { padding: '4 8', backgroundColor: '#e0e7ff', borderRadius: '6' } }, events: { tap: 'rwPipeRight' }, children: [text('→', { fontSize: '12' })] }
        ], { gap: '6' })
      ]
    }));

    return {
      type: 'Container',
      props: { style: { padding: '8', backgroundColor: '#f8fafc', borderRadius: '10', border: '1px solid #e2e8f0', flex: '1' } },
      children: [
        text(title, { fontSize: '13', fontWeight: 'bold', color: '#1e293b' }),
        spacer(6),
        ...cards
      ]
    };
  }

  return scope(col([
    heading('Pipeline'),
    spacer(6),
    text('Move work items across stages with quick actions.', { fontSize: '14', color: '#64748b' }),
    spacer(10),
    row([
      column('To Do', rwPipeline.todo, 'todo'),
      column('In Progress', rwPipeline.doing, 'doing'),
      column('Done', rwPipeline.done, 'done')
    ], { gap: '8', flexWrap: 'wrap' })
  ]), 'scope-pipeline');
}

// ─────────────────────────────────────────────────────────
// Root renderer
// ─────────────────────────────────────────────────────────
function renderApp() {
  askHost('render', JSON.stringify({
    type: 'Column',
    children: [
      scope(buildTabBar(), SHELL_TABS_SCOPE_KEY),
      scope(buildShellBody(), SHELL_BODY_SCOPE_KEY)
    ]
  }));
}

// ─────────────────────────────────────────────────────────
// Event handlers (called from Flutter via tap events)
// ─────────────────────────────────────────────────────────

// Tab switching
function switchTab(index) {
  activeTab = index;
  activeSubTab = 0;
  rerenderShellTabs();
  rerenderShellContent();
}

function switchTab_0() { switchTab(0); }
function switchTab_1() { switchTab(1); }
function switchTab_2() { switchTab(2); }
function switchTab_3() { switchTab(3); }
function switchTab_4() { switchTab(4); }
function switchTab_5() { switchTab(5); }
function switchTab_6() { switchTab(6); }
function switchTab_7() { switchTab(7); }

// Sub-tab switching
function switchSubTab(index) {
  activeSubTab = index;
  rerenderActiveTab();
}

function switchSubTab_0() { switchSubTab(0); }
function switchSubTab_1() { switchSubTab(1); }
function switchSubTab_2() { switchSubTab(2); }
function switchSubTab_3() { switchSubTab(3); }
function switchSubTab_4() { switchSubTab(4); }
function switchSubTab_5() { switchSubTab(5); }

// Counter
function increment() {
  count += 1;
  askHost('println', `Count: ${count}`);
  askHost('updateApp', JSON.stringify({ source: 'quickjs', action: 'increment', value: count }));
  if (vmSubTabVisible(0)) rerenderVmPanel();
}

function decrement() {
  count = Math.max(0, count - 1);
  askHost('println', `Count: ${count}`);
  if (vmSubTabVisible(0)) rerenderVmPanel();
}

function resetCounter() {
  count = 0;
  if (vmSubTabVisible(0)) rerenderVmPanel();
}

// Clock
function refreshClock() {
  clockTime = new Date().toISOString();
  if (vmSubTabVisible(1) || vmSubTabVisible(2)) rerenderVmPanel();
  if (activeTab === 4) rerenderActiveTab();
}

function tickClock() {
  clockTime = new Date().toISOString();
  if (vmSubTabVisible(1) || vmSubTabVisible(2)) rerenderVmPanel();
}

// Theme
function toggleTheme() {
  isDark = !isDark;
  askHost('println', `Theme toggled: isDark=${isDark}`);
  if (vmSubTabVisible(4)) rerenderVmPanel();
  if (activeTab === 4) rerenderActiveTab();
}

// Host data
function loadProfile() {
  const response = askHost('getProfile', '{}');
  try {
    const parsed = JSON.parse(response);
    if (parsed && parsed.type === 'string' && parsed.data && parsed.data.value) {
      profile = JSON.parse(parsed.data.value);
    }
  } catch (e) {
    askHost('println', `Profile parse error: ${String(e)}`);
  }
  askHost('updateApp', JSON.stringify({ source: 'quickjs', action: 'profileLoaded', profile: profile }));
  if (vmSubTabVisible(5)) rerenderVmPanel();
}

// DOM+Canvas
function domCanvasInc() {
  domCanvasCount += 1;
  domCanvasColorIdx = (domCanvasColorIdx + 1) % domCanvasColors.length;
  if (activeTab === 3) rerenderActiveTab();
}

function domCanvasDec() {
  domCanvasCount = Math.max(0, domCanvasCount - 1);
  domCanvasColorIdx = (domCanvasColorIdx + domCanvasColors.length - 1) % domCanvasColors.length;
  if (activeTab === 3) rerenderActiveTab();
}

// 3D demo toggles
function toggleBevyInteractive() {
  bevyInteractive = !bevyInteractive;
  if (activeTab === 5) rerenderActiveTab();
}

function toggleBevyFps() {
  bevyFps = bevyFps === 60 ? 30 : 60;
  if (activeTab === 5) rerenderActiveTab();
}

function toggleGameInteractive() {
  gameInteractive = !gameInteractive;
  if (activeTab === 6) rerenderActiveTab();
}

function toggleGameFps() {
  gameFps = gameFps === 60 ? 30 : 60;
  if (activeTab === 6) rerenderActiveTab();
}

// Real-world demo handlers
function rwSearchInput(e) {
  rwSearch = (e && e.value) ? String(e.value) : '';
  if (realWorldSubTabVisible(0)) renderScoped('scope-ops', buildOpsConsole());
}

function rwFilterAll() {
  rwFilter = 'all';
  if (realWorldSubTabVisible(0)) renderScoped('scope-ops', buildOpsConsole());
}

function rwFilterOpen() {
  rwFilter = 'open';
  if (realWorldSubTabVisible(0)) renderScoped('scope-ops', buildOpsConsole());
}

function rwFilterClosed() {
  rwFilter = 'closed';
  if (realWorldSubTabVisible(0)) renderScoped('scope-ops', buildOpsConsole());
}

function rwToggleTicket(e) {
  const key = (e && e.currentTarget) ? String(e.currentTarget) : '';
  const id = key.replace('ticket_', '');
  for (let i = 0; i < rwTickets.length; i += 1) {
    if (rwTickets[i].id === id) {
      rwTickets[i].status = rwTickets[i].status === 'open' ? 'closed' : 'open';
      break;
    }
  }
  if (realWorldSubTabVisible(0)) renderScoped('scope-ops', buildOpsConsole());
}

function rwCartInc(e) {
  const key = (e && e.currentTarget) ? String(e.currentTarget) : '';
  const id = key.replace('cart_inc_', '');
  for (let i = 0; i < rwCart.length; i += 1) {
    if (rwCart[i].id === id) rwCart[i].qty += 1;
  }
  if (realWorldSubTabVisible(1)) renderScoped('scope-checkout', buildCheckoutDemo());
}

function rwCartDec(e) {
  const key = (e && e.currentTarget) ? String(e.currentTarget) : '';
  const id = key.replace('cart_dec_', '');
  for (let i = 0; i < rwCart.length; i += 1) {
    if (rwCart[i].id === id) rwCart[i].qty = Math.max(0, rwCart[i].qty - 1);
  }
  if (realWorldSubTabVisible(1)) renderScoped('scope-checkout', buildCheckoutDemo());
}

function rwPromoInput(e) { rwPromoCode = (e && e.value) ? String(e.value) : ''; }
function rwPromoApply() {
  const code = (rwPromoCode || '').toLowerCase();
  if (code === 'shipfree') rwDiscount = 5;
  else if (code === 'save10') rwDiscount = 10;
  else rwDiscount = 0;
  if (realWorldSubTabVisible(1)) renderScoped('scope-checkout', buildCheckoutDemo());
}

function rwChatInput(e) { rwChatDraft = (e && e.value) ? String(e.value) : ''; }
function rwChatSend() {
  const msg = (rwChatDraft || '').trim();
  if (!msg) return;
  rwChatMessages.push({ id: Date.now(), from: 'You', text: msg });
  rwChatDraft = '';
  if (realWorldSubTabVisible(2)) renderScoped('scope-chat', buildSupportChat());
}

function rwPipeLeft(e) {
  const key = (e && e.currentTarget) ? String(e.currentTarget) : '';
  const parts = key.split('_');
  if (parts.length < 4) return;
  const status = parts[2];
  const id = parts.slice(3).join('_');
  const order = ['todo', 'doing', 'done'];
  const idx = order.indexOf(status);
  if (idx <= 0) return;
  const current = rwPipeline[status];
  const itemIdx = current.findIndex((t) => t.id === id);
  if (itemIdx === -1) return;
  const item = current.splice(itemIdx, 1)[0];
  rwPipeline[order[idx - 1]].push(item);
  if (realWorldSubTabVisible(3)) renderScoped('scope-pipeline', buildPipelineDemo());
}

function rwPipeRight(e) {
  const key = (e && e.currentTarget) ? String(e.currentTarget) : '';
  const parts = key.split('_');
  if (parts.length < 4) return;
  const status = parts[2];
  const id = parts.slice(3).join('_');
  const order = ['todo', 'doing', 'done'];
  const idx = order.indexOf(status);
  if (idx === -1 || idx >= order.length - 1) return;
  const current = rwPipeline[status];
  const itemIdx = current.findIndex((t) => t.id === id);
  if (itemIdx === -1) return;
  const item = current.splice(itemIdx, 1)[0];
  rwPipeline[order[idx + 1]].push(item);
  if (realWorldSubTabVisible(3)) renderScoped('scope-pipeline', buildPipelineDemo());
}

// No-op for static buttons
function noop() {}

function wbEventPoint(e) {
  if (!e) return null;
  if (e.localPosition && e.localPosition.x != null) {
    return { x: Number(e.localPosition.x), y: Number(e.localPosition.y) };
  }
  if (e.position && e.position.x != null) {
    return { x: Number(e.position.x), y: Number(e.position.y) };
  }
  return null;
}

function wbStartStroke(p) {
  if (!p) return;
  wbEnsureContext();
  const stroke = {
    color: wbEraser ? '#ffffff' : wbColor,
    width: wbEraser ? wbBrush * 2 : wbBrush,
    points: [p]
  };
  wbCurrentStroke = stroke;
  wbStrokes.push(stroke);
  if (stroke.points.length === 1 && wbContextId) {
    hostTimerCall('canvas.ctx.addCommands', {
      id: wbContextId,
      commands: [
        { type: 'setStrokeStyle', params: { color: stroke.color } },
        { type: 'setLineWidth', params: { width: stroke.width } },
        { type: 'beginPath', params: {} },
        { type: 'moveTo', params: { x: p.x, y: p.y } }
      ]
    });
  }
}

function wbTap(e) {
  const p = wbEventPoint(e);
  wbStartStroke(p);
  wbCurrentStroke = null;
  wbScheduleRender();
}

function wbDragStart(e) {
  wbStartStroke(wbEventPoint(e));
  wbScheduleRender();
}

function wbDrag(e) {
  if (!wbCurrentStroke) return;
  const p = wbEventPoint(e);
  if (!p) return;
  wbCurrentStroke.points.push(p);
  if (wbContextId) {
    hostTimerCall('canvas.ctx.addCommands', {
      id: wbContextId,
      commands: [
        { type: 'lineTo', params: { x: p.x, y: p.y } },
        { type: 'stroke', params: {} }
      ]
    });
  }
  wbScheduleRender();
}

function wbDragEnd(_e) {
  wbCurrentStroke = null;
}

function wbPointerDown(e) {
  if (!wbIsDrawing) {
    wbIsDrawing = true;
    rerenderShellBody();
  }
  wbStartStroke(wbEventPoint(e));
  wbScheduleRender();
}

function wbPointerMove(e) {
  if (!wbCurrentStroke) return;
  const p = wbEventPoint(e);
  if (!p) return;
  wbCurrentStroke.points.push(p);
  if (wbContextId) {
    hostTimerCall('canvas.ctx.addCommands', {
      id: wbContextId,
      commands: [
        { type: 'lineTo', params: { x: p.x, y: p.y } },
        { type: 'stroke', params: {} }
      ]
    });
  }
  wbScheduleRender();
}

function wbPointerUp(_e) {
  wbCurrentStroke = null;
  if (wbIsDrawing) {
    wbIsDrawing = false;
    rerenderShellBody();
  }
  if (vmSubTabVisible(3)) rerenderVmPanel();
}

function wbClear() {
  wbStrokes = [];
  wbCurrentStroke = null;
  wbEnsureContext();
  wbInitContext();
  if (vmSubTabVisible(3)) rerenderVmPanel();
}

function wbUndo() {
  if (wbStrokes.length > 0) {
    wbStrokes.pop();
    wbCurrentStroke = null;
    wbEnsureContext();
    wbInitContext();
    for (let i = 0; i < wbStrokes.length; i += 1) {
      const stroke = wbStrokes[i];
      if (!stroke || !stroke.points || stroke.points.length === 0) continue;
      if (stroke.points.length === 1) {
        hostTimerCall('canvas.ctx.addCommands', {
          id: wbContextId,
          commands: [
            { type: 'setFillStyle', params: { color: stroke.color } },
            { type: 'fillCircle', params: { x: stroke.points[0].x, y: stroke.points[0].y, radius: stroke.width } }
          ]
        });
        continue;
      }
      hostTimerCall('canvas.ctx.addCommands', {
        id: wbContextId,
        commands: [
          { type: 'setStrokeStyle', params: { color: stroke.color } },
          { type: 'setLineWidth', params: { width: stroke.width } },
          { type: 'beginPath', params: {} },
          { type: 'moveTo', params: { x: stroke.points[0].x, y: stroke.points[0].y } }
        ]
      });
      for (let p = 1; p < stroke.points.length; p += 1) {
        hostTimerCall('canvas.ctx.addCommands', {
          id: wbContextId,
          commands: [
            { type: 'lineTo', params: { x: stroke.points[p].x, y: stroke.points[p].y } }
          ]
        });
      }
      hostTimerCall('canvas.ctx.addCommands', {
        id: wbContextId,
        commands: [{ type: 'stroke', params: {} }]
      });
    }
    if (vmSubTabVisible(3)) rerenderVmPanel();
  }
}

function wbToggleEraser() {
  wbEraser = !wbEraser;
  if (vmSubTabVisible(3)) rerenderVmPanel();
}

function wbBrushSmall() { wbBrush = 2; wbEraser = false; if (vmSubTabVisible(3)) rerenderVmPanel(); }
function wbBrushMedium() { wbBrush = 4; wbEraser = false; if (vmSubTabVisible(3)) rerenderVmPanel(); }
function wbBrushLarge() { wbBrush = 7; wbEraser = false; if (vmSubTabVisible(3)) rerenderVmPanel(); }

function wbColor_0() { wbColor = wbPalette[0]; wbEraser = false; if (vmSubTabVisible(3)) rerenderVmPanel(); }
function wbColor_1() { wbColor = wbPalette[1]; wbEraser = false; if (vmSubTabVisible(3)) rerenderVmPanel(); }
function wbColor_2() { wbColor = wbPalette[2]; wbEraser = false; if (vmSubTabVisible(3)) rerenderVmPanel(); }
function wbColor_3() { wbColor = wbPalette[3]; wbEraser = false; if (vmSubTabVisible(3)) rerenderVmPanel(); }
function wbColor_4() { wbColor = wbPalette[4]; wbEraser = false; if (vmSubTabVisible(3)) rerenderVmPanel(); }
function wbColor_5() { wbColor = wbPalette[5]; wbEraser = false; if (vmSubTabVisible(3)) rerenderVmPanel(); }

// ─────────────────────────────────────────────────────────
// Boot
// ─────────────────────────────────────────────────────────
renderApp();
startClockTimer();
