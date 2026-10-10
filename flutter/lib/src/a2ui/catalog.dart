/// Catalogs as the renderer sees them: for each component its properties
/// (with the kind of value each accepts), required properties and enums; for
/// each function its arguments and return type. The basic catalog below is a
/// compact, hand-portable transcription of
/// `a2ui/spec/catalogs/basic/catalog.json` (a test checks the two agree) —
/// the same table the web, Android and iOS renderers carry.
library;

import 'functions.dart';

/// The `catalogId` inside the vendored basic catalog file.
const String basicCatalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

/// Other spellings of the basic catalog id accepted on `createSurface` — the
/// protocol document's examples use the v0_9_1 path.
const List<String> basicCatalogAliases = [
  'https://a2ui.org/specification/v0_9_1/catalogs/basic/catalog.json',
];

/// `DynamicString`, `DynamicNumber`, `DynamicBoolean`, `DynamicStringList`,
/// `DynamicValue`, `ComponentId`, `ChildList`, `Action`, `Checks`,
/// `Accessibility`, `IconName`, `TabList`, `OptionList`, `string`, `number`,
/// `boolean` (and, for function arguments, `any` / `DynamicBooleanList`).
typedef PropKind = String;

class PropSpec {
  const PropSpec(this.kind, {this.enumValues, this.defaultValue});
  final PropKind kind;
  final List<String>? enumValues;
  final Object? defaultValue;
}

class ComponentSpec {
  const ComponentSpec(this.props, this.required);
  final Map<String, PropSpec> props;
  final List<String> required;
}

class FunctionSpec {
  const FunctionSpec(this.args, this.required, this.returnType, {this.anyOf});
  final Map<String, PropKind> args;
  final List<String> required;

  /// At least one of these groups must be fully present (`length`/`numeric`: min or max).
  final List<List<String>>? anyOf;
  final String returnType;
}

class A2UICatalog {
  const A2UICatalog({
    required this.id,
    this.aliases = const [],
    required this.components,
    required this.functions,
    required this.implementations,
  });

  final String id;
  final List<String> aliases;
  final Map<String, ComponentSpec> components;
  final Map<String, FunctionSpec> functions;
  final Map<String, A2UIFunction> implementations;
}

/// Properties every component accepts.
const Map<String, PropSpec> commonProps = {
  'id': PropSpec('ComponentId'),
  'component': PropSpec('string'),
  'accessibility': PropSpec('Accessibility'),
  'weight': PropSpec('number'),
};

const List<String> iconNames = [
  'accountCircle', 'add', 'arrowBack', 'arrowForward', 'attachFile', //
  'calendarToday', 'call', 'camera', 'check', 'close', 'delete', 'download',
  'edit', 'event', 'error', 'fastForward', 'favorite', 'favoriteOff',
  'folder', 'help', 'home', 'info', 'locationOn', 'lock', 'lockOpen', 'mail',
  'menu', 'moreVert', 'moreHoriz', 'notificationsOff', 'notifications',
  'pause', 'payment', 'person', 'phone', 'photo', 'play', 'print', 'refresh',
  'rewind', 'search', 'send', 'settings', 'share', 'shoppingCart',
  'skipNext', 'skipPrevious', 'star', 'starHalf', 'starOff', 'stop',
  'upload', 'visibility', 'visibilityOff', 'volumeDown', 'volumeMute',
  'volumeOff', 'volumeUp', 'warning',
];

const List<String> _justify = [
  'start', 'center', 'end', 'spaceBetween', 'spaceAround', 'spaceEvenly', //
  'stretch',
];
const List<String> _align = ['start', 'center', 'end', 'stretch'];
const PropSpec _checks = PropSpec('Checks');

const Map<String, ComponentSpec> basicComponents = {
  'Text': ComponentSpec({
    'text': PropSpec('DynamicString'),
    'variant': PropSpec('string',
        enumValues: ['h1', 'h2', 'h3', 'h4', 'h5', 'caption', 'body'],
        defaultValue: 'body'),
  }, [
    'text'
  ]),
  'Image': ComponentSpec({
    'url': PropSpec('DynamicString'),
    'description': PropSpec('DynamicString'),
    'fit': PropSpec('string',
        enumValues: ['contain', 'cover', 'fill', 'none', 'scaleDown'],
        defaultValue: 'fill'),
    'variant': PropSpec('string',
        enumValues: [
          'icon', 'avatar', 'smallFeature', 'mediumFeature', 'largeFeature', //
          'header',
        ],
        defaultValue: 'mediumFeature'),
  }, [
    'url'
  ]),
  'Icon': ComponentSpec({'name': PropSpec('IconName')}, ['name']),
  'Video': ComponentSpec({'url': PropSpec('DynamicString')}, ['url']),
  'AudioPlayer': ComponentSpec({
    'url': PropSpec('DynamicString'),
    'description': PropSpec('DynamicString'),
  }, [
    'url'
  ]),
  'Row': ComponentSpec({
    'children': PropSpec('ChildList'),
    'justify': PropSpec('string', enumValues: _justify, defaultValue: 'start'),
    'align': PropSpec('string', enumValues: _align, defaultValue: 'stretch'),
  }, [
    'children'
  ]),
  'Column': ComponentSpec({
    'children': PropSpec('ChildList'),
    'justify': PropSpec('string', enumValues: _justify, defaultValue: 'start'),
    'align': PropSpec('string', enumValues: _align, defaultValue: 'stretch'),
  }, [
    'children'
  ]),
  'List': ComponentSpec({
    'children': PropSpec('ChildList'),
    'direction': PropSpec('string',
        enumValues: ['vertical', 'horizontal'], defaultValue: 'vertical'),
    'align': PropSpec('string', enumValues: _align, defaultValue: 'stretch'),
  }, [
    'children'
  ]),
  'Card': ComponentSpec({'child': PropSpec('ComponentId')}, ['child']),
  'Tabs': ComponentSpec({'tabs': PropSpec('TabList')}, ['tabs']),
  'Modal': ComponentSpec({
    'trigger': PropSpec('ComponentId'),
    'content': PropSpec('ComponentId'),
  }, [
    'trigger',
    'content'
  ]),
  'Divider': ComponentSpec({
    'axis': PropSpec('string',
        enumValues: ['horizontal', 'vertical'], defaultValue: 'horizontal'),
  }, []),
  'Button': ComponentSpec({
    'checks': _checks,
    'child': PropSpec('ComponentId'),
    'variant': PropSpec('string',
        enumValues: ['default', 'primary', 'borderless'],
        defaultValue: 'default'),
    'action': PropSpec('Action'),
  }, [
    'child',
    'action'
  ]),
  'TextField': ComponentSpec({
    'checks': _checks,
    'label': PropSpec('DynamicString'),
    'value': PropSpec('DynamicString'),
    'variant': PropSpec('string',
        enumValues: ['longText', 'number', 'shortText', 'obscured'],
        defaultValue: 'shortText'),
    'validationRegexp': PropSpec('string'),
  }, [
    'label'
  ]),
  'CheckBox': ComponentSpec({
    'checks': _checks,
    'label': PropSpec('DynamicString'),
    'value': PropSpec('DynamicBoolean'),
  }, [
    'label',
    'value'
  ]),
  'ChoicePicker': ComponentSpec({
    'checks': _checks,
    'label': PropSpec('DynamicString'),
    'variant': PropSpec('string',
        enumValues: ['multipleSelection', 'mutuallyExclusive'],
        defaultValue: 'mutuallyExclusive'),
    'options': PropSpec('OptionList'),
    'value': PropSpec('DynamicStringList'),
    'displayStyle': PropSpec('string',
        enumValues: ['checkbox', 'chips'], defaultValue: 'checkbox'),
    'filterable': PropSpec('boolean', defaultValue: false),
  }, [
    'options',
    'value'
  ]),
  'Slider': ComponentSpec({
    'checks': _checks,
    'label': PropSpec('DynamicString'),
    'min': PropSpec('number', defaultValue: 0),
    'max': PropSpec('number'),
    'value': PropSpec('DynamicNumber'),
  }, [
    'value',
    'max'
  ]),
  'DateTimeInput': ComponentSpec({
    'checks': _checks,
    'value': PropSpec('DynamicString'),
    'enableDate': PropSpec('boolean', defaultValue: false),
    'enableTime': PropSpec('boolean', defaultValue: false),
    'min': PropSpec('DynamicString'),
    'max': PropSpec('DynamicString'),
    'label': PropSpec('DynamicString'),
  }, [
    'value'
  ]),
};

const Map<String, FunctionSpec> basicFunctionSpecs = {
  'required': FunctionSpec({'value': 'any'}, ['value'], 'boolean'),
  'regex': FunctionSpec({'value': 'DynamicString', 'pattern': 'string'},
      ['value', 'pattern'], 'boolean'),
  'length': FunctionSpec(
      {'value': 'DynamicString', 'min': 'number', 'max': 'number'},
      ['value'],
      'boolean',
      anyOf: [
        ['min'],
        ['max']
      ]),
  'numeric': FunctionSpec(
      {'value': 'DynamicNumber', 'min': 'number', 'max': 'number'},
      ['value'],
      'boolean',
      anyOf: [
        ['min'],
        ['max']
      ]),
  'email': FunctionSpec({'value': 'DynamicString'}, ['value'], 'boolean'),
  'formatString': FunctionSpec({'value': 'DynamicString'}, ['value'], 'string'),
  'formatNumber': FunctionSpec({
    'value': 'DynamicNumber',
    'decimals': 'DynamicNumber',
    'grouping': 'DynamicBoolean',
  }, [
    'value'
  ], 'string'),
  'formatCurrency': FunctionSpec({
    'value': 'DynamicNumber',
    'currency': 'DynamicString',
    'decimals': 'DynamicNumber',
    'grouping': 'DynamicBoolean',
  }, [
    'currency',
    'value'
  ], 'string'),
  'formatDate': FunctionSpec(
      {'value': 'DynamicValue', 'format': 'DynamicString'},
      ['format', 'value'],
      'string'),
  'pluralize': FunctionSpec({
    'value': 'DynamicNumber',
    'zero': 'DynamicString',
    'one': 'DynamicString',
    'two': 'DynamicString',
    'few': 'DynamicString',
    'many': 'DynamicString',
    'other': 'DynamicString',
  }, [
    'value',
    'other'
  ], 'string'),
  'openUrl': FunctionSpec({'url': 'string'}, ['url'], 'void'),
  'and': FunctionSpec({'values': 'DynamicBooleanList'}, ['values'], 'boolean'),
  'or': FunctionSpec({'values': 'DynamicBooleanList'}, ['values'], 'boolean'),
  'not': FunctionSpec({'value': 'DynamicBoolean'}, ['value'], 'boolean'),
};

final A2UICatalog basicCatalog = A2UICatalog(
  id: basicCatalogId,
  aliases: basicCatalogAliases,
  components: basicComponents,
  functions: basicFunctionSpecs,
  implementations: basicFunctions,
);

/// One component-to-component reference (validators walk these).
class ChildReference {
  const ChildReference(this.prop, this.id, this.template);
  final String prop;
  final String id;
  final bool template;
}

/// Component properties that reference other components.
List<ChildReference> childReferences(
    Map<String, dynamic> component, A2UICatalog catalog) {
  final spec = catalog.components[component['component']?.toString()];
  final out = <ChildReference>[];
  if (spec == null) return out;
  spec.props.forEach((prop, ps) {
    final v = component[prop];
    if (v == null) return;
    if (ps.kind == 'ComponentId' && v is String) {
      out.add(ChildReference(prop, v, false));
    } else if (ps.kind == 'ChildList') {
      if (v is List) {
        for (var i = 0; i < v.length; i++) {
          if (v[i] is String) out.add(ChildReference('$prop/$i', v[i], false));
        }
      } else if (v is Map && v['componentId'] is String) {
        out.add(ChildReference('$prop/componentId', v['componentId'], true));
      }
    } else if (ps.kind == 'TabList' && v is List) {
      for (var i = 0; i < v.length; i++) {
        final t = v[i];
        if (t is Map && t['child'] is String) {
          out.add(ChildReference('$prop/$i/child', t['child'], false));
        }
      }
    }
  });
  return out;
}
