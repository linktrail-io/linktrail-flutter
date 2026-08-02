import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing values live (untracked) in android/local.properties as KICKFLIP_UPLOAD_*.
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingProp(name: String): String? =
    (localProps.getProperty(name) ?: System.getenv(name))?.takeIf { it.isNotBlank() }
val hasReleaseKeystore = signingProp("KICKFLIP_UPLOAD_STORE_FILE") != null

android {
    namespace = "io.linktrail.linktrail_flutter_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Registered in the LinkTrail dashboard — this is what the SDK reports to the backend.
        applicationId = "io.linktrail.example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                // Resolve relative to android/ (where local.properties + the keystore live);
                // an absolute path is used as-is.
                storeFile = rootProject.file(signingProp("KICKFLIP_UPLOAD_STORE_FILE")!!)
                storePassword = signingProp("KICKFLIP_UPLOAD_STORE_PASSWORD")
                keyAlias = signingProp("KICKFLIP_UPLOAD_KEY_ALIAS")
                keyPassword = signingProp("KICKFLIP_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Sign with the release keystore when its KICKFLIP_UPLOAD_* values are present in
            // local.properties; otherwise fall back to debug signing so `flutter run --release`
            // and CI still work without a keystore.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
