# Elpian 2D Graphics Reference (Complete Schema + Examples)

This reference is generated from the current engine registry and model classes. It covers:

- Full JSON node schema.
- All registered Flutter widget types.
- All registered HTML element types.
- Full CSS style field schema.
- Example snippets for every item.

## 1) Universal Node Schema

| Field | Type | Required | Description | Example |
|---|---|---|---|---|
| `type` | `String` | Yes | Widget or HTML tag registered in engine. | `"Container"` |
| `key` | `String?` | No | Stable unique node id; required for robust event routing and tree updates. | `"header-title"` |
| `props` | `Map<String,dynamic>` | No | Type-specific API props + optional `style`. | `{ "text": "Hello" }` |
| `props.style` | `Map<String,dynamic>` | No | CSS-like style map parsed to `CSSStyle`. | `{ "padding": "12 16" }` |
| `events` | `Map<String,String>` | No | Map of event name to VM function name. | `{ "click": "onSave" }` |
| `children` | `List<Node>` | No | Child nodes. | `[ {"type":"Text","props":{"text":"Child"}} ]` |

### Event keys supported by the engine

`click`, `doubleClick`, `longPress`, `tap`, `tapDown`, `tapUp`, `tapCancel`, `pointerDown`, `pointerUp`, `pointerMove`, `pointerEnter`, `pointerExit`, `pointerHover`, `pointerCancel`, `dragStart`, `drag`, `dragEnd`, `dragEnter`, `dragLeave`, `dragOver`, `drop`, `focus`, `blur`, `focusIn`, `focusOut`, `input`, `change`, `submit`, `keyDown`, `keyUp`, `keyPress`, `scroll`, `reset`, `select`, `resize`, `load`, `unload`, `touchStart`, `touchMove`, `touchEnd`, `touchCancel`, `swipeLeft`, `swipeRight`, `swipeUp`, `swipeDown`, `pinchStart`, `pinchUpdate`, `pinchEnd`, `scaleStart`, `scaleUpdate`, `scaleEnd`, `rotateStart`, `rotateUpdate`, `rotateEnd`, `custom`


## 2) Flutter Widget Type Schemas

### `Container`

- Builder: `ElpianContainer.build`
- Source: `lib/src/widgets/elpian_container.dart`
- Widget-specific props used in implementation: `alignment`, `decoration`, `height`, `margin`, `padding`, `width`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Container`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.alignment` | `dynamic` | No | Parsed by widget implementation. |
| `props.decoration` | `dynamic` | No | Parsed by widget implementation. |
| `props.height` | `dynamic` | No | Parsed by widget implementation. |
| `props.margin` | `dynamic` | No | Parsed by widget implementation. |
| `props.padding` | `dynamic` | No | Parsed by widget implementation. |
| `props.width` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Container",
  "key": "container-1",
  "props": {
    "alignment": "<value>",
    "decoration": "<value>",
    "height": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": [
    {
      "type": "Text",
      "props": {
        "text": "Child"
      }
    }
  ]
}
```

### `Text`

- Builder: `ElpianText.build`
- Source: `lib/src/widgets/elpian_text.dart`
- Widget-specific props used in implementation: `data`, `maxLines`, `overflow`, `softWrap`, `style`, `text`, `textAlign`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Text`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.data` | `dynamic` | No | Parsed by widget implementation. |
| `props.maxLines` | `dynamic` | No | Parsed by widget implementation. |
| `props.overflow` | `dynamic` | No | Parsed by widget implementation. |
| `props.softWrap` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `dynamic` | No | Parsed by widget implementation. |
| `props.text` | `dynamic` | No | Parsed by widget implementation. |
| `props.textAlign` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Text",
  "key": "text-1",
  "props": {
    "data": "<value>",
    "maxLines": "<value>",
    "overflow": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Button`

- Builder: `ElpianButton.build`
- Source: `lib/src/widgets/elpian_button.dart`
- Widget-specific props used in implementation: `text`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Button`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.text` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Button",
  "key": "button-1",
  "props": {
    "text": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": [],
  "events": {
    "click": "onClick"
  }
}
```

### `Image`

- Builder: `ElpianImage.build`
- Source: `lib/src/widgets/elpian_image.dart`
- Widget-specific props used in implementation: `fit`, `src`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Image`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.fit` | `dynamic` | No | Parsed by widget implementation. |
| `props.src` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Image",
  "key": "image-1",
  "props": {
    "fit": "<value>",
    "src": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Column`

- Builder: `ElpianColumn.build`
- Source: `lib/src/widgets/elpian_column.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Column`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Column",
  "key": "column-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": [
    {
      "type": "Text",
      "props": {
        "text": "Child"
      }
    }
  ]
}
```

### `Row`

- Builder: `ElpianRow.build`
- Source: `lib/src/widgets/elpian_row.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Row`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Row",
  "key": "row-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": [
    {
      "type": "Text",
      "props": {
        "text": "Child"
      }
    }
  ]
}
```

### `Stack`

- Builder: `ElpianStack.build`
- Source: `lib/src/widgets/elpian_stack.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Stack`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Stack",
  "key": "stack-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": [
    {
      "type": "Text",
      "props": {
        "text": "Child"
      }
    }
  ]
}
```

### `Positioned`

- Builder: `ElpianPositioned.build`
- Source: `lib/src/widgets/elpian_positioned.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Positioned`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Positioned",
  "key": "positioned-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Expanded`

- Builder: `ElpianExpanded.build`
- Source: `lib/src/widgets/elpian_expanded.dart`
- Widget-specific props used in implementation: `flex`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Expanded`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.flex` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Expanded",
  "key": "expanded-1",
  "props": {
    "flex": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Flexible`

- Builder: `ElpianFlexible.build`
- Source: `lib/src/widgets/elpian_flexible.dart`
- Widget-specific props used in implementation: `flex`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Flexible`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.flex` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Flexible",
  "key": "flexible-1",
  "props": {
    "flex": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Center`

- Builder: `ElpianCenter.build`
- Source: `lib/src/widgets/elpian_center.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Center`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Center",
  "key": "center-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Padding`

- Builder: `ElpianPadding.build`
- Source: `lib/src/widgets/elpian_padding.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Padding`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Padding",
  "key": "padding-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Align`

- Builder: `ElpianAlign.build`
- Source: `lib/src/widgets/elpian_align.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Align`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Align",
  "key": "align-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `SizedBox`

- Builder: `ElpianSizedBox.build`
- Source: `lib/src/widgets/elpian_sized_box.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `SizedBox`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "SizedBox",
  "key": "sizedbox-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `ListView`

- Builder: `ElpianListView.build`
- Source: `lib/src/widgets/elpian_list_view.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `ListView`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "ListView",
  "key": "listview-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": [
    {
      "type": "Text",
      "props": {
        "text": "Child"
      }
    }
  ]
}
```

### `GridView`

- Builder: `ElpianGridView.build`
- Source: `lib/src/widgets/elpian_grid_view.dart`
- Widget-specific props used in implementation: `crossAxisCount`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `GridView`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.crossAxisCount` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "GridView",
  "key": "gridview-1",
  "props": {
    "crossAxisCount": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": [
    {
      "type": "Text",
      "props": {
        "text": "Child"
      }
    }
  ]
}
```

### `TextField`

- Builder: `ElpianTextField.build`
- Source: `lib/src/widgets/elpian_text_field.dart`
- Widget-specific props used in implementation: `hint`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `TextField`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.hint` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "TextField",
  "key": "textfield-1",
  "props": {
    "hint": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": [],
  "events": {
    "change": "onChange"
  }
}
```

### `Checkbox`

- Builder: `ElpianCheckbox.build`
- Source: `lib/src/widgets/elpian_checkbox.dart`
- Widget-specific props used in implementation: `value`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Checkbox`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.value` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Checkbox",
  "key": "checkbox-1",
  "props": {
    "value": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": [],
  "events": {
    "change": "onChange"
  }
}
```

### `Radio`

- Builder: `ElpianRadio.build`
- Source: `lib/src/widgets/elpian_radio.dart`
- Widget-specific props used in implementation: `groupValue`, `value`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Radio`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.groupValue` | `dynamic` | No | Parsed by widget implementation. |
| `props.value` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Radio",
  "key": "radio-1",
  "props": {
    "groupValue": "<value>",
    "value": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": [],
  "events": {
    "change": "onChange"
  }
}
```

### `Switch`

- Builder: `ElpianSwitch.build`
- Source: `lib/src/widgets/elpian_switch.dart`
- Widget-specific props used in implementation: `value`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Switch`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.value` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Switch",
  "key": "switch-1",
  "props": {
    "value": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": [],
  "events": {
    "change": "onChange"
  }
}
```

### `Slider`

- Builder: `ElpianSlider.build`
- Source: `lib/src/widgets/elpian_slider.dart`
- Widget-specific props used in implementation: `max`, `min`, `value`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Slider`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.max` | `dynamic` | No | Parsed by widget implementation. |
| `props.min` | `dynamic` | No | Parsed by widget implementation. |
| `props.value` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Slider",
  "key": "slider-1",
  "props": {
    "max": "<value>",
    "min": "<value>",
    "value": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": [],
  "events": {
    "change": "onChange"
  }
}
```

### `Icon`

- Builder: `ElpianIcon.build`
- Source: `lib/src/widgets/elpian_icon.dart`
- Widget-specific props used in implementation: `icon`, `size`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Icon`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.icon` | `dynamic` | No | Parsed by widget implementation. |
| `props.size` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Icon",
  "key": "icon-1",
  "props": {
    "icon": "<value>",
    "size": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Card`

- Builder: `ElpianCard.build`
- Source: `lib/src/widgets/elpian_card.dart`
- Widget-specific props used in implementation: `elevation`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Card`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.elevation` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Card",
  "key": "card-1",
  "props": {
    "elevation": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": [
    {
      "type": "Text",
      "props": {
        "text": "Child"
      }
    }
  ]
}
```

### `Scaffold`

- Builder: `ElpianScaffold.build`
- Source: `lib/src/widgets/elpian_scaffold.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Scaffold`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Scaffold",
  "key": "scaffold-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": [
    {
      "type": "Text",
      "props": {
        "text": "Child"
      }
    }
  ]
}
```

### `AppBar`

- Builder: `ElpianAppBar.build`
- Source: `lib/src/widgets/elpian_app_bar.dart`
- Widget-specific props used in implementation: `title`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AppBar`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.title` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AppBar",
  "key": "appbar-1",
  "props": {
    "title": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Canvas`

- Builder: `ElpianCanvasWidget.build`
- Source: `lib/src/widgets/elpian_canvas_widget.dart`
- Widget-specific props used in implementation: `backgroundColor`, `commands`, `height`, `width`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Canvas`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.backgroundColor` | `dynamic` | No | Parsed by widget implementation. |
| `props.commands` | `dynamic` | No | Parsed by widget implementation. |
| `props.height` | `dynamic` | No | Parsed by widget implementation. |
| `props.width` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Canvas",
  "key": "canvas-1",
  "props": {
    "backgroundColor": "<value>",
    "commands": "<value>",
    "height": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `BevyScene`

- Builder: `BevySceneWidget.build`
- Source: `lib/src/bevy/bevy_scene_widget.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `BevyScene`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "BevyScene",
  "key": "bevyscene-1",
  "props": {
    "sceneMap": {
      "world": []
    },
    "style": {
      "height": 300
    }
  },
  "children": []
}
```

### `Bevy3D`

- Builder: `BevySceneWidget.build`
- Source: `lib/src/bevy/bevy_scene_widget.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Bevy3D`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Bevy3D",
  "key": "bevy3d-1",
  "props": {
    "sceneMap": {
      "world": []
    },
    "style": {
      "height": 300
    }
  },
  "children": []
}
```

### `Scene3D`

- Builder: `BevySceneWidget.build`
- Source: `lib/src/bevy/bevy_scene_widget.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Scene3D`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Scene3D",
  "key": "scene3d-1",
  "props": {
    "sceneMap": {
      "world": []
    },
    "style": {
      "height": 300
    }
  },
  "children": []
}
```

### `GameScene`

- Builder: `GameSceneWidget.build`
- Source: `lib/src/scene3d/game_scene_widget.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `GameScene`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "GameScene",
  "key": "gamescene-1",
  "props": {
    "sceneMap": {
      "world": []
    },
    "style": {
      "height": 300
    }
  },
  "children": []
}
```

### `Game3D`

- Builder: `GameSceneWidget.build`
- Source: `lib/src/scene3d/game_scene_widget.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Game3D`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Game3D",
  "key": "game3d-1",
  "props": {
    "sceneMap": {
      "world": []
    },
    "style": {
      "height": 300
    }
  },
  "children": []
}
```

### `Wrap`

- Builder: `ElpianWrap.build`
- Source: `lib/src/widgets/elpian_wrap.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Wrap`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Wrap",
  "key": "wrap-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `InkWell`

- Builder: `ElpianInkWell.build`
- Source: `lib/src/widgets/elpian_inkwell.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `InkWell`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "InkWell",
  "key": "inkwell-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": [],
  "events": {
    "click": "onClick"
  }
}
```

### `GestureDetector`

- Builder: `ElpianGestureDetector.build`
- Source: `lib/src/widgets/elpian_gesture_detector.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `GestureDetector`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "GestureDetector",
  "key": "gesturedetector-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": [],
  "events": {
    "click": "onClick"
  }
}
```

### `Opacity`

- Builder: `ElpianOpacity.build`
- Source: `lib/src/widgets/elpian_opacity.dart`
- Widget-specific props used in implementation: `opacity`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Opacity`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.opacity` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Opacity",
  "key": "opacity-1",
  "props": {
    "opacity": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Transform`

- Builder: `ElpianTransform.build`
- Source: `lib/src/widgets/elpian_transform.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Transform`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Transform",
  "key": "transform-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `ClipRRect`

- Builder: `ElpianClipRRect.build`
- Source: `lib/src/widgets/elpian_clip_rrect.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `ClipRRect`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "ClipRRect",
  "key": "cliprrect-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `ConstrainedBox`

- Builder: `ElpianConstrainedBox.build`
- Source: `lib/src/widgets/elpian_constrained_box.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `ConstrainedBox`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "ConstrainedBox",
  "key": "constrainedbox-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AspectRatio`

- Builder: `ElpianAspectRatio.build`
- Source: `lib/src/widgets/elpian_aspect_ratio.dart`
- Widget-specific props used in implementation: `aspectRatio`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AspectRatio`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.aspectRatio` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AspectRatio",
  "key": "aspectratio-1",
  "props": {
    "aspectRatio": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `FractionallySizedBox`

- Builder: `ElpianFractionallySizedBox.build`
- Source: `lib/src/widgets/elpian_fractionally_sized_box.dart`
- Widget-specific props used in implementation: `heightFactor`, `widthFactor`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `FractionallySizedBox`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.heightFactor` | `dynamic` | No | Parsed by widget implementation. |
| `props.widthFactor` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "FractionallySizedBox",
  "key": "fractionallysizedbox-1",
  "props": {
    "heightFactor": "<value>",
    "widthFactor": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `FittedBox`

- Builder: `ElpianFittedBox.build`
- Source: `lib/src/widgets/elpian_fitted_box.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `FittedBox`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "FittedBox",
  "key": "fittedbox-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `LimitedBox`

- Builder: `ElpianLimitedBox.build`
- Source: `lib/src/widgets/elpian_limited_box.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `LimitedBox`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "LimitedBox",
  "key": "limitedbox-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `OverflowBox`

- Builder: `ElpianOverflowBox.build`
- Source: `lib/src/widgets/elpian_overflow_box.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `OverflowBox`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "OverflowBox",
  "key": "overflowbox-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Baseline`

- Builder: `ElpianBaseline.build`
- Source: `lib/src/widgets/elpian_baseline.dart`
- Widget-specific props used in implementation: `baseline`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Baseline`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.baseline` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Baseline",
  "key": "baseline-1",
  "props": {
    "baseline": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Spacer`

- Builder: `ElpianSpacer.build`
- Source: `lib/src/widgets/elpian_spacer.dart`
- Widget-specific props used in implementation: `flex`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Spacer`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.flex` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Spacer",
  "key": "spacer-1",
  "props": {
    "flex": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Divider`

- Builder: `ElpianDivider.build`
- Source: `lib/src/widgets/elpian_divider.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Divider`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Divider",
  "key": "divider-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `VerticalDivider`

- Builder: `ElpianVerticalDivider.build`
- Source: `lib/src/widgets/elpian_vertical_divider.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `VerticalDivider`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "VerticalDivider",
  "key": "verticaldivider-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `CircularProgressIndicator`

- Builder: `ElpianCircularProgressIndicator.build`
- Source: `lib/src/widgets/elpian_circular_progress_indicator.dart`
- Widget-specific props used in implementation: `value`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `CircularProgressIndicator`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.value` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "CircularProgressIndicator",
  "key": "circularprogressindicator-1",
  "props": {
    "value": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `LinearProgressIndicator`

- Builder: `ElpianLinearProgressIndicator.build`
- Source: `lib/src/widgets/elpian_linear_progress_indicator.dart`
- Widget-specific props used in implementation: `value`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `LinearProgressIndicator`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.value` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "LinearProgressIndicator",
  "key": "linearprogressindicator-1",
  "props": {
    "value": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Tooltip`

- Builder: `ElpianTooltip.build`
- Source: `lib/src/widgets/elpian_tooltip.dart`
- Widget-specific props used in implementation: `message`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Tooltip`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.message` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Tooltip",
  "key": "tooltip-1",
  "props": {
    "message": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Badge`

- Builder: `ElpianBadge.build`
- Source: `lib/src/widgets/elpian_badge.dart`
- Widget-specific props used in implementation: `label`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Badge`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.label` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Badge",
  "key": "badge-1",
  "props": {
    "label": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Chip`

- Builder: `ElpianChip.build`
- Source: `lib/src/widgets/elpian_chip.dart`
- Widget-specific props used in implementation: `label`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Chip`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.label` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Chip",
  "key": "chip-1",
  "props": {
    "label": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Dismissible`

- Builder: `ElpianDismissible.build`
- Source: `lib/src/widgets/elpian_dismissible.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Dismissible`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Dismissible",
  "key": "dismissible-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Draggable`

- Builder: `ElpianDraggable.build`
- Source: `lib/src/widgets/elpian_draggable.dart`
- Widget-specific props used in implementation: `data`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Draggable`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.data` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Draggable",
  "key": "draggable-1",
  "props": {
    "data": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `DragTarget`

- Builder: `ElpianDragTarget.build`
- Source: `lib/src/widgets/elpian_drag_target.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `DragTarget`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "DragTarget",
  "key": "dragtarget-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Hero`

- Builder: `ElpianHero.build`
- Source: `lib/src/widgets/elpian_hero.dart`
- Widget-specific props used in implementation: `tag`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Hero`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.tag` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Hero",
  "key": "hero-1",
  "props": {
    "tag": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `IndexedStack`

- Builder: `ElpianIndexedStack.build`
- Source: `lib/src/widgets/elpian_indexed_stack.dart`
- Widget-specific props used in implementation: `index`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `IndexedStack`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.index` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "IndexedStack",
  "key": "indexedstack-1",
  "props": {
    "index": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `RotatedBox`

- Builder: `ElpianRotatedBox.build`
- Source: `lib/src/widgets/elpian_rotated_box.dart`
- Widget-specific props used in implementation: `quarterTurns`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `RotatedBox`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.quarterTurns` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "RotatedBox",
  "key": "rotatedbox-1",
  "props": {
    "quarterTurns": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `DecoratedBox`

- Builder: `ElpianDecoratedBox.build`
- Source: `lib/src/widgets/elpian_decorated_box.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `DecoratedBox`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "DecoratedBox",
  "key": "decoratedbox-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedContainer`

- Builder: `ElpianAnimatedContainer.build`
- Source: `lib/src/widgets/elpian_animated_container.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedContainer`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedContainer",
  "key": "animatedcontainer-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedOpacity`

- Builder: `ElpianAnimatedOpacity.build`
- Source: `lib/src/widgets/elpian_animated_opacity.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedOpacity`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedOpacity",
  "key": "animatedopacity-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedCrossFade`

- Builder: `ElpianAnimatedCrossFade.build`
- Source: `lib/src/widgets/elpian_animated_cross_fade.dart`
- Widget-specific props used in implementation: `showFirst`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedCrossFade`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.showFirst` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedCrossFade",
  "key": "animatedcrossfade-1",
  "props": {
    "showFirst": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedSwitcher`

- Builder: `ElpianAnimatedSwitcher.build`
- Source: `lib/src/widgets/elpian_animated_switcher.dart`
- Widget-specific props used in implementation: `transitionType`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedSwitcher`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.transitionType` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedSwitcher",
  "key": "animatedswitcher-1",
  "props": {
    "transitionType": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedAlign`

- Builder: `ElpianAnimatedAlign.build`
- Source: `lib/src/widgets/elpian_animated_align.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedAlign`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedAlign",
  "key": "animatedalign-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedPadding`

- Builder: `ElpianAnimatedPadding.build`
- Source: `lib/src/widgets/elpian_animated_padding.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedPadding`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedPadding",
  "key": "animatedpadding-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedPositioned`

- Builder: `ElpianAnimatedPositioned.build`
- Source: `lib/src/widgets/elpian_animated_positioned.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedPositioned`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedPositioned",
  "key": "animatedpositioned-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedScale`

- Builder: `ElpianAnimatedScale.build`
- Source: `lib/src/widgets/elpian_animated_scale.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedScale`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedScale",
  "key": "animatedscale-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedRotation`

- Builder: `ElpianAnimatedRotation.build`
- Source: `lib/src/widgets/elpian_animated_rotation.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedRotation`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedRotation",
  "key": "animatedrotation-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedSlide`

- Builder: `ElpianAnimatedSlide.build`
- Source: `lib/src/widgets/elpian_animated_slide.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedSlide`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedSlide",
  "key": "animatedslide-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedSize`

- Builder: `ElpianAnimatedSize.build`
- Source: `lib/src/widgets/elpian_animated_size.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedSize`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedSize",
  "key": "animatedsize-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedDefaultTextStyle`

- Builder: `ElpianAnimatedDefaultTextStyle.build`
- Source: `lib/src/widgets/elpian_animated_default_text_style.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedDefaultTextStyle`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedDefaultTextStyle",
  "key": "animateddefaulttextstyle-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `FadeTransition`

- Builder: `ElpianFadeTransition.build`
- Source: `lib/src/widgets/elpian_fade_transition.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `FadeTransition`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "FadeTransition",
  "key": "fadetransition-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `SlideTransition`

- Builder: `ElpianSlideTransition.build`
- Source: `lib/src/widgets/elpian_slide_transition.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `SlideTransition`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "SlideTransition",
  "key": "slidetransition-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `ScaleTransition`

- Builder: `ElpianScaleTransition.build`
- Source: `lib/src/widgets/elpian_scale_transition.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `ScaleTransition`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "ScaleTransition",
  "key": "scaletransition-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `RotationTransition`

- Builder: `ElpianRotationTransition.build`
- Source: `lib/src/widgets/elpian_rotation_transition.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `RotationTransition`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "RotationTransition",
  "key": "rotationtransition-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `SizeTransition`

- Builder: `ElpianSizeTransition.build`
- Source: `lib/src/widgets/elpian_size_transition.dart`
- Widget-specific props used in implementation: `axis`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `SizeTransition`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.axis` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "SizeTransition",
  "key": "sizetransition-1",
  "props": {
    "axis": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `TweenAnimationBuilder`

- Builder: `ElpianTweenAnimationBuilder.build`
- Source: `lib/src/widgets/elpian_tween_animation_builder.dart`
- Widget-specific props used in implementation: `tweenType`
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `TweenAnimationBuilder`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props.tweenType` | `dynamic` | No | Parsed by widget implementation. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "TweenAnimationBuilder",
  "key": "tweenanimationbuilder-1",
  "props": {
    "tweenType": "<value>",
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `StaggeredAnimation`

- Builder: `ElpianStaggeredAnimation.build`
- Source: `lib/src/widgets/elpian_staggered_animation.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `StaggeredAnimation`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "StaggeredAnimation",
  "key": "staggeredanimation-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Shimmer`

- Builder: `ElpianShimmer.build`
- Source: `lib/src/widgets/elpian_shimmer.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Shimmer`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Shimmer",
  "key": "shimmer-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `Pulse`

- Builder: `ElpianPulse.build`
- Source: `lib/src/widgets/elpian_pulse.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `Pulse`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "Pulse",
  "key": "pulse-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```

### `AnimatedGradient`

- Builder: `ElpianAnimatedGradient.build`
- Source: `lib/src/widgets/elpian_animated_gradient.dart`
- Widget-specific props used in implementation: none (uses generic children/style behavior).
- Standard fields: `type`, `key`, `props`, `props.style`, `events`, `children`.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be exactly `AnimatedGradient`. |
| `key` | `String?` | No | Strongly recommended for event targeting. |
| `props` | `Map<String,dynamic>?` | No | Optional; may include style. |
| `props.style` | `Map<String,dynamic>?` | No | Any CSS properties from section 4. |
| `events` | `Map<String,String>?` | No | Event key -> VM function name. |
| `children` | `List<Node>?` | No | Child nodes, if the widget accepts children. |

Example:

```json
{
  "type": "AnimatedGradient",
  "key": "animatedgradient-1",
  "props": {
    "style": {
      "padding": "8 12"
    }
  },
  "children": []
}
```


## 3) HTML Element Type Schemas

### `div`

- Builder: `HtmlDiv.build`
- Source: `lib/src/html_widgets/html_div.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `div`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "div",
  "key": "div-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `span`

- Builder: `HtmlSpan.build`
- Source: `lib/src/html_widgets/html_span.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `span`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `span` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "span",
  "key": "span-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `h1`

- Builder: `HtmlH1.build`
- Source: `lib/src/html_widgets/html_h1.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `h1`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `h1` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "h1",
  "key": "h1-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `h2`

- Builder: `HtmlH2.build`
- Source: `lib/src/html_widgets/html_h2.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `h2`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `h2` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "h2",
  "key": "h2-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `h3`

- Builder: `HtmlH3.build`
- Source: `lib/src/html_widgets/html_h3.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `h3`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `h3` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "h3",
  "key": "h3-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `h4`

- Builder: `HtmlH4.build`
- Source: `lib/src/html_widgets/html_h4.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `h4`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `h4` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "h4",
  "key": "h4-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `h5`

- Builder: `HtmlH5.build`
- Source: `lib/src/html_widgets/html_h5.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `h5`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `h5` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "h5",
  "key": "h5-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `h6`

- Builder: `HtmlH6.build`
- Source: `lib/src/html_widgets/html_h6.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `h6`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `h6` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "h6",
  "key": "h6-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `p`

- Builder: `HtmlP.build`
- Source: `lib/src/html_widgets/html_p.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `p`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `p` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "p",
  "key": "p-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `a`

- Builder: `HtmlA.build`
- Source: `lib/src/html_widgets/html_a.dart`
- Element-specific props used in implementation: `href`, `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `a`. |
| `key` | `String?` | No | Optional id. |
| `props.href` | `dynamic` | No | Used by `a` element builder. |
| `props.text` | `dynamic` | No | Used by `a` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "a",
  "key": "a-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Link",
    "href": "https://example.com"
  },
  "children": [],
  "events": {
    "click": "onOpenLink"
  }
}
```

### `button`

- Builder: `HtmlButton.build`
- Source: `lib/src/html_widgets/html_button.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `button`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `button` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "button",
  "key": "button-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Submit"
  },
  "children": [],
  "events": {
    "click": "onSubmit"
  }
}
```

### `input`

- Builder: `HtmlInput.build`
- Source: `lib/src/html_widgets/html_input.dart`
- Element-specific props used in implementation: `placeholder`, `type`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `input`. |
| `key` | `String?` | No | Optional id. |
| `props.placeholder` | `dynamic` | No | Used by `input` element builder. |
| `props.type` | `dynamic` | No | Used by `input` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "input",
  "key": "input-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "type": "text",
    "placeholder": "Type here"
  },
  "children": [],
  "events": {
    "input": "onInput"
  }
}
```

### `img`

- Builder: `HtmlImg.build`
- Source: `lib/src/html_widgets/html_img.dart`
- Element-specific props used in implementation: `alt`, `src`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `img`. |
| `key` | `String?` | No | Optional id. |
| `props.alt` | `dynamic` | No | Used by `img` element builder. |
| `props.src` | `dynamic` | No | Used by `img` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "img",
  "key": "img-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "src": "assets/image.png",
    "alt": "image"
  },
  "children": []
}
```

### `ul`

- Builder: `HtmlUl.build`
- Source: `lib/src/html_widgets/html_ul.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `ul`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "ul",
  "key": "ul-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": [
    {
      "type": "li",
      "props": {
        "text": "Item 1"
      }
    },
    {
      "type": "li",
      "props": {
        "text": "Item 2"
      }
    }
  ]
}
```

### `ol`

- Builder: `HtmlOl.build`
- Source: `lib/src/html_widgets/html_ol.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `ol`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "ol",
  "key": "ol-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": [
    {
      "type": "li",
      "props": {
        "text": "Item 1"
      }
    },
    {
      "type": "li",
      "props": {
        "text": "Item 2"
      }
    }
  ]
}
```

### `li`

- Builder: `HtmlLi.build`
- Source: `lib/src/html_widgets/html_li.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `li`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `li` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "li",
  "key": "li-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `table`

- Builder: `HtmlTable.build`
- Source: `lib/src/html_widgets/html_table.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `table`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "table",
  "key": "table-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `tr`

- Builder: `HtmlTr.build`
- Source: `lib/src/html_widgets/html_tr.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `tr`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "tr",
  "key": "tr-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `td`

- Builder: `HtmlTd.build`
- Source: `lib/src/html_widgets/html_td.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `td`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `td` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "td",
  "key": "td-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `th`

- Builder: `HtmlTh.build`
- Source: `lib/src/html_widgets/html_th.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `th`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `th` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "th",
  "key": "th-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `form`

- Builder: `HtmlForm.build`
- Source: `lib/src/html_widgets/html_form.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `form`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "form",
  "key": "form-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `label`

- Builder: `HtmlLabel.build`
- Source: `lib/src/html_widgets/html_label.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `label`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `label` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "label",
  "key": "label-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `select`

- Builder: `HtmlSelect.build`
- Source: `lib/src/html_widgets/html_select.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `select`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "select",
  "key": "select-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `option`

- Builder: `HtmlOption.build`
- Source: `lib/src/html_widgets/html_option.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `option`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `option` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "option",
  "key": "option-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `textarea`

- Builder: `HtmlTextarea.build`
- Source: `lib/src/html_widgets/html_textarea.dart`
- Element-specific props used in implementation: `placeholder`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `textarea`. |
| `key` | `String?` | No | Optional id. |
| `props.placeholder` | `dynamic` | No | Used by `textarea` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "textarea",
  "key": "textarea-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `section`

- Builder: `HtmlSection.build`
- Source: `lib/src/html_widgets/html_section.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `section`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "section",
  "key": "section-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `article`

- Builder: `HtmlArticle.build`
- Source: `lib/src/html_widgets/html_article.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `article`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "article",
  "key": "article-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `header`

- Builder: `HtmlHeader.build`
- Source: `lib/src/html_widgets/html_header.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `header`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "header",
  "key": "header-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `footer`

- Builder: `HtmlFooter.build`
- Source: `lib/src/html_widgets/html_footer.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `footer`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "footer",
  "key": "footer-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `nav`

- Builder: `HtmlNav.build`
- Source: `lib/src/html_widgets/html_nav.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `nav`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "nav",
  "key": "nav-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `aside`

- Builder: `HtmlAside.build`
- Source: `lib/src/html_widgets/html_aside.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `aside`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "aside",
  "key": "aside-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `main`

- Builder: `HtmlMain.build`
- Source: `lib/src/html_widgets/html_main.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `main`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "main",
  "key": "main-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `video`

- Builder: `HtmlVideo.build`
- Source: `lib/src/html_widgets/html_video.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `video`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "video",
  "key": "video-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `audio`

- Builder: `HtmlAudio.build`
- Source: `lib/src/html_widgets/html_audio.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `audio`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "audio",
  "key": "audio-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `canvas`

- Builder: `HtmlCanvas.build`
- Source: `lib/src/html_widgets/html_canvas.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `canvas`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "canvas",
  "key": "canvas-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `iframe`

- Builder: `HtmlIframe.build`
- Source: `lib/src/html_widgets/html_iframe.dart`
- Element-specific props used in implementation: `src`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `iframe`. |
| `key` | `String?` | No | Optional id. |
| `props.src` | `dynamic` | No | Used by `iframe` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "iframe",
  "key": "iframe-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `strong`

- Builder: `HtmlStrong.build`
- Source: `lib/src/html_widgets/html_strong.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `strong`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `strong` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "strong",
  "key": "strong-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `em`

- Builder: `HtmlEm.build`
- Source: `lib/src/html_widgets/html_em.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `em`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `em` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "em",
  "key": "em-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `code`

- Builder: `HtmlCode.build`
- Source: `lib/src/html_widgets/html_code.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `code`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `code` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "code",
  "key": "code-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `pre`

- Builder: `HtmlPre.build`
- Source: `lib/src/html_widgets/html_pre.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `pre`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `pre` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "pre",
  "key": "pre-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `blockquote`

- Builder: `HtmlBlockquote.build`
- Source: `lib/src/html_widgets/html_blockquote.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `blockquote`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `blockquote` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "blockquote",
  "key": "blockquote-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `hr`

- Builder: `HtmlHr.build`
- Source: `lib/src/html_widgets/html_hr.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `hr`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "hr",
  "key": "hr-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `br`

- Builder: `HtmlBr.build`
- Source: `lib/src/html_widgets/html_br.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `br`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "br",
  "key": "br-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `figure`

- Builder: `HtmlFigure.build`
- Source: `lib/src/html_widgets/html_figure.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `figure`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "figure",
  "key": "figure-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `figcaption`

- Builder: `HtmlFigcaption.build`
- Source: `lib/src/html_widgets/html_figcaption.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `figcaption`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `figcaption` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "figcaption",
  "key": "figcaption-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `mark`

- Builder: `HtmlMark.build`
- Source: `lib/src/html_widgets/html_mark.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `mark`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `mark` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "mark",
  "key": "mark-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `del`

- Builder: `HtmlDel.build`
- Source: `lib/src/html_widgets/html_del.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `del`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `del` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "del",
  "key": "del-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `ins`

- Builder: `HtmlIns.build`
- Source: `lib/src/html_widgets/html_ins.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `ins`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `ins` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "ins",
  "key": "ins-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `sub`

- Builder: `HtmlSub.build`
- Source: `lib/src/html_widgets/html_sub.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `sub`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `sub` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "sub",
  "key": "sub-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `sup`

- Builder: `HtmlSup.build`
- Source: `lib/src/html_widgets/html_sup.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `sup`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `sup` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "sup",
  "key": "sup-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `small`

- Builder: `HtmlSmall.build`
- Source: `lib/src/html_widgets/html_small.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `small`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `small` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "small",
  "key": "small-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `abbr`

- Builder: `HtmlAbbr.build`
- Source: `lib/src/html_widgets/html_abbr.dart`
- Element-specific props used in implementation: `text`, `title`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `abbr`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `abbr` element builder. |
| `props.title` | `dynamic` | No | Used by `abbr` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "abbr",
  "key": "abbr-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `cite`

- Builder: `HtmlCite.build`
- Source: `lib/src/html_widgets/html_cite.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `cite`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `cite` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "cite",
  "key": "cite-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `kbd`

- Builder: `HtmlKbd.build`
- Source: `lib/src/html_widgets/html_kbd.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `kbd`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `kbd` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "kbd",
  "key": "kbd-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `samp`

- Builder: `HtmlSamp.build`
- Source: `lib/src/html_widgets/html_samp.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `samp`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `samp` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "samp",
  "key": "samp-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `var`

- Builder: `HtmlVar.build`
- Source: `lib/src/html_widgets/html_var.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `var`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `var` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "var",
  "key": "var-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `details`

- Builder: `HtmlDetails.build`
- Source: `lib/src/html_widgets/html_details.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `details`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "details",
  "key": "details-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `summary`

- Builder: `HtmlSummary.build`
- Source: `lib/src/html_widgets/html_summary.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `summary`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `summary` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "summary",
  "key": "summary-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `dialog`

- Builder: `HtmlDialog.build`
- Source: `lib/src/html_widgets/html_dialog.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `dialog`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "dialog",
  "key": "dialog-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `progress`

- Builder: `HtmlProgress.build`
- Source: `lib/src/html_widgets/html_progress.dart`
- Element-specific props used in implementation: `max`, `value`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `progress`. |
| `key` | `String?` | No | Optional id. |
| `props.max` | `dynamic` | No | Used by `progress` element builder. |
| `props.value` | `dynamic` | No | Used by `progress` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "progress",
  "key": "progress-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `meter`

- Builder: `HtmlMeter.build`
- Source: `lib/src/html_widgets/html_meter.dart`
- Element-specific props used in implementation: `max`, `min`, `value`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `meter`. |
| `key` | `String?` | No | Optional id. |
| `props.max` | `dynamic` | No | Used by `meter` element builder. |
| `props.min` | `dynamic` | No | Used by `meter` element builder. |
| `props.value` | `dynamic` | No | Used by `meter` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "meter",
  "key": "meter-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `time`

- Builder: `HtmlTime.build`
- Source: `lib/src/html_widgets/html_time.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `time`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `time` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "time",
  "key": "time-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `data`

- Builder: `HtmlData.build`
- Source: `lib/src/html_widgets/html_data.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `data`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `data` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "data",
  "key": "data-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `output`

- Builder: `HtmlOutput.build`
- Source: `lib/src/html_widgets/html_output.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `output`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `output` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "output",
  "key": "output-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `fieldset`

- Builder: `HtmlFieldset.build`
- Source: `lib/src/html_widgets/html_fieldset.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `fieldset`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "fieldset",
  "key": "fieldset-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `legend`

- Builder: `HtmlLegend.build`
- Source: `lib/src/html_widgets/html_legend.dart`
- Element-specific props used in implementation: `text`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `legend`. |
| `key` | `String?` | No | Optional id. |
| `props.text` | `dynamic` | No | Used by `legend` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "legend",
  "key": "legend-1",
  "props": {
    "style": {
      "margin": "4 0"
    },
    "text": "Example text"
  },
  "children": []
}
```

### `datalist`

- Builder: `HtmlDatalist.build`
- Source: `lib/src/html_widgets/html_datalist.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `datalist`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "datalist",
  "key": "datalist-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `optgroup`

- Builder: `HtmlOptgroup.build`
- Source: `lib/src/html_widgets/html_optgroup.dart`
- Element-specific props used in implementation: `label`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `optgroup`. |
| `key` | `String?` | No | Optional id. |
| `props.label` | `dynamic` | No | Used by `optgroup` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "optgroup",
  "key": "optgroup-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `picture`

- Builder: `HtmlPicture.build`
- Source: `lib/src/html_widgets/html_picture.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `picture`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "picture",
  "key": "picture-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `source`

- Builder: `HtmlSource.build`
- Source: `lib/src/html_widgets/html_source.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `source`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "source",
  "key": "source-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `track`

- Builder: `HtmlTrack.build`
- Source: `lib/src/html_widgets/html_track.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `track`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "track",
  "key": "track-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `embed`

- Builder: `HtmlEmbed.build`
- Source: `lib/src/html_widgets/html_embed.dart`
- Element-specific props used in implementation: `src`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `embed`. |
| `key` | `String?` | No | Optional id. |
| `props.src` | `dynamic` | No | Used by `embed` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "embed",
  "key": "embed-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `object`

- Builder: `HtmlObject.build`
- Source: `lib/src/html_widgets/html_object.dart`
- Element-specific props used in implementation: `data`

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `object`. |
| `key` | `String?` | No | Optional id. |
| `props.data` | `dynamic` | No | Used by `object` element builder. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "object",
  "key": "object-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `param`

- Builder: `HtmlParam.build`
- Source: `lib/src/html_widgets/html_param.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `param`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "param",
  "key": "param-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `map`

- Builder: `HtmlMap.build`
- Source: `lib/src/html_widgets/html_map.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `map`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "map",
  "key": "map-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```

### `area`

- Builder: `HtmlArea.build`
- Source: `lib/src/html_widgets/html_area.dart`
- Element-specific props used in implementation: none discovered; generic style/children path.

| Prop | Type | Required | Notes |
|---|---|---|---|
| `type` | `String` | Yes | Must be `area`. |
| `key` | `String?` | No | Optional id. |
| `props` | `Map<String,dynamic>?` | No | Generic props map. |
| `props.style` | `Map<String,dynamic>?` | No | CSS style map. |
| `events` | `Map<String,String>?` | No | Event mapping to VM function names. |
| `children` | `List<Node>?` | No | Nested content. |

Example:
```json
{
  "type": "area",
  "key": "area-1",
  "props": {
    "style": {
      "margin": "4 0"
    }
  },
  "children": []
}
```


## 4) Complete CSS Property Schema

All properties are read from `CSSStyle` and parsed via `CSSParser`. Use in `props.style`.

| CSS Property | Dart Type | JSON keys accepted | Required | Example value | Description |
|---|---|---|---|---|---|
| `width` | `double?` | `width` | No | `1` | Controls `width` for style/layout/rendering/animation. |
| `height` | `double?` | `height` | No | `1` | Controls `height` for style/layout/rendering/animation. |
| `minWidth` | `double?` | `min-width` | No | `1` | Controls `minWidth` for style/layout/rendering/animation. |
| `maxWidth` | `double?` | `max-width` | No | `1` | Controls `maxWidth` for style/layout/rendering/animation. |
| `minHeight` | `double?` | `min-height` | No | `1` | Controls `minHeight` for style/layout/rendering/animation. |
| `maxHeight` | `double?` | `max-height` | No | `1` | Controls `maxHeight` for style/layout/rendering/animation. |
| `padding` | `EdgeInsets?` | `padding` | No | `"8 12"` | Controls `padding` for style/layout/rendering/animation. |
| `margin` | `EdgeInsets?` | `margin` | No | `"8 12"` | Controls `margin` for style/layout/rendering/animation. |
| `paddingTop` | `EdgeInsets?` | `paddingTop` | No | `"8 12"` | Controls `paddingTop` for style/layout/rendering/animation. |
| `paddingRight` | `EdgeInsets?` | `paddingRight` | No | `"8 12"` | Controls `paddingRight` for style/layout/rendering/animation. |
| `paddingBottom` | `EdgeInsets?` | `paddingBottom` | No | `"8 12"` | Controls `paddingBottom` for style/layout/rendering/animation. |
| `paddingLeft` | `EdgeInsets?` | `paddingLeft` | No | `"8 12"` | Controls `paddingLeft` for style/layout/rendering/animation. |
| `marginTop` | `EdgeInsets?` | `marginTop` | No | `"8 12"` | Controls `marginTop` for style/layout/rendering/animation. |
| `marginRight` | `EdgeInsets?` | `marginRight` | No | `"8 12"` | Controls `marginRight` for style/layout/rendering/animation. |
| `marginBottom` | `EdgeInsets?` | `marginBottom` | No | `"8 12"` | Controls `marginBottom` for style/layout/rendering/animation. |
| `marginLeft` | `EdgeInsets?` | `marginLeft` | No | `"8 12"` | Controls `marginLeft` for style/layout/rendering/animation. |
| `alignment` | `AlignmentGeometry?` | `alignment` | No | `"center"` | Controls `alignment` for style/layout/rendering/animation. |
| `position` | `String?` | `position` | No | `1` | Controls `position` for style/layout/rendering/animation. |
| `top` | `double?` | `top` | No | `1` | Controls `top` for style/layout/rendering/animation. |
| `right` | `double?` | `right` | No | `1` | Controls `right` for style/layout/rendering/animation. |
| `bottom` | `double?` | `bottom` | No | `1` | Controls `bottom` for style/layout/rendering/animation. |
| `left` | `double?` | `left` | No | `1` | Controls `left` for style/layout/rendering/animation. |
| `zIndex` | `double?` | `z-index` | No | `1` | Controls `zIndex` for style/layout/rendering/animation. |
| `display` | `String?` | `display` | No | `"flex"` | Controls `display` for style/layout/rendering/animation. |
| `flexDirection` | `String?` | `flex-direction` | No | `1` | Controls `flexDirection` for style/layout/rendering/animation. |
| `justifyContent` | `String?` | `justify-content` | No | `1` | Controls `justifyContent` for style/layout/rendering/animation. |
| `alignItems` | `String?` | `align-items` | No | `1` | Controls `alignItems` for style/layout/rendering/animation. |
| `alignContent` | `String?` | `alignContent` | No | `1` | Controls `alignContent` for style/layout/rendering/animation. |
| `alignSelf` | `String?` | `alignSelf` | No | `1` | Controls `alignSelf` for style/layout/rendering/animation. |
| `flex` | `int?` | `flex` | No | `1` | Controls `flex` for style/layout/rendering/animation. |
| `flexGrow` | `int?` | `flexGrow` | No | `1` | Controls `flexGrow` for style/layout/rendering/animation. |
| `flexShrink` | `int?` | `flexShrink` | No | `1` | Controls `flexShrink` for style/layout/rendering/animation. |
| `flexBasis` | `String?` | `flexBasis` | No | `1` | Controls `flexBasis` for style/layout/rendering/animation. |
| `overflow` | `Overflow?` | `overflow` | No | `"clip"` | Controls `overflow` for style/layout/rendering/animation. |
| `overflowX` | `Overflow?` | `overflowX` | No | `"clip"` | Controls `overflowX` for style/layout/rendering/animation. |
| `overflowY` | `Overflow?` | `overflowY` | No | `"clip"` | Controls `overflowY` for style/layout/rendering/animation. |
| `gridTemplateColumns` | `String?` | `gridTemplateColumns` | No | `1` | Controls `gridTemplateColumns` for style/layout/rendering/animation. |
| `gridTemplateRows` | `String?` | `gridTemplateRows` | No | `1` | Controls `gridTemplateRows` for style/layout/rendering/animation. |
| `gridTemplateAreas` | `String?` | `gridTemplateAreas` | No | `1` | Controls `gridTemplateAreas` for style/layout/rendering/animation. |
| `gridAutoColumns` | `String?` | `gridAutoColumns` | No | `1` | Controls `gridAutoColumns` for style/layout/rendering/animation. |
| `gridAutoRows` | `String?` | `gridAutoRows` | No | `1` | Controls `gridAutoRows` for style/layout/rendering/animation. |
| `gridAutoFlow` | `String?` | `gridAutoFlow` | No | `1` | Controls `gridAutoFlow` for style/layout/rendering/animation. |
| `gridColumnGap` | `double?` | `gridColumnGap` | No | `1` | Controls `gridColumnGap` for style/layout/rendering/animation. |
| `gridRowGap` | `double?` | `gridRowGap` | No | `1` | Controls `gridRowGap` for style/layout/rendering/animation. |
| `gridGap` | `double?` | `gridGap` | No | `1` | Controls `gridGap` for style/layout/rendering/animation. |
| `gridColumn` | `String?` | `gridColumn` | No | `1` | Controls `gridColumn` for style/layout/rendering/animation. |
| `gridRow` | `String?` | `gridRow` | No | `1` | Controls `gridRow` for style/layout/rendering/animation. |
| `gridArea` | `String?` | `gridArea` | No | `1` | Controls `gridArea` for style/layout/rendering/animation. |
| `justifyItems` | `String?` | `justifyItems` | No | `1` | Controls `justifyItems` for style/layout/rendering/animation. |
| `justifySelf` | `String?` | `justifySelf` | No | `1` | Controls `justifySelf` for style/layout/rendering/animation. |
| `backgroundColor` | `Color?` | `backgroundColor` | No | `"#3366FF"` | Controls `backgroundColor` for style/layout/rendering/animation. |
| `backgroundImage` | `String?` | `background-image, backgroundImage` | No | `"assets/bg.png"` | Controls `backgroundImage` for style/layout/rendering/animation. |
| `backgroundSize` | `BoxFit?` | `backgroundSize` | No | `1` | Controls `backgroundSize` for style/layout/rendering/animation. |
| `backgroundPosition` | `AlignmentGeometry?` | `backgroundPosition` | No | `1` | Controls `backgroundPosition` for style/layout/rendering/animation. |
| `backgroundRepeat` | `String?` | `backgroundRepeat` | No | `1` | Controls `backgroundRepeat` for style/layout/rendering/animation. |
| `backgroundAttachment` | `String?` | `backgroundAttachment` | No | `1` | Controls `backgroundAttachment` for style/layout/rendering/animation. |
| `backgroundClip` | `String?` | `backgroundClip` | No | `1` | Controls `backgroundClip` for style/layout/rendering/animation. |
| `backgroundOrigin` | `String?` | `backgroundOrigin` | No | `1` | Controls `backgroundOrigin` for style/layout/rendering/animation. |
| `gradient` | `Gradient?` | `gradient` | No | `1` | Controls `gradient` for style/layout/rendering/animation. |
| `gradientColors` | `List<Color>?` | `gradientColors` | No | `"#3366FF"` | Controls `gradientColors` for style/layout/rendering/animation. |
| `gradientStops` | `List<double>?` | `gradientStops` | No | `1` | Controls `gradientStops` for style/layout/rendering/animation. |
| `border` | `Border?` | `border` | No | `1` | Controls `border` for style/layout/rendering/animation. |
| `borderRadius` | `BorderRadius?` | `borderRadius` | No | `1` | Controls `borderRadius` for style/layout/rendering/animation. |
| `borderColor` | `Color?` | `border-color` | No | `"#3366FF"` | Controls `borderColor` for style/layout/rendering/animation. |
| `borderWidth` | `double?` | `border-width` | No | `1` | Controls `borderWidth` for style/layout/rendering/animation. |
| `borderStyle` | `String?` | `border-style` | No | `1` | Controls `borderStyle` for style/layout/rendering/animation. |
| `borderTop` | `BorderSide?` | `borderTop` | No | `1` | Controls `borderTop` for style/layout/rendering/animation. |
| `borderRight` | `BorderSide?` | `borderRight` | No | `1` | Controls `borderRight` for style/layout/rendering/animation. |
| `borderBottom` | `BorderSide?` | `borderBottom` | No | `1` | Controls `borderBottom` for style/layout/rendering/animation. |
| `borderLeft` | `BorderSide?` | `borderLeft` | No | `1` | Controls `borderLeft` for style/layout/rendering/animation. |
| `borderTopLeftRadius` | `double?` | `borderTopLeftRadius` | No | `1` | Controls `borderTopLeftRadius` for style/layout/rendering/animation. |
| `borderTopRightRadius` | `double?` | `borderTopRightRadius` | No | `1` | Controls `borderTopRightRadius` for style/layout/rendering/animation. |
| `borderBottomLeftRadius` | `double?` | `borderBottomLeftRadius` | No | `1` | Controls `borderBottomLeftRadius` for style/layout/rendering/animation. |
| `borderBottomRightRadius` | `double?` | `borderBottomRightRadius` | No | `1` | Controls `borderBottomRightRadius` for style/layout/rendering/animation. |
| `outlineColor` | `Color?` | `outlineColor` | No | `"#3366FF"` | Controls `outlineColor` for style/layout/rendering/animation. |
| `outlineWidth` | `double?` | `outlineWidth` | No | `1` | Controls `outlineWidth` for style/layout/rendering/animation. |
| `outlineStyle` | `String?` | `outlineStyle` | No | `1` | Controls `outlineStyle` for style/layout/rendering/animation. |
| `outlineOffset` | `double?` | `outlineOffset` | No | `1` | Controls `outlineOffset` for style/layout/rendering/animation. |
| `color` | `Color?` | `color` | No | `"#3366FF"` | Controls `color` for style/layout/rendering/animation. |
| `fontSize` | `double?` | `font-size` | No | `1` | Controls `fontSize` for style/layout/rendering/animation. |
| `fontWeight` | `FontWeight?` | `font-weight` | No | `1` | Controls `fontWeight` for style/layout/rendering/animation. |
| `fontStyle` | `FontStyle?` | `font-style` | No | `1` | Controls `fontStyle` for style/layout/rendering/animation. |
| `fontFamily` | `String?` | `font-family` | No | `1` | Controls `fontFamily` for style/layout/rendering/animation. |
| `letterSpacing` | `double?` | `letter-spacing` | No | `1` | Controls `letterSpacing` for style/layout/rendering/animation. |
| `wordSpacing` | `double?` | `word-spacing` | No | `1` | Controls `wordSpacing` for style/layout/rendering/animation. |
| `lineHeight` | `double?` | `line-height` | No | `1` | Controls `lineHeight` for style/layout/rendering/animation. |
| `textAlign` | `TextAlign?` | `text-align` | No | `"example"` | Controls `textAlign` for style/layout/rendering/animation. |
| `textDecoration` | `TextDecoration?` | `textDecoration` | No | `"example"` | Controls `textDecoration` for style/layout/rendering/animation. |
| `textDecorationColor` | `Color?` | `textDecorationColor` | No | `"#3366FF"` | Controls `textDecorationColor` for style/layout/rendering/animation. |
| `textDecorationStyle` | `TextDecorationStyle?` | `textDecorationStyle` | No | `"example"` | Controls `textDecorationStyle` for style/layout/rendering/animation. |
| `textDecorationThickness` | `double?` | `textDecorationThickness` | No | `"example"` | Controls `textDecorationThickness` for style/layout/rendering/animation. |
| `textOverflow` | `TextOverflow?` | `textOverflow` | No | `"clip"` | Controls `textOverflow` for style/layout/rendering/animation. |
| `textTransform` | `String?` | `text-transform` | No | `"rotate(10deg)"` | Controls `textTransform` for style/layout/rendering/animation. |
| `whiteSpace` | `String?` | `whiteSpace` | No | `1` | Controls `whiteSpace` for style/layout/rendering/animation. |
| `textBaseline` | `TextBaseline?` | `textBaseline` | No | `"example"` | Controls `textBaseline` for style/layout/rendering/animation. |
| `verticalAlign` | `String?` | `verticalAlign` | No | `1` | Controls `verticalAlign` for style/layout/rendering/animation. |
| `writingMode` | `String?` | `writingMode` | No | `1` | Controls `writingMode` for style/layout/rendering/animation. |
| `textOrientation` | `String?` | `textOrientation` | No | `"example"` | Controls `textOrientation` for style/layout/rendering/animation. |
| `boxShadow` | `List<BoxShadow>?` | `box-shadow` | No | `"0 2 8 rgba(0,0,0,0.2)"` | Controls `boxShadow` for style/layout/rendering/animation. |
| `textShadow` | `List<Shadow>?` | `text-shadow` | No | `"0 2 8 rgba(0,0,0,0.2)"` | Controls `textShadow` for style/layout/rendering/animation. |
| `dropShadow` | `Shadow?` | `dropShadow` | No | `"0 2 8 rgba(0,0,0,0.2)"` | Controls `dropShadow` for style/layout/rendering/animation. |
| `transform` | `Matrix4?` | `transform` | No | `"rotate(10deg)"` | Controls `transform` for style/layout/rendering/animation. |
| `rotate` | `double?` | `rotate` | No | `1` | Controls `rotate` for style/layout/rendering/animation. |
| `rotateX` | `double?` | `rotateX` | No | `1` | Controls `rotateX` for style/layout/rendering/animation. |
| `rotateY` | `double?` | `rotateY` | No | `1` | Controls `rotateY` for style/layout/rendering/animation. |
| `rotateZ` | `double?` | `rotateZ` | No | `1` | Controls `rotateZ` for style/layout/rendering/animation. |
| `scale` | `double?` | `scale` | No | `1` | Controls `scale` for style/layout/rendering/animation. |
| `scaleX` | `double?` | `scaleX` | No | `1` | Controls `scaleX` for style/layout/rendering/animation. |
| `scaleY` | `double?` | `scaleY` | No | `1` | Controls `scaleY` for style/layout/rendering/animation. |
| `translate` | `Offset?` | `translate` | No | `1` | Controls `translate` for style/layout/rendering/animation. |
| `translateX` | `double?` | `translateX` | No | `1` | Controls `translateX` for style/layout/rendering/animation. |
| `translateY` | `double?` | `translateY` | No | `1` | Controls `translateY` for style/layout/rendering/animation. |
| `skewX` | `double?` | `skewX` | No | `1` | Controls `skewX` for style/layout/rendering/animation. |
| `skewY` | `double?` | `skewY` | No | `1` | Controls `skewY` for style/layout/rendering/animation. |
| `transformOrigin` | `String?` | `transformOrigin` | No | `"rotate(10deg)"` | Controls `transformOrigin` for style/layout/rendering/animation. |
| `transformStyle` | `String?` | `transformStyle` | No | `"rotate(10deg)"` | Controls `transformStyle` for style/layout/rendering/animation. |
| `perspective` | `String?` | `perspective` | No | `1` | Controls `perspective` for style/layout/rendering/animation. |
| `perspectiveOrigin` | `String?` | `perspectiveOrigin` | No | `1` | Controls `perspectiveOrigin` for style/layout/rendering/animation. |
| `backfaceVisibility` | `String?` | `backfaceVisibility` | No | `1` | Controls `backfaceVisibility` for style/layout/rendering/animation. |
| `opacity` | `double?` | `opacity` | No | `1` | Controls `opacity` for style/layout/rendering/animation. |
| `visible` | `bool?` | `visible` | No | `true` | Controls `visible` for style/layout/rendering/animation. |
| `visibility` | `String?` | `visibility` | No | `1` | Controls `visibility` for style/layout/rendering/animation. |
| `cursor` | `String?` | `cursor` | No | `1` | Controls `cursor` for style/layout/rendering/animation. |
| `pointerEvents` | `String?` | `pointer-events` | No | `1` | Controls `pointerEvents` for style/layout/rendering/animation. |
| `userSelect` | `String?` | `userSelect` | No | `1` | Controls `userSelect` for style/layout/rendering/animation. |
| `touchAction` | `String?` | `touchAction` | No | `1` | Controls `touchAction` for style/layout/rendering/animation. |
| `gap` | `double?` | `gap` | No | `1` | Controls `gap` for style/layout/rendering/animation. |
| `rowGap` | `double?` | `rowGap` | No | `1` | Controls `rowGap` for style/layout/rendering/animation. |
| `columnGap` | `double?` | `columnGap` | No | `1` | Controls `columnGap` for style/layout/rendering/animation. |
| `flexWrap` | `String?` | `flex-wrap` | No | `1` | Controls `flexWrap` for style/layout/rendering/animation. |
| `order` | `int?` | `order` | No | `1` | Controls `order` for style/layout/rendering/animation. |
| `boxSizing` | `String?` | `boxSizing` | No | `1` | Controls `boxSizing` for style/layout/rendering/animation. |
| `objectFit` | `String?` | `objectFit` | No | `1` | Controls `objectFit` for style/layout/rendering/animation. |
| `objectPosition` | `String?` | `objectPosition` | No | `1` | Controls `objectPosition` for style/layout/rendering/animation. |
| `clipBehavior` | `Clip?` | `clipBehavior` | No | `1` | Controls `clipBehavior` for style/layout/rendering/animation. |
| `clipPath` | `String?` | `clipPath` | No | `1` | Controls `clipPath` for style/layout/rendering/animation. |
| `shape` | `BoxShape?` | `shape` | No | `1` | Controls `shape` for style/layout/rendering/animation. |
| `blur` | `double?` | `blur` | No | `1` | Controls `blur` for style/layout/rendering/animation. |
| `brightness` | `double?` | `brightness` | No | `1` | Controls `brightness` for style/layout/rendering/animation. |
| `contrast` | `double?` | `contrast` | No | `1` | Controls `contrast` for style/layout/rendering/animation. |
| `grayscale` | `double?` | `grayscale` | No | `1` | Controls `grayscale` for style/layout/rendering/animation. |
| `hueRotate` | `double?` | `hueRotate` | No | `1` | Controls `hueRotate` for style/layout/rendering/animation. |
| `invert` | `double?` | `invert` | No | `1` | Controls `invert` for style/layout/rendering/animation. |
| `saturate` | `double?` | `saturate` | No | `1` | Controls `saturate` for style/layout/rendering/animation. |
| `sepia` | `double?` | `sepia` | No | `1` | Controls `sepia` for style/layout/rendering/animation. |
| `backdropColor` | `Color?` | `backdropColor` | No | `"#3366FF"` | Controls `backdropColor` for style/layout/rendering/animation. |
| `backdropBlur` | `double?` | `backdropBlur` | No | `1` | Controls `backdropBlur` for style/layout/rendering/animation. |
| `transitionDuration` | `Duration?` | `transitionDuration` | No | `"300ms"` | Controls `transitionDuration` for style/layout/rendering/animation. |
| `transitionCurve` | `Curve?` | `transitionCurve` | No | `"easeInOut"` | Controls `transitionCurve` for style/layout/rendering/animation. |
| `transitionProperty` | `String?` | `transition-property` | No | `1` | Controls `transitionProperty` for style/layout/rendering/animation. |
| `transitionDelay` | `Duration?` | `transitionDelay` | No | `"300ms"` | Controls `transitionDelay` for style/layout/rendering/animation. |
| `animationName` | `String?` | `animation-name` | No | `1` | Controls `animationName` for style/layout/rendering/animation. |
| `animationDuration` | `Duration?` | `animationDuration` | No | `"300ms"` | Controls `animationDuration` for style/layout/rendering/animation. |
| `animationTimingFunction` | `String?` | `animation-timing-function` | No | `1` | Controls `animationTimingFunction` for style/layout/rendering/animation. |
| `animationDelay` | `Duration?` | `animationDelay` | No | `"300ms"` | Controls `animationDelay` for style/layout/rendering/animation. |
| `animationIterationCount` | `int?` | `animationIterationCount` | No | `1` | Controls `animationIterationCount` for style/layout/rendering/animation. |
| `animationDirection` | `String?` | `animation-direction` | No | `1` | Controls `animationDirection` for style/layout/rendering/animation. |
| `animationFillMode` | `String?` | `animation-fill-mode` | No | `1` | Controls `animationFillMode` for style/layout/rendering/animation. |
| `animationPlayState` | `String?` | `animation-play-state` | No | `1` | Controls `animationPlayState` for style/layout/rendering/animation. |
| `animateOnBuild` | `bool?` | `animate-on-build` | No | `true` | Controls `animateOnBuild` for style/layout/rendering/animation. |
| `staggerDelay` | `Duration?` | `staggerDelay` | No | `"300ms"` | Controls `staggerDelay` for style/layout/rendering/animation. |
| `staggerChildren` | `int?` | `staggerChildren` | No | `1` | Controls `staggerChildren` for style/layout/rendering/animation. |
| `animationFrom` | `double?` | `animationFrom` | No | `1` | Controls `animationFrom` for style/layout/rendering/animation. |
| `animationTo` | `double?` | `animationTo` | No | `1` | Controls `animationTo` for style/layout/rendering/animation. |
| `slideBegin` | `Offset?` | `slideBegin` | No | `1` | Controls `slideBegin` for style/layout/rendering/animation. |
| `slideEnd` | `Offset?` | `slideEnd` | No | `1` | Controls `slideEnd` for style/layout/rendering/animation. |
| `scaleBegin` | `double?` | `scaleBegin` | No | `1` | Controls `scaleBegin` for style/layout/rendering/animation. |
| `scaleEnd` | `double?` | `scaleEnd` | No | `1` | Controls `scaleEnd` for style/layout/rendering/animation. |
| `rotationBegin` | `double?` | `rotationBegin` | No | `1` | Controls `rotationBegin` for style/layout/rendering/animation. |
| `rotationEnd` | `double?` | `rotationEnd` | No | `1` | Controls `rotationEnd` for style/layout/rendering/animation. |
| `fadeBegin` | `double?` | `fadeBegin` | No | `1` | Controls `fadeBegin` for style/layout/rendering/animation. |
| `fadeEnd` | `double?` | `fadeEnd` | No | `1` | Controls `fadeEnd` for style/layout/rendering/animation. |
| `colorBegin` | `Color?` | `colorBegin` | No | `"#3366FF"` | Controls `colorBegin` for style/layout/rendering/animation. |
| `colorEnd` | `Color?` | `colorEnd` | No | `"#3366FF"` | Controls `colorEnd` for style/layout/rendering/animation. |
| `paddingBegin` | `EdgeInsets?` | `paddingBegin` | No | `"8 12"` | Controls `paddingBegin` for style/layout/rendering/animation. |
| `paddingEnd` | `EdgeInsets?` | `paddingEnd` | No | `"8 12"` | Controls `paddingEnd` for style/layout/rendering/animation. |
| `alignmentBegin` | `AlignmentGeometry?` | `alignmentBegin` | No | `"center"` | Controls `alignmentBegin` for style/layout/rendering/animation. |
| `alignmentEnd` | `AlignmentGeometry?` | `alignmentEnd` | No | `"center"` | Controls `alignmentEnd` for style/layout/rendering/animation. |
| `shimmerBaseColor` | `Color?` | `shimmerBaseColor` | No | `"#3366FF"` | Controls `shimmerBaseColor` for style/layout/rendering/animation. |
| `shimmerHighlightColor` | `Color?` | `shimmerHighlightColor` | No | `"#3366FF"` | Controls `shimmerHighlightColor` for style/layout/rendering/animation. |
| `animationAutoReverse` | `bool?` | `animation-auto-reverse` | No | `true` | Controls `animationAutoReverse` for style/layout/rendering/animation. |
| `animationRepeat` | `bool?` | `animation-repeat` | No | `true` | Controls `animationRepeat` for style/layout/rendering/animation. |
| `keyframes` | `List<Map<String, dynamic>>?` | `keyframes` | No | `[{"offset":0,"opacity":0},{"offset":1,"opacity":1}]` | Controls `keyframes` for style/layout/rendering/animation. |
| `content` | `String?` | `content` | No | `1` | Controls `content` for style/layout/rendering/animation. |
| `listStyleType` | `String?` | `listStyleType` | No | `1` | Controls `listStyleType` for style/layout/rendering/animation. |
| `listStylePosition` | `String?` | `listStylePosition` | No | `1` | Controls `listStylePosition` for style/layout/rendering/animation. |
| `listStyleImage` | `String?` | `listStyleImage` | No | `"assets/bg.png"` | Controls `listStyleImage` for style/layout/rendering/animation. |
| `tableLayout` | `String?` | `tableLayout` | No | `1` | Controls `tableLayout` for style/layout/rendering/animation. |
| `borderCollapse` | `String?` | `borderCollapse` | No | `1` | Controls `borderCollapse` for style/layout/rendering/animation. |
| `borderSpacing` | `double?` | `borderSpacing` | No | `1` | Controls `borderSpacing` for style/layout/rendering/animation. |
| `captionSide` | `String?` | `captionSide` | No | `1` | Controls `captionSide` for style/layout/rendering/animation. |
| `emptyCells` | `String?` | `emptyCells` | No | `1` | Controls `emptyCells` for style/layout/rendering/animation. |
| `resize` | `String?` | `resize` | No | `1` | Controls `resize` for style/layout/rendering/animation. |
| `float` | `String?` | `float` | No | `1` | Controls `float` for style/layout/rendering/animation. |
| `clear` | `String?` | `clear` | No | `1` | Controls `clear` for style/layout/rendering/animation. |
| `tabSize` | `int?` | `tabSize` | No | `1` | Controls `tabSize` for style/layout/rendering/animation. |
| `direction` | `String?` | `direction` | No | `1` | Controls `direction` for style/layout/rendering/animation. |
| `unicodeBidi` | `String?` | `unicodeBidi` | No | `1` | Controls `unicodeBidi` for style/layout/rendering/animation. |

### Full style object example

```json
{
  "type": "Container",
  "props": {
    "style": {
      "width": 320,
      "padding": "16 20",
      "backgroundColor": "#F4F7FF",
      "borderRadius": 12,
      "boxShadow": "0 6 18 rgba(0,0,0,0.15)",
      "display": "flex",
      "flexDirection": "column",
      "gap": 8,
      "transitionDuration": "250ms",
      "animationDuration": "500ms"
    }
  },
  "children": [
    {"type":"Text","props":{"text":"Complete style schema example"}}
  ]
}
```

## 5) Feature-rich real-world UI DSL examples

These examples are intentionally complex and VM-event-friendly. They use `events` keys as VM function names so no app-layer glue is required.

### Example A: Auth + profile setup flow (multi-step form)

```json
{
  "type": "Scaffold",
  "key": "auth-flow",
  "props": {
    "style": {
      "backgroundColor": "#F7F9FC",
      "padding": "24",
      "display": "flex",
      "flexDirection": "column"
    }
  },
  "children": [
    {
      "type": "Column",
      "props": {
        "style": {
          "maxWidth": 520,
          "margin": "0 auto",
          "gap": 12
        }
      },
      "children": [
        {"type": "Text", "props": {"text": "Create your account", "style": {"fontSize": 28, "fontWeight": "700"}}},
        {"type": "Text", "props": {"text": "Step 2 of 3 · Profile details", "style": {"color": "#667085"}}},
        {"type": "LinearProgressIndicator", "props": {"value": 0.66}},

        {
          "type": "TextField",
          "key": "first-name",
          "props": {"hintText": "First name", "style": {"backgroundColor": "#FFFFFF", "padding": "10"}},
          "events": {"change": "onFirstNameChanged", "focus": "onFieldFocus"}
        },
        {
          "type": "TextField",
          "key": "last-name",
          "props": {"hintText": "Last name", "style": {"backgroundColor": "#FFFFFF", "padding": "10"}},
          "events": {"change": "onLastNameChanged"}
        },
        {
          "type": "TextField",
          "key": "email",
          "props": {"hintText": "Work email", "keyboardType": "emailAddress", "style": {"backgroundColor": "#FFFFFF", "padding": "10"}},
          "events": {"change": "onEmailChanged", "blur": "onEmailBlurValidate"}
        },

        {
          "type": "Row",
          "props": {"style": {"gap": 8}},
          "children": [
            {"type": "Checkbox", "key": "terms", "props": {"value": false}, "events": {"change": "onTermsToggle"}},
            {"type": "Text", "props": {"text": "I agree to Terms & Privacy Policy", "style": {"fontSize": 13}}}
          ]
        },

        {
          "type": "Row",
          "props": {"style": {"justifyContent": "spaceBetween", "margin": "8 0 0 0"}},
          "children": [
            {"type": "Button", "props": {"text": "Back"}, "events": {"click": "onBackStep"}},
            {"type": "Button", "props": {"text": "Continue", "style": {"backgroundColor": "#2563EB", "color": "#FFFFFF"}}, "events": {"click": "onContinueStep"}}
          ]
        }
      ]
    }
  ]
}
```

### Example B: Analytics dashboard (cards + list + filter chips + chart host)

```json
{
  "type": "Scaffold",
  "key": "analytics-dashboard",
  "props": {"style": {"backgroundColor": "#0B1020", "padding": "16", "color": "#E6EAF2"}},
  "children": [
    {
      "type": "Column",
      "props": {"style": {"gap": 12}},
      "children": [
        {
          "type": "Row",
          "props": {"style": {"justifyContent": "spaceBetween", "alignItems": "center"}},
          "children": [
            {"type": "Text", "props": {"text": "Growth Dashboard", "style": {"fontSize": 26, "fontWeight": "700"}}},
            {
              "type": "Row",
              "props": {"style": {"gap": 8}},
              "children": [
                {"type": "Chip", "props": {"label": "7D"}, "events": {"click": "onRange7D"}},
                {"type": "Chip", "props": {"label": "30D"}, "events": {"click": "onRange30D"}},
                {"type": "Chip", "props": {"label": "90D"}, "events": {"click": "onRange90D"}}
              ]
            }
          ]
        },

        {
          "type": "GridView",
          "props": {
            "crossAxisCount": 4,
            "shrinkWrap": true,
            "style": {"gap": 10}
          },
          "children": [
            {"type": "Card", "props": {"style": {"padding": "14", "backgroundColor": "#141B34"}}, "children": [{"type": "Text", "props": {"text": "MRR\n$124.2k"}}]},
            {"type": "Card", "props": {"style": {"padding": "14", "backgroundColor": "#141B34"}}, "children": [{"type": "Text", "props": {"text": "Churn\n2.1%"}}]},
            {"type": "Card", "props": {"style": {"padding": "14", "backgroundColor": "#141B34"}}, "children": [{"type": "Text", "props": {"text": "CAC\n$38"}}]},
            {"type": "Card", "props": {"style": {"padding": "14", "backgroundColor": "#141B34"}}, "children": [{"type": "Text", "props": {"text": "LTV\n$1,020"}}]}
          ]
        },

        {
          "type": "Card",
          "props": {"style": {"padding": "12", "backgroundColor": "#141B34", "height": 280}},
          "children": [
            {"type": "Text", "props": {"text": "Revenue Trend", "style": {"fontSize": 16, "fontWeight": "600"}}},
            {"type": "Canvas", "key": "rev-chart", "props": {"style": {"height": 230}}, "events": {"pointerMove": "onChartHover"}}
          ]
        },

        {
          "type": "ListView",
          "props": {"shrinkWrap": true, "style": {"maxHeight": 220}},
          "children": [
            {"type": "Row", "props": {"style": {"justifyContent": "spaceBetween", "padding": "10", "backgroundColor": "#11172B"}}, "children": [{"type": "Text", "props": {"text": "Acme Inc."}}, {"type": "Badge", "props": {"label": "+14%"}}]},
            {"type": "Row", "props": {"style": {"justifyContent": "spaceBetween", "padding": "10", "backgroundColor": "#11172B"}}, "children": [{"type": "Text", "props": {"text": "Globex"}}, {"type": "Badge", "props": {"label": "+8%"}}]},
            {"type": "Row", "props": {"style": {"justifyContent": "spaceBetween", "padding": "10", "backgroundColor": "#11172B"}}, "children": [{"type": "Text", "props": {"text": "Umbrella"}}, {"type": "Badge", "props": {"label": "-3%"}}]}
          ]
        }
      ]
    }
  ]
}
```

### Example C: E-commerce product details (media gallery + variants + cart actions)

```json
{
  "type": "Row",
  "key": "product-page",
  "props": {"style": {"padding": "20", "gap": 18, "backgroundColor": "#FAFAFA"}},
  "children": [
    {
      "type": "Column",
      "props": {"style": {"flex": 2, "gap": 8}},
      "children": [
        {"type": "Image", "props": {"src": "assets/products/shoe-main.png", "fit": "cover", "style": {"height": 360, "borderRadius": 10}}},
        {
          "type": "Row",
          "props": {"style": {"gap": 6}},
          "children": [
            {"type": "Image", "props": {"src": "assets/products/shoe-1.png", "style": {"width": 80, "height": 80}}, "events": {"click": "onThumb1"}},
            {"type": "Image", "props": {"src": "assets/products/shoe-2.png", "style": {"width": 80, "height": 80}}, "events": {"click": "onThumb2"}},
            {"type": "Image", "props": {"src": "assets/products/shoe-3.png", "style": {"width": 80, "height": 80}}, "events": {"click": "onThumb3"}}
          ]
        }
      ]
    },

    {
      "type": "Column",
      "props": {"style": {"flex": 3, "gap": 10, "padding": "4 8"}},
      "children": [
        {"type": "Text", "props": {"text": "Velocity X Running Shoes", "style": {"fontSize": 26, "fontWeight": "700"}}},
        {"type": "Row", "children": [{"type": "Rating", "props": {"value": 4.7}}, {"type": "Text", "props": {"text": "(1,284 reviews)"}}]},
        {"type": "Text", "props": {"text": "$129.00", "style": {"fontSize": 22, "fontWeight": "700", "color": "#0F766E"}}},

        {"type": "Text", "props": {"text": "Color"}},
        {"type": "Row", "props": {"style": {"gap": 6}}, "children": [
          {"type": "Chip", "props": {"label": "Black"}, "events": {"click": "onColorBlack"}},
          {"type": "Chip", "props": {"label": "Blue"}, "events": {"click": "onColorBlue"}},
          {"type": "Chip", "props": {"label": "White"}, "events": {"click": "onColorWhite"}}
        ]},

        {"type": "Text", "props": {"text": "Size"}},
        {"type": "Wrap", "props": {"style": {"gap": 6}}, "children": [
          {"type": "Button", "props": {"text": "7"}, "events": {"click": "onSize7"}},
          {"type": "Button", "props": {"text": "8"}, "events": {"click": "onSize8"}},
          {"type": "Button", "props": {"text": "9"}, "events": {"click": "onSize9"}},
          {"type": "Button", "props": {"text": "10"}, "events": {"click": "onSize10"}}
        ]},

        {"type": "Row", "props": {"style": {"gap": 8, "margin": "10 0 0 0"}}, "children": [
          {"type": "Button", "props": {"text": "Add to Cart", "style": {"backgroundColor": "#2563EB", "color": "#FFFFFF"}}, "events": {"click": "onAddToCart"}},
          {"type": "Button", "props": {"text": "Buy Now"}, "events": {"click": "onBuyNow"}},
          {"type": "Icon", "props": {"icon": "favorite_border"}, "events": {"click": "onWishlistToggle"}}
        ]}
      ]
    }
  ]
}
```

### Example D: Team chat workspace (sidebar, channel list, messages, composer)

```json
{
  "type": "Row",
  "key": "chat-workspace",
  "props": {"style": {"height": "100%", "backgroundColor": "#0F172A"}},
  "children": [
    {
      "type": "Column",
      "props": {"style": {"width": 260, "backgroundColor": "#111827", "padding": "12", "gap": 8}},
      "children": [
        {"type": "Text", "props": {"text": "Acme Team", "style": {"fontSize": 20, "fontWeight": "700", "color": "#F8FAFC"}}},
        {"type": "TextField", "props": {"hintText": "Search channels"}, "events": {"input": "onSearchChannels"}},
        {"type": "ListView", "props": {"style": {"gap": 4}}, "children": [
          {"type": "Button", "props": {"text": "# general"}, "events": {"click": "onOpenGeneral"}},
          {"type": "Button", "props": {"text": "# product"}, "events": {"click": "onOpenProduct"}},
          {"type": "Button", "props": {"text": "# design"}, "events": {"click": "onOpenDesign"}}
        ]}
      ]
    },

    {
      "type": "Column",
      "props": {"style": {"flex": 1, "padding": "14", "gap": 10, "backgroundColor": "#0B1220"}},
      "children": [
        {"type": "Row", "props": {"style": {"justifyContent": "spaceBetween"}}, "children": [
          {"type": "Text", "props": {"text": "# general", "style": {"fontSize": 20, "fontWeight": "600", "color": "#F8FAFC"}}},
          {"type": "Row", "children": [
            {"type": "Icon", "props": {"icon": "call"}, "events": {"click": "onStartCall"}},
            {"type": "Icon", "props": {"icon": "more_vert"}, "events": {"click": "onChannelMenu"}}
          ]}
        ]},

        {"type": "ListView", "key": "message-list", "props": {"style": {"flex": 1, "gap": 8}}, "children": [
          {"type": "Card", "props": {"style": {"padding": "8", "backgroundColor": "#1E293B"}}, "children": [{"type": "Text", "props": {"text": "@maria: Shipping the hotfix now.", "style": {"color": "#E2E8F0"}}}]},
          {"type": "Card", "props": {"style": {"padding": "8", "backgroundColor": "#1E293B"}}, "children": [{"type": "Text", "props": {"text": "@liam: QA report uploaded.", "style": {"color": "#E2E8F0"}}}]}
        ]},

        {"type": "Row", "props": {"style": {"gap": 8}}, "children": [
          {"type": "TextField", "key": "composer", "props": {"hintText": "Message #general", "style": {"flex": 1, "backgroundColor": "#1E293B", "padding": "8"}}, "events": {"input": "onComposerInput", "keyDown": "onComposerKeyDown"}},
          {"type": "Button", "props": {"text": "Send"}, "events": {"click": "onSendMessage"}}
        ]}
      ]
    }
  ]
}
```

### Example E: Hybrid admin console with embedded 3D preview + HTML content

```json
{
  "type": "Row",
  "key": "hybrid-admin",
  "props": {"style": {"padding": "16", "gap": 14, "backgroundColor": "#F3F4F6"}},
  "children": [
    {
      "type": "Column",
      "props": {"style": {"flex": 3, "gap": 10}},
      "children": [
        {"type": "Card", "props": {"style": {"padding": "10"}}, "children": [
          {"type": "Text", "props": {"text": "Digital Twin Preview", "style": {"fontSize": 18, "fontWeight": "600"}}},
          {
            "type": "GameScene",
            "key": "plant-scene",
            "props": {
              "style": {"height": 360},
              "sceneMap": {
                "world": [
                  {"type": "environment", "ambient_intensity": 0.3},
                  {"type": "camera", "camera_type": "Perspective", "transform": {"position": {"x": 0, "y": 6, "z": 14}}},
                  {"type": "light", "light_type": "Directional", "transform": {"rotation": {"x": -35, "y": 30, "z": 0}}},
                  {"type": "mesh3d", "id": "reactor", "mesh": "Cube", "transform": {"scale": {"x": 3, "y": 3, "z": 3}}, "animation": {"animation_type": {"type": "Rotate", "axis": {"x": 0, "y": 1, "z": 0}, "degrees": 360}, "duration": 8, "looping": true}}
                ]
              }
            },
            "events": {"pointerDown": "onScenePointerDown", "pointerMove": "onScenePointerMove"}
          }
        ]}
      ]
    },

    {
      "type": "Column",
      "props": {"style": {"flex": 2, "gap": 10}},
      "children": [
        {"type": "div", "props": {"style": {"backgroundColor": "#FFFFFF", "padding": "12", "borderRadius": 8}}, "children": [
          {"type": "h3", "props": {"text": "Incident Feed"}},
          {"type": "ul", "children": [
            {"type": "li", "props": {"text": "Pump-02 temperature threshold crossed"}},
            {"type": "li", "props": {"text": "Valve-7 auto-calibration completed"}}
          ]}
        ]},

        {"type": "Card", "props": {"style": {"padding": "12", "backgroundColor": "#FFFFFF"}}, "children": [
          {"type": "Text", "props": {"text": "Controls"}},
          {"type": "Row", "props": {"style": {"gap": 8}}, "children": [
            {"type": "Switch", "props": {"value": true}, "events": {"change": "onCoolingToggle"}},
            {"type": "Slider", "props": {"min": 0, "max": 100, "value": 68}, "events": {"change": "onTargetTempChange"}}
          ]},
          {"type": "Button", "props": {"text": "Apply"}, "events": {"click": "onApplyControlChanges"}}
        ]}
      ]
    }
  ]
}
```
