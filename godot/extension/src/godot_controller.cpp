/* godot_controller.cpp — reflective op interpreter + Variant marshaling.
 * See godot_controller.h for the protocol and design notes. */

#include "godot_controller.h"
#include "elpian_callable.h"

#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/expression.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/canvas_layer.hpp>
#include <godot_cpp/classes/main_loop.hpp>
#include <godot_cpp/classes/marshalls.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

/* The @GlobalScope constant table (KEY_*, MOUSE_BUTTON_*, ERR_*, PI, …) is
 * GENERATED from godot-cpp's extension_api.json by tools/gen_global_constants.py
 * — complete by construction against the engine dump, never hand-written. */
#if __has_include("gen/global_constants_map.inc")
#include "gen/global_constants_map.inc"
#define ELPIAN_HAS_GLOBAL_CONSTANTS 1
#endif

namespace elpian {

static Dictionary dart_error(const String &msg) {
	Dictionary d;
	d["__dart_error__"] = msg;
	return d;
}

GodotController::GodotController(Node *p_host) :
		host_node(p_host), sink(std::make_shared<CallbackSink>()) {
	sink->ctl = this;
}

GodotController::~GodotController() {
	sink->ctl = nullptr; /* outstanding ElpianCallables become no-ops */
}

/* ---- handles ------------------------------------------------------------ */

int64_t GodotController::register_object(Object *obj) {
	if (obj == nullptr) {
		return 0;
	}
	const uint64_t oid = obj->get_instance_id();
	auto found = reverse.find(oid);
	if (found != reverse.end()) {
		return found->second;
	}
	const int64_t id = next_host_id--;
	Handle h;
	h.object_id = oid;
	RefCounted *rc = Object::cast_to<RefCounted>(obj);
	if (rc != nullptr) {
		h.ref = Ref<RefCounted>(rc); /* hold a reference while bridged */
	}
	if (ctx_sbx != 0) {
		h.owners.push_back(ctx_sbx); /* private to the creating sandbox */
	}
	handles[id] = h;
	reverse[oid] = id;
	return id;
}

/* ---- the node sandbox ------------------------------------------------------ */

Node *GodotController::sandbox_root(String *r_err) {
	if (ctx_sbx == 0) {
		return nullptr;
	}
	String err;
	Object *o = resolve(ctx_sbx, &err);
	Node *root = Object::cast_to<Node>(o);
	if (root == nullptr) {
		*r_err = "sandbox: this VM's root node is gone";
	}
	return root;
}

bool GodotController::sandbox_allows(int64_t handle_id, Object *obj, String *r_err) {
	if (ctx_sbx == 0 || obj == nullptr) {
		return true; /* unrestricted context */
	}
	/* The SceneTree (MainLoop) reaches the whole scene — never sandboxed. */
	if (Object::cast_to<MainLoop>(obj) != nullptr) {
		*r_err = "sandbox: MainLoop is not reachable from a sandboxed VM";
		return false;
	}
	Node *node = Object::cast_to<Node>(obj);
	if (node != nullptr) {
		/* Nodes: containment under the sandbox root. */
		Node *root = sandbox_root(r_err);
		if (root == nullptr) {
			return false;
		}
		if (node == root || root->is_ancestor_of(node)) {
			return true;
		}
		/* A node this VM created but has not parented anywhere yet must stay
		 * reachable, or it could never be mounted into the sandbox at all
		 * (fresh nodes are outside every subtree by definition — the old
		 * containment-only rule made a child VM's very first add_child fail
		 * with a null argument). The attach target is containment-checked
		 * independently, so a detached owned node can only ever be added
		 * inside this VM's own subtree. */
		if (node->get_parent() == nullptr) {
			auto it = handles.find(handle_id);
			if (it != handles.end()) {
				for (int64_t o : it->second.owners) {
					if (o == ctx_sbx) {
						return true;
					}
				}
			}
		}
		*r_err = "sandbox: node is outside this VM's subtree";
		return false;
	}
	/* Non-nodes: ownership. Empty = created unrestricted = shared space. */
	auto it = handles.find(handle_id);
	if (it == handles.end()) {
		*r_err = String("unknown object handle ") + String::num_int64(handle_id);
		return false;
	}
	const std::vector<int64_t> &owners = it->second.owners;
	if (owners.empty()) {
		return true;
	}
	for (int64_t o : owners) {
		if (o == ctx_sbx) {
			return true;
		}
	}
	*r_err = "sandbox: object belongs to another VM (ask its owner to grant it)";
	return false;
}

Object *GodotController::resolve_checked(int64_t handle_id, String *r_err) {
	Object *obj = resolve(handle_id, r_err);
	if (obj == nullptr) {
		return nullptr;
	}
	if (!sandbox_allows(handle_id, obj, r_err)) {
		return nullptr;
	}
	return obj;
}

Object *GodotController::resolve_handle_checked(int64_t handle_id, int64_t sbx, String *r_err) {
	/* Set the sandbox context so resolve_checked applies the same containment
	 * rules as a normal op `ref`, then restore. Single-thread confined like the
	 * rest of the controller. */
	const int64_t saved = ctx_sbx;
	ctx_sbx = sbx;
	Object *obj = resolve_checked(handle_id, r_err);
	ctx_sbx = saved;
	return obj;
}

Object *GodotController::resolve(int64_t handle_id, String *r_err) {
	auto it = handles.find(handle_id);
	if (it == handles.end()) {
		*r_err = String("unknown object handle ") + String::num_int64(handle_id);
		return nullptr;
	}
	Object *obj = ObjectDB::get_instance(it->second.object_id);
	if (obj == nullptr) {
		*r_err = String("object behind handle ") + String::num_int64(handle_id) +
				" has been freed";
		return nullptr;
	}
	return obj;
}

Object *GodotController::resolve_op_ref(const Dictionary &op, String *r_err) {
	if (!op.has("ref")) {
		*r_err = "op is missing 'ref'";
		return nullptr;
	}
	return resolve_checked((int64_t)op["ref"], r_err);
}

void GodotController::drop_handle(int64_t handle_id) {
	auto it = handles.find(handle_id);
	if (it == handles.end()) {
		return;
	}
	reverse.erase(it->second.object_id);
	handles.erase(it);
}

void GodotController::queue_callback(int64_t cb_id, const Array &args) {
	QueuedCallback ev;
	ev.cb_id = cb_id;
	ev.args = args;
	queue.push_back(ev);
}

std::deque<QueuedCallback> GodotController::take_queue() {
	std::deque<QueuedCallback> out;
	out.swap(queue);
	return out;
}

Callable GodotController::make_callable(int64_t cb_id) {
	const uint64_t host_oid = host_node != nullptr ? host_node->get_instance_id() : 0;
	return Callable(memnew(ElpianCallable(sink, host_oid, cb_id)));
}

/* ---- marshaling: wire (parsed JSON) -> engine Variant -------------------- */

Variant GodotController::to_variant(const Variant &wire) {
	switch (wire.get_type()) {
		case Variant::NIL:
		case Variant::BOOL:
		case Variant::INT:
		case Variant::FLOAT:
		case Variant::STRING:
			return wire;
		case Variant::ARRAY: {
			const Array in = wire;
			Array out;
			for (int i = 0; i < in.size(); i++) {
				out.push_back(to_variant(in[i]));
			}
			return out;
		}
		case Variant::DICTIONARY:
			break; /* tagged shapes below */
		default:
			return wire; /* already an engine value (internal callers) */
	}

	const Dictionary d = wire;

	if (d.has("ref") || d.has("obj")) { /* accept either spelling for handles */
		String err;
		/* Sandboxed: an outside node handed as an ARGUMENT is an escape too
		 * (e.g. reparent(outside)) — resolve under the same containment. */
		Object *obj = resolve_checked((int64_t)d.get(d.has("ref") ? "ref" : "obj", 0), &err);
		return obj != nullptr ? Variant(obj) : Variant();
	}
	if (d.has("vec2")) {
		const Array a = d["vec2"];
		return Vector2((double)a[0], (double)a[1]);
	}
	if (d.has("vec2i")) {
		const Array a = d["vec2i"];
		return Vector2i((int64_t)a[0], (int64_t)a[1]);
	}
	if (d.has("vec3")) {
		const Array a = d["vec3"];
		return Vector3((double)a[0], (double)a[1], (double)a[2]);
	}
	if (d.has("vec3i")) {
		const Array a = d["vec3i"];
		return Vector3i((int64_t)a[0], (int64_t)a[1], (int64_t)a[2]);
	}
	if (d.has("vec4")) {
		const Array a = d["vec4"];
		return Vector4((double)a[0], (double)a[1], (double)a[2], (double)a[3]);
	}
	if (d.has("vec4i")) {
		const Array a = d["vec4i"];
		return Vector4i((int64_t)a[0], (int64_t)a[1], (int64_t)a[2], (int64_t)a[3]);
	}
	if (d.has("color")) {
		const Array a = d["color"];
		return Color((double)a[0], (double)a[1], (double)a[2],
				a.size() > 3 ? (double)a[3] : 1.0);
	}
	if (d.has("rect2")) {
		const Array a = d["rect2"];
		return Rect2((double)a[0], (double)a[1], (double)a[2], (double)a[3]);
	}
	if (d.has("rect2i")) {
		const Array a = d["rect2i"];
		return Rect2i((int64_t)a[0], (int64_t)a[1], (int64_t)a[2], (int64_t)a[3]);
	}
	if (d.has("plane")) {
		const Array a = d["plane"];
		return Plane((double)a[0], (double)a[1], (double)a[2], (double)a[3]);
	}
	if (d.has("quat")) {
		const Array a = d["quat"];
		return Quaternion((double)a[0], (double)a[1], (double)a[2], (double)a[3]);
	}
	if (d.has("aabb")) {
		const Array a = d["aabb"];
		return AABB(Vector3((double)a[0], (double)a[1], (double)a[2]),
				Vector3((double)a[3], (double)a[4], (double)a[5]));
	}
	if (d.has("basis")) {
		const Array a = d["basis"];
		Basis b;
		b.rows[0] = Vector3((double)a[0], (double)a[1], (double)a[2]);
		b.rows[1] = Vector3((double)a[3], (double)a[4], (double)a[5]);
		b.rows[2] = Vector3((double)a[6], (double)a[7], (double)a[8]);
		return b;
	}
	if (d.has("xform2d")) {
		const Array a = d["xform2d"];
		return Transform2D((double)a[0], (double)a[1], (double)a[2], (double)a[3],
				(double)a[4], (double)a[5]);
	}
	if (d.has("xform3d")) {
		const Array a = d["xform3d"];
		Basis b;
		b.rows[0] = Vector3((double)a[0], (double)a[1], (double)a[2]);
		b.rows[1] = Vector3((double)a[3], (double)a[4], (double)a[5]);
		b.rows[2] = Vector3((double)a[6], (double)a[7], (double)a[8]);
		return Transform3D(b, Vector3((double)a[9], (double)a[10], (double)a[11]));
	}
	if (d.has("proj")) {
		const Array a = d["proj"];
		Projection p;
		for (int c = 0; c < 4; c++) {
			p.columns[c] = Vector4((double)a[c * 4 + 0], (double)a[c * 4 + 1],
					(double)a[c * 4 + 2], (double)a[c * 4 + 3]);
		}
		return p;
	}
	if (d.has("sname")) {
		return StringName((String)d["sname"]);
	}
	if (d.has("npath")) {
		return NodePath((String)d["npath"]);
	}
	if (d.has("rid")) {
		auto it = rids.find((uint64_t)(int64_t)d["rid"]);
		return it != rids.end() ? Variant(it->second) : Variant(RID());
	}
	if (d.has("int")) {
		return (int64_t)d["int"];
	}
	if (d.has("float")) {
		return (double)d["float"];
	}
	if (d.has("callable")) {
		return make_callable((int64_t)d["callable"]);
	}
	if (d.has("sig")) {
		const Array a = d["sig"];
		String err;
		Object *obj = nullptr;
		if (a.size() > 0 && a[0].get_type() == Variant::DICTIONARY) {
			const Dictionary src = a[0];
			obj = resolve_checked((int64_t)src.get(src.has("ref") ? "ref" : "obj", 0), &err);
		}
		return obj != nullptr ? Variant(Signal(obj, StringName((String)a[1]))) : Variant();
	}
	if (d.has("u8")) {
		return Marshalls::get_singleton()->base64_to_raw((String)d["u8"]);
	}
	if (d.has("i32")) {
		const Array a = d["i32"];
		PackedInt32Array out;
		out.resize(a.size());
		for (int i = 0; i < a.size(); i++) {
			out[i] = (int32_t)(int64_t)a[i];
		}
		return out;
	}
	if (d.has("i64")) {
		const Array a = d["i64"];
		PackedInt64Array out;
		out.resize(a.size());
		for (int i = 0; i < a.size(); i++) {
			out[i] = (int64_t)a[i];
		}
		return out;
	}
	if (d.has("f32")) {
		const Array a = d["f32"];
		PackedFloat32Array out;
		out.resize(a.size());
		for (int i = 0; i < a.size(); i++) {
			out[i] = (float)(double)a[i];
		}
		return out;
	}
	if (d.has("f64")) {
		const Array a = d["f64"];
		PackedFloat64Array out;
		out.resize(a.size());
		for (int i = 0; i < a.size(); i++) {
			out[i] = (double)a[i];
		}
		return out;
	}
	if (d.has("strs")) {
		const Array a = d["strs"];
		PackedStringArray out;
		out.resize(a.size());
		for (int i = 0; i < a.size(); i++) {
			out[i] = (String)a[i];
		}
		return out;
	}
	if (d.has("pv2")) {
		const Array a = d["pv2"];
		PackedVector2Array out;
		out.resize(a.size() / 2);
		for (int i = 0; i + 1 < a.size(); i += 2) {
			out[i / 2] = Vector2((double)a[i], (double)a[i + 1]);
		}
		return out;
	}
	if (d.has("pv3")) {
		const Array a = d["pv3"];
		PackedVector3Array out;
		out.resize(a.size() / 3);
		for (int i = 0; i + 2 < a.size(); i += 3) {
			out[i / 3] = Vector3((double)a[i], (double)a[i + 1], (double)a[i + 2]);
		}
		return out;
	}
	if (d.has("pv4")) {
		const Array a = d["pv4"];
		PackedVector4Array out;
		out.resize(a.size() / 4);
		for (int i = 0; i + 3 < a.size(); i += 4) {
			out[i / 4] = Vector4((double)a[i], (double)a[i + 1], (double)a[i + 2],
					(double)a[i + 3]);
		}
		return out;
	}
	if (d.has("pcol")) {
		const Array a = d["pcol"];
		PackedColorArray out;
		out.resize(a.size() / 4);
		for (int i = 0; i + 3 < a.size(); i += 4) {
			out[i / 4] = Color((double)a[i], (double)a[i + 1], (double)a[i + 2],
					(double)a[i + 3]);
		}
		return out;
	}
	if (d.has("dict")) {
		const Dictionary in = d["dict"];
		Dictionary out;
		const Array keys = in.keys();
		for (int i = 0; i < keys.size(); i++) {
			out[keys[i]] = to_variant(in[keys[i]]);
		}
		return out;
	}
	if (d.has("dictv")) {
		const Array pairs = d["dictv"];
		Dictionary out;
		for (int i = 0; i < pairs.size(); i++) {
			const Array kv = pairs[i];
			out[to_variant(kv[0])] = to_variant(kv[1]);
		}
		return out;
	}

	/* Untagged dictionary: a plain Godot Dictionary (values marshal too). */
	Dictionary out;
	const Array keys = d.keys();
	for (int i = 0; i < keys.size(); i++) {
		out[keys[i]] = to_variant(d[keys[i]]);
	}
	return out;
}

/* ---- marshaling: engine Variant -> wire ----------------------------------- */

static Dictionary tag1(const char *tag, const Variant &v) {
	Dictionary d;
	d[tag] = v;
	return d;
}

Variant GodotController::to_wire(const Variant &value) {
	switch (value.get_type()) {
		case Variant::NIL:
		case Variant::BOOL:
		case Variant::INT:
		case Variant::FLOAT:
		case Variant::STRING:
			return value;
		case Variant::VECTOR2: {
			const Vector2 v = value;
			Array a;
			a.push_back(v.x);
			a.push_back(v.y);
			return tag1("vec2", a);
		}
		case Variant::VECTOR2I: {
			const Vector2i v = value;
			Array a;
			a.push_back((int64_t)v.x);
			a.push_back((int64_t)v.y);
			return tag1("vec2i", a);
		}
		case Variant::VECTOR3: {
			const Vector3 v = value;
			Array a;
			a.push_back(v.x);
			a.push_back(v.y);
			a.push_back(v.z);
			return tag1("vec3", a);
		}
		case Variant::VECTOR3I: {
			const Vector3i v = value;
			Array a;
			a.push_back((int64_t)v.x);
			a.push_back((int64_t)v.y);
			a.push_back((int64_t)v.z);
			return tag1("vec3i", a);
		}
		case Variant::VECTOR4: {
			const Vector4 v = value;
			Array a;
			a.push_back(v.x);
			a.push_back(v.y);
			a.push_back(v.z);
			a.push_back(v.w);
			return tag1("vec4", a);
		}
		case Variant::VECTOR4I: {
			const Vector4i v = value;
			Array a;
			a.push_back((int64_t)v.x);
			a.push_back((int64_t)v.y);
			a.push_back((int64_t)v.z);
			a.push_back((int64_t)v.w);
			return tag1("vec4i", a);
		}
		case Variant::COLOR: {
			const Color c = value;
			Array a;
			a.push_back(c.r);
			a.push_back(c.g);
			a.push_back(c.b);
			a.push_back(c.a);
			return tag1("color", a);
		}
		case Variant::RECT2: {
			const Rect2 r = value;
			Array a;
			a.push_back(r.position.x);
			a.push_back(r.position.y);
			a.push_back(r.size.x);
			a.push_back(r.size.y);
			return tag1("rect2", a);
		}
		case Variant::RECT2I: {
			const Rect2i r = value;
			Array a;
			a.push_back((int64_t)r.position.x);
			a.push_back((int64_t)r.position.y);
			a.push_back((int64_t)r.size.x);
			a.push_back((int64_t)r.size.y);
			return tag1("rect2i", a);
		}
		case Variant::PLANE: {
			const Plane p = value;
			Array a;
			a.push_back(p.normal.x);
			a.push_back(p.normal.y);
			a.push_back(p.normal.z);
			a.push_back(p.d);
			return tag1("plane", a);
		}
		case Variant::QUATERNION: {
			const Quaternion q = value;
			Array a;
			a.push_back(q.x);
			a.push_back(q.y);
			a.push_back(q.z);
			a.push_back(q.w);
			return tag1("quat", a);
		}
		case Variant::AABB: {
			const AABB b = value;
			Array a;
			a.push_back(b.position.x);
			a.push_back(b.position.y);
			a.push_back(b.position.z);
			a.push_back(b.size.x);
			a.push_back(b.size.y);
			a.push_back(b.size.z);
			return tag1("aabb", a);
		}
		case Variant::BASIS: {
			const Basis b = value;
			Array a;
			for (int r = 0; r < 3; r++) {
				a.push_back(b.rows[r].x);
				a.push_back(b.rows[r].y);
				a.push_back(b.rows[r].z);
			}
			return tag1("basis", a);
		}
		case Variant::TRANSFORM2D: {
			const Transform2D t = value;
			Array a;
			for (int c = 0; c < 3; c++) {
				a.push_back(t.columns[c].x);
				a.push_back(t.columns[c].y);
			}
			return tag1("xform2d", a);
		}
		case Variant::TRANSFORM3D: {
			const Transform3D t = value;
			Array a;
			for (int r = 0; r < 3; r++) {
				a.push_back(t.basis.rows[r].x);
				a.push_back(t.basis.rows[r].y);
				a.push_back(t.basis.rows[r].z);
			}
			a.push_back(t.origin.x);
			a.push_back(t.origin.y);
			a.push_back(t.origin.z);
			return tag1("xform3d", a);
		}
		case Variant::PROJECTION: {
			const Projection p = value;
			Array a;
			for (int c = 0; c < 4; c++) {
				a.push_back(p.columns[c].x);
				a.push_back(p.columns[c].y);
				a.push_back(p.columns[c].z);
				a.push_back(p.columns[c].w);
			}
			return tag1("proj", a);
		}
		case Variant::STRING_NAME:
			return tag1("sname", String(value));
		case Variant::NODE_PATH:
			return tag1("npath", String(value));
		case Variant::RID: {
			const RID rid = value;
			rids[(uint64_t)rid.get_id()] = rid;
			return tag1("rid", (int64_t)rid.get_id());
		}
		case Variant::OBJECT: {
			Object *obj = value;
			if (obj == nullptr) {
				return Variant();
			}
			Dictionary d;
			d["obj"] = register_object(obj);
			d["class"] = obj->get_class();
			return d;
		}
		case Variant::CALLABLE:
			/* A host-side Callable has no wire identity the guest could use;
			 * surface an opaque marker (guest-made callables never come back
			 * this way — signal delivery carries the cb id directly). */
			return tag1("callable", (int64_t)0);
		case Variant::SIGNAL: {
			const Signal s = value;
			Array a;
			Object *src = ObjectDB::get_instance(s.get_object_id());
			a.push_back(src != nullptr ? to_wire(Variant(src)) : Variant());
			a.push_back(String(s.get_name()));
			return tag1("sig", a);
		}
		case Variant::DICTIONARY: {
			const Dictionary in = value;
			const Array keys = in.keys();
			bool all_string_keys = true;
			for (int i = 0; i < keys.size(); i++) {
				if (keys[i].get_type() != Variant::STRING &&
						keys[i].get_type() != Variant::STRING_NAME) {
					all_string_keys = false;
					break;
				}
			}
			if (all_string_keys) {
				Dictionary out;
				for (int i = 0; i < keys.size(); i++) {
					out[String(keys[i])] = to_wire(in[keys[i]]);
				}
				return tag1("dict", out);
			}
			Array pairs;
			for (int i = 0; i < keys.size(); i++) {
				Array kv;
				kv.push_back(to_wire(keys[i]));
				kv.push_back(to_wire(in[keys[i]]));
				pairs.push_back(kv);
			}
			return tag1("dictv", pairs);
		}
		case Variant::ARRAY: {
			const Array in = value;
			Array out;
			for (int i = 0; i < in.size(); i++) {
				out.push_back(to_wire(in[i]));
			}
			return out;
		}
		case Variant::PACKED_BYTE_ARRAY:
			return tag1("u8", Marshalls::get_singleton()->raw_to_base64(value));
		case Variant::PACKED_INT32_ARRAY: {
			const PackedInt32Array in = value;
			Array a;
			for (int i = 0; i < in.size(); i++) {
				a.push_back((int64_t)in[i]);
			}
			return tag1("i32", a);
		}
		case Variant::PACKED_INT64_ARRAY: {
			const PackedInt64Array in = value;
			Array a;
			for (int i = 0; i < in.size(); i++) {
				a.push_back(in[i]);
			}
			return tag1("i64", a);
		}
		case Variant::PACKED_FLOAT32_ARRAY: {
			const PackedFloat32Array in = value;
			Array a;
			for (int i = 0; i < in.size(); i++) {
				a.push_back((double)in[i]);
			}
			return tag1("f32", a);
		}
		case Variant::PACKED_FLOAT64_ARRAY: {
			const PackedFloat64Array in = value;
			Array a;
			for (int i = 0; i < in.size(); i++) {
				a.push_back(in[i]);
			}
			return tag1("f64", a);
		}
		case Variant::PACKED_STRING_ARRAY: {
			const PackedStringArray in = value;
			Array a;
			for (int i = 0; i < in.size(); i++) {
				a.push_back(in[i]);
			}
			return tag1("strs", a);
		}
		case Variant::PACKED_VECTOR2_ARRAY: {
			const PackedVector2Array in = value;
			Array a;
			for (int i = 0; i < in.size(); i++) {
				a.push_back(in[i].x);
				a.push_back(in[i].y);
			}
			return tag1("pv2", a);
		}
		case Variant::PACKED_VECTOR3_ARRAY: {
			const PackedVector3Array in = value;
			Array a;
			for (int i = 0; i < in.size(); i++) {
				a.push_back(in[i].x);
				a.push_back(in[i].y);
				a.push_back(in[i].z);
			}
			return tag1("pv3", a);
		}
		case Variant::PACKED_VECTOR4_ARRAY: {
			const PackedVector4Array in = value;
			Array a;
			for (int i = 0; i < in.size(); i++) {
				a.push_back(in[i].x);
				a.push_back(in[i].y);
				a.push_back(in[i].z);
				a.push_back(in[i].w);
			}
			return tag1("pv4", a);
		}
		case Variant::PACKED_COLOR_ARRAY: {
			const PackedColorArray in = value;
			Array a;
			for (int i = 0; i < in.size(); i++) {
				a.push_back(in[i].r);
				a.push_back(in[i].g);
				a.push_back(in[i].b);
				a.push_back(in[i].a);
			}
			return tag1("pcol", a);
		}
		default:
			return Variant();
	}
}

/* ---- constants / expressions / introspection ------------------------------ */

Variant GodotController::lookup_constant(const String &name) {
	ClassDBSingleton *cdb = ClassDBSingleton::get_singleton();
	const int dot = name.find(".");
	if (dot >= 0) {
		const String cls = name.substr(0, dot);
		const String cst = name.substr(dot + 1);
		if (cdb->class_has_integer_constant(cls, cst)) {
			return cdb->class_get_integer_constant(cls, cst);
		}
		return dart_error(String("unknown constant ") + name);
	}
#ifdef ELPIAN_HAS_GLOBAL_CONSTANTS
	{
		const CharString utf8 = name.utf8();
		bool found = false;
		const int64_t v = elpian_lookup_global_constant(utf8.get_data(), found);
		if (found) {
			return v;
		}
	}
#endif
	return dart_error(String("unknown constant ") + name);
}

Variant GodotController::eval_expression(const Dictionary &op) {
	Ref<Expression> expr;
	expr.instantiate();
	PackedStringArray names;
	if (op.has("names")) {
		const Array n = op["names"];
		for (int i = 0; i < n.size(); i++) {
			names.push_back((String)n[i]);
		}
	}
	const Error perr = expr->parse((String)op["expr"], names);
	if (perr != OK) {
		return dart_error(String("expression parse error: ") + expr->get_error_text());
	}
	Array inputs;
	if (op.has("values")) {
		const Array v = op["values"];
		for (int i = 0; i < v.size(); i++) {
			inputs.push_back(to_variant(v[i]));
		}
	}
	Object *base = nullptr;
	if (op.has("base")) {
		String err;
		base = resolve((int64_t)op["base"], &err);
	}
	const Variant result = expr->execute(inputs, base, false);
	if (expr->has_execute_failed()) {
		return dart_error(String("expression failed: ") + expr->get_error_text());
	}
	return to_wire(result);
}

Variant GodotController::class_info(const String &cls) {
	ClassDBSingleton *cdb = ClassDBSingleton::get_singleton();
	if (!cdb->class_exists(cls)) {
		return dart_error(String("unknown class ") + cls);
	}
	Dictionary info;
	info["name"] = cls;
	info["parent"] = String(cdb->get_parent_class(cls));
	info["can_instantiate"] = cdb->can_instantiate(cls);
	info["methods"] = to_wire(cdb->class_get_method_list(cls, true));
	info["properties"] = to_wire(cdb->class_get_property_list(cls, true));
	info["signals"] = to_wire(cdb->class_get_signal_list(cls, true));
	Dictionary constants;
	const PackedStringArray consts = cdb->class_get_integer_constant_list(cls, true);
	for (int i = 0; i < consts.size(); i++) {
		constants[consts[i]] = cdb->class_get_integer_constant(cls, consts[i]);
	}
	info["constants"] = constants;
	Dictionary enums;
	const PackedStringArray enum_names = cdb->class_get_enum_list(cls, true);
	for (int i = 0; i < enum_names.size(); i++) {
		enums[enum_names[i]] = cdb->class_get_enum_constants(cls, enum_names[i], true);
	}
	info["enums"] = to_wire(Variant(enums));
	return to_wire(Variant(info));
}

Dictionary GodotController::audit() {
	ClassDBSingleton *cdb = ClassDBSingleton::get_singleton();
	Engine *engine = Engine::get_singleton();
	const PackedStringArray classes = cdb->get_class_list();
	int64_t methods = 0, properties = 0, signals = 0, constants = 0, instantiable = 0;
	Array unreachable;
	for (int i = 0; i < classes.size(); i++) {
		const String &cls = classes[i];
		if (!cdb->class_exists(cls)) {
			unreachable.push_back(cls); /* cannot happen by construction */
			continue;
		}
		methods += cdb->class_get_method_list(cls, true).size();
		properties += cdb->class_get_property_list(cls, true).size();
		signals += cdb->class_get_signal_list(cls, true).size();
		constants += cdb->class_get_integer_constant_list(cls, true).size();
		if (cdb->can_instantiate(cls)) {
			instantiable++;
		}
	}
	const PackedStringArray singleton_names = engine->get_singleton_list();
	for (int i = 0; i < singleton_names.size(); i++) {
		if (engine->get_singleton(singleton_names[i]) == nullptr) {
			unreachable.push_back(String("singleton ") + singleton_names[i]);
		}
	}
	Dictionary report;
	report["classes"] = (int64_t)classes.size();
	report["instantiable"] = instantiable;
	report["methods"] = methods;
	report["properties"] = properties;
	report["signals"] = signals;
	report["constants"] = constants;
	report["singletons"] = (int64_t)singleton_names.size();
	report["unreachable"] = unreachable;
	return report;
}

/* ---- signal plumbing ------------------------------------------------------ */

Variant GodotController::op_connect(const Dictionary &op, Object *obj) {
	const String signal_name = op["connect"];
	const int64_t cb_id = (int64_t)op["cb"];
	const uint32_t flags = op.has("flags") ? (uint32_t)(int64_t)op["flags"] : 0;
	const Callable callable = make_callable(cb_id);
	const Error err = obj->connect(StringName(signal_name), callable, flags);
	if (err != OK) {
		return dart_error(String("connect failed for signal ") + signal_name);
	}
	const String key = String::num_int64((int64_t)op["ref"]) + "|" + signal_name + "|" +
			String::num_int64(cb_id);
	connections[key] = callable;
	return Variant();
}

Variant GodotController::op_disconnect(const Dictionary &op, Object *obj) {
	const String signal_name = op["disconnect"];
	const int64_t cb_id = (int64_t)op["cb"];
	const String key = String::num_int64((int64_t)op["ref"]) + "|" + signal_name + "|" +
			String::num_int64(cb_id);
	const Callable callable =
			connections.has(key) ? connections[key] : make_callable(cb_id);
	if (obj->is_connected(StringName(signal_name), callable)) {
		obj->disconnect(StringName(signal_name), callable);
	}
	connections.erase(key);
	return Variant();
}

/* ---- lifetime ------------------------------------------------------------- */

Variant GodotController::op_free(const Dictionary &op) {
	const int64_t handle_id = (int64_t)op["free"];
	const String mode = op.has("mode") ? (String)op["mode"] : String("handle");
	String err;
	Object *obj = resolve(handle_id, &err);
	if (mode == "handle" || obj == nullptr) {
		drop_handle(handle_id); /* releases any held Ref — always harmless */
		return Variant();
	}
	/* Destructive modes must stay inside the caller's sandbox. */
	if (!sandbox_allows(handle_id, obj, &err)) {
		return dart_error(err);
	}
	if (mode == "queue") {
		Node *node = Object::cast_to<Node>(obj);
		if (node != nullptr) {
			node->queue_free();
		} else {
			return dart_error("free mode 'queue' requires a Node");
		}
		drop_handle(handle_id);
		return Variant();
	}
	if (mode == "now") {
		const bool is_refcounted = Object::cast_to<RefCounted>(obj) != nullptr;
		drop_handle(handle_id); /* for RefCounted, releasing the Ref may delete */
		if (!is_refcounted) {
			memdelete(obj);
		}
		return Variant();
	}
	return dart_error(String("unknown free mode ") + mode);
}

/* ---- the op interpreter ----------------------------------------------------
 * One uniform dispatcher; every branch is name-driven, so anything ClassDB
 * (present or future) registers is reachable with no per-class code. */

Variant GodotController::exec_op(const Dictionary &op) {
	/* Establish the sandbox context for this op (stamped by the Rust
	 * VmManager; absent for the root VM and for GDScript callers), run the
	 * interpreter, then always restore the unrestricted context so engine-
	 * driven marshaling (signal flushes, input events) stays public. */
	ctx_sbx = op.has("__sbx") ? (int64_t)op["__sbx"] : 0;
	const Variant result = exec_op_inner(op);
	ctx_sbx = 0;
	return result;
}

Variant GodotController::exec_op_inner(const Dictionary &op) {
	ClassDBSingleton *cdb = ClassDBSingleton::get_singleton();

	if (op.has("chk")) {
		/* Containment probe (issued by the VM manager before adopting a child
		 * whose sandbox is the probed node): is this a live Node the CURRENT
		 * context may reach? */
		String err;
		Object *obj = resolve_checked((int64_t)op["chk"], &err);
		return obj != nullptr && Object::cast_to<Node>(obj) != nullptr;
	}

	if (op.has("grant")) {
		/* Share a handle the current context owns with another sandbox. */
		const int64_t handle_id = (int64_t)op["grant"];
		String err;
		Object *obj = resolve_checked(handle_id, &err);
		if (obj == nullptr) {
			return dart_error(err);
		}
		auto it = handles.find(handle_id);
		if (it == handles.end()) {
			return dart_error("grant: unknown handle");
		}
		it->second.owners.push_back((int64_t)op.get("sbx", 0));
		return true;
	}

	if (op.has("new")) {
		const String cls = op["new"];
		if (!cdb->class_exists(cls)) {
			return dart_error(String("unknown class ") + cls);
		}
		if (!cdb->can_instantiate(cls)) {
			return dart_error(String("class ") + cls + " cannot be instantiated");
		}
		const Variant inst = cdb->instantiate(cls);
		Object *obj = inst;
		if (obj == nullptr) {
			return dart_error(String("instantiate returned null for ") + cls);
		}
		if (ctx_sbx != 0 && Object::cast_to<Script>(obj) != nullptr) {
			/* A sandboxed VM minting a Script could attach engine-privileged
			 * code to its nodes — refused. (RefCounted: dropping `inst`
			 * frees it.) */
			return dart_error("sandbox: Script types cannot be instantiated");
		}
		if (ctx_sbx != 0) {
			/* A sandboxed VM's canvas layers are pinned below the platform
			 * shell (layer >= 1): a game must never draw over — or steal
			 * input from — the host app's chrome (HUD, exit button). */
			CanvasLayer *cl = Object::cast_to<CanvasLayer>(obj);
			if (cl != nullptr) {
				cl->set_layer(0);
			}
		}
		const int64_t def = op.has("def") ? (int64_t)op["def"] : 0;
		if (def != 0) {
			Handle h;
			h.object_id = obj->get_instance_id();
			RefCounted *rc = Object::cast_to<RefCounted>(obj);
			if (rc != nullptr) {
				h.ref = Ref<RefCounted>(rc);
			}
			if (ctx_sbx != 0) {
				h.owners.push_back(ctx_sbx);
			}
			handles[def] = h;
			reverse[obj->get_instance_id()] = def;
			return def;
		}
		return register_object(obj);
	}

	if (op.has("singleton")) {
		if (ctx_sbx != 0) {
			return dart_error("sandbox: singletons require the 'scene' permission");
		}
		const String name = op["singleton"];
		Object *obj = Engine::get_singleton()->get_singleton(StringName(name));
		if (obj == nullptr) {
			return dart_error(String("unknown singleton ") + name);
		}
		const int64_t def = op.has("def") ? (int64_t)op["def"] : 0;
		if (def != 0) {
			Handle h;
			h.object_id = obj->get_instance_id();
			handles[def] = h;
			reverse[obj->get_instance_id()] = def;
			return def;
		}
		return register_object(obj);
	}

	/* "self"/"tree" address the hosting node / SceneTree. Without an action
	 * key the op is a pure bind ({"self": true, "def": id} — GD.host()); with
	 * one ({"self": true, "method": "add_child", …} — GD.mount) the addressing
	 * only selects the target and the op must fall through to the action
	 * dispatch below, not short-circuit into a bind that drops the action.
	 * For a sandboxed VM, "self" IS its sandbox root — its whole world —
	 * while "tree" (the SceneTree) needs the whole-scene role. */
	Object *self_target = nullptr;
	if (op.has("tree") || op.has("self")) {
		if (ctx_sbx != 0 && op.has("tree")) {
			return dart_error("sandbox: the SceneTree requires the 'scene' permission");
		}
		Object *obj = nullptr;
		if (op.has("self")) {
			if (ctx_sbx != 0) {
				String err;
				obj = sandbox_root(&err);
				if (obj == nullptr) {
					return dart_error(err);
				}
			} else {
				obj = (Object *)host_node;
			}
		} else {
			obj = host_node != nullptr ? (Object *)host_node->get_tree() : nullptr;
		}
		if (obj == nullptr) {
			return dart_error("no hosting node / scene tree available");
		}
		const bool has_action = op.has("connect") || op.has("disconnect") ||
				op.has("method") || op.has("get") || op.has("set") ||
				op.has("geti") || op.has("seti");
		if (!has_action) {
			const int64_t def = op.has("def") ? (int64_t)op["def"] : 0;
			if (def != 0) {
				Handle h;
				h.object_id = obj->get_instance_id();
				handles[def] = h;
				reverse[obj->get_instance_id()] = def;
				return def;
			}
			return register_object(obj);
		}
		self_target = obj;
	}

	if (op.has("load")) {
		const String path = op["load"];
		const Ref<Resource> res = ResourceLoader::get_singleton()->load(path);
		if (res.is_null()) {
			return dart_error(String("failed to load resource ") + path);
		}
		Object *obj = res.ptr();
		if (ctx_sbx != 0 && Object::cast_to<Script>(obj) != nullptr) {
			return dart_error("sandbox: Script resources cannot be loaded");
		}
		const int64_t def = op.has("def") ? (int64_t)op["def"] : 0;
		if (def != 0) {
			Handle h;
			h.object_id = obj->get_instance_id();
			h.ref = res;
			if (ctx_sbx != 0) {
				h.owners.push_back(ctx_sbx);
			}
			handles[def] = h;
			reverse[obj->get_instance_id()] = def;
			return def;
		}
		return register_object(obj);
	}

	if (op.has("const")) {
		return lookup_constant((String)op["const"]);
	}
	if (op.has("expr")) {
		if (ctx_sbx != 0) {
			/* Expressions reach every @GlobalScope function (including
			 * instance_from_id and resource loaders) — whole-scene only. */
			return dart_error("sandbox: expressions require the 'scene' permission");
		}
		return eval_expression(op);
	}
	if (op.has("static")) {
		if (ctx_sbx != 0) {
			return dart_error("sandbox: static calls require the 'scene' permission");
		}
		/* ClassDB.class_call_static landed in Godot 4.4; reach it reflectively
		 * so this binary (built against 4.3 headers) uses it when the running
		 * engine has it and errors cleanly when it does not. */
		const String target = op["static"];
		const int dot = target.find(".");
		if (dot < 0) {
			return dart_error("static op expects 'Class.method'");
		}
		if (!cdb->has_method(StringName("class_call_static"))) {
			return dart_error("ClassDB.class_call_static requires Godot 4.4+");
		}
		Array call_args;
		call_args.push_back(StringName(target.substr(0, dot)));
		call_args.push_back(StringName(target.substr(dot + 1)));
		if (op.has("args")) {
			const Array in = op["args"];
			for (int i = 0; i < in.size(); i++) {
				call_args.push_back(to_variant(in[i]));
			}
		}
		return to_wire(cdb->callv(StringName("class_call_static"), call_args));
	}
	if (op.has("classes")) {
		return to_wire(Variant(cdb->get_class_list()));
	}
	if (op.has("classinfo")) {
		return class_info((String)op["classinfo"]);
	}
	if (op.has("audit")) {
		return to_wire(Variant(audit()));
	}
	if (op.has("free")) {
		return op_free(op);
	}

	/* Everything below addresses an existing object: the self/tree target
	 * resolved above, or a bridged handle named by "ref". */
	Object *obj = self_target;
	if (obj == nullptr) {
		String err;
		obj = resolve_op_ref(op, &err);
		if (obj == nullptr) {
			return dart_error(err);
		}
	}

	if (op.has("connect")) {
		return op_connect(op, obj);
	}
	if (op.has("disconnect")) {
		return op_disconnect(op, obj);
	}
	if (op.has("method")) {
		const String method_name = op["method"];
		if (ctx_sbx != 0 && method_name == "set_script") {
			return dart_error("sandbox: set_script is not permitted");
		}
		const StringName method = StringName(method_name);
		if (!obj->has_method(method)) {
			return dart_error(String("no method ") + method_name + " on " +
					obj->get_class());
		}
		Array args;
		if (op.has("args")) {
			const Array in = op["args"];
			for (int i = 0; i < in.size(); i++) {
				args.push_back(to_variant(in[i]));
			}
		}
		return to_wire(obj->callv(method, args));
	}
	if (op.has("get")) {
		return to_wire(obj->get(StringName((String)op["get"])));
	}
	if (op.has("set")) {
		const String prop = op["set"];
		if (ctx_sbx != 0 && prop == "script") {
			return dart_error("sandbox: the script property is not writable");
		}
		if (ctx_sbx != 0 && prop == "layer" && Object::cast_to<CanvasLayer>(obj) != nullptr) {
			/* Keep sandboxed canvas layers below the platform shell (>= 1):
			 * a game must never draw over or steal input from host chrome. */
			const int64_t requested = (int64_t)to_variant(op["value"]);
			obj->set(StringName(prop), Variant(requested > 0 ? (int64_t)0 : requested));
			return Variant();
		}
		obj->set(StringName(prop), to_variant(op["value"]));
		return Variant();
	}
	if (op.has("geti")) {
		return to_wire(obj->get_indexed(NodePath((String)op["geti"])));
	}
	if (op.has("seti")) {
		const String path = op["seti"];
		if (ctx_sbx != 0 && (path == "script" || path.begins_with("script:"))) {
			return dart_error("sandbox: the script property is not writable");
		}
		obj->set_indexed(NodePath(path), to_variant(op["value"]));
		return Variant();
	}

	return dart_error("unrecognized op");
}

/* ---- the host-call entry point --------------------------------------------- */

String GodotController::service(const String &api_name, const String &args_json) {
	const Variant parsed = JSON::parse_string(args_json);
	const Array args = parsed.get_type() == Variant::ARRAY ? (Array)parsed : Array();

	Variant reply;
	if (api_name == "godot.op") {
		reply = args.size() > 0 && args[0].get_type() == Variant::DICTIONARY
				? exec_op((Dictionary)args[0])
				: Variant(dart_error("godot.op expects one op dictionary"));
	} else if (api_name == "godot.batch") {
		Array results;
		if (args.size() > 0 && args[0].get_type() == Variant::ARRAY) {
			const Array ops = args[0];
			for (int i = 0; i < ops.size(); i++) {
				results.push_back(ops[i].get_type() == Variant::DICTIONARY
								? exec_op((Dictionary)ops[i])
								: Variant(dart_error("batch entries must be op dictionaries")));
			}
		}
		reply = results;
	} else {
		reply = Variant(); /* unknown godot.* name -> null */
	}
	return JSON::stringify(reply);
}

} // namespace elpian
