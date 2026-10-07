group = "com.therivanta.pixelcompressor"
version = "0.3.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

// AGP 9 compiles Kotlin itself ("built-in Kotlin") unless the app opts out
// with android.builtInKotlin=false, which current Flutter templates still
// do. Apply the Kotlin plugin ourselves whenever built-in Kotlin is off, so
// the plugin compiles without relying on the app or Flutter's Gradle plugin
// to apply it.
val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()
val builtInKotlin = agpMajor >= 9 &&
    (findProperty("android.builtInKotlin")?.toString()?.toBooleanStrictOrNull() ?: true)
if (!builtInKotlin && !pluginManager.hasPlugin("org.jetbrains.kotlin.android")) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

extensions.configure<com.android.build.api.dsl.LibraryExtension> {
    namespace = "com.therivanta.pixelcompressor"

    compileSdk = 37

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 28
    }
}

dependencies {
    // Image. exifinterface 1.3.7+ fixes the
    // WebP EXIF writer bugs that keepExif=true on WebP output depends on.
    "implementation"("androidx.exifinterface:exifinterface:1.4.2")
    "implementation"("androidx.heifwriter:heifwriter:1.0.0")

    // Video (Media3 Transformer engine).
    "implementation"("androidx.media3:media3-transformer:1.11.1")
    "implementation"("androidx.media3:media3-effect:1.11.1")
    "implementation"("androidx.media3:media3-common:1.11.1")
}

extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
