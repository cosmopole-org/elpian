/* elpian_callable.h — a Godot Callable whose target is a guest closure.
 *
 * Minted by GodotController for two uses that share one mechanism:
 *   1. signal connections (`{"ref", "connect", "cb"}`), and
 *   2. closure arguments (`{"callable": cbId}`) handed to any Godot API that
 *      takes a Callable (Tween.tween_callback, SceneTreeTimer.timeout, …).
 *
 * Invocation QUEUES (cb_id, marshaled args) on the controller instead of
 * re-entering the VM — the VM may be paused mid-op when a synchronous signal
 * fires (see the reentrancy note in godot_controller.h). The host transport
 * flushes the queue into the guest at a frame boundary.
 *
 * Equality is by cb_id, so disconnect can present a freshly-minted equal
 * Callable. A weak_ptr to the controller's CallbackSink makes stale callables
 * harmless no-ops after the Scene3D node is freed.
 */
#ifndef ELPIAN_CALLABLE_H
#define ELPIAN_CALLABLE_H

#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/callable_custom.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <memory>

#include "godot_controller.h"

namespace elpian {

class ElpianCallable : public godot::CallableCustom {
public:
	ElpianCallable(std::weak_ptr<CallbackSink> p_sink, uint64_t p_host_object_id, int64_t p_cb_id) :
			sink(std::move(p_sink)), host_object_id(p_host_object_id), cb_id(p_cb_id) {}

	uint32_t hash() const override {
		return static_cast<uint32_t>(cb_id * 2654435761u + 1);
	}

	godot::String get_as_text() const override {
		return godot::String("ElpianCallable(cb ") + godot::String::num_int64(cb_id) + ")";
	}

	static bool compare_equal(const godot::CallableCustom *p_a, const godot::CallableCustom *p_b) {
		/* The engine only calls this when both sides share this comparator,
		 * which only ElpianCallable installs — the casts are safe. */
		return static_cast<const ElpianCallable *>(p_a)->cb_id ==
				static_cast<const ElpianCallable *>(p_b)->cb_id;
	}

	static bool compare_less(const godot::CallableCustom *p_a, const godot::CallableCustom *p_b) {
		return static_cast<const ElpianCallable *>(p_a)->cb_id <
				static_cast<const ElpianCallable *>(p_b)->cb_id;
	}

	CompareEqualFunc get_compare_equal_func() const override { return compare_equal; }
	CompareLessFunc get_compare_less_func() const override { return compare_less; }

	bool is_valid() const override { return !sink.expired(); }

	godot::ObjectID get_object() const override { return godot::ObjectID(host_object_id); }

	void call(const godot::Variant **p_arguments, int p_argcount, godot::Variant &r_return_value,
			GDExtensionCallError &r_call_error) const override {
		r_call_error.error = GDEXTENSION_CALL_OK;
		r_return_value = godot::Variant();
		std::shared_ptr<CallbackSink> s = sink.lock();
		if (!s || !s->ctl) {
			return; /* VM gone: fire-and-forget no-op */
		}
		godot::Array args;
		for (int i = 0; i < p_argcount; i++) {
			args.push_back(*p_arguments[i]);
		}
		s->ctl->queue_callback(cb_id, args);
	}

	int64_t callback_id() const { return cb_id; }

private:
	std::weak_ptr<CallbackSink> sink;
	uint64_t host_object_id = 0;
	int64_t cb_id = 0;
};

} // namespace elpian

#endif /* ELPIAN_CALLABLE_H */
