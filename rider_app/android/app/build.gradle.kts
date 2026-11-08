import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Google Maps key lives in android/local.properties, which is gitignored,
// so it never reaches the repository. Add a line to that file:
//
//     MAPS_API_KEY=AIza...
//
// GitHub Actions passes it as the MAPS_API_KEY environment variable instead.
// The build succeeds without it — the map simply renders blank tiles.
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}
val mapsApiKey: String = localProperties.getProperty("MAPS_API_KEY")
    ?: System.getenv("MAPS_API_KEY")
    ?: ""

// Release signing. One key signs every build of the three apps, so an update
// downloaded from GitHub installs over the copy already on the phone. On a
// developer machine it comes from android/key.properties; in GitHub Actions
// from environment variables. Neither the key nor its passwords are ever
// committed: key.properties, *.jks and *.keystore are gitignored.
//
//     storeFile=C:/path/to/yellowribbon-release.jks
//     storePassword=...
//     keyAlias=yellowribbon
//     keyPassword=...
//
// Without a key, release builds fall back to the debug key so that
// `flutter run --release` still works. Such an APK cannot update an install
// signed with the release key, so it must never be handed out.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}
fun releaseSetting(property: String, env: String): String? =
    keyProperties.getProperty(property)?.takeIf { it.isNotBlank() }
        ?: System.getenv(env)?.takeIf { it.isNotBlank() }
val releaseStoreFile: String? = releaseSetting("storeFile", "ANDROID_KEYSTORE_PATH")

android {
    namespace = "com.yellowribbon.rider"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs the java.time backport on older
        // Android versions; without this the build fails outright at
        // checkDebugAarMetadata.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.yellowribbon.rider"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Substituted into the <meta-data> tag in AndroidManifest.xml.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    signingConfigs {
        create("release") {
            if (releaseStoreFile != null) {
                storeFile = file(releaseStoreFile)
                storePassword = releaseSetting("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = releaseSetting("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = releaseSetting("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseStoreFile != null) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("No release key configured: signing the release build with the debug key.")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
