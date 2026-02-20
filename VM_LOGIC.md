# Elpian VM — Complete AST & API Reference

This document is the definitive reference for writing Elpian VM code. It covers the AST JSON format, all node types with their exact structures, the typed value system, the host call protocol, arithmetic/comparison operators, and the Dart/FFI API surface.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Typed Value Format](#typed-value-format)
3. [AST Program Structure](#ast-program-structure)
4. [Expression Nodes](#expression-nodes)
5. [Statement Nodes](#statement-nodes)
6. [Operators & Arithmetic](#operators--arithmetic)
7. [Host Call Protocol](#host-call-protocol)
8. [Built-in Functions](#built-in-functions)
9. [FFI / Dart API](#ffi--dart-api)
10. [Complete Examples](#complete-examples)

---

## Architecture Overview

```
Source Code / AST JSON
        │
        ▼
   ┌──────────┐
   │ Compiler  │  compiler.rs — AST JSON → bytecode (Vec<u8>)
   └──────────┘
        │
        ▼
   ┌──────────┐
   │ Executor  │  executor.rs — bytecode interpreter, ~4900 lines
   └──────────┘
        │
        ▼
   ┌──────────┐
   │ Context   │  context.rs — scope/variable management
   └──────────┘
        │
        ▼
   ┌──────────┐
   │   Data    │  data.rs — Val, Object, Array, Function types
   └──────────┘
```

The VM compiles AST JSON into bytecode, then executes it. When the VM needs to communicate with the host (Flutter/Dart), it **pauses** execution and returns a host call request. The host processes it and calls `continue_execution` to resume the VM.

---

## Typed Value Format

All values crossing the FFI boundary use a typed JSON envelope:

```json
{ "type": "<type_name>", "data": { "value": <actual_value> } }
```

### Type Table

| Type Name | Type ID | JSON Example | Rust `Val.typ` |
|-----------|---------|-------------|-----------------|
| `null`    | 0       | N/A (empty Val) | 0 |
| `i16`     | 1       | `{"type":"i16","data":{"value":42}}` | 1 |
| `i32`     | 2       | `{"type":"i32","data":{"value":100000}}` | 2 |
| `i64`     | 3       | `{"type":"i64","data":{"value":9999999999}}` | 3 |
| `f32`     | 4       | `{"type":"f32","data":{"value":3.14}}` | 4 |
| `f64`     | 5       | `{"type":"f64","data":{"value":3.141592653589793}}` | 5 |
| `bool`    | 6       | `{"type":"bool","data":{"value":true}}` | 6 |
| `string`  | 7       | `{"type":"string","data":{"value":"hello"}}` | 7 |
| `object`  | 8       | `{"type":"object","data":{"value":{"key":{...}}}}` | 8 |
| `array`   | 9       | `{"type":"array","data":{"value":[...]}}` | 9 |
| `function`| 10      | (internal only) | 10 |
| `host_call_pending` | 253 | (internal — VM is paused) | 253 |
| `native_func` | 255 | (internal — askHost marker) | 255 |

### Nested Object Example

```json
{
  "type": "object",
  "data": {
    "value": {
      "name": { "type": "string", "data": { "value": "Alice" } },
      "age": { "type": "i16", "data": { "value": 30 } }
    }
  }
}
```

### Nested Array Example

```json
{
  "type": "array",
  "data": {
    "value": [
      { "type": "string", "data": { "value": "item1" } },
      { "type": "i16", "data": { "value": 42 } }
    ]
  }
}
```

---

## AST Program Structure

Every AST is a JSON object with a `"type": "program"` root and a `"body"` array of statement nodes.

```json
{
  "type": "program",
  "body": [
    { "type": "<statement_type>", "data": { ... } },
    { "type": "<statement_type>", "data": { ... } }
  ]
}
```

The `"body"` array is also used recursively inside `functionDefinition`, `ifStmt`, `loopStmt`, and `switchStmt` to hold their inner statements.

---

## Expression Nodes

Expression nodes are used as values inside statements (right-hand side of definitions, function arguments, conditions, etc.).

### Literal: `i16`

```json
{ "type": "i16", "data": { "value": 42 } }
```

### Literal: `i32`

```json
{ "type": "i32", "data": { "value": 100000 } }
```

### Literal: `i64`

```json
{ "type": "i64", "data": { "value": 9999999999 } }
```

### Literal: `f32`

```json
{ "type": "f32", "data": { "value": 3.14 } }
```

### Literal: `f64`

```json
{ "type": "f64", "data": { "value": 3.141592653589793 } }
```

### Literal: `bool`

```json
{ "type": "bool", "data": { "value": true } }
```

### Literal: `string`

```json
{ "type": "string", "data": { "value": "hello world" } }
```

### Literal: `object`

An inline object literal. Each property value is a typed expression node.

```json
{
  "type": "object",
  "data": {
    "value": {
      "name": { "type": "string", "data": { "value": "Alice" } },
      "age": { "type": "i16", "data": { "value": 30 } },
      "active": { "type": "bool", "data": { "value": true } }
    }
  }
}
```

### Literal: `array`

An inline array literal. Each element is a typed expression node.

```json
{
  "type": "array",
  "data": {
    "value": [
      { "type": "string", "data": { "value": "a" } },
      { "type": "string", "data": { "value": "b" } },
      { "type": "i16", "data": { "value": 3 } }
    ]
  }
}
```

### `identifier`

References a variable by name. Resolved at runtime via the context/scope chain.

```json
{ "type": "identifier", "data": { "name": "myVariable" } }
```

### `indexer`

Access a property of an object (by string key) or an element of an array (by integer index). Both `target` and `index` are expression nodes.

```json
{
  "type": "indexer",
  "data": {
    "target": { "type": "identifier", "data": { "name": "myObj" } },
    "index": { "type": "string", "data": { "value": "name" } }
  }
}
```

Array index example:
```json
{
  "type": "indexer",
  "data": {
    "target": { "type": "identifier", "data": { "name": "myArr" } },
    "index": { "type": "i16", "data": { "value": 0 } }
  }
}
```

### `arithmetic`

Binary operation on two operands. See [Operators & Arithmetic](#operators--arithmetic) for all operations.

```json
{
  "type": "arithmetic",
  "data": {
    "operation": "+",
    "operand1": { "type": "i16", "data": { "value": 10 } },
    "operand2": { "type": "i16", "data": { "value": 20 } }
  }
}
```

### `not`

Logical NOT. Negates a boolean expression.

```json
{
  "type": "not",
  "data": {
    "value": { "type": "identifier", "data": { "name": "isActive" } }
  }
}
```

### `cast`

Type casting. Converts a value to a target type.

| `targetType` | Description |
|--------------|-------------|
| `"i16"` | Cast to 16-bit integer |
| `"i32"` | Cast to 32-bit integer |
| `"i64"` | Cast to 64-bit integer |
| `"f32"` | Cast to 32-bit float |
| `"f64"` | Cast to 64-bit float |
| `"string"` | Cast to string |
| `"bool"` | Cast to boolean |

```json
{
  "type": "cast",
  "data": {
    "value": { "type": "i16", "data": { "value": 42 } },
    "targetType": "string"
  }
}
```

### `callback`

Creates a reference to a function (function pointer / callback). Used to pass functions as arguments.

```json
{
  "type": "callback",
  "data": {
    "value": {
      "funcId": { "type": "identifier", "data": { "name": "myHandler" } }
    }
  }
}
```

### `functionCall` (as expression)

Calls a function and uses its return value as an expression. Same structure as the statement version.

```json
{
  "type": "functionCall",
  "data": {
    "callee": { "type": "identifier", "data": { "name": "add" } },
    "args": [
      { "type": "i16", "data": { "value": 1 } },
      { "type": "i16", "data": { "value": 2 } }
    ]
  }
}
```

---

## Statement Nodes

Statement nodes are the entries in a `"body"` array. They are executed sequentially.

### `definition`

Declares a new variable in the current scope.

| Property | Type | Description |
|----------|------|-------------|
| `data.leftSide` | identifier node | Variable name to define |
| `data.rightSide` | expression node | Initial value |

```json
{
  "type": "definition",
  "data": {
    "leftSide": { "type": "identifier", "data": { "name": "count" } },
    "rightSide": { "type": "i16", "data": { "value": 0 } }
  }
}
```

### `assignment`

Assigns a new value to an existing variable. The left side can be an `identifier` or an `indexer`.

**Assign to variable:**
```json
{
  "type": "assignment",
  "data": {
    "leftSide": { "type": "identifier", "data": { "name": "count" } },
    "rightSide": {
      "type": "arithmetic",
      "data": {
        "operation": "+",
        "operand1": { "type": "identifier", "data": { "name": "count" } },
        "operand2": { "type": "i16", "data": { "value": 1 } }
      }
    }
  }
}
```

**Assign to object property:**
```json
{
  "type": "assignment",
  "data": {
    "leftSide": {
      "type": "indexer",
      "data": {
        "target": { "type": "identifier", "data": { "name": "user" } },
        "index": { "type": "string", "data": { "value": "name" } }
      }
    },
    "rightSide": { "type": "string", "data": { "value": "Bob" } }
  }
}
```

### `functionCall` (as statement)

Calls a function. Discards the return value.

| Property | Type | Description |
|----------|------|-------------|
| `data.callee` | expression node | The function to call (usually identifier) |
| `data.args` | array of expression nodes | Arguments |

```json
{
  "type": "functionCall",
  "data": {
    "callee": { "type": "identifier", "data": { "name": "println" } },
    "args": [
      { "type": "string", "data": { "value": "Hello World" } }
    ]
  }
}
```

### `functionDefinition`

Defines a named function in the current scope.

| Property | Type | Description |
|----------|------|-------------|
| `data.name` | string | Function name |
| `data.params` | array of strings | Parameter names |
| `data.body` | array of statement nodes | Function body |

```json
{
  "type": "functionDefinition",
  "data": {
    "name": "add",
    "params": ["a", "b"],
    "body": [
      {
        "type": "returnOperation",
        "data": {
          "value": {
            "type": "arithmetic",
            "data": {
              "operation": "+",
              "operand1": { "type": "identifier", "data": { "name": "a" } },
              "operand2": { "type": "identifier", "data": { "name": "b" } }
            }
          }
        }
      }
    ]
  }
}
```

### `returnOperation`

Returns a value from a function.

```json
{
  "type": "returnOperation",
  "data": {
    "value": { "type": "string", "data": { "value": "done" } }
  }
}
```

### `ifStmt`

Conditional branching with optional `elseifStmt` and `elseStmt` chains.

| Property | Type | Description |
|----------|------|-------------|
| `data.condition` | expression node | Boolean condition |
| `data.body` | array of statement nodes | Body if condition is true |
| `data.elseifStmt` | (optional) ifStmt-like node | Else-if chain |
| `data.elseStmt` | (optional) block node | Else block |

```json
{
  "type": "ifStmt",
  "data": {
    "condition": {
      "type": "arithmetic",
      "data": {
        "operation": ">",
        "operand1": { "type": "identifier", "data": { "name": "x" } },
        "operand2": { "type": "i16", "data": { "value": 10 } }
      }
    },
    "body": [
      {
        "type": "functionCall",
        "data": {
          "callee": { "type": "identifier", "data": { "name": "println" } },
          "args": [{ "type": "string", "data": { "value": "big" } }]
        }
      }
    ],
    "elseifStmt": {
      "type": "ifStmt",
      "data": {
        "condition": {
          "type": "arithmetic",
          "data": {
            "operation": ">",
            "operand1": { "type": "identifier", "data": { "name": "x" } },
            "operand2": { "type": "i16", "data": { "value": 5 } }
          }
        },
        "body": [
          {
            "type": "functionCall",
            "data": {
              "callee": { "type": "identifier", "data": { "name": "println" } },
              "args": [{ "type": "string", "data": { "value": "medium" } }]
            }
          }
        ]
      }
    },
    "elseStmt": {
      "data": {
        "body": [
          {
            "type": "functionCall",
            "data": {
              "callee": { "type": "identifier", "data": { "name": "println" } },
              "args": [{ "type": "string", "data": { "value": "small" } }]
            }
          }
        ]
      }
    }
  }
}
```

### `loopStmt`

While-loop. Repeats body while condition is true.

| Property | Type | Description |
|----------|------|-------------|
| `data.condition` | expression node | Loop condition (evaluated each iteration) |
| `data.body` | array of statement nodes | Loop body |

```json
{
  "type": "loopStmt",
  "data": {
    "condition": {
      "type": "arithmetic",
      "data": {
        "operation": "<",
        "operand1": { "type": "identifier", "data": { "name": "i" } },
        "operand2": { "type": "i16", "data": { "value": 10 } }
      }
    },
    "body": [
      {
        "type": "assignment",
        "data": {
          "leftSide": { "type": "identifier", "data": { "name": "i" } },
          "rightSide": {
            "type": "arithmetic",
            "data": {
              "operation": "+",
              "operand1": { "type": "identifier", "data": { "name": "i" } },
              "operand2": { "type": "i16", "data": { "value": 1 } }
            }
          }
        }
      }
    ]
  }
}
```

### `switchStmt`

Switch/match on a value. Each case has a value to compare and a body.

| Property | Type | Description |
|----------|------|-------------|
| `data.value` | expression node | Value to switch on |
| `data.cases` | array of case objects | Each with `value` (expression) and `body` (program-like with `body` array) |

```json
{
  "type": "switchStmt",
  "data": {
    "value": { "type": "identifier", "data": { "name": "color" } },
    "cases": [
      {
        "value": { "type": "string", "data": { "value": "red" } },
        "body": {
          "body": [
            {
              "type": "functionCall",
              "data": {
                "callee": { "type": "identifier", "data": { "name": "println" } },
                "args": [{ "type": "string", "data": { "value": "It's red!" } }]
              }
            }
          ]
        }
      },
      {
        "value": { "type": "string", "data": { "value": "blue" } },
        "body": {
          "body": [
            {
              "type": "functionCall",
              "data": {
                "callee": { "type": "identifier", "data": { "name": "println" } },
                "args": [{ "type": "string", "data": { "value": "It's blue!" } }]
              }
            }
          ]
        }
      }
    ]
  }
}
```

### `host_call` (as statement)

Calls a host API function. This is a high-level convenience node that the compiler desugars into a `functionCall` to the internal `askHost` function.

| Property | Type | Description |
|----------|------|-------------|
| `data.name` | string | Host API name (e.g. `"render"`, `"println"`, `"updateApp"`) |
| `data.args` | array of expression nodes | Arguments to pass to the host |

```json
{
  "type": "host_call",
  "data": {
    "name": "render",
    "args": [
      {
        "type": "object",
        "data": {
          "value": {
            "type": { "type": "string", "data": { "value": "Text" } },
            "props": {
              "type": "object",
              "data": {
                "value": {
                  "data": { "type": "string", "data": { "value": "Hello Flutter!" } }
                }
              }
            }
          }
        }
      }
    ]
  }
}
```

### `jumpOperation` (low-level)

Unconditional jump to a step number. Used internally by the compiler for control flow. Step numbers correspond to the 1-based index in the body array.

```json
{
  "type": "jumpOperation",
  "data": { "stepNumber": 3 }
}
```

### `conditionalBranch` (low-level)

Conditional jump. If the condition is true, jump to `trueBranch`; otherwise jump to `falseBranch`. Step numbers are 1-based indices into the body array.

```json
{
  "type": "conditionalBranch",
  "data": {
    "condition": {
      "type": "arithmetic",
      "data": {
        "operation": "==",
        "operand1": { "type": "identifier", "data": { "name": "x" } },
        "operand2": { "type": "i16", "data": { "value": 0 } }
      }
    },
    "trueBranch": 5,
    "falseBranch": 3
  }
}
```

---

## Operators & Arithmetic

All binary operations use the `"arithmetic"` node type.

### Comparison Operators

| Operation | Bytecode | Description |
|-----------|----------|-------------|
| `"=="` | 0xf0 | Equality |
| `">"` | 0xf1 | Greater than |
| `">="` | 0xf2 | Greater than or equal |
| `"<"` | 0xf3 | Less than |
| `"<="` | 0xf4 | Less than or equal |
| `"!="` | 0xf5 | Not equal |

### Arithmetic Operators

| Operation | Bytecode | Description |
|-----------|----------|-------------|
| `"+"` | 0xf6 | Addition (also string concatenation) |
| `"-"` | 0xf7 | Subtraction |
| `"*"` | 0xf8 | Multiplication |
| `"/"` | 0xf9 | Division |
| `"%"` | 0xfa | Modulo |
| `"^"` | 0xfb | Power/exponentiation |

### Unary Operators

| Node Type | Bytecode | Description |
|-----------|----------|-------------|
| `"not"` | 0xfc | Logical NOT |
| `"cast"` | 0xfd | Type cast |

### String Concatenation

The `+` operator works on strings too:

```json
{
  "type": "arithmetic",
  "data": {
    "operation": "+",
    "operand1": { "type": "string", "data": { "value": "Hello " } },
    "operand2": { "type": "string", "data": { "value": "World" } }
  }
}
```

---

## Host Call Protocol

### How It Works

1. VM code calls a host function (via `host_call` node or `askHost` identifier)
2. The executor **pauses** and sets `reserved_host_call`
3. VM returns to Dart with `VmExecResult { has_host_call: true, host_call_data: "..." }`
4. Dart parses the host call data, processes the request
5. Dart calls `continue_execution(machineId, responseJson)` to resume the VM
6. If the VM makes another host call, the loop repeats

### Host Call Data Format (VM → Dart)

```json
{
  "machineId": "vm-001",
  "apiName": "render",
  "payload": "<stringified value>"
}
```

The `payload` is the stringified representation of the arguments passed from the VM. For objects, it follows the `Val.stringify()` format:

```
{ "key1": "value1", "key2": 42 }
```

### Host Call Response Format (Dart → VM)

The response must be a typed value JSON:

```json
{ "type": "string", "data": { "value": "ok" } }
```

Or for a null/void response:

```json
{ "type": "i16", "data": { "value": 0 } }
```

### Registered Host API Names

These are registered in the VM's `func_group` when creating a VM instance:

| API Name | Purpose |
|----------|---------|
| `println` | Print a message to the console |
| `stringify` | Convert a value to its string representation |
| `render` | Render a UI view (sends JSON view tree to Flutter) |
| `updateApp` | Update the app state / trigger a re-render |

### Using `host_call` in AST

The simplest way to call a host function:

```json
{
  "type": "host_call",
  "data": {
    "name": "println",
    "args": [
      { "type": "string", "data": { "value": "Hello from VM!" } }
    ]
  }
}
```

### Manual `askHost` Call (equivalent)

The `host_call` node is syntactic sugar. You can also call `askHost` directly as a function call:

```json
{
  "type": "functionCall",
  "data": {
    "callee": { "type": "identifier", "data": { "name": "askHost" } },
    "args": [
      { "type": "string", "data": { "value": "render" } },
      {
        "type": "array",
        "data": {
          "value": [
            {
              "type": "object",
              "data": {
                "value": {
                  "type": { "type": "string", "data": { "value": "Text" } }
                }
              }
            }
          ]
        }
      }
    ]
  }
}
```

When calling `askHost` directly, the first argument is the API name (string), and the second is an array of the actual arguments.

---

## Built-in Functions

The VM has no built-in functions in the traditional sense. All external capabilities come through the host call mechanism. The `func_group` list (`println`, `stringify`, `render`, `updateApp`) defines which API names the VM is allowed to call. These are handled on the Dart side by the `HostHandler`.

User-defined functions (via `functionDefinition`) are fully supported and live in the VM scope.

---

## FFI / Dart API

### Rust FFI Functions (extern "C")

| Function | Signature | Description |
|----------|-----------|-------------|
| `elpian_init` | `() → void` | Initialize the VM subsystem. Call once at startup. |
| `elpian_create_vm_from_ast` | `(machine_id: *c_char, ast_json: *c_char) → i32` | Create VM from AST JSON. Returns 1 on success, 0 on failure. |
| `elpian_create_vm_from_code` | `(machine_id: *c_char, code: *c_char) → i32` | Create VM from source code string. Returns 1/0. |
| `elpian_validate_ast` | `(ast_json: *c_char) → i32` | Validate AST without creating a VM. Returns 1/0. |
| `elpian_execute` | `(machine_id: *c_char) → *c_char` | Execute main program. Returns JSON `VmExecResult`. |
| `elpian_execute_func` | `(machine_id: *c_char, func_name: *c_char, cb_id: i64) → *c_char` | Execute a named function. Returns JSON `VmExecResult`. |
| `elpian_execute_func_with_input` | `(machine_id: *c_char, func_name: *c_char, input_json: *c_char, cb_id: i64) → *c_char` | Execute function with typed JSON input. |
| `elpian_continue_execution` | `(machine_id: *c_char, input_json: *c_char) → *c_char` | Resume VM after host call. Input is typed JSON value. |
| `elpian_destroy_vm` | `(machine_id: *c_char) → i32` | Destroy a VM instance. Returns 1/0. |
| `elpian_vm_exists` | `(machine_id: *c_char) → i32` | Check if VM exists. Returns 1/0. |
| `elpian_free_string` | `(ptr: *c_char) → void` | Free a string returned by the VM. |

### VmExecResult (returned as JSON)

```json
{
  "has_host_call": true,
  "host_call_data": "{\"machineId\":\"vm1\",\"apiName\":\"render\",\"payload\":\"...\"}",
  "result_value": ""
}
```

When `has_host_call` is `false`, execution is complete and `result_value` contains the stringified result.

### Dart API (`ElpianVmApi`)

```dart
class ElpianVmApi {
  static Future<void> init();
  static Future<bool> createVmFromAst(String machineId, String astJson);
  static Future<bool> createVmFromCode(String machineId, String code);
  static Future<bool> validateAst(String astJson);
  static Future<VmExecResult> execute(String machineId);
  static Future<VmExecResult> executeFunc(String machineId, String funcName, int cbId);
  static Future<VmExecResult> executeFuncWithInput(String machineId, String funcName, String inputJson, int cbId);
  static Future<VmExecResult> continueExecution(String machineId, String inputJson);
  static Future<bool> destroyVm(String machineId);
  static Future<bool> vmExists(String machineId);
}
```

### Dart High-Level Wrapper (`ElpianVm`)

```dart
// Create from AST
final vm = await ElpianVm.fromAst("vm-001", jsonEncode(astJson));

// Create from source code
final vm = await ElpianVm.fromCode("vm-001", 'println("hello")');

// Register host handlers
vm.registerHostHandler("render", (payload) async {
  // Process render request, return typed JSON response
  return '{"type":"string","data":{"value":"ok"}}';
});

vm.registerHostHandler("println", (payload) async {
  print(payload);
  return '{"type":"i16","data":{"value":0}}';
});

// Run (automatically loops through host calls)
final result = await vm.run();
```

---

## Complete Examples

### Example 1: Hello World

```json
{
  "type": "program",
  "body": [
    {
      "type": "host_call",
      "data": {
        "name": "println",
        "args": [
          { "type": "string", "data": { "value": "Hello World!" } }
        ]
      }
    }
  ]
}
```

### Example 2: Variable Definition and Arithmetic

```json
{
  "type": "program",
  "body": [
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "x" } },
        "rightSide": { "type": "i16", "data": { "value": 10 } }
      }
    },
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "y" } },
        "rightSide": { "type": "i16", "data": { "value": 20 } }
      }
    },
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "sum" } },
        "rightSide": {
          "type": "arithmetic",
          "data": {
            "operation": "+",
            "operand1": { "type": "identifier", "data": { "name": "x" } },
            "operand2": { "type": "identifier", "data": { "name": "y" } }
          }
        }
      }
    },
    {
      "type": "host_call",
      "data": {
        "name": "println",
        "args": [
          { "type": "identifier", "data": { "name": "sum" } }
        ]
      }
    }
  ]
}
```

### Example 3: Function Definition and Calls

```json
{
  "type": "program",
  "body": [
    {
      "type": "functionDefinition",
      "data": {
        "name": "greet",
        "params": ["name"],
        "body": [
          {
            "type": "definition",
            "data": {
              "leftSide": { "type": "identifier", "data": { "name": "msg" } },
              "rightSide": {
                "type": "arithmetic",
                "data": {
                  "operation": "+",
                  "operand1": { "type": "string", "data": { "value": "Hello, " } },
                  "operand2": { "type": "identifier", "data": { "name": "name" } }
                }
              }
            }
          },
          {
            "type": "returnOperation",
            "data": {
              "value": { "type": "identifier", "data": { "name": "msg" } }
            }
          }
        ]
      }
    },
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "result" } },
        "rightSide": {
          "type": "functionCall",
          "data": {
            "callee": { "type": "identifier", "data": { "name": "greet" } },
            "args": [
              { "type": "string", "data": { "value": "Flutter" } }
            ]
          }
        }
      }
    },
    {
      "type": "host_call",
      "data": {
        "name": "println",
        "args": [
          { "type": "identifier", "data": { "name": "result" } }
        ]
      }
    }
  ]
}
```

### Example 4: If/Else Conditional

```json
{
  "type": "program",
  "body": [
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "score" } },
        "rightSide": { "type": "i16", "data": { "value": 85 } }
      }
    },
    {
      "type": "ifStmt",
      "data": {
        "condition": {
          "type": "arithmetic",
          "data": {
            "operation": ">=",
            "operand1": { "type": "identifier", "data": { "name": "score" } },
            "operand2": { "type": "i16", "data": { "value": 90 } }
          }
        },
        "body": [
          {
            "type": "host_call",
            "data": {
              "name": "println",
              "args": [{ "type": "string", "data": { "value": "Grade: A" } }]
            }
          }
        ],
        "elseifStmt": {
          "type": "ifStmt",
          "data": {
            "condition": {
              "type": "arithmetic",
              "data": {
                "operation": ">=",
                "operand1": { "type": "identifier", "data": { "name": "score" } },
                "operand2": { "type": "i16", "data": { "value": 80 } }
              }
            },
            "body": [
              {
                "type": "host_call",
                "data": {
                  "name": "println",
                  "args": [{ "type": "string", "data": { "value": "Grade: B" } }]
                }
              }
            ]
          }
        },
        "elseStmt": {
          "data": {
            "body": [
              {
                "type": "host_call",
                "data": {
                  "name": "println",
                  "args": [{ "type": "string", "data": { "value": "Grade: C" } }]
                }
              }
            ]
          }
        }
      }
    }
  ]
}
```

### Example 5: Loop (While)

```json
{
  "type": "program",
  "body": [
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "i" } },
        "rightSide": { "type": "i16", "data": { "value": 0 } }
      }
    },
    {
      "type": "loopStmt",
      "data": {
        "condition": {
          "type": "arithmetic",
          "data": {
            "operation": "<",
            "operand1": { "type": "identifier", "data": { "name": "i" } },
            "operand2": { "type": "i16", "data": { "value": 5 } }
          }
        },
        "body": [
          {
            "type": "host_call",
            "data": {
              "name": "println",
              "args": [
                { "type": "identifier", "data": { "name": "i" } }
              ]
            }
          },
          {
            "type": "assignment",
            "data": {
              "leftSide": { "type": "identifier", "data": { "name": "i" } },
              "rightSide": {
                "type": "arithmetic",
                "data": {
                  "operation": "+",
                  "operand1": { "type": "identifier", "data": { "name": "i" } },
                  "operand2": { "type": "i16", "data": { "value": 1 } }
                }
              }
            }
          }
        ]
      }
    }
  ]
}
```

### Example 6: Object and Property Access

```json
{
  "type": "program",
  "body": [
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "user" } },
        "rightSide": {
          "type": "object",
          "data": {
            "value": {
              "name": { "type": "string", "data": { "value": "Alice" } },
              "age": { "type": "i16", "data": { "value": 30 } }
            }
          }
        }
      }
    },
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "userName" } },
        "rightSide": {
          "type": "indexer",
          "data": {
            "target": { "type": "identifier", "data": { "name": "user" } },
            "index": { "type": "string", "data": { "value": "name" } }
          }
        }
      }
    },
    {
      "type": "host_call",
      "data": {
        "name": "println",
        "args": [
          { "type": "identifier", "data": { "name": "userName" } }
        ]
      }
    }
  ]
}
```

### Example 7: Render a Flutter UI View

This is the main use-case: the VM sends a JSON view tree to Flutter via `render`.

```json
{
  "type": "program",
  "body": [
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "view" } },
        "rightSide": {
          "type": "object",
          "data": {
            "value": {
              "type": { "type": "string", "data": { "value": "Column" } },
              "props": {
                "type": "object",
                "data": {
                  "value": {
                    "mainAxisAlignment": { "type": "string", "data": { "value": "center" } },
                    "children": {
                      "type": "array",
                      "data": {
                        "value": [
                          {
                            "type": "object",
                            "data": {
                              "value": {
                                "type": { "type": "string", "data": { "value": "Text" } },
                                "props": {
                                  "type": "object",
                                  "data": {
                                    "value": {
                                      "data": { "type": "string", "data": { "value": "Hello from Elpian VM!" } },
                                      "style": {
                                        "type": "object",
                                        "data": {
                                          "value": {
                                            "fontSize": { "type": "i16", "data": { "value": 24 } },
                                            "fontWeight": { "type": "string", "data": { "value": "bold" } }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          },
                          {
                            "type": "object",
                            "data": {
                              "value": {
                                "type": { "type": "string", "data": { "value": "ElevatedButton" } },
                                "props": {
                                  "type": "object",
                                  "data": {
                                    "value": {
                                      "child": {
                                        "type": "object",
                                        "data": {
                                          "value": {
                                            "type": { "type": "string", "data": { "value": "Text" } },
                                            "props": {
                                              "type": "object",
                                              "data": {
                                                "value": {
                                                  "data": { "type": "string", "data": { "value": "Click Me" } }
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
                            }
                          }
                        ]
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
    {
      "type": "host_call",
      "data": {
        "name": "render",
        "args": [
          { "type": "identifier", "data": { "name": "view" } }
        ]
      }
    }
  ]
}
```

### Example 8: Counter App with State

```json
{
  "type": "program",
  "body": [
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "count" } },
        "rightSide": { "type": "i16", "data": { "value": 0 } }
      }
    },
    {
      "type": "functionDefinition",
      "data": {
        "name": "increment",
        "params": [],
        "body": [
          {
            "type": "assignment",
            "data": {
              "leftSide": { "type": "identifier", "data": { "name": "count" } },
              "rightSide": {
                "type": "arithmetic",
                "data": {
                  "operation": "+",
                  "operand1": { "type": "identifier", "data": { "name": "count" } },
                  "operand2": { "type": "i16", "data": { "value": 1 } }
                }
              }
            }
          },
          {
            "type": "host_call",
            "data": {
              "name": "render",
              "args": [
                {
                  "type": "object",
                  "data": {
                    "value": {
                      "type": { "type": "string", "data": { "value": "Text" } },
                      "props": {
                        "type": "object",
                        "data": {
                          "value": {
                            "data": {
                              "type": "cast",
                              "data": {
                                "value": { "type": "identifier", "data": { "name": "count" } },
                                "targetType": "string"
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    },
    {
      "type": "host_call",
      "data": {
        "name": "render",
        "args": [
          {
            "type": "object",
            "data": {
              "value": {
                "type": { "type": "string", "data": { "value": "Text" } },
                "props": {
                  "type": "object",
                  "data": {
                    "value": {
                      "data": { "type": "string", "data": { "value": "0" } }
                    }
                  }
                }
              }
            }
          }
        ]
      }
    }
  ]
}
```

The Dart side can call `vm.callFunction("increment")` to trigger `increment`, which updates `count` and re-renders.

### Example 9: Array Manipulation in Loop

```json
{
  "type": "program",
  "body": [
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "items" } },
        "rightSide": {
          "type": "array",
          "data": {
            "value": [
              { "type": "string", "data": { "value": "apple" } },
              { "type": "string", "data": { "value": "banana" } },
              { "type": "string", "data": { "value": "cherry" } }
            ]
          }
        }
      }
    },
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "i" } },
        "rightSide": { "type": "i16", "data": { "value": 0 } }
      }
    },
    {
      "type": "loopStmt",
      "data": {
        "condition": {
          "type": "arithmetic",
          "data": {
            "operation": "<",
            "operand1": { "type": "identifier", "data": { "name": "i" } },
            "operand2": { "type": "i16", "data": { "value": 3 } }
          }
        },
        "body": [
          {
            "type": "definition",
            "data": {
              "leftSide": { "type": "identifier", "data": { "name": "item" } },
              "rightSide": {
                "type": "indexer",
                "data": {
                  "target": { "type": "identifier", "data": { "name": "items" } },
                  "index": { "type": "identifier", "data": { "name": "i" } }
                }
              }
            }
          },
          {
            "type": "host_call",
            "data": {
              "name": "println",
              "args": [
                { "type": "identifier", "data": { "name": "item" } }
              ]
            }
          },
          {
            "type": "assignment",
            "data": {
              "leftSide": { "type": "identifier", "data": { "name": "i" } },
              "rightSide": {
                "type": "arithmetic",
                "data": {
                  "operation": "+",
                  "operand1": { "type": "identifier", "data": { "name": "i" } },
                  "operand2": { "type": "i16", "data": { "value": 1 } }
                }
              }
            }
          }
        ]
      }
    }
  ]
}
```

### Example 10: Switch Statement

```json
{
  "type": "program",
  "body": [
    {
      "type": "definition",
      "data": {
        "leftSide": { "type": "identifier", "data": { "name": "day" } },
        "rightSide": { "type": "string", "data": { "value": "Monday" } }
      }
    },
    {
      "type": "switchStmt",
      "data": {
        "value": { "type": "identifier", "data": { "name": "day" } },
        "cases": [
          {
            "value": { "type": "string", "data": { "value": "Monday" } },
            "body": {
              "body": [
                {
                  "type": "host_call",
                  "data": {
                    "name": "println",
                    "args": [{ "type": "string", "data": { "value": "Start of the week" } }]
                  }
                }
              ]
            }
          },
          {
            "value": { "type": "string", "data": { "value": "Friday" } },
            "body": {
              "body": [
                {
                  "type": "host_call",
                  "data": {
                    "name": "println",
                    "args": [{ "type": "string", "data": { "value": "Almost weekend!" } }]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ]
}
```

---

## Quick Reference: All AST Node Types

### Expression Nodes (used as values)

| Type | Key Properties | Notes |
|------|---------------|-------|
| `i16` | `data.value` (integer) | 16-bit integer literal |
| `i32` | `data.value` (integer) | 32-bit integer literal |
| `i64` | `data.value` (integer) | 64-bit integer literal |
| `f32` | `data.value` (float) | 32-bit float literal |
| `f64` | `data.value` (float) | 64-bit float literal |
| `bool` | `data.value` (boolean) | Boolean literal |
| `string` | `data.value` (string) | String literal |
| `object` | `data.value` (object of typed values) | Object literal |
| `array` | `data.value` (array of typed values) | Array literal |
| `identifier` | `data.name` (string) | Variable reference |
| `indexer` | `data.target`, `data.index` | Property/element access |
| `arithmetic` | `data.operation`, `data.operand1`, `data.operand2` | Binary operation |
| `not` | `data.value` | Logical NOT |
| `cast` | `data.value`, `data.targetType` | Type cast |
| `callback` | `data.value.funcId` | Function reference |
| `functionCall` | `data.callee`, `data.args` | Function call (returns value) |

### Statement Nodes (used in body arrays)

| Type | Key Properties | Notes |
|------|---------------|-------|
| `definition` | `data.leftSide`, `data.rightSide` | Variable declaration |
| `assignment` | `data.leftSide`, `data.rightSide` | Variable assignment |
| `functionCall` | `data.callee`, `data.args` | Function call (discards result) |
| `functionDefinition` | `data.name`, `data.params`, `data.body` | Function definition |
| `returnOperation` | `data.value` | Return from function |
| `ifStmt` | `data.condition`, `data.body`, `data.elseifStmt?`, `data.elseStmt?` | Conditional |
| `loopStmt` | `data.condition`, `data.body` | While loop |
| `switchStmt` | `data.value`, `data.cases` | Switch/match |
| `host_call` | `data.name`, `data.args` | Host API call |
| `jumpOperation` | `data.stepNumber` | Unconditional jump (low-level) |
| `conditionalBranch` | `data.condition`, `data.trueBranch`, `data.falseBranch` | Conditional jump (low-level) |

---

## ElpianVmWidget

`ElpianVmWidget` is a Flutter widget that runs a VM sandbox and renders the view tree it produces. It handles the full lifecycle: VM creation, host call routing, rendering, and disposal.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `machineId` | String | *required* | Unique VM instance identifier |
| `code` | String? | null | Source code to run |
| `astJson` | String? | null | Pre-compiled AST JSON to run |
| `engine` | ElpianEngine? | null | Custom engine instance (creates default if null) |
| `stylesheet` | Map? | null | JSON stylesheet to load |
| `loadingWidget` | Widget? | null | Widget shown during initialization |
| `errorBuilder` | Function? | null | Custom error display |
| `onPrintln` | Function? | null | Callback for VM `println` calls |
| `onUpdateApp` | Function? | null | Callback for VM `updateApp` calls |
| `hostHandlers` | Map? | null | Additional host call handlers |
| `entryFunction` | String? | null | Function to call after initial execution |
| `entryInput` | String? | null | Typed JSON input for the entry function |

### Usage

```dart
// From source code
ElpianVmWidget(
  machineId: 'my-app',
  code: r'''
    def title = "Hello from VM!"
    def view = {
      "type": "Column",
      "children": [
        { "type": "h1", "props": { "text": title } },
        { "type": "p", "props": { "text": "Rendered by the VM sandbox." } }
      ]
    }
    askHost("render", view)
  ''',
)

// From AST JSON
ElpianVmWidget.fromAst(
  machineId: 'my-app',
  astJson: '{"type":"program","body":[...]}',
)

// With stylesheet and custom handlers
ElpianVmWidget(
  machineId: 'themed-app',
  code: vmCode,
  stylesheet: {
    'rules': [
      {'selector': '.card', 'styles': {'padding': '16', 'borderRadius': '8'}}
    ]
  },
  hostHandlers: {
    'fetchData': (apiName, payload) async {
      final data = await myApi.fetch(payload);
      return '{"type": "string", "data": {"value": "$data"}}';
    },
  },
  onPrintln: (msg) => print('VM: $msg'),
)
```

---

## Event Bridging: VM ↔ Flutter

The VM and Flutter communicate events through two mechanisms:

### 1. Dart → VM: `callFunction` / `callFunctionWithInput`

Flutter code can invoke named functions inside the running VM. This is how UI events (button clicks, input changes, etc.) trigger VM-side logic.

```dart
// Simple call (no arguments)
await vm.callFunction('increment');

// Call with typed JSON input
await vm.callFunctionWithInput('handleClick', '''
  {"type": "object", "data": {"value": {
    "x": {"type": "f32", "data": {"value": 100.5}},
    "y": {"type": "f32", "data": {"value": 200.3}}
  }}}
''');
```

The VM function receives the input as its first parameter and can use `askHost("render", ...)` to update the UI:

```
// VM source code
def count = 0

func increment() {
  count = count + 1
  askHost("render", buildView())
}

func buildView() {
  return {
    "type": "Column",
    "children": [
      { "type": "Text", "props": { "data": count } },
      { "type": "Button", "props": { "text": "Add" } }
    ]
  }
}

askHost("render", buildView())
```

### 2. VM → Dart: Host Calls

The VM sends data to Dart through `askHost`. The four built-in host APIs are:

| Host API | Direction | Purpose |
|----------|-----------|---------|
| `render` | VM → Dart | Send JSON view tree for rendering |
| `updateApp` | VM → Dart | Send state updates to the Dart side |
| `println` | VM → Dart | Print debug messages |
| `stringify` | VM → Dart | Convert a value to string |

Custom host APIs can be registered:

```dart
ElpianVmWidget(
  machineId: 'my-app',
  code: vmCode,
  hostHandlers: {
    'saveData': (apiName, payload) async {
      await database.save(jsonDecode(payload));
      return '{"type": "bool", "data": {"value": true}}';
    },
    'navigate': (apiName, payload) async {
      Navigator.of(context).pushNamed(payload);
      return '{"type": "i16", "data": {"value": 0}}';
    },
  },
)
```

### Event Flow Diagram

```
┌──────────────────────────────────────────────────────────┐
│ Flutter Side                                             │
│                                                          │
│  User taps button                                        │
│       │                                                  │
│       ▼                                                  │
│  ElpianVmWidget.callVmFunction("increment")              │
│       │                                                  │
│       ▼                                                  │
│  ElpianVm.callFunction("increment")                      │
│       │                                                  │
└───────┼──────────────────────────────────────────────────┘
        │  FFI / WASM
┌───────┼──────────────────────────────────────────────────┐
│       ▼                                                  │
│  Rust VM: Execute "increment" function                   │
│       │                                                  │
│       ▼                                                  │
│  VM: askHost("render", updatedView)                      │
│       │  (VM pauses)                                     │
│       │                                                  │
└───────┼──────────────────────────────────────────────────┘
        │
┌───────┼──────────────────────────────────────────────────┐
│       ▼                                                  │
│  Dart: HostHandler.handleRender(viewJson)                │
│       │                                                  │
│       ▼                                                  │
│  setState() → ElpianEngine.renderFromJson(viewJson)      │
│       │                                                  │
│       ▼                                                  │
│  Flutter rebuilds widget tree with new view               │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## ElpianVmController

`ElpianVmController` provides programmatic access to a running VM from ancestor widgets. Use it with `ElpianVmScope` to call VM functions from outside the widget.

### Usage

```dart
class MyPage extends StatefulWidget {
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  final _vmController = ElpianVmController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Button outside the VM widget tree
        ElevatedButton(
          onPressed: () {
            _vmController.callFunction('increment');
          },
          child: Text('Increment from Dart'),
        ),
        // The VM widget
        Expanded(
          child: ElpianVmScope(
            controller: _vmController,
            machineId: 'counter-app',
            code: counterVmCode,
          ),
        ),
      ],
    );
  }
}
```

### Controller API

| Method | Parameters | Description |
|--------|-----------|-------------|
| `callFunction` | `funcName`, `input?` | Call a VM function with optional typed JSON input |

---

## Typed JSON Input Format for Events

When passing event data to VM functions via `callFunctionWithInput`, use the typed value format:

### Passing a Click Position

```json
{
  "type": "object",
  "data": {
    "value": {
      "x": { "type": "f64", "data": { "value": 150.0 } },
      "y": { "type": "f64", "data": { "value": 230.5 } },
      "button": { "type": "i16", "data": { "value": 0 } }
    }
  }
}
```

### Passing a Text Input Value

```json
{
  "type": "string",
  "data": { "value": "user typed this" }
}
```

### Passing a Keyboard Event

```json
{
  "type": "object",
  "data": {
    "value": {
      "key": { "type": "string", "data": { "value": "Enter" } },
      "keyCode": { "type": "i32", "data": { "value": 13 } },
      "ctrl": { "type": "bool", "data": { "value": false } },
      "shift": { "type": "bool", "data": { "value": false } }
    }
  }
}
```

### Passing a Selection Index

```json
{
  "type": "i16",
  "data": { "value": 2 }
}
```

---

## Complete Interactive App Example

A counter app with VM state management and Dart-side event wiring:

### VM Code

```
def count = 0

func getView() {
  return {
    "type": "Column",
    "style": { "padding": "24", "gap": "16", "alignItems": "center" },
    "children": [
      {
        "type": "Text",
        "props": { "data": "Count: " + stringify(count) },
        "style": { "fontSize": "32", "fontWeight": "bold" }
      },
      {
        "type": "Row",
        "style": { "gap": "12" },
        "children": [
          {
            "type": "Button",
            "props": { "text": "- Decrease" },
            "style": { "backgroundColor": "#F44336", "color": "white" }
          },
          {
            "type": "Button",
            "props": { "text": "+ Increase" },
            "style": { "backgroundColor": "#4CAF50", "color": "white" }
          }
        ]
      }
    ]
  }
}

func increment() {
  count = count + 1
  askHost("render", getView())
}

func decrement() {
  count = count - 1
  askHost("render", getView())
}

func handleInput(data) {
  def action = data["action"]
  if (action == "increment") {
    increment()
  }
  if (action == "decrement") {
    decrement()
  }
}

askHost("render", getView())
```

### Dart Integration

```dart
ElpianVmWidget(
  machineId: 'counter',
  code: counterCode,
  onUpdateApp: (data) {
    // Handle app-level state changes from VM
    print('App update: $data');
  },
)
```

To trigger actions from Dart, use the controller:

```dart
final controller = ElpianVmController();

// Wire up event handlers
controller.callFunction('increment');
controller.callFunction('decrement');

// Pass structured data
controller.callFunction('handleInput', input: '''
  {"type": "object", "data": {"value": {
    "action": {"type": "string", "data": {"value": "increment"}}
  }}}
''');
```
