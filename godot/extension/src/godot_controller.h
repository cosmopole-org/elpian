/* godot_controller.h — the reflective Godot controller the Elpian VM drives.
 *
 * This is the native half of Elpian's Scene3D bridge. It interprets the
 * uniform "Godot op"
 * protocol — the same paradigm as the CanvasKit/Skia reflective bridge in
 * `web-demo/canvaskit_bridge.js` — so the guest reaches EVERY engine surface
 * by name through ClassDB instead of through per-class wrappers:
 *
 *   {"new": cls, "def": id}                  instantiate any registered class
 *   {"singleton": name, "def": id}           bind any engine singleton
 *   {"tree": true, "def": id}                the SceneTree
 *   {"self": true, "def": id}                the hosting Scene3D node
 *     ("self"/"tree" may also replace "ref" in the action ops below to
 *      address the hosting node / SceneTree directly, e.g. GD.mount's
 *      {"self": true, "method": "add_child", "args": […]})
 *   {"load": path, "def": id}                load any resource
 *   {"ref", "method", "args"}                call any method (Object::callv)
 *   {"ref", "get"} / {"ref","set","value"}   any property
 *   {"ref", "geti"} / {"ref","seti","value"} any indexed sub-property path
 *   {"ref", "connect", "cb", "flags"}        any signal -> Dart closure
 *   {"ref", "disconnect", "cb"}              undo a connect
 *   {"free": id, "mode": handle|queue|now}   handle / queue_free / memdelete
 *   {"const": "Class.NAME" | "GLOBAL_NAME"}  any class/global constant or enum
 *   {"expr", "names", "values", "base"?}     evaluate any Godot Expression
 *   {"static": "Class.method", "args"}       ClassDB.class_call_static (4.4+)
 *   {"classes": true} / {"classinfo": cls}   full ClassDB introspection
 *   {"audit": true}                          machine-checked coverage report
 *   {"chk": handle}                          containment probe: is handle a
 *                                            Node inside the op's sandbox?
 *   {"grant": handle, "sbx": target}         share a handle with a sandbox
 *
 * plus `godot.batch` (an array of ops -> array of results, ONE seam crossing).
 *
 * ## The multi-VM node sandbox ("__sbx")
 *
 * The Rust VmManager stamps every op forwarded from a sandboxed VM with
 * `"__sbx": <handle of the VM's assigned root node>` (the key is stripped
 * from guest input first — it cannot be forged). Under a non-zero sandbox:
 *
 *   * object references only resolve to Nodes INSIDE the sandbox root's
 *     subtree (root included) — a parent VM can therefore reach into its
 *     children's node trees (they are inside its own sandbox by
 *     construction) while a child can never address outward, even with a
 *     handle it obtained (e.g. from get_parent());
 *   * non-Node objects (resources, refcounted helpers) resolve only if the
 *     handle was created by the same sandbox, was created by an
 *     unrestricted context (host/root — the shared "inter-VM space"), or
 *     was explicitly shared via the "grant" op;
 *   * MainLoop-derived objects (the SceneTree) never resolve;
 *   * {"self"} binds the sandbox root, not the hosting Scene3D node —
 *     GD.host()/GD.mount() then operate on the VM's own world;
 *   * whole-scene ops are refused: tree / singleton / expr / static;
 *   * script injection is refused: set_script calls, script property
 *     writes, and instantiating/loading Script-derived types.
 *
 * Ops without "__sbx" (the root VM, GDScript callers) are unrestricted.
 *
 * Value marshaling covers every Variant shape both directions (vectors,
 * transforms, colors, rects, packed arrays, dictionaries, node paths, string
 * names, RIDs, objects, callables, signals) via small tagged JSON objects;
 * Objects never cross the seam — 64-bit handles do (guest-chosen ids are
 * positive, host-assigned ids negative, zero never valid).
 *
 * Reentrancy: while the VM is paused inside an op, a call that synchronously
 * fires a connected signal cannot re-enter the VM; bridged Callables therefore
 * QUEUE their invocation (cb id + marshaled args) for the host transport to
 * flush at a frame boundary.
 */
#ifndef ELPIAN_GODOT_CONTROLLER_H
#define ELPIAN_GODOT_CONTROLLER_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <deque>
#include <memory>
#include <unordered_map>
#include <vector>

namespace elpian {

class GodotController;

/* A queued guest-callback invocation (bridged signal emission or Callable
 * call), delivered as `__godotDispatch([cb_id, [args…]])` on the next flush. */
struct QueuedCallback {
	int64_t cb_id = 0;
	godot::Array args;
};

/* Liveness anchor shared with every ElpianCallable the controller mints: the
 * engine may hold a bridged Callable longer than the VM node lives, so calls
 * route through this sink and become no-ops once the controller is gone. */
struct CallbackSink {
	GodotController *ctl = nullptr;
};

class GodotController {
public:
	explicit GodotController(godot::Node *host_node);
	~GodotController();

	/* Service one host call from the VM: api_name ∈ {godot.op, godot.batch},
	 * args_json is the JSON argument array. Returns the reply as JSON. */
	godot::String service(const godot::String &api_name, const godot::String &args_json);

	/* Execute one already-parsed op. Errors return {"__dart_error__": …}. */
	godot::Variant exec_op(const godot::Dictionary &op);

	/* Called by bridged callables (any thread-confined signal emission). */
	void queue_callback(int64_t cb_id, const godot::Array &args);

	/* Drain the pending callback queue (returns and clears it). */
	std::deque<QueuedCallback> take_queue();
	bool has_queued() const { return !queue.empty(); }

	/* Marshaling used by the Scene3D host transport. */
	godot::Variant to_variant(const godot::Variant &wire); /* wire -> engine   */
	godot::Variant to_wire(const godot::Variant &value); /*   engine -> wire */

	/* Register (or find) the handle for an engine object. */
	int64_t register_object(godot::Object *obj);

	/* Resolve a handle to an Object under sandbox `sbx` (0 = unrestricted),
	 * applying the same containment/ownership checks as an op's `ref`. Used by
	 * the FlutterController to resolve the Godot node a Flutter view mounts
	 * under, so a sandboxed VM can only mount inside its own subtree. Returns
	 * nullptr (with *r_err set) on failure. */
	godot::Object *resolve_handle_checked(int64_t handle_id, int64_t sbx, godot::String *r_err);

	/* The machine-checked coverage report over the whole of ClassDB. */
	godot::Dictionary audit();

private:
	struct Handle {
		uint64_t object_id = 0; /* ObjectID for liveness checks           */
		godot::Ref<godot::RefCounted> ref; /* keeps RefCounted objects alive */
		/* Sandboxes allowed to use this (non-Node) object: the creating
		 * sandbox plus any added via the "grant" op. Empty = created by an
		 * unrestricted context = shared inter-VM space. Nodes ignore this —
		 * they are governed by subtree containment instead. */
		std::vector<int64_t> owners;
	};

	godot::Node *host_node = nullptr;
	std::shared_ptr<CallbackSink> sink;

	/* Sandbox of the op currently executing (0 = unrestricted). Set from the
	 * op's "__sbx" key on entry to exec_op and cleared on exit; single-thread
	 * confined like everything else here. */
	int64_t ctx_sbx = 0;

	std::unordered_map<int64_t, Handle> handles;
	std::unordered_map<uint64_t, int64_t> reverse; /* ObjectID -> handle id */
	int64_t next_host_id = -1; /* host-assigned ids are negative */

	/* RIDs are opaque (no public raw-id constructor), so both directions go
	 * through this table keyed by RID::get_id(). */
	std::unordered_map<uint64_t, godot::RID> rids;

	/* Live connections: "handle|signal|cb" -> the exact Callable connected,
	 * so disconnect uses an equal value. */
	godot::HashMap<godot::String, godot::Callable> connections;

	std::deque<QueuedCallback> queue;

	godot::Object *resolve(int64_t handle_id, godot::String *r_err);
	godot::Object *resolve_op_ref(const godot::Dictionary &op, godot::String *r_err);
	/* resolve + sandbox enforcement (containment / ownership / MainLoop). */
	godot::Object *resolve_checked(int64_t handle_id, godot::String *r_err);
	/* The current sandbox root node, or nullptr (with r_err) if it is gone. */
	godot::Node *sandbox_root(godot::String *r_err);
	bool sandbox_allows(int64_t handle_id, godot::Object *obj, godot::String *r_err);
	/* The op interpreter proper; exec_op wraps it with sandbox-context setup. */
	godot::Variant exec_op_inner(const godot::Dictionary &op);
	void drop_handle(int64_t handle_id);
	godot::Callable make_callable(int64_t cb_id);
	godot::Variant lookup_constant(const godot::String &name);
	godot::Variant class_info(const godot::String &cls);
	godot::Variant eval_expression(const godot::Dictionary &op);
	godot::Variant op_free(const godot::Dictionary &op);
	godot::Variant op_connect(const godot::Dictionary &op, godot::Object *obj);
	godot::Variant op_disconnect(const godot::Dictionary &op, godot::Object *obj);

	friend class ElpianCallable;
};

} // namespace elpian

#endif /* ELPIAN_GODOT_CONTROLLER_H */
