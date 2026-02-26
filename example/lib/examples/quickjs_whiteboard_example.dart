import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';

class QuickJsWhiteboardExamplePage extends StatelessWidget {
  const QuickJsWhiteboardExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050A14),
      body: SafeArea(
        child: ElpianVmWidget.fromCode(
          machineId: 'quickjs-whiteboard-demo',
          runtime: ElpianRuntime.quickJs,
          code: _whiteboardProgram,
          onPrintln: (msg) => debugPrint('[quickjs-whiteboard] $msg'),
          onUpdateApp: (data) {
            debugPrint('[quickjs-whiteboard:updateApp] $data');
          },
        ),
      ),
    );
  }
}

const String _whiteboardProgram = r'''
let hostEnvCache = {};
let hostEnvDigest = '';
let envRefreshTimerId = null;

let currentTool = 'pen';
let currentColor = '#2563EB';
let brushSize = 4;
let showGrid = true;
let darkCanvas = false;
let smoothMode = true;
let statusText = 'Drag to draw';

let strokes = [];
let redoStrokes = [];
let activeStroke = null;
let pointerDown = false;
let lastPointerPoint = null;

const MAX_STROKES = 480;
const HOST_ENV_REFRESH_MS = 1200;
const PALETTE = ['#2563EB', '#06B6D4', '#10B981', '#F59E0B', '#EF4444', '#A855F7', '#111827', '#FFFFFF'];
const BRUSH_STEPS = [2, 4, 7, 11, 16];

let uiTokens = {
  outerPadding: '8',
  sectionGap: '7',
  rowGap: '6',
  panelWidth: 360,
  frameHeight: 640,
  boardWidth: 340,
  boardHeight: 300,
  boardRadius: 18,
  rowHeight: 36,
  headerHeight: 56,
  fontHeader: '20',
  fontBody: '12',
  fontSmall: '11',
  buttonRadius: '13',
  buttonFontSize: '12',
  gridSpacing: 24,
  showFooter: true,
  paletteRows: 1,
};

function typedHostValue(response) {
  try {
    const parsed = JSON.parse(response);
    if (parsed && parsed.data) return parsed.data.value;
  } catch (_) {}
  return null;
}

function hostTimerCall(apiName, payload) {
  try {
    const response = askHost(apiName, JSON.stringify(payload || {}));
    return typedHostValue(response);
  } catch (_) {
    return null;
  }
}

function readHostEnvFromGlobal() {
  const envObj = globalThis.__ELPIAN_HOST_ENV__ || globalThis.ELPIAN_HOST_ENV;
  if (envObj && typeof envObj === 'object') return envObj;
  return null;
}

function readHostEnvFromHostApi() {
  try {
    const response = askHost('env.get', '{}');
    const value = typedHostValue(response);
    if (value && typeof value === 'object') return value;
  } catch (_) {}
  return null;
}

function refreshHostEnvironment(forceRerender) {
  const next = readHostEnvFromGlobal() || readHostEnvFromHostApi();
  if (!next || typeof next !== 'object') return false;

  let digest = '';
  try {
    digest = JSON.stringify(next) || '';
  } catch (_) {
    return false;
  }

  if (!digest || digest === hostEnvDigest) return false;
  hostEnvDigest = digest;
  hostEnvCache = next;
  if (forceRerender === true) rerender();
  return true;
}

function onEnvRefreshTick() {
  refreshHostEnvironment(true);
}

function ensureHostEnvRefreshTimer() {
  if (envRefreshTimerId !== null) return;
  const timerId = hostTimerCall('setInterval', {
    handler: 'onEnvRefreshTick',
    delay: HOST_ENV_REFRESH_MS
  });
  if (timerId !== null && timerId !== undefined) {
    envRefreshTimerId = timerId;
  }
}

function numericOr(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function clamp(value, minV, maxV) {
  return Math.max(minV, Math.min(maxV, value));
}

function px(value) {
  return String(Math.max(0, Math.round(value)));
}

function viewportWidth() {
  const viewport = hostEnvCache.viewport || {};
  return numericOr(viewport.width, 400);
}

function viewportHeight() {
  const viewport = hostEnvCache.viewport || {};
  return numericOr(viewport.height, 760);
}

function backgroundFillColor() {
  return darkCanvas ? '#0B1220' : '#FFFFFF';
}

function boardFrameColor() {
  return darkCanvas ? '#111827' : '#F1F5F9';
}

function boardBorderColor() {
  return darkCanvas ? '#334155' : '#CBD5E1';
}

function gridColor() {
  return darkCanvas ? 'rgba(148, 163, 184, 0.18)' : '#E2E8F0';
}

function eraserColor() {
  return backgroundFillColor();
}

function buildUiTokens() {
  const vw = viewportWidth();
  const vh = viewportHeight();

  const compact = vw < 500 || vh < 760;
  const tiny = vw < 360 || vh < 680;
  const showFooter = vh >= 700;
  const paletteRows = vw < 390 ? 2 : 1;

  const outerPadding = tiny ? 6 : (compact ? 8 : 12);
  const sectionGap = tiny ? 5 : (compact ? 6 : 9);
  const rowGap = tiny ? 4 : (compact ? 5 : 7);
  const rowHeight = tiny ? 30 : (compact ? 34 : 40);
  const headerHeight = tiny ? 48 : (compact ? 56 : 64);
  const headerChrome = 20;
  const footerHeight = showFooter ? (tiny ? 12 : 18) : 0;

  const panelWidth = Math.max(220, Math.min(1180, Math.floor(vw - (outerPadding * 2))));
  const controlRowCount = 3 + paletteRows; // tool + action + size + palette row(s)
  const controlsHeight = rowHeight * controlRowCount;
  const itemCount = 5 + paletteRows + (showFooter ? 1 : 0); // header + tool + action + board + palette + size + footer?
  const gapCount = Math.max(0, itemCount - 1);

  let boardHeight = Math.floor(vh - (
    (outerPadding * 2) +
    headerHeight +
    headerChrome +
    controlsHeight +
    footerHeight +
    (sectionGap * gapCount) +
    8
  ));
  boardHeight = clamp(boardHeight, 110, 900);

  return {
    outerPadding: px(outerPadding),
    sectionGap: px(sectionGap),
    rowGap: px(rowGap),
    panelWidth: panelWidth,
    frameHeight: Math.max(240, Math.floor(vh - 2)),
    boardWidth: Math.max(160, panelWidth - (outerPadding * 2) - 2),
    boardHeight: boardHeight,
    boardRadius: tiny ? 12 : (compact ? 14 : 18),
    rowHeight: rowHeight,
    headerHeight: headerHeight,
    fontHeader: px(tiny ? 16 : (compact ? 18 : 23)),
    fontBody: px(tiny ? 10 : (compact ? 11 : 12)),
    fontSmall: px(tiny ? 9 : (compact ? 10 : 11)),
    buttonRadius: px(tiny ? 9 : (compact ? 11 : 13)),
    buttonFontSize: px(tiny ? 10 : (compact ? 11 : 12)),
    gridSpacing: tiny ? 18 : (compact ? 22 : 26),
    showFooter: showFooter,
    paletteRows: paletteRows,
  };
}

function textNode(value, style) {
  return {
    type: 'Text',
    props: {
      text: String(value),
      style: style || {}
    }
  };
}

function container(children, style, key, events) {
  const node = {
    type: 'Container',
    props: {
      style: style || {}
    },
    children: children || []
  };
  if (key) node.key = key;
  if (events) node.events = events;
  return node;
}

function row(children, style) {
  const base = {
    gap: uiTokens.rowGap,
    alignItems: 'center'
  };
  if (style) {
    for (const k in style) base[k] = style[k];
  }
  return {
    type: 'Row',
    props: { style: base },
    children: children
  };
}

function column(children, style) {
  const base = {
    gap: uiTokens.sectionGap,
    alignItems: 'stretch'
  };
  if (style) {
    for (const k in style) base[k] = style[k];
  }
  return {
    type: 'Column',
    props: { style: base },
    children: children
  };
}

function expanded(child, flex) {
  return {
    type: 'Expanded',
    props: {
      flex: flex || 1
    },
    children: [child]
  };
}

function sanitizeKeyPart(input) {
  return String(input).replace(/[^a-zA-Z0-9_]/g, '_');
}

function controlButton(label, handler, active, tone) {
  const keyId = 'ctl_' + sanitizeKeyPart(handler) + '_' + sanitizeKeyPart(label);
  let bg = '#0F172A';
  let border = '#334155';
  let fg = '#E2E8F0';

  if (active) {
    bg = '#1D4ED8';
    border = '#93C5FD';
    fg = '#FFFFFF';
  }

  if (tone === 'danger') {
    bg = active ? '#B91C1C' : '#7F1D1D';
    border = '#F87171';
    fg = '#FEE2E2';
  }

  return expanded(
    container(
      [
        {
          type: 'Center',
          children: [
            textNode(label, {
              color: fg,
              fontSize: uiTokens.buttonFontSize,
              fontWeight: 'w600'
            })
          ]
        }
      ],
      {
        height: px(uiTokens.rowHeight),
        borderRadius: uiTokens.buttonRadius,
        backgroundColor: bg,
        borderColor: border,
        borderWidth: '1'
      },
      keyId,
      { tap: handler }
    ),
    1
  );
}

function colorSwatchButton(index) {
  const color = PALETTE[index];
  const active = currentColor === color;
  const keyId = 'swatch_' + index;

  return expanded(
    container(
      [
        {
          type: 'Center',
          children: [
            container(
              [],
              {
                width: px(uiTokens.rowHeight - 12),
                height: px(uiTokens.rowHeight - 12),
                borderRadius: '999',
                backgroundColor: color,
                borderColor: active ? '#60A5FA' : '#1E293B',
                borderWidth: active ? '2' : '1'
              }
            )
          ]
        }
      ],
      {
        height: px(uiTokens.rowHeight),
        borderRadius: uiTokens.buttonRadius,
        backgroundColor: active ? '#0B244D' : '#0B1324',
        borderColor: active ? '#3B82F6' : '#1E293B',
        borderWidth: '1'
      },
      keyId,
      { tap: 'selectColor' + index }
    ),
    1
  );
}

function sizeButton(index, label) {
  const size = BRUSH_STEPS[index];
  const active = brushSize === size;
  return controlButton(label, 'selectSize' + index, active, null);
}

function paletteRow(start, end) {
  const children = [];
  for (let i = start; i < end; i += 1) {
    children.push(colorSwatchButton(i));
  }
  return row(children);
}

function decodeTypedValue(value) {
  if (value === null || value === undefined) return value;
  if (typeof value !== 'object') return value;
  if (!('type' in value) || !('data' in value)) return value;

  const nodeType = value.type;
  const raw = (value.data || {}).value;

  if (nodeType === 'object') {
    const out = {};
    if (raw && typeof raw === 'object') {
      for (const key in raw) {
        out[key] = decodeTypedValue(raw[key]);
      }
    }
    return out;
  }

  if (nodeType === 'array') {
    if (!Array.isArray(raw)) return [];
    return raw.map(decodeTypedValue);
  }

  return raw;
}

function decodeVmInput(input) {
  try {
    const value = decodeTypedValue(input);
    if (value && typeof value === 'object') return value;
  } catch (_) {}
  return {};
}

function distance(a, b) {
  const dx = numericOr(b.x, 0) - numericOr(a.x, 0);
  const dy = numericOr(b.y, 0) - numericOr(a.y, 0);
  return Math.sqrt((dx * dx) + (dy * dy));
}

function clampPoint(point) {
  return {
    x: clamp(numericOr(point.x, 0), 0, uiTokens.boardWidth),
    y: clamp(numericOr(point.y, 0), 0, uiTokens.boardHeight)
  };
}

function pointFromVmInput(input) {
  const event = decodeVmInput(input);
  const local = event.localPosition || event.position || { x: 0, y: 0 };
  return clampPoint({
    x: numericOr(local.x, 0),
    y: numericOr(local.y, 0)
  });
}

function isShapeTool(toolName) {
  return toolName === 'line' || toolName === 'rect' || toolName === 'circle';
}

function beginStroke(point) {
  const p = clampPoint(point);
  lastPointerPoint = p;
  pointerDown = true;

  if (isShapeTool(currentTool)) {
    activeStroke = {
      kind: 'shape',
      shape: currentTool,
      color: currentColor,
      size: brushSize,
      start: p,
      end: p,
    };
  } else {
    const isEraser = currentTool === 'eraser';
    activeStroke = {
      kind: 'path',
      tool: currentTool,
      color: isEraser ? eraserColor() : currentColor,
      size: isEraser ? (brushSize * 1.6) : brushSize,
      opacity: currentTool === 'highlighter' ? 0.32 : 1.0,
      points: [p],
    };
  }
}

function updateStroke(point) {
  if (!pointerDown || !activeStroke) return;

  const p = clampPoint(point);
  lastPointerPoint = p;

  if (activeStroke.kind === 'path') {
    const pts = activeStroke.points;
    const last = pts[pts.length - 1];
    const threshold = smoothMode ? 1.9 : 0.6;
    if (distance(last, p) >= threshold) {
      pts.push(p);
    }
  } else {
    activeStroke.end = p;
  }
}

function commitActiveStroke() {
  if (!activeStroke) {
    pointerDown = false;
    lastPointerPoint = null;
    return;
  }

  strokes.push(activeStroke);
  if (strokes.length > MAX_STROKES) {
    strokes = strokes.slice(strokes.length - MAX_STROKES);
  }

  redoStrokes = [];
  activeStroke = null;
  pointerDown = false;
  lastPointerPoint = null;

  askHost('updateApp', JSON.stringify({
    source: 'quickjs-whiteboard',
    action: 'strokeCommitted',
    tool: currentTool,
    strokeCount: strokes.length
  }));
}

function addGridCommands(cmds, width, height) {
  cmds.push({ type: 'setStrokeStyle', params: { color: gridColor() } });
  cmds.push({ type: 'setLineWidth', params: { width: 1 } });

  const spacing = uiTokens.gridSpacing;

  for (let x = spacing; x < width; x += spacing) {
    cmds.push({ type: 'beginPath', params: {} });
    cmds.push({ type: 'moveTo', params: { x: x, y: 0 } });
    cmds.push({ type: 'lineTo', params: { x: x, y: height } });
    cmds.push({ type: 'stroke', params: {} });
  }

  for (let y = spacing; y < height; y += spacing) {
    cmds.push({ type: 'beginPath', params: {} });
    cmds.push({ type: 'moveTo', params: { x: 0, y: y } });
    cmds.push({ type: 'lineTo', params: { x: width, y: y } });
    cmds.push({ type: 'stroke', params: {} });
  }
}

function addPathCommands(cmds, stroke, preview) {
  const points = stroke.points || [];
  if (points.length === 0) return;

  const alphaBase = clamp(numericOr(stroke.opacity, 1), 0.05, 1);
  const alpha = preview ? (alphaBase * 0.8) : alphaBase;

  cmds.push({ type: 'setGlobalAlpha', params: { alpha: alpha } });
  cmds.push({ type: 'setLineCap', params: { cap: 'round' } });
  cmds.push({ type: 'setLineJoin', params: { join: 'round' } });

  if (points.length === 1) {
    cmds.push({ type: 'setFillStyle', params: { color: stroke.color } });
    cmds.push({
      type: 'fillCircle',
      params: {
        x: points[0].x,
        y: points[0].y,
        radius: Math.max(1, numericOr(stroke.size, 2) / 2)
      }
    });
    cmds.push({ type: 'setGlobalAlpha', params: { alpha: 1 } });
    return;
  }

  cmds.push({ type: 'setStrokeStyle', params: { color: stroke.color } });
  cmds.push({ type: 'setLineWidth', params: { width: numericOr(stroke.size, 2) } });
  cmds.push({ type: 'beginPath', params: {} });
  cmds.push({ type: 'moveTo', params: { x: points[0].x, y: points[0].y } });
  for (let i = 1; i < points.length; i += 1) {
    cmds.push({ type: 'lineTo', params: { x: points[i].x, y: points[i].y } });
  }
  cmds.push({ type: 'stroke', params: {} });
  cmds.push({ type: 'setGlobalAlpha', params: { alpha: 1 } });
}

function addShapeCommands(cmds, stroke, preview) {
  const start = stroke.start || { x: 0, y: 0 };
  const end = stroke.end || start;
  const alpha = preview ? 0.76 : 1.0;

  cmds.push({ type: 'setGlobalAlpha', params: { alpha: alpha } });
  cmds.push({ type: 'setStrokeStyle', params: { color: stroke.color } });
  cmds.push({ type: 'setLineCap', params: { cap: 'round' } });
  cmds.push({ type: 'setLineJoin', params: { join: 'round' } });
  cmds.push({ type: 'setLineWidth', params: { width: numericOr(stroke.size, 2) } });

  if (stroke.shape === 'line') {
    cmds.push({ type: 'beginPath', params: {} });
    cmds.push({ type: 'moveTo', params: { x: start.x, y: start.y } });
    cmds.push({ type: 'lineTo', params: { x: end.x, y: end.y } });
    cmds.push({ type: 'stroke', params: {} });
  } else if (stroke.shape === 'rect') {
    const x = Math.min(start.x, end.x);
    const y = Math.min(start.y, end.y);
    const w = Math.abs(end.x - start.x);
    const h = Math.abs(end.y - start.y);

    if (w < 1 || h < 1) {
      cmds.push({ type: 'strokeCircle', params: { x: start.x, y: start.y, radius: 1.2 } });
    } else {
      cmds.push({ type: 'strokeRect', params: { x: x, y: y, width: w, height: h } });
    }
  } else {
    const r = distance(start, end);
    cmds.push({ type: 'strokeCircle', params: { x: start.x, y: start.y, radius: r } });
  }

  cmds.push({ type: 'setGlobalAlpha', params: { alpha: 1 } });
}

function addStrokeCommands(cmds, stroke, preview) {
  if (!stroke) return;
  if (stroke.kind === 'path') {
    addPathCommands(cmds, stroke, preview === true);
  } else {
    addShapeCommands(cmds, stroke, preview === true);
  }
}

function buildBoardCommands() {
  const width = uiTokens.boardWidth;
  const height = uiTokens.boardHeight;

  const cmds = [
    { type: 'setFillStyle', params: { color: backgroundFillColor() } },
    { type: 'fillRect', params: { x: 0, y: 0, width: width, height: height } }
  ];

  if (showGrid) {
    addGridCommands(cmds, width, height);
  }

  for (let i = 0; i < strokes.length; i += 1) {
    addStrokeCommands(cmds, strokes[i], false);
  }

  if (activeStroke) {
    addStrokeCommands(cmds, activeStroke, true);
  }

  return cmds;
}

function refreshBoard() {
  rerender();
}

function setTool(name) {
  currentTool = name;
  statusText = 'Tool: ' + name;
  rerender();
}

function toolPen() { setTool('pen'); }
function toolHighlighter() { setTool('highlighter'); }
function toolEraser() { setTool('eraser'); }
function toolLine() { setTool('line'); }
function toolRect() { setTool('rect'); }
function toolCircle() { setTool('circle'); }

function setColor(index) {
  if (index < 0 || index >= PALETTE.length) return;
  currentColor = PALETTE[index];
  if (currentTool === 'eraser') {
    currentTool = 'pen';
  }
  statusText = 'Color changed';
  rerender();
}

function selectColor0() { setColor(0); }
function selectColor1() { setColor(1); }
function selectColor2() { setColor(2); }
function selectColor3() { setColor(3); }
function selectColor4() { setColor(4); }
function selectColor5() { setColor(5); }
function selectColor6() { setColor(6); }
function selectColor7() { setColor(7); }

function setBrush(index) {
  if (index < 0 || index >= BRUSH_STEPS.length) return;
  brushSize = BRUSH_STEPS[index];
  statusText = 'Brush size: ' + brushSize;
  rerender();
}

function selectSize0() { setBrush(0); }
function selectSize1() { setBrush(1); }
function selectSize2() { setBrush(2); }
function selectSize3() { setBrush(3); }
function selectSize4() { setBrush(4); }

function undoStroke() {
  if (strokes.length === 0) return;
  const removed = strokes.pop();
  redoStrokes.push(removed);
  if (redoStrokes.length > MAX_STROKES) {
    redoStrokes = redoStrokes.slice(redoStrokes.length - MAX_STROKES);
  }
  statusText = 'Undo';
  rerender();
}

function redoStroke() {
  if (redoStrokes.length === 0) return;
  const restored = redoStrokes.pop();
  strokes.push(restored);
  statusText = 'Redo';
  rerender();
}

function clearBoard() {
  strokes = [];
  redoStrokes = [];
  activeStroke = null;
  pointerDown = false;
  lastPointerPoint = null;
  statusText = 'Canvas cleared';
  rerender();
}

function toggleGrid() {
  showGrid = !showGrid;
  statusText = showGrid ? 'Grid enabled' : 'Grid hidden';
  rerender();
}

function toggleTheme() {
  darkCanvas = !darkCanvas;
  statusText = darkCanvas ? 'Dark canvas theme' : 'Light canvas theme';
  rerender();
}

function toggleSmooth() {
  smoothMode = !smoothMode;
  statusText = smoothMode ? 'Smoothing on' : 'Smoothing off';
  rerender();
}

function onBoardDragStart(input) {
  const p = pointFromVmInput(input);
  beginStroke(p);
  rerender();
}

function onBoardDrag(input) {
  if (!pointerDown) return;
  updateStroke(pointFromVmInput(input));
  rerender();
}

function onBoardDragEnd(input) {
  if (!pointerDown) return;
  // Engine dragend payload may report zeroed coordinates.
  // Finalize using the last tracked drag position instead.
  if (lastPointerPoint) {
    updateStroke(lastPointerPoint);
  }
  commitActiveStroke();
  rerender();
}

function formatToolName(name) {
  if (name === 'highlighter') return 'Glow';
  if (name === 'eraser') return 'Eraser';
  if (name === 'line') return 'Line';
  if (name === 'rect') return 'Rect';
  if (name === 'circle') return 'Circle';
  return 'Pen';
}

function viewTree() {
  refreshHostEnvironment(false);
  uiTokens = buildUiTokens();

  const envViewport = hostEnvCache.viewport || {};
  const viewportLine =
    Math.round(numericOr(envViewport.width, viewportWidth())) +
    ' x ' +
    Math.round(numericOr(envViewport.height, viewportHeight()));

  const boardCommands = buildBoardCommands();

  return container(
    [
      {
        type: 'Center',
        children: [
          {
            type: 'ConstrainedBox',
            props: {
              style: {
                maxWidth: uiTokens.panelWidth,
              }
            },
            children: [
              container(
                [
                  column(
                    [
                      container(
                        [
                          row([
                            expanded(textNode('QuickJS Whiteboard', {
                              color: '#F8FAFC',
                              fontSize: uiTokens.fontHeader,
                              fontWeight: 'bold'
                            }), 1),
                            container([
                              {
                                type: 'Center',
                                children: [
                                  textNode(formatToolName(currentTool), {
                                    color: '#DBEAFE',
                                    fontSize: uiTokens.fontBody,
                                    fontWeight: 'w700'
                                  })
                                ]
                              }
                            ], {
                              padding: '6 10',
                              borderRadius: '999',
                              backgroundColor: '#1D4ED8',
                              borderColor: '#60A5FA',
                              borderWidth: '1'
                            })
                          ]),
                          row([
                            expanded(textNode(statusText, {
                              color: '#CBD5E1',
                              fontSize: uiTokens.fontBody
                            }), 1),
                            textNode('Strokes: ' + strokes.length, {
                              color: '#93C5FD',
                              fontSize: uiTokens.fontBody
                            })
                          ])
                        ],
                        {
                          minHeight: px(uiTokens.headerHeight),
                          padding: '10',
                          borderRadius: px(uiTokens.boardRadius),
                          backgroundColor: 'rgba(15, 23, 42, 0.72)',
                          borderColor: 'rgba(96, 165, 250, 0.45)',
                          borderWidth: '1'
                        }
                      ),

                      row([
                        controlButton('Pen', 'toolPen', currentTool === 'pen', null),
                        controlButton('Glow', 'toolHighlighter', currentTool === 'highlighter', null),
                        controlButton('Erase', 'toolEraser', currentTool === 'eraser', null),
                        controlButton('Line', 'toolLine', currentTool === 'line', null),
                        controlButton('Rect', 'toolRect', currentTool === 'rect', null),
                        controlButton('Circle', 'toolCircle', currentTool === 'circle', null)
                      ]),

                      row([
                        controlButton('Undo', 'undoStroke', false, null),
                        controlButton('Redo', 'redoStroke', false, null),
                        controlButton('Clear', 'clearBoard', false, 'danger'),
                        controlButton('Grid', 'toggleGrid', showGrid, null),
                        controlButton('Theme', 'toggleTheme', darkCanvas, null),
                        controlButton('Smooth', 'toggleSmooth', smoothMode, null)
                      ]),

                      container(
                        [
                          {
                            type: 'Canvas',
                            props: {
                              width: uiTokens.boardWidth,
                              height: uiTokens.boardHeight,
                              commands: boardCommands
                            }
                          }
                        ],
                        {
                          width: px(uiTokens.boardWidth),
                          height: px(uiTokens.boardHeight),
                          borderRadius: px(uiTokens.boardRadius),
                          backgroundColor: boardFrameColor(),
                          borderColor: boardBorderColor(),
                          borderWidth: '1'
                        },
                        'board_surface',
                        {
                          dragstart: 'onBoardDragStart',
                          drag: 'onBoardDrag',
                          dragend: 'onBoardDragEnd'
                        }
                      ),

                      uiTokens.paletteRows > 1
                        ? column([
                            paletteRow(0, 4),
                            paletteRow(4, 8)
                          ], { gap: uiTokens.rowGap })
                        : paletteRow(0, 8),

                      row([
                        sizeButton(0, 'XS'),
                        sizeButton(1, 'S'),
                        sizeButton(2, 'M'),
                        sizeButton(3, 'L'),
                        sizeButton(4, 'XL'),
                        controlButton('Refresh', 'refreshBoard', false, null)
                      ]),

                      uiTokens.showFooter
                        ? textNode(
                            'Responsive whiteboard | ' + viewportLine + ' | Tool: ' + formatToolName(currentTool) + ' | Brush ' + brushSize,
                            {
                              color: '#64748B',
                              fontSize: uiTokens.fontSmall,
                              textAlign: 'center'
                            }
                          )
                        : container([], { height: '1' })
                    ],
                    {
                      gap: uiTokens.sectionGap,
                      alignItems: 'stretch'
                    }
                  )
                ],
                {
                  height: px(uiTokens.frameHeight),
                  padding: uiTokens.outerPadding
                }
              )
            ]
          }
        ]
      }
    ],
    {
      height: px(uiTokens.frameHeight),
      gradient: {
        type: 'linear',
        begin: 'top-center',
        end: 'bottom-center',
        colors: ['#030712', '#071126', '#0B1835']
      }
    }
  );
}

function rerender() {
  askHost('render', JSON.stringify(viewTree()));
}

refreshHostEnvironment(false);
uiTokens = buildUiTokens();
ensureHostEnvRefreshTimer();
rerender();
''';
