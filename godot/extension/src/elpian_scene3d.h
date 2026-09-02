/* elpian_scene3d.h — a Scene3D op-sink node that owns ONLY the reflective
 * GodotController, no Elpian VM.
 *
 * The single Elpian VM lives in the Flutter app and drives everything; Godot is
 * a 3D widget that services the guest's `godot.*` ops. The extension therefore
 * contains the op interpreter but does not embed another VM.
 *
 *   Flutter (owns the Elpian VM) --godot.op--> ElpianScene3D.exec_op_json
 *                                               --> GodotController --> 3D
 */
#ifndef ELPIAN_SCENE3D_H
#define ELPIAN_SCENE3D_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>

#include "godot_controller.h"

namespace elpian {

class ElpianScene3D : public godot::Node {
	GDCLASS(ElpianScene3D, godot::Node)

public:
	ElpianScene3D() = default;
	~ElpianScene3D() override = default;

	void _ready() override;

	/* Service one bridge op (the same JSON op vocabulary the VM emits over
	 * `godot.op`) against this node's subtree, returning its JSON reply. */
	godot::String exec_op_json(const godot::String &op_json);

protected:
	static void _bind_methods();

private:
	std::unique_ptr<GodotController> controller;
	GodotController *ensure_controller();
};

} // namespace elpian

#endif // ELPIAN_SCENE3D_H
