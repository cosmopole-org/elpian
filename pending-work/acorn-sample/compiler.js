
let acorn = require("acorn");
var jsx = require("acorn-jsx");
const fs = require('fs');

let parser = acorn.Parser.extend(jsx());

let code = `
    function log(data) {
        askHost("log", data);
    }
    function delayed(callable, delay) {
        askHost("timer.delayed", { "callable": callable, "time": delay });
    }
    function periodic(callable, interval) {
        askHost("timer.periodic", { "callable": callable, "time": interval });
    }
    function stringify(data) {
        return askHost("stringify", data);
    }
    function render(ui) {
        askHost("render", { "html": ui });
    }
    function Text(props) {
        return { type: "text", content: props.content };
    }
    function Input(props) {
        return { type: "input", key: props.key, label: props.label, onChange: props.onChange };
    }
    function Image(props) {
        return { type: "image", url: props.url };
    }
    function Array(props) {
        return { type: "array", items: props.items, orientation: props.orientation };
    }
    function Container(props) {
        return { type: "glassContainer", child: props.child, padding: props.padding };
    }
    function Button(props) {
        return { type: "button", label: props.label, onPress: props.onPress };
    }

    let display = "";
    let op2 = 0;
    let op1 = 0;
    let result = 0;

    function rerender() {
        render(Calculator());
    }

    function onSum() {
        if (display != "") {
            op2 = cast(display, "i64");
            op1 = op1 + op2;
            result = op1;
            display = "";
            rerender();
        }
    }

    function onSub() {
        if (display != "") {
            op2 = cast(display, "i64");
            op1 = op1 - op2;
            result = op1;
            display = "";
            rerender();
        }
    }

    function onMul() {
        if (display != "") {
            op2 = cast(display, "i64");
            op1 = op1 * op2;
            result = op1;
            display = "";
            rerender();
        }
    }

    function on1() {
        display = display + "1";
        rerender();
    }

    function on2() {
        display = display + "2";
        rerender();
    }

    function on3() {
        display = display + "3";
        rerender();
    }

    function on4() {
        display = display + "4";
        rerender();
    }

    function on5() {
        display = display + "5";
        rerender();
    }

    function on6() {
        display = display + "6";
        rerender();
    }

    function on7() {
        display = display + "7";
        rerender();
    }

    function on8() {
        display = display + "8";
        rerender();
    }

    function on9() {
        display = display + "9";
        rerender();
    }

    let hour = 0;
    let minute = 0;
    let second = 0;

    let on = false;
    let color = "primary";

    function onButtonPress() {
        if (on) {
            log("on was true !");
            on = false;
            color = "primary";
        } else {
            log("on was false !");
            on = true;
            color = "secondary";
        }
        render(Calculator());
    }
    
    function Calculator() {
        return (
            <elevatedButton
                style={{ backgroundColor: color, foregroundColor: "#FFFFFF" }}
                onPressed={{ actionType: "event", appId: meta.appId, key: onButtonPress, args: [] }}
            >
                Click Me !
            </elevatedButton>
        );
    }
    function recheckTime() {
        second = second + 1;
        if (second >= 60) {
            second = 0;
            minute = minute + 1;
        }
        if (minute >= 60) {
            minute = 0;
            hour = hour + 1;
        }
        if (hour >= 12) {
            hour = 0;
        }
        render(Calculator());
    }

    render(Calculator());

    // periodic(recheckTime, 1000);
`;

let parsed = parser.parse(code, { ecmaVersion: 2020 });

console.log(JSON.stringify(parsed, null, 2));

function resolve(unit) {
    if (typeof unit === 'object') {
        if (unit.type === "JSXElement") {
            let r = {
                "type": "object",
                "data": {
                    "value": {
                        "type": {
                            "type": "string",
                            "data": {
                                "value": unit.openingElement.name.name,
                            },
                        },
                        "child": {
                            "type": "object",
                            "data": {
                                "value": {
                                    "type": {
                                        "type": "string",
                                        "data": {
                                            "value": "container"
                                        }
                                    }
                                }
                            },
                        },
                        "children": {
                            "type": "array",
                            "data": {
                                "value": []
                            }
                        }
                    }
                }
            };
            unit.openingElement.attributes.forEach(attr => {
                r.data.value[attr.name.name] = resolve(attr.value);
            });
            if (unit.children.length <= 3) {
                r.data.value.child = resolve(unit.children.length > 1 ? unit.children[1] : unit.children[0]);
            }
            unit.children.forEach(child => {
                r.data.value.children.data.value.push(resolve(child));
            });
            return r;
        } else if (unit.type === "JSXExpressionContainer") {
            return resolve(unit.expression);
        } else if (unit.type === "JSXText") {
            return {
                "type": "object",
                "data": {
                    "value": {
                        "type": {
                            "type": "string",
                            "data": {
                                "value": "text"
                            }
                        },
                        "data": {
                            "type": "string",
                            "data": {
                                "value": unit.value.trim()
                            }
                        },
                    }
                }
            };
        } else if (unit.type === "ArrowFunctionExpression") {
            return {
                "type": "callback",
                "data": {
                    "params": unit.params.map(p => p.name),
                    "body": unit.body.type === "BlockStatement" ? transform(unit.body) : [{
                        "type": "returnOperation",
                        "data": {
                            "value": resolve(unit.body)
                        }
                    }]
                }
            };
        } else if (unit.type === "Identifier") {
            return {
                "type": "identifier",
                "data": {
                    "name": unit.name
                }
            };
        } else if (unit.type === "ObjectExpression") {
            let r = {};
            unit.properties.forEach(p => {
                r[p.key.type === "Literal" ? p.key.value : p.key.name] = resolve(p.value);
            });
            return {
                "type": "object",
                "data": {
                    "value": r
                }
            };
        } else if (unit.type === "ArrayExpression") {
            return {
                "type": "array",
                "data": {
                    "value": unit.elements.map(e => resolve(e))
                }
            };
        } else if (unit.type === "MemberExpression") {
            return {
                "type": "indexer",
                "data": {
                    "target": resolve(unit.object),
                    "index": unit.property.type === "Literal" ? resolve(unit.property) : {
                        "type": "string",
                        "data": {
                            "value": unit.property.name
                        }
                    }
                }
            };
        } else if (unit.type === "CallExpression") {
            let id = resolve(unit.callee);
            if (id.data.name === "cast") {
                return {
                    "type": "cast",
                    "data": {
                        "value": resolve(unit.arguments[0]),
                        "targetType": unit.arguments[1].value
                    }
                };
            } else {
                return {
                    "type": "functionCall",
                    "data": {
                        "callee": id,
                        "args": unit.arguments.map(a => resolve(a)),
                    }
                };
            }
        } else if (unit.type === "AssignmentExpression") {
            return {
                "type": "assignment",
                "data": {
                    "leftSide": resolve(unit.left),
                    "rightSide": resolve(unit.right),
                }
            };
        } else if (unit.type === "BinaryExpression") {
            return {
                "type": "arithmetic",
                "data": {
                    "operand1": resolve(unit.left),
                    "operand2": resolve(unit.right),
                    "operation": unit.operator
                }
            };
        } else if (unit.type === "TemplateLiteral") {
            if (unit.quasis && (unit.quasis[0].type === "TemplateElement")) {
                return {
                    "type": "string",
                    "data": {
                        "value": unit.quasis[0].value.cooked
                    }
                };
            }
        } else if (unit.type === "Literal") {
            if (typeof unit.value === 'number') {
                try {
                    let r = Number.parseInt(unit.value);
                    return {
                        "type": "i64",
                        "data": {
                            "value": r
                        }
                    };
                } catch (ex) {
                    let r = Number.parseFloat(unit.value);
                    return {
                        "type": "f64",
                        "data": {
                            "value": r
                        }
                    };
                }
            } else if (typeof unit.value === 'boolean') {
                return {
                    "type": "bool",
                    "data": {
                        "value": unit.value
                    }
                };
            } else {
                if (typeof unit.value === 'string') {
                    return {
                        "type": "string",
                        "data": {
                            "value": unit.value
                        }
                    };
                }
            }
        }
    }
}

function transform(ast) {
    let result = [];
    for (let i = 0; i < ast.body.length; i++) {
        let item = ast.body[i];
        if (item.type === "ReturnStatement") {
            result.push({
                "type": "returnOperation",
                "data": {
                    "value": resolve(item.argument)
                }
            });
        } else if (item.type === "FunctionDeclaration") {
            result.push({
                "type": "functionDefinition",
                "data": {
                    "name": item.id.name,
                    "params": item.params.map(p => p.name),
                    "body": transform(item.body)
                }
            });
        } else if (item.type === "IfStatement") {
            let res = {
                "type": "ifStmt",
                "data": {
                    "condition": resolve(item.test),
                    "body": transform(item.consequent)
                }
            };
            while (true) {
                if (item.alternate) {
                    if (item.alternate.type === "IfStatement") {
                        res.data.elseStmt = {
                            "type": "elseifStmt",
                            "data": {
                                "condition": resolve(item.test),
                                "body": transform(item.alternate.consequent)
                            }
                        };
                        item = item.alternate;
                    } else {
                        res.data.elseStmt = {
                            "type": "elseStmt",
                            "data": {
                                "body": transform(item.alternate)
                            }
                        };
                        break;
                    }
                } else {
                    break;
                }
            }
            result.push(res);
        } else if (item.type === "WhileStatement") {
            result.push({
                "type": "ifStmt",
                "data": {
                    "condition": resolve(item.test),
                    "body": transform(item.body)
                }
            });
        } else if (item.type === "ExpressionStatement") {
            let expr = item.expression;
            result.push(resolve(expr));
        } else if (item.type === "VariableDeclaration") {
            for (let j = 0; j < item.declarations.length; j++) {
                let decl = item.declarations[j];
                if (decl.type === "VariableDeclarator") {
                    result.push({
                        "type": "definition",
                        "data": {
                            "leftSide": resolve(decl.id),
                            "rightSide": resolve(decl.init)
                        }
                    });
                }
            }
        }
    }
    return result;
}

let transformed = transform(parsed);

let output = JSON.stringify(transformed, null, 2);

fs.writeFileSync("../../assets/output.txt", output, { encoding: 'utf8' });

console.log("done !");
