/* elpian_scene3d.cpp — see elpian_scene3d.h. A GodotController with no VM. */
#include "elpian_scene3d.h"

#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace elpian {

void ElpianScene3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("exec_op_json", "op_json"), &ElpianScene3D::exec_op_json);
}

GodotController *ElpianScene3D::ensure_controller() {
	if (controller == nullptr) {
		controller = std::make_unique<GodotController>(this);
	}
	return controller.get();
}

void ElpianScene3D::_ready() {
	ensure_controller();
}

String ElpianScene3D::exec_op_json(const String &op_json) {
	GodotController *ctrl = ensure_controller();
	const Variant parsed = JSON::parse_string(op_json);
	if (parsed.get_type() != Variant::DICTIONARY) {
		return "null";
	}
	return JSON::stringify(ctrl->exec_op((Dictionary)parsed));
}

} // namespace elpian
