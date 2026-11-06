import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Push notifications need Firebase's config file (README "Push notifications").
// Without it the app builds and runs, just without notifications.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Upload key for Google Play, kept out of git (see README "Publish on Google Play").
// Without android/key.properties, release builds are signed with the debug key:
// fine to install on a phone, rejected by Google Play.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasUploadKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = "es.donagalleta.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Google Play identifies the app by this ID: it can never change once published.
        applicationId = "es.donagalleta.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // From `version: x.y.z+N` in pubspec.yaml. Raise N for every upload.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasUploadKey) "upload" else "debug")
        }
    }
}

if (!hasUploadKey) {
    logger.warn("android/key.properties not found: the release build is signed with the debug key and Google Play will reject it.")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
