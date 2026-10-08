// Android Views renderer and platform for the Kotlin Elpian core.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

// The embedded Godot engine (Scene3D). The Godot library is ~87 MB of native
// code, so it is opt-in: pass `-Pelpian.godot=true`, or put the engine AAR in
// godot/android/libs as godot/README.md describes (the engine itself is then
// resolved from Maven Central, like the Flutter plugin does). The bridge
// sources are the Flutter plugin's own (godot/android: OpQueue,
// ElpianGodotBridge, ElpianGodotFragment) minus its Flutter glue, plus the
// packed op-sink project from its assets. AndroidGodotBinding reaches them by
// reflection, so without Godot this module still builds and reports
// isLive = false.
val godotAndroid: File = rootDir.resolve("../../godot/android")
val elpianGodot: Boolean = (findProperty("elpian.godot") as String?)?.toBoolean()
    ?: (godotAndroid.resolve("libs").listFiles()?.any { it.name.endsWith(".aar") } == true)
val godotSources: File = layout.buildDirectory.dir("generated/elpianGodot/kotlin").get().asFile
val syncGodotSources = tasks.register<Sync>("syncGodotSources") {
    from(godotAndroid.resolve("src/main/kotlin")) {
        include("dev/elpian/godot/OpQueue.kt", "dev/elpian/godot/ElpianGodotBridge.kt", "dev/elpian/godot/ElpianGodotFragment.kt")
    }
    into(godotSources)
}

android {
    namespace = "dev.elpian.android"
    compileSdk = 35
    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Chicory (the WASM engine) is built against Java 11+ library APIs.
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = "17" }
    sourceSets["main"].assets.srcDirs("src/main/assets")
    if (elpianGodot) {
        sourceSets["main"].java.srcDir(godotSources)
        sourceSets["main"].assets.srcDirs(godotAndroid.resolve("src/main/assets"))
    }
    testOptions {
        unitTests.isReturnDefaultValues = true
        unitTests.isIncludeAndroidResources = true
    }
}

if (elpianGodot) tasks.named("preBuild") { dependsOn(syncGodotSources) }

/**
 * Bundles the repository's Material Icons font (native/assets/fonts, the same
 * file the web host ships) as `assets/fonts/MaterialIcons-Regular.ttf`
 * without committing a second copy of the binary.
 */
abstract class CopyElpianFonts : DefaultTask() {
    @get:InputFiles
    abstract val fonts: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val out = outputDir.get().asFile.resolve("fonts")
        out.mkdirs()
        for (f in fonts.files) if (f.isFile) f.copyTo(out.resolve(f.name), overwrite = true)
    }
}

val copyElpianFonts = tasks.register<CopyElpianFonts>("copyElpianFonts") {
    fonts.from(rootProject.file("../assets/fonts/MaterialIcons-Regular.ttf"))
    outputDir.set(layout.buildDirectory.dir("generated/elpian-assets"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(copyElpianFonts, CopyElpianFonts::outputDir)
    }
}

// Chicory's runtime jar minus `ByteArrayMemory`: that opt-in memory uses
// VarHandles, which D8 rejects below minSdk 26 and fails every app dexing the
// jar. Nothing else references it; Chicory's default (and our) memory is
// `ByteBufferMemory`.
val chicoryVersion = "1.7.5"
val chicoryRuntime: Configuration by configurations.creating { isTransitive = false }
val chicoryAndroidJar = tasks.register<Jar>("chicoryAndroidJar") {
    archiveFileName.set("chicory-runtime-android-$chicoryVersion.jar")
    destinationDirectory.set(layout.buildDirectory.dir("chicory"))
    from({ chicoryRuntime.map { zipTree(it) } }) {
        exclude("com/dylibso/chicory/runtime/ByteArrayMemory*.class", "module-info.class", "META-INF/versions/**")
    }
}

dependencies {
    api(project(":elpian-core"))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // Guest sandboxes: QuickJS for JS mini apps, Chicory for WASM.
    implementation("wang.harlon.quickjs:wrapper-android:3.2.3")
    chicoryRuntime("com.dylibso.chicory:runtime:$chicoryVersion")
    implementation(files(chicoryAndroidJar))
    implementation("com.dylibso.chicory:wasm:$chicoryVersion")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.3")
    // Godot (see above); the binding compiles against the fragment API either way.
    if (elpianGodot) {
        implementation("org.godotengine:godot:4.3.0.stable")
        implementation("androidx.fragment:fragment-ktx:1.6.2")
    } else {
        compileOnly("androidx.fragment:fragment:1.6.2")
    }
    testImplementation("junit:junit:4.13.2")
    testImplementation(kotlin("test"))
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
}
