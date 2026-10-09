/**
 * Catalogs as the renderer sees them: for each component its properties
 * (with the kind of value each accepts), required properties and enums; for
 * each function its arguments and return type. The basic catalog below is a
 * compact, hand-portable transcription of
 * `a2ui/spec/catalogs/basic/catalog.json` (a test checks the two agree), so
 * the Dart, Kotlin and Swift renderers can carry the same table without a
 * JSON Schema engine.
 */
import { BASIC_FUNCTIONS, type A2UIFunction } from './functions.js';

/** The `catalogId` inside the vendored basic catalog file. */
export const BASIC_CATALOG_ID = 'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

/**
 * Other spellings of the basic catalog id accepted on `createSurface` — the
 * protocol document's examples use the v0_9_1 path.
 */
export const BASIC_CATALOG_ALIASES: readonly string[] = ['https://a2ui.org/specification/v0_9_1/catalogs/basic/catalog.json'];

export type PropKind =
  | 'DynamicString'
  | 'DynamicNumber'
  | 'DynamicBoolean'
  | 'DynamicStringList'
  | 'DynamicValue'
  | 'ComponentId'
  | 'ChildList'
  | 'Action'
  | 'Checks'
  | 'Accessibility'
  | 'IconName'
  | 'TabList'
  | 'OptionList'
  | 'string'
  | 'number'
  | 'boolean';

export interface PropSpec {
  kind: PropKind;
  enum?: readonly string[];
  default?: unknown;
}

export interface ComponentSpec {
  props: Record<string, PropSpec>;
  required: readonly string[];
}

export type ReturnType = 'string' | 'number' | 'boolean' | 'array' | 'object' | 'any' | 'void';

export interface FunctionSpec {
  args: Record<string, PropKind | 'any' | 'DynamicBooleanList'>;
  required: readonly string[];
  /** At least one of these groups must be fully present (`length`/`numeric`: min or max). */
  anyOf?: readonly (readonly string[])[];
  returnType: ReturnType;
}

export interface A2UICatalog {
  id: string;
  aliases?: readonly string[];
  components: Record<string, ComponentSpec>;
  functions: Record<string, FunctionSpec>;
  implementations: Record<string, A2UIFunction>;
}

/** Properties every component accepts. */
export const COMMON_PROPS: Record<string, PropSpec> = {
  id: { kind: 'ComponentId' },
  component: { kind: 'string' },
  accessibility: { kind: 'Accessibility' },
  weight: { kind: 'number' },
};

const CHECKABLE: Record<string, PropSpec> = { checks: { kind: 'Checks' } };

export const ICON_NAMES: readonly string[] = [
  'accountCircle', 'add', 'arrowBack', 'arrowForward', 'attachFile', 'calendarToday', 'call', 'camera', 'check', 'close',
  'delete', 'download', 'edit', 'event', 'error', 'fastForward', 'favorite', 'favoriteOff', 'folder', 'help', 'home', 'info',
  'locationOn', 'lock', 'lockOpen', 'mail', 'menu', 'moreVert', 'moreHoriz', 'notificationsOff', 'notifications', 'pause',
  'payment', 'person', 'phone', 'photo', 'play', 'print', 'refresh', 'rewind', 'search', 'send', 'settings', 'share',
  'shoppingCart', 'skipNext', 'skipPrevious', 'star', 'starHalf', 'starOff', 'stop', 'upload', 'visibility', 'visibilityOff',
  'volumeDown', 'volumeMute', 'volumeOff', 'volumeUp', 'warning',
];

const JUSTIFY = ['start', 'center', 'end', 'spaceBetween', 'spaceAround', 'spaceEvenly', 'stretch'] as const;
const ALIGN = ['start', 'center', 'end', 'stretch'] as const;

export const BASIC_COMPONENTS: Record<string, ComponentSpec> = {
  Text: {
    props: { text: { kind: 'DynamicString' }, variant: { kind: 'string', enum: ['h1', 'h2', 'h3', 'h4', 'h5', 'caption', 'body'], default: 'body' } },
    required: ['text'],
  },
  Image: {
    props: {
      url: { kind: 'DynamicString' },
      description: { kind: 'DynamicString' },
      fit: { kind: 'string', enum: ['contain', 'cover', 'fill', 'none', 'scaleDown'], default: 'fill' },
      variant: { kind: 'string', enum: ['icon', 'avatar', 'smallFeature', 'mediumFeature', 'largeFeature', 'header'], default: 'mediumFeature' },
    },
    required: ['url'],
  },
  Icon: { props: { name: { kind: 'IconName' } }, required: ['name'] },
  Video: { props: { url: { kind: 'DynamicString' } }, required: ['url'] },
  AudioPlayer: { props: { url: { kind: 'DynamicString' }, description: { kind: 'DynamicString' } }, required: ['url'] },
  Row: {
    props: { children: { kind: 'ChildList' }, justify: { kind: 'string', enum: JUSTIFY, default: 'start' }, align: { kind: 'string', enum: ALIGN, default: 'stretch' } },
    required: ['children'],
  },
  Column: {
    props: { children: { kind: 'ChildList' }, justify: { kind: 'string', enum: JUSTIFY, default: 'start' }, align: { kind: 'string', enum: ALIGN, default: 'stretch' } },
    required: ['children'],
  },
  List: {
    props: { children: { kind: 'ChildList' }, direction: { kind: 'string', enum: ['vertical', 'horizontal'], default: 'vertical' }, align: { kind: 'string', enum: ALIGN, default: 'stretch' } },
    required: ['children'],
  },
  Card: { props: { child: { kind: 'ComponentId' } }, required: ['child'] },
  Tabs: { props: { tabs: { kind: 'TabList' } }, required: ['tabs'] },
  Modal: { props: { trigger: { kind: 'ComponentId' }, content: { kind: 'ComponentId' } }, required: ['trigger', 'content'] },
  Divider: { props: { axis: { kind: 'string', enum: ['horizontal', 'vertical'], default: 'horizontal' } }, required: [] },
  Button: {
    props: { ...CHECKABLE, child: { kind: 'ComponentId' }, variant: { kind: 'string', enum: ['default', 'primary', 'borderless'], default: 'default' }, action: { kind: 'Action' } },
    required: ['child', 'action'],
  },
  TextField: {
    props: {
      ...CHECKABLE,
      label: { kind: 'DynamicString' },
      value: { kind: 'DynamicString' },
      variant: { kind: 'string', enum: ['longText', 'number', 'shortText', 'obscured'], default: 'shortText' },
      validationRegexp: { kind: 'string' },
    },
    required: ['label'],
  },
  CheckBox: { props: { ...CHECKABLE, label: { kind: 'DynamicString' }, value: { kind: 'DynamicBoolean' } }, required: ['label', 'value'] },
  ChoicePicker: {
    props: {
      ...CHECKABLE,
      label: { kind: 'DynamicString' },
      variant: { kind: 'string', enum: ['multipleSelection', 'mutuallyExclusive'], default: 'mutuallyExclusive' },
      options: { kind: 'OptionList' },
      value: { kind: 'DynamicStringList' },
      displayStyle: { kind: 'string', enum: ['checkbox', 'chips'], default: 'checkbox' },
      filterable: { kind: 'boolean', default: false },
    },
    required: ['options', 'value'],
  },
  Slider: {
    props: { ...CHECKABLE, label: { kind: 'DynamicString' }, min: { kind: 'number', default: 0 }, max: { kind: 'number' }, value: { kind: 'DynamicNumber' } },
    required: ['value', 'max'],
  },
  DateTimeInput: {
    props: {
      ...CHECKABLE,
      value: { kind: 'DynamicString' },
      enableDate: { kind: 'boolean', default: false },
      enableTime: { kind: 'boolean', default: false },
      min: { kind: 'DynamicString' },
      max: { kind: 'DynamicString' },
      label: { kind: 'DynamicString' },
    },
    required: ['value'],
  },
};

export const BASIC_FUNCTION_SPECS: Record<string, FunctionSpec> = {
  required: { args: { value: 'any' }, required: ['value'], returnType: 'boolean' },
  regex: { args: { value: 'DynamicString', pattern: 'string' }, required: ['value', 'pattern'], returnType: 'boolean' },
  length: { args: { value: 'DynamicString', min: 'number', max: 'number' }, required: ['value'], anyOf: [['min'], ['max']], returnType: 'boolean' },
  numeric: { args: { value: 'DynamicNumber', min: 'number', max: 'number' }, required: ['value'], anyOf: [['min'], ['max']], returnType: 'boolean' },
  email: { args: { value: 'DynamicString' }, required: ['value'], returnType: 'boolean' },
  formatString: { args: { value: 'DynamicString' }, required: ['value'], returnType: 'string' },
  formatNumber: { args: { value: 'DynamicNumber', decimals: 'DynamicNumber', grouping: 'DynamicBoolean' }, required: ['value'], returnType: 'string' },
  formatCurrency: {
    args: { value: 'DynamicNumber', currency: 'DynamicString', decimals: 'DynamicNumber', grouping: 'DynamicBoolean' },
    required: ['currency', 'value'],
    returnType: 'string',
  },
  formatDate: { args: { value: 'DynamicValue', format: 'DynamicString' }, required: ['format', 'value'], returnType: 'string' },
  pluralize: {
    args: {
      value: 'DynamicNumber',
      zero: 'DynamicString',
      one: 'DynamicString',
      two: 'DynamicString',
      few: 'DynamicString',
      many: 'DynamicString',
      other: 'DynamicString',
    },
    required: ['value', 'other'],
    returnType: 'string',
  },
  openUrl: { args: { url: 'string' }, required: ['url'], returnType: 'void' },
  and: { args: { values: 'DynamicBooleanList' }, required: ['values'], returnType: 'boolean' },
  or: { args: { values: 'DynamicBooleanList' }, required: ['values'], returnType: 'boolean' },
  not: { args: { value: 'DynamicBoolean' }, required: ['value'], returnType: 'boolean' },
};

export const BASIC_CATALOG: A2UICatalog = {
  id: BASIC_CATALOG_ID,
  aliases: BASIC_CATALOG_ALIASES,
  components: BASIC_COMPONENTS,
  functions: BASIC_FUNCTION_SPECS,
  implementations: BASIC_FUNCTIONS,
};

/** Component properties that reference other components (validators walk these). */
export function childReferences(component: Record<string, any>, catalog: A2UICatalog): { prop: string; id: string; template: boolean }[] {
  const spec = catalog.components[String(component.component)];
  const out: { prop: string; id: string; template: boolean }[] = [];
  if (!spec) return out;
  for (const [prop, ps] of Object.entries(spec.props)) {
    const v = component[prop];
    if (v == null) continue;
    if (ps.kind === 'ComponentId' && typeof v === 'string') out.push({ prop, id: v, template: false });
    else if (ps.kind === 'ChildList') {
      if (Array.isArray(v)) v.forEach((id, i) => typeof id === 'string' && out.push({ prop: `${prop}/${i}`, id, template: false }));
      else if (v && typeof v === 'object' && typeof v.componentId === 'string') out.push({ prop: `${prop}/componentId`, id: v.componentId, template: true });
    } else if (ps.kind === 'TabList' && Array.isArray(v)) {
      v.forEach((t, i) => t && typeof t === 'object' && typeof t.child === 'string' && out.push({ prop: `${prop}/${i}/child`, id: t.child, template: false }));
    }
  }
  return out;
}
