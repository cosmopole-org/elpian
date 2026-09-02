# Op-sink: the embedded engine's content. Each frame it drains the 3D ops the
# Flutter host queued (via the ElpianGodotBridge plugin singleton) and applies
# them to THIS live 3D scene through the reflective GodotController
# (ElpianScene3D.exec_op_json).
#
# ElpianScene3D owns ONLY the op interpreter — no Elpian VM. Godot is just the
# 3D surface servicing the host's ops; the app's logic lives in Flutter (or in
# an Elpian VM there). Embedding a second VM here would be redundant.
#
# Adapted from Victor's React Native op-sink. The engine side is host-agnostic,
# so the only differences are the message shapes the Flutter transport sends
# ({"ops":[…]} batches and {"req":n} reply requests) and replying through
# ElpianGodotBridge.reply().
extends Node3D

var _sink
var _bridge          # Android: the ElpianGodotBridge JNI singleton
var _web := false    # Web: drain the op queue over JavaScriptBridge instead
var _seeded := {}
var _frame := 0
var _first := ""   # raw first op batch (to inspect actual device handles)
const SELF_HANDLE := 1

func _ready() -> void:
	if not ClassDB.class_exists("ElpianScene3D"):
		push_error("ElpianScene3D (elpian_godot GDExtension) not loaded")
		return
	_sink = ClassDB.instantiate("ElpianScene3D")
	add_child(_sink)                                  # in-tree → its children render
	_sink.call("exec_op_json", JSON.stringify({"self": true, "def": SELF_HANDLE}))
	if Engine.has_singleton("ElpianGodotBridge"):
		_bridge = Engine.get_singleton("ElpianGodotBridge")
	elif OS.has_feature("web"):
		# The page (godot/web/elpian_godot_web.js) queues 3D ops on window and
		# drains them over JavaScriptBridge each frame. The glue installs its
		# hooks before booting the engine, so this normally binds immediately;
		# _process re-checks anyway, because deciding the transport once in
		# _ready would strand the sink forever on any other boot order.
		_web = _has_web_bridge()

func _has_web_bridge() -> bool:
	return bool(JavaScriptBridge.eval("typeof window.__elpianGodotDrain === 'function'", true))

func _drain() -> String:
	if _bridge != null:
		return _bridge.pollOps()
	if _web:
		var r = JavaScriptBridge.eval("window.__elpianGodotDrain()", true)
		return str(r) if r != null else ""
	return ""

func _process(_dt: float) -> void:
	if _sink == null:
		return
	if _bridge == null and not _web:
		# Cheap enough once a second; the alternative is a permanently dead sink
		# if the page installed its hooks after the engine came up.
		_frame += 1
		if _frame % 60 == 0 and OS.has_feature("web"):
			_web = _has_web_bridge()
		return
	var json: String = _drain()
	if not json.is_empty():
		if _first == "":
			_first = json.substr(0, 220)
		var msgs = JSON.parse_string(json)
		if typeof(msgs) == TYPE_ARRAY:
			for m in msgs:
				_apply(m)
	# The guest's G3.camera sets current=true BEFORE add_child, which can fail to
	# register the active camera once it enters the tree — leaving the viewport
	# with no camera (renders grey). Force the first camera current each frame.
	_ensure_camera()
	# Report the built scene back to the RN overlay ~1x/sec (Android diagnostics).
	# Call report() directly: Godot Android plugin methods are callable but
	# has_method() returns false for them, so a has_method guard would skip it.
	_frame += 1
	if _frame % 60 == 0 and _bridge != null:
		_bridge.call("report", _summarize())

func _ensure_camera() -> void:
	var cam = _find_camera(_sink)
	if cam != null and not cam.current:
		cam.make_current()

func _find_camera(n: Node):
	if n is Camera3D:
		return n
	for c in n.get_children():
		var r = _find_camera(c)
		if r != null:
			return r
	return null

func _summarize() -> String:
	var total := 0
	var cams := 0
	var cur := 0
	var meshes := 0
	var envs := 0
	var campos := "-"
	var stack: Array = [_sink]
	while not stack.is_empty():
		var n = stack.pop_back()
		total += 1
		if n is Camera3D:
			cams += 1
			if n.current:
				cur += 1
				campos = str(n.global_position)
		if n is MeshInstance3D:
			meshes += 1
		if n is WorldEnvironment:
			envs += 1
		for c in n.get_children():
			stack.push_back(c)
	var vp = get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
	return "nodes=%d cam=%d/%d mesh=%d env=%d vp=%s mounts=%s first=%s" % [total, cur, cams, meshes, envs, str(vp), str(_seeded.keys()), _first]

# A message is one of:
#   {"ops": [ … ]}            a batch of ops (the Flutter transport's normal form)
#   {"ops": [ … ], "req": n}  a batch whose results the host is awaiting
#   {"op": { … }}             a single op (kept for the React Native shape)
#   {"mount": <handle>}       bind a Scene3D surface's root into the scene
#   {"release": <surface>}    the surface's widget went away
func _apply(m: Dictionary) -> void:
	if m.has("mount"):
		var h := int(m["mount"])
		if not _seeded.has(h):
			_seeded[h] = true
			# The host allocates the mount handle and creates its subtree eagerly,
			# so the node and its children already exist here — just re-parent it
			# into the scene so it renders. Creating it again would orphan the
			# host's subtree.
			_sink.call("exec_op_json", JSON.stringify({"ref": SELF_HANDLE, "method": "add_child", "args": [{"ref": h}]}))
	elif m.has("release"):
		# The surface is gone; forget its seed so a remount re-parents cleanly.
		_seeded.erase(int(m["release"]))
	elif m.has("ops"):
		var results: Array = []
		for op in m["ops"]:
			results.append(_exec(op))
		# Only a batch the host is awaiting needs a reply crossing.
		if m.has("req"):
			_reply(int(m["req"]), results)
	elif m.has("op"):
		_exec(m["op"])

# Return one awaited batch's results to the host, over whichever transport is
# bound. On the web there is no bridge singleton to call back through, so the
# reply is handed to the page, which parks it where the Dart side polls.
func _reply(req: int, results: Array) -> void:
	if _bridge != null:
		_bridge.call("reply", req, JSON.stringify(results))
	elif _web:
		# JSON is a subset of JS object literal syntax, so the payload can be
		# embedded in the call expression directly.
		var payload := JSON.stringify({"req": req, "values": results})
		JavaScriptBridge.eval("window.__elpianGodotReply(%s)" % payload, true)

# Apply one op and return its (already unmarshaled) result.
func _exec(op) -> Variant:
	var raw = _sink.call("exec_op_json", JSON.stringify(op))
	if typeof(raw) == TYPE_STRING and raw != "":
		return JSON.parse_string(raw)
	return raw
