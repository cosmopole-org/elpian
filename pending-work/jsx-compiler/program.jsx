try {
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
            console.log("on was true !");
            on = false;
            color = "primary";
        } else {
            console.log("on was false !");
            on = true;
            color = "secondary";
        }
        render(Calculator());
    }

    function Calculator() {
        return (
            <elevatedButton
                style={{ "backgroundColor": color, "foregroundColor": "#FFFFFF" }}
                onPressed={{ "actionType": "event", "appId": meta.appId, "key": "onButtonPress", "args": [] }}
            >
                {on ? "On !" : "Off !"}
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

    setInterval(() => {
        onButtonPress();
    }, 1000);
} catch (e) {
    console.log("Error in Elpian widget code: " + e);
}