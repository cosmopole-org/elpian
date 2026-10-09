# JNI exports of libelpian_vm.so bind to these names.
-keep class dev.elpian.android.vm.ElpianVmNative { native <methods>; }
# The QuickJS wrapper's native code calls back into its Java classes by name
# (callFunctionBack, the JSObject creators) and the library ships no rules.
-keep class com.whl.quickjs.** { *; }
# AndroidGodotBinding reaches the Godot bridge by reflection; the engine calls
# ElpianGodotBridge's @UsedByGodot methods by name.
-keep class dev.elpian.godot.** { *; }
