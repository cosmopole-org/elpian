allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// AGP 8 requires every Android module to declare a `namespace`; plugins written
// before that only set `package` in their AndroidManifest, and configuring the
// project fails outright:
//
//   Namespace not specified. Specify a namespace in the module's build file:
//   .../wasm_run_flutter-0.1.0/android/build.gradle
//
// `wasm_run_flutter` is the one dependency here that predates the requirement,
// and neither published version is usable without help: 0.1.0 omits the
// namespace, and 0.2.0 moved to a Dart native-assets build hook that asks for a
// *static* Android binary whose checksum upstream never published, so a release
// build dies later with
//
//   Sha256 hash for the asset wasm_run_dart-static-armv7-linux-androideabi
//   was not provided
//
// (`buildStatic` is `linkModePreference == static || linkingEnabled`, and
// Flutter enables linking for release builds — so that path cannot succeed at
// all in release). Staying on 0.1.0 and supplying the missing namespace here is
// the half that is actually in our control. Derived from the module's group so
// each plugin keeps a distinct one, and only applied where it is missing, so a
// plugin that declares its own is untouched.
// Configure the extension as soon as the library plugin creates it. Besides
// avoiding an `afterEvaluate` timing dependency, this runs before the root
// script forces `:app` evaluation below. Reached reflectively rather than
// through AGP's typed DSL: the Kotlin DSL is compiled, so naming an AGP type
// here would make this script fail to *compile* on any setup where those
// classes are not on the root build script's classpath. Nothing is assumed
// beyond the property existing.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val android = project.extensions.findByName("android") ?: return@withPlugin
        val get = android.javaClass.methods.firstOrNull {
            it.name == "getNamespace" && it.parameterCount == 0
        }
        val set = android.javaClass.methods.firstOrNull {
            it.name == "setNamespace" && it.parameterCount == 1
        }
        if (get != null && set != null && get.invoke(android) == null) {
            val fallback = project.group.toString().ifEmpty { "dev.elpian.${project.name}" }
            set.invoke(android, fallback)
            logger.lifecycle("elpian: supplied missing AGP namespace '$fallback' for ${project.name}")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
