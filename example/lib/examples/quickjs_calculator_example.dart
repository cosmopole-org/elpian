import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';

class QuickJsCalculatorExampleApp extends StatelessWidget {
  const QuickJsCalculatorExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elpian QuickJS Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
      ),
      home: const QuickJsCalculatorExamplePage(),
    );
  }
}

class QuickJsCalculatorExamplePage extends StatelessWidget {
  const QuickJsCalculatorExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: SafeArea(
        child: ElpianVmWidget.fromCode(
          machineId: 'quickjs-feature-rich-calculator',
          runtime: ElpianRuntime.quickJs,
          code: _calculatorProgram,
          onPrintln: (msg) {
            debugPrint('[quickjs-calculator] $msg');
          },
        ),
      ),
    );
  }
}

const String _calculatorProgram = r'''
let expression = '';
let displayValue = '0';
let statusText = 'Ready';
let history = [];
let memoryValue = 0;
let lastAnswer = 0;
let angleMode = 'DEG';
let justEvaluated = false;
let hostEnvCache = {};
let hostEnvDigest = '';
let envRefreshTimerId = null;

const MAX_HISTORY = 24;
const SHOW_HISTORY = 6;
const CHART_HEIGHT_BASE = 92;
const CHART_WIDTH_MIN = 180;
const CHART_WIDTH_MAX = 560;
const HOST_ENV_REFRESH_MS = 1400;

let uiTokens = {
  outerGap: '10',
  outerPadding: '10',
  cardPadding: '12',
  cardRadius: '18',
  keyGap: '6',
  keyRowGap: '5',
  keyPadding: '9 6',
  keyRadius: '13',
  keyFontSize: '15',
  titleFontSize: '20',
  statusFontSize: '12',
  sectionLabelFontSize: '12',
  expressionFontSize: '17',
  resultFontSize: '31',
  envFontSize: '11',
  historyExpressionFontSize: '11',
  historyResultFontSize: '13',
  footerFontSize: '11',
  chartHeight: 76,
  showTrend: true,
  showEnvDetails: true,
  historySlots: 2
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

  if (forceRerender === true) {
    rerender();
  }
  return true;
}

function refreshHostEnvironmentManual() {
  const changed = refreshHostEnvironment(false);
  statusText = changed ? 'Host environment updated' : 'Host environment unchanged';
  rerender();
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

function viewportWidth() {
  const viewport = hostEnvCache.viewport || {};
  return numericOr(viewport.width, 420);
}

function viewportHeight() {
  const viewport = hostEnvCache.viewport || {};
  return numericOr(viewport.height, 840);
}

function chartWidth() {
  const responsive = Math.floor(layoutMaxWidth() - 28);
  return Math.max(CHART_WIDTH_MIN, Math.min(CHART_WIDTH_MAX, responsive));
}

function layoutMaxWidth() {
  const responsive = Math.floor(viewportWidth() - 12);
  return Math.max(220, Math.min(560, responsive));
}

function fmtInt(value, fallback) {
  return String(Math.round(numericOr(value, fallback)));
}

function fmtDpr(value) {
  return numericOr(value, 1).toFixed(2);
}

function clamp(v, minV, maxV) {
  return Math.max(minV, Math.min(maxV, v));
}

function px(v) {
  return String(Math.max(0, Math.round(v)));
}

function buildUiTokens() {
  const vw = viewportWidth();
  const vh = viewportHeight();
  const compact = vw < 390 || vh < 820;
  const tight = vw < 355 || vh < 730;
  const veryTight = vw < 330 || vh < 670;

  const outerPadding = veryTight ? 6 : (tight ? 8 : (compact ? 10 : 12));
  const outerGap = veryTight ? 6 : (tight ? 7 : (compact ? 8 : 11));
  const cardPadding = veryTight ? 7 : (tight ? 8 : (compact ? 10 : 12));
  const keyPadY = veryTight ? 4 : (tight ? 5 : (compact ? 7 : 10));
  const keyPadX = veryTight ? 3 : (tight ? 4 : (compact ? 6 : 8));
  const keyRadius = veryTight ? 9 : (tight ? 10 : (compact ? 12 : 16));
  const keyGap = veryTight ? 3 : (tight ? 4 : (compact ? 5 : 7));
  const keyRowGap = veryTight ? 2 : (tight ? 3 : (compact ? 4 : 6));
  const labelFont = veryTight ? 11 : (tight ? 12 : (compact ? 14 : 18));
  const titleFont = veryTight ? 15 : (tight ? 16 : (compact ? 19 : 24));
  const statusFont = veryTight ? 10 : (tight ? 11 : 13);
  const sectionLabelFont = veryTight ? 10 : (tight ? 11 : 13);
  const exprFont = veryTight ? 12 : (tight ? 13 : (compact ? 15 : 19));
  const resultFont = veryTight ? 20 : (tight ? 24 : (compact ? 30 : 36));
  const envFont = veryTight ? 9 : (tight ? 10 : 12);
  const historyExprFont = veryTight ? 10 : (tight ? 11 : 12);
  const historyResultFont = veryTight ? 11 : (tight ? 12 : 14);
  const footerFont = veryTight ? 9 : (tight ? 10 : 12);
  const chartHeight = veryTight ? 52 : (tight ? 60 : (compact ? 74 : CHART_HEIGHT_BASE));
  const showTrend = vh >= 700;
  const showEnvDetails = vh >= 770 && vw >= 335;
  let historySlots = 0;
  if (vh >= 980) {
    historySlots = 4;
  } else if (vh >= 900) {
    historySlots = 3;
  } else if (vh >= 830) {
    historySlots = 2;
  } else if (vh >= 760) {
    historySlots = 1;
  }
  if (vw < 350) historySlots = Math.min(historySlots, 1);

  return {
    outerGap: px(outerGap),
    outerPadding: px(outerPadding),
    cardPadding: px(cardPadding),
    cardRadius: px(veryTight ? 12 : (tight ? 14 : 20)),
    keyGap: px(keyGap),
    keyRowGap: px(keyRowGap),
    keyPadding: px(keyPadY) + ' ' + px(keyPadX),
    keyRadius: px(keyRadius),
    keyFontSize: px(labelFont),
    titleFontSize: px(titleFont),
    statusFontSize: px(statusFont),
    sectionLabelFontSize: px(sectionLabelFont),
    expressionFontSize: px(exprFont),
    resultFontSize: px(resultFont),
    envFontSize: px(envFont),
    historyExpressionFontSize: px(historyExprFont),
    historyResultFontSize: px(historyResultFont),
    footerFontSize: px(footerFont),
    chartHeight: chartHeight,
    showTrend: showTrend,
    showEnvDetails: showEnvDetails,
    historySlots: historySlots
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
  const n = {
    type: 'Container',
    props: { style: style || {} },
    children: children || []
  };
  if (key) n.key = key;
  if (events) n.events = events;
  return n;
}

function row(children, style) {
  const base = {
    gap: '8',
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
    gap: '10',
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
    props: { flex: flex || 1 },
    children: [child]
  };
}

function sanitizeKeyPart(input) {
  return String(input).replace(/[^a-zA-Z0-9_]/g, '_');
}

function keyToneStyle(kind) {
  if (kind === 'operator') {
    return {
      backgroundColor: '#1D4ED8',
      borderColor: '#60A5FA',
      borderWidth: '1',
      color: '#F8FAFC'
    };
  }
  if (kind === 'function') {
    return {
      backgroundColor: '#172033',
      borderColor: '#334155',
      borderWidth: '1',
      color: '#C7D2FE'
    };
  }
  if (kind === 'danger') {
    return {
      backgroundColor: '#7F1D1D',
      borderColor: '#EF4444',
      borderWidth: '1',
      color: '#FEE2E2'
    };
  }
  if (kind === 'equal') {
    return {
      backgroundColor: '#15803D',
      borderColor: '#4ADE80',
      borderWidth: '1',
      color: '#ECFDF5'
    };
  }
  return {
    backgroundColor: '#0F172A',
    borderColor: '#334155',
    borderWidth: '1',
    color: '#E2E8F0'
  };
}

function keyButton(label, handler, kind, flex) {
  const tone = keyToneStyle(kind || 'digit');
  const keyId = 'btn_' + sanitizeKeyPart(handler) + '_' + sanitizeKeyPart(label);
  return expanded(
    container(
      [
        {
          type: 'Center',
          children: [
            textNode(label, {
              color: tone.color,
              fontSize: uiTokens.keyFontSize,
              fontWeight: 'w600'
            })
          ]
        }
      ],
      {
        padding: uiTokens.keyPadding,
        borderRadius: uiTokens.keyRadius,
        backgroundColor: tone.backgroundColor,
        borderColor: tone.borderColor,
        borderWidth: tone.borderWidth,
        boxShadow: [
          {
            color: 'rgba(2, 6, 23, 0.45)',
            blurRadius: 12,
            offset: { x: 0, y: 4 }
          }
        ]
      },
      keyId,
      { tap: handler }
    ),
    flex || 1
  );
}

function compactActionButton(label, handler) {
  const keyId = 'action_' + sanitizeKeyPart(handler) + '_' + sanitizeKeyPart(label);
  return container(
    [
      {
        type: 'Center',
        children: [
          textNode(label, {
            color: '#E2E8F0',
            fontSize: uiTokens.sectionLabelFontSize,
            fontWeight: 'w600'
          })
        ]
      }
    ],
    {
      padding: '6 10',
      borderRadius: '999',
      backgroundColor: '#1E293B',
      borderColor: '#334155',
      borderWidth: '1'
    },
    keyId,
    { tap: handler }
  );
}

function keypadRow(children) {
  return expanded(
    row(children, { gap: uiTokens.keyGap, alignItems: 'stretch' }),
    1
  );
}

function cleanError(err) {
  const raw = String(err || 'Error');
  return raw.replace('Error: ', '').slice(0, 72);
}

function formatNumber(value) {
  let v = Number(value);
  if (!Number.isFinite(v)) return 'Error';
  if (Math.abs(v) < 1e-12) v = 0;

  const abs = Math.abs(v);
  if (abs >= 1e12 || (abs > 0 && abs < 1e-9)) {
    return v.toExponential(6);
  }

  let s = v.toFixed(10);
  s = s.replace(/\.0+$/, '');
  s = s.replace(/(\.\d*?)0+$/, '$1');
  return s;
}

function endsWithOperand() {
  if (!expression) return false;
  if (/[0-9)]$/.test(expression)) return true;
  if (/pi$/.test(expression)) return true;
  if (/ANS$/.test(expression)) return true;
  if (/E$/.test(expression)) return true;
  return false;
}

function resetForInput(nextType) {
  if (!justEvaluated) return;
  if (nextType === 'operator') {
    expression = formatNumber(lastAnswer);
  } else {
    expression = '';
  }
  justEvaluated = false;
}

function appendDigit(d) {
  resetForInput('digit');
  if (endsWithOperand() && /(?:pi|ANS|E|\))$/.test(expression)) {
    expression += '*';
  }
  if (expression === '0') {
    expression = d;
  } else {
    expression += d;
  }
  statusText = 'Editing';
  rerender();
}

function appendOperator(op) {
  resetForInput('operator');
  if (!expression) {
    if (op === '-') {
      expression = '-';
      statusText = 'Editing';
      rerender();
      return;
    }
    if (lastAnswer !== 0) {
      expression = formatNumber(lastAnswer) + op;
      statusText = 'Editing';
      rerender();
    }
    return;
  }

  if (/[+\-*/^]$/.test(expression)) {
    expression = expression.slice(0, -1) + op;
  } else if (/\($/.test(expression) && op !== '-') {
    return;
  } else {
    expression += op;
  }

  statusText = 'Editing';
  rerender();
}

function appendDecimal() {
  resetForInput('digit');

  if (endsWithOperand() && /(?:pi|ANS|E|\))$/.test(expression)) {
    expression += '*0.';
    statusText = 'Editing';
    rerender();
    return;
  }

  let i = expression.length - 1;
  let foundDot = false;
  while (i >= 0) {
    const ch = expression[i];
    if (ch === '.') {
      foundDot = true;
      break;
    }
    if ((ch >= '0' && ch <= '9')) {
      i -= 1;
      continue;
    }
    break;
  }

  if (foundDot) return;

  if (!expression || /[+\-*/^(]$/.test(expression)) {
    expression += '0.';
  } else {
    expression += '.';
  }

  statusText = 'Editing';
  rerender();
}

function openParen() {
  resetForInput('digit');
  if (endsWithOperand()) {
    expression += '*';
  }
  expression += '(';
  statusText = 'Editing';
  rerender();
}

function closeParen() {
  if (!expression) return;
  if (/[+\-*/^(]$/.test(expression)) return;

  let open = 0;
  let close = 0;
  for (let i = 0; i < expression.length; i += 1) {
    if (expression[i] === '(') open += 1;
    if (expression[i] === ')') close += 1;
  }

  if (open <= close) return;
  expression += ')';
  statusText = 'Editing';
  rerender();
}

function appendFunction(name) {
  resetForInput('digit');
  if (endsWithOperand()) {
    expression += '*';
  }
  expression += name + '(';
  statusText = 'Editing';
  rerender();
}

function appendConstant(token) {
  resetForInput('digit');
  if (endsWithOperand()) {
    expression += '*';
  }
  expression += token;
  statusText = 'Editing';
  rerender();
}

function appendAns() {
  resetForInput('digit');
  if (endsWithOperand()) {
    expression += '*';
  }
  expression += 'ANS';
  statusText = 'Editing';
  rerender();
}

function backspace() {
  if (!expression) return;
  expression = expression.slice(0, -1);
  justEvaluated = false;
  statusText = 'Editing';
  rerender();
}

function clearEntry() {
  expression = '';
  displayValue = '0';
  justEvaluated = false;
  statusText = 'Entry cleared';
  rerender();
}

function clearAll() {
  expression = '';
  displayValue = '0';
  lastAnswer = 0;
  justEvaluated = false;
  statusText = 'All cleared';
  rerender();
}

function clearHistory() {
  history = [];
  statusText = 'History cleared';
  rerender();
}

function toggleAngle() {
  angleMode = angleMode === 'DEG' ? 'RAD' : 'DEG';
  statusText = 'Angle mode: ' + angleMode;
  rerender();
}

function autoCloseParens(raw) {
  let open = 0;
  let close = 0;
  for (let i = 0; i < raw.length; i += 1) {
    if (raw[i] === '(') open += 1;
    if (raw[i] === ')') close += 1;
  }
  let out = raw;
  while (close < open) {
    out += ')';
    close += 1;
  }
  return out;
}

function safeEval(rawInput) {
  let raw = String(rawInput || '').trim();
  if (!raw) return 0;

  if (/[+\-*/^.]$/.test(raw)) {
    throw new Error('Incomplete expression');
  }

  raw = autoCloseParens(raw);

  let jsExpr = raw
    .replace(/\^/g, '**')
    .replace(/\bpi\b/g, 'PI')
    .replace(/ANS/g, '(' + formatNumber(lastAnswer) + ')');

  const reduced = jsExpr
    .replace(/sin|cos|tan|sqrt|ln|log|exp|abs|pow|PI|E/g, '');
  if (/[^0-9+\-*/().,\s*]/.test(reduced)) {
    throw new Error('Unsupported token');
  }

  const toRad = function (x) {
    return angleMode === 'DEG' ? (x * Math.PI) / 180 : x;
  };

  const sin = function (x) { return Math.sin(toRad(x)); };
  const cos = function (x) { return Math.cos(toRad(x)); };
  const tan = function (x) { return Math.tan(toRad(x)); };
  const sqrt = function (x) { return Math.sqrt(x); };
  const ln = function (x) { return Math.log(x); };
  const log = function (x) { return Math.log(x) / Math.LN10; };
  const exp = function (x) { return Math.exp(x); };
  const abs = function (x) { return Math.abs(x); };
  const pow = function (a, b) { return Math.pow(a, b); };

  const val = Function(
    'sin', 'cos', 'tan', 'sqrt', 'ln', 'log', 'exp', 'abs', 'pow', 'PI', 'E',
    '"use strict"; return (' + jsExpr + ');'
  )(sin, cos, tan, sqrt, ln, log, exp, abs, pow, Math.PI, Math.E);

  if (!Number.isFinite(val)) {
    throw new Error('Math error');
  }

  return Number(val);
}

function pushHistory(exprText, resultText, numericValue) {
  const rec = {
    expression: String(exprText),
    result: String(resultText),
    value: Number(numericValue),
    timestamp: Date.now()
  };

  if (history.length > 0) {
    const top = history[0];
    if (top.expression === rec.expression && top.result === rec.result) {
      return;
    }
  }

  history.unshift(rec);
  if (history.length > MAX_HISTORY) {
    history = history.slice(0, MAX_HISTORY);
  }
}

function evaluateNow() {
  try {
    const source = expression.trim().length > 0 ? expression : formatNumber(lastAnswer);
    const value = safeEval(source);
    const result = formatNumber(value);

    displayValue = result;
    expression = result;
    lastAnswer = value;
    justEvaluated = true;
    statusText = 'Computed';
    pushHistory(source, result, value);

    askHost('updateApp', JSON.stringify({
      source: 'quickjs-calculator',
      action: 'evaluated',
      expression: source,
      result,
      memory: memoryValue,
      mode: angleMode
    }));
  } catch (e) {
    displayValue = 'Error';
    statusText = cleanError(e);
    justEvaluated = false;
    askHost('println', 'Calculator error: ' + String(e));
  }

  rerender();
}

function applyUnary(name, op) {
  try {
    const base = expression.trim().length > 0 ? safeEval(expression) : lastAnswer;
    const value = Number(op(base));
    if (!Number.isFinite(value)) {
      throw new Error('Math error');
    }

    const result = formatNumber(value);
    const label = name + '(' + formatNumber(base) + ')';
    pushHistory(label, result, value);

    expression = result;
    displayValue = result;
    lastAnswer = value;
    justEvaluated = true;
    statusText = name + ' applied';
  } catch (e) {
    displayValue = 'Error';
    statusText = name + ': ' + cleanError(e);
  }

  rerender();
}

function toggleSign() {
  applyUnary('neg', function (x) { return -x; });
}

function unarySquare() {
  applyUnary('square', function (x) { return x * x; });
}

function unarySqrt() {
  applyUnary('sqrt', function (x) { return Math.sqrt(x); });
}

function unaryInverse() {
  applyUnary('inv', function (x) {
    if (Math.abs(x) < 1e-12) throw new Error('division by zero');
    return 1 / x;
  });
}

function unaryPercent() {
  applyUnary('percent', function (x) { return x / 100; });
}

function readCurrentValue() {
  try {
    if (expression.trim().length > 0) return safeEval(expression);
    return lastAnswer;
  } catch (_) {
    return lastAnswer;
  }
}

function memoryClear() {
  memoryValue = 0;
  statusText = 'Memory cleared';
  rerender();
}

function memoryAdd() {
  memoryValue += readCurrentValue();
  statusText = 'M = ' + formatNumber(memoryValue);
  rerender();
}

function memorySubtract() {
  memoryValue -= readCurrentValue();
  statusText = 'M = ' + formatNumber(memoryValue);
  rerender();
}

function memoryRecall() {
  resetForInput('digit');
  let token = formatNumber(memoryValue);
  if (token.startsWith('-')) token = '(' + token + ')';
  if (endsWithOperand()) expression += '*';
  expression += token;
  statusText = 'Memory recalled';
  rerender();
}

function useHistoryIndex(idx) {
  if (idx < 0 || idx >= history.length) return;
  const rec = history[idx];
  expression = rec.result;
  displayValue = rec.result;
  lastAnswer = rec.value;
  justEvaluated = true;
  statusText = 'Loaded from history';
  rerender();
}

function useHistory0() { useHistoryIndex(0); }
function useHistory1() { useHistoryIndex(1); }
function useHistory2() { useHistoryIndex(2); }
function useHistory3() { useHistoryIndex(3); }
function useHistory4() { useHistoryIndex(4); }
function useHistory5() { useHistoryIndex(5); }

function chartCommands() {
  const width = chartWidth();
  const chartHeight = uiTokens.chartHeight;
  const values = history.slice(0, 12).map(function (h) { return h.value; }).reverse();
  const cmds = [
    { type: 'setStrokeStyle', params: { color: '#1F2937' } },
    { type: 'setLineWidth', params: { width: 1 } },
    { type: 'strokeRect', params: { x: 0, y: 0, width: width, height: chartHeight } }
  ];

  if (values.length === 0) {
    cmds.push({ type: 'setFillStyle', params: { color: '#64748B' } });
    cmds.push({
      type: 'fillText',
      params: {
        text: chartHeight < 60 ? 'Sparkline appears after calculations' : 'History sparkline appears after calculations',
        x: 12,
        y: Math.round(chartHeight * 0.58)
      }
    });
    return cmds;
  }

  let minV = values[0];
  let maxV = values[0];
  for (let i = 1; i < values.length; i += 1) {
    if (values[i] < minV) minV = values[i];
    if (values[i] > maxV) maxV = values[i];
  }

  const range = Math.abs(maxV - minV) < 1e-12 ? 1 : (maxV - minV);
  const padX = chartHeight < 62 ? 10 : 14;
  const padY = chartHeight < 62 ? 8 : 12;
  const w = width - (padX * 2);
  const h = chartHeight - (padY * 2);

  cmds.push({ type: 'setStrokeStyle', params: { color: '#60A5FA' } });
  cmds.push({ type: 'setLineWidth', params: { width: 2.5 } });
  cmds.push({ type: 'beginPath', params: {} });

  for (let i = 0; i < values.length; i += 1) {
    const t = values.length === 1 ? 0 : i / (values.length - 1);
    const x = padX + (w * t);
    const y = padY + h - (((values[i] - minV) / range) * h);
    if (i === 0) {
      cmds.push({ type: 'moveTo', params: { x, y } });
    } else {
      cmds.push({ type: 'lineTo', params: { x, y } });
    }
  }

  cmds.push({ type: 'stroke', params: {} });
  cmds.push({ type: 'setFillStyle', params: { color: '#93C5FD' } });
  for (let i = 0; i < values.length; i += 1) {
    const t = values.length === 1 ? 0 : i / (values.length - 1);
    const x = padX + (w * t);
    const y = padY + h - (((values[i] - minV) / range) * h);
    cmds.push({ type: 'fillCircle', params: { x, y, radius: 2.8 } });
  }

  return cmds;
}

function historyTile(index) {
  const tilePadding = uiTokens.showEnvDetails ? '8 10' : '7 9';
  if (index >= history.length) {
    return container(
      [textNode('No entry', { color: '#64748B', fontSize: uiTokens.historyExpressionFontSize })],
      {
        padding: tilePadding,
        borderRadius: '12',
        backgroundColor: '#0B1220',
        borderColor: '#1E293B',
        borderWidth: '1'
      }
    );
  }

  const rec = history[index];

  return container(
    [
      row(
        [
          expanded(textNode(rec.expression, {
            color: '#93C5FD',
            fontSize: uiTokens.historyExpressionFontSize
          }), 3),
          expanded(
            {
              type: 'Container',
              children: [
                textNode(rec.result, {
                  color: '#E2E8F0',
                  fontSize: uiTokens.historyResultFontSize,
                  fontWeight: 'w600',
                  textAlign: 'right'
                })
              ]
            },
            2
          )
        ],
        { alignItems: 'center' }
      )
    ],
    {
      padding: tilePadding,
      borderRadius: '12',
      backgroundColor: '#0B1220',
      borderColor: '#1E293B',
      borderWidth: '1'
    },
    'history_' + index,
    { tap: 'useHistory' + index }
  );
}

function previewValue() {
  if (!expression.trim()) {
    return formatNumber(lastAnswer);
  }
  try {
    return formatNumber(safeEval(expression));
  } catch (_) {
    return '...';
  }
}

function viewTree() {
  refreshHostEnvironment(false);
  uiTokens = buildUiTokens();

  const memLabel = Math.abs(memoryValue) < 1e-12 ? 'M: empty' : ('M: ' + formatNumber(memoryValue));
  const exprLabel = expression.trim().length ? expression : '0';
  const livePreview = previewValue();
  const viewport = hostEnvCache.viewport || {};
  const screen = hostEnvCache.screen || {};
  const page = hostEnvCache.page || {};
  const platform = hostEnvCache.platform || {};
  const runtimeName = String(hostEnvCache.runtime || 'unknown');
  const machine = String(hostEnvCache.machineId || 'n/a');
  const panelWidth = layoutMaxWidth();
  const sparklineWidth = chartWidth();
  const chartHeight = uiTokens.chartHeight;
  const frameHeight = Math.max(360, Math.floor(viewportHeight() - 2));
  const visibleHistory = Math.min(uiTokens.historySlots, SHOW_HISTORY);
  const pageHost = page.host ? String(page.host) : 'local';
  const pagePath = page.path ? String(page.path) : '/';
  const pageQuery = page.query ? ('?' + String(page.query)) : '';
  const pageLine = pageHost + pagePath + pageQuery;
  const viewportLine = fmtInt(viewport.width, viewportWidth()) + ' x ' +
    fmtInt(viewport.height, viewportHeight()) + ' (' +
    String(viewport.orientation || 'unknown') + ', dpr ' + fmtDpr(viewport.devicePixelRatio) + ')';
  const screenLine = fmtInt(screen.physicalWidth, 0) + ' x ' + fmtInt(screen.physicalHeight, 0);
  const platformLine = String(platform.defaultTargetPlatform || 'unknown') +
    (platform.locale ? (' • ' + String(platform.locale)) : '');

  const envChildren = [
    row([
      expanded(textNode('Host Environment', {
        color: '#BFDBFE',
        fontSize: uiTokens.sectionLabelFontSize,
        fontWeight: 'w700'
      }), 1),
      compactActionButton('ENV', 'refreshHostEnvironmentManual')
    ], { alignItems: 'center', gap: '8' }),
    textNode('Runtime: ' + runtimeName + ' • Machine: ' + machine, {
      color: '#CBD5E1',
      fontSize: uiTokens.envFontSize
    }),
    textNode('Viewport: ' + viewportLine, {
      color: '#CBD5E1',
      fontSize: uiTokens.envFontSize
    })
  ];
  if (uiTokens.showEnvDetails) {
    envChildren.push(
      textNode('Screen: ' + screenLine, {
        color: '#CBD5E1',
        fontSize: uiTokens.envFontSize
      }),
    );
    envChildren.push(
      textNode('Page: ' + pageLine, {
        color: '#93C5FD',
        fontSize: uiTokens.envFontSize
      }),
    );
    envChildren.push(
      textNode('Platform: ' + platformLine, {
        color: '#94A3B8',
        fontSize: uiTokens.envFontSize
      }),
    );
  }

  const keypadRows = [
    keypadRow([
      keyButton('MC', 'memoryClear', 'function'),
      keyButton('MR', 'memoryRecall', 'function'),
      keyButton('M+', 'memoryAdd', 'function'),
      keyButton('M-', 'memorySubtract', 'function')
    ]),
    keypadRow([
      keyButton('(', 'openParen', 'function'),
      keyButton(')', 'closeParen', 'function'),
      keyButton('BK', 'backspace', 'function'),
      keyButton('AC', 'clearAll', 'danger')
    ]),
    keypadRow([
      keyButton('sin', 'fnSin', 'function'),
      keyButton('cos', 'fnCos', 'function'),
      keyButton('tan', 'fnTan', 'function'),
      keyButton('pi', 'constPi', 'function')
    ]),
    keypadRow([
      keyButton('x2', 'unarySquare', 'function'),
      keyButton('sqrt', 'unarySqrt', 'function'),
      keyButton('1/x', 'unaryInverse', 'function'),
      keyButton('%', 'unaryPercent', 'function')
    ]),
    keypadRow([
      keyButton('7', 'd7', 'digit'),
      keyButton('8', 'd8', 'digit'),
      keyButton('9', 'd9', 'digit'),
      keyButton('/', 'opDiv', 'operator')
    ]),
    keypadRow([
      keyButton('4', 'd4', 'digit'),
      keyButton('5', 'd5', 'digit'),
      keyButton('6', 'd6', 'digit'),
      keyButton('*', 'opMul', 'operator')
    ]),
    keypadRow([
      keyButton('1', 'd1', 'digit'),
      keyButton('2', 'd2', 'digit'),
      keyButton('3', 'd3', 'digit'),
      keyButton('-', 'opSub', 'operator')
    ]),
    keypadRow([
      keyButton('+/-', 'toggleSign', 'function'),
      keyButton('0', 'd0', 'digit'),
      keyButton('.', 'decimal', 'digit'),
      keyButton('+', 'opAdd', 'operator')
    ]),
    keypadRow([
      keyButton('ANS', 'appendAns', 'function'),
      keyButton('ln', 'fnLn', 'function'),
      keyButton('log', 'fnLog', 'function'),
      keyButton('=', 'evaluateNow', 'equal')
    ]),
    keypadRow([
      keyButton('exp', 'fnExp', 'function'),
      keyButton('e', 'constE', 'function'),
      keyButton('^', 'opPow', 'operator'),
      keyButton('C', 'clearEntry', 'danger')
    ])
  ];

  const contentChildren = [
    container(
      [
        row([
          expanded(textNode('Elpian QuickJS Calculator', {
            color: '#F8FAFC',
            fontSize: uiTokens.titleFontSize,
            fontWeight: 'bold'
          }), 1),
          compactActionButton(angleMode, 'toggleAngle')
        ], { alignItems: 'center' }),
        textNode(statusText, {
          color: '#94A3B8',
          fontSize: uiTokens.statusFontSize
        })
      ],
      {
        padding: uiTokens.cardPadding,
        borderRadius: uiTokens.cardRadius,
        backgroundColor: 'rgba(15, 23, 42, 0.72)',
        borderColor: 'rgba(96, 165, 250, 0.45)',
        borderWidth: '1'
      }
    ),
    container(
      [
        textNode('Expression', {
          color: '#94A3B8',
          fontSize: uiTokens.sectionLabelFontSize
        }),
        textNode(exprLabel, {
          color: '#D1D5DB',
          fontSize: uiTokens.expressionFontSize,
          fontFamily: 'monospace'
        }),
        textNode('Preview: ' + livePreview, {
          color: '#60A5FA',
          fontSize: uiTokens.sectionLabelFontSize
        }),
        row([
          expanded(textNode('Result', {
            color: '#94A3B8',
            fontSize: uiTokens.sectionLabelFontSize
          }), 1),
          expanded(
            {
              type: 'Container',
              children: [
                textNode(displayValue, {
                  color: '#F8FAFC',
                  fontSize: uiTokens.resultFontSize,
                  fontWeight: 'bold',
                  textAlign: 'right',
                  fontFamily: 'monospace'
                })
              ]
            },
            3
          )
        ], { alignItems: 'center' }),
        textNode(memLabel, {
          color: '#A7F3D0',
          fontSize: uiTokens.sectionLabelFontSize
        })
      ],
      {
        padding: uiTokens.cardPadding,
        borderRadius: uiTokens.cardRadius,
        backgroundColor: '#0A1020',
        borderColor: '#1E293B',
        borderWidth: '1'
      }
    ),
    container(
      envChildren,
      {
        padding: uiTokens.cardPadding,
        borderRadius: uiTokens.cardRadius,
        backgroundColor: 'rgba(15, 23, 42, 0.74)',
        borderColor: '#1E3A8A',
        borderWidth: '1'
      }
    )
  ];

  if (uiTokens.showTrend) {
    contentChildren.push(
      container(
        [
          textNode('Calculation Trend', {
            color: '#C7D2FE',
            fontSize: uiTokens.sectionLabelFontSize,
            fontWeight: 'w600'
          }),
          {
            type: 'Canvas',
            props: {
              width: sparklineWidth,
              height: chartHeight,
              commands: chartCommands()
            }
          }
        ],
        {
          padding: uiTokens.cardPadding,
          borderRadius: uiTokens.cardRadius,
          backgroundColor: '#0A1020',
          borderColor: '#1E293B',
          borderWidth: '1'
        }
      ),
    );
  }

  contentChildren.push(
    expanded(
      container(
        [
          column(keypadRows, {
            gap: uiTokens.keyRowGap,
            alignItems: 'stretch'
          })
        ],
        {
          padding: uiTokens.cardPadding,
          borderRadius: uiTokens.cardRadius,
          backgroundColor: '#0B1324',
          borderColor: '#1E293B',
          borderWidth: '1'
        }
      ),
      1
    ),
  );

  if (visibleHistory > 0) {
    const historyChildren = [
      row([
        expanded(textNode('History (tap to reuse)', {
          color: '#C7D2FE',
          fontSize: uiTokens.sectionLabelFontSize,
          fontWeight: 'w600'
        }), 1),
        compactActionButton('Clear', 'clearHistory')
      ], { alignItems: 'center' })
    ];

    for (let i = 0; i < visibleHistory; i += 1) {
      historyChildren.push(historyTile(i));
    }

    contentChildren.push(
      container(
        historyChildren,
        {
          padding: uiTokens.cardPadding,
          borderRadius: uiTokens.cardRadius,
          backgroundColor: '#0A1020',
          borderColor: '#1E293B',
          borderWidth: '1'
        }
      ),
    );
  }

  if (viewportHeight() >= 760) {
    contentChildren.push(
      textNode(
        'QuickJS VM + Elpian widgets + CSS + Canvas. History shown: ' + Math.min(history.length, visibleHistory),
        {
          color: '#64748B',
          fontSize: uiTokens.footerFontSize,
          textAlign: 'center'
        },
      ),
    );
  }

  return container(
    [
      {
        type: 'Center',
        children: [
          {
            type: 'ConstrainedBox',
            props: {
              style: {
                maxWidth: panelWidth
              }
            },
            children: [
              container(
                [
                  column(contentChildren, {
                    gap: uiTokens.outerGap,
                    alignItems: 'stretch'
                  })
                ],
                {
                  height: px(frameHeight),
                  padding: uiTokens.outerPadding
                }
              )
            ]
          }
        ]
      }
    ],
    {
      height: px(frameHeight),
      gradient: {
        type: 'linear',
        begin: 'top-center',
        end: 'bottom-center',
        colors: ['#020617', '#0A1122', '#0F1D3A']
      }
    }
  );
}

function rerender() {
  askHost('render', JSON.stringify(viewTree()));
}

function d0() { appendDigit('0'); }
function d1() { appendDigit('1'); }
function d2() { appendDigit('2'); }
function d3() { appendDigit('3'); }
function d4() { appendDigit('4'); }
function d5() { appendDigit('5'); }
function d6() { appendDigit('6'); }
function d7() { appendDigit('7'); }
function d8() { appendDigit('8'); }
function d9() { appendDigit('9'); }

function opAdd() { appendOperator('+'); }
function opSub() { appendOperator('-'); }
function opMul() { appendOperator('*'); }
function opDiv() { appendOperator('/'); }
function opPow() { appendOperator('^'); }

function decimal() { appendDecimal(); }

function fnSin() { appendFunction('sin'); }
function fnCos() { appendFunction('cos'); }
function fnTan() { appendFunction('tan'); }
function fnLn() { appendFunction('ln'); }
function fnLog() { appendFunction('log'); }
function fnExp() { appendFunction('exp'); }

function constPi() { appendConstant('pi'); }
function constE() { appendConstant('E'); }

refreshHostEnvironment(false);
ensureHostEnvRefreshTimer();
rerender();
''';
