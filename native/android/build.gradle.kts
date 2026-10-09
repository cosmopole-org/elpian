plugins {
    id("com.android.library") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.jvm") version "2.0.21" apply false
}

extra["elpianVersion"] = "1.0.0"
extra["elpianRepo"] = (findProperty("elpian.repo") as String?) ?: layout.buildDirectory.dir("repo").get().asFile.absolutePath
