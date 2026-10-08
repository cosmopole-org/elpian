# JNI exports of libelpian_vm.so bind to these names.
-keep class dev.elpian.android.vm.ElpianVmNative { native <methods>; }
# QuickJS calls the host interface's methods by name.
-keep interface dev.elpian.android.vm.ElpianJsHost { *; }
# AndroidGodotBinding reaches the Godot bridge by reflection; the engine calls
# ElpianGodotBridge's @UsedByGodot methods by name.
-keep class dev.elpian.godot.** { *; }
