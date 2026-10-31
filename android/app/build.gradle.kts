import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties (never committed).
// See docs/PRODUCTION_SETUP.md. Without it, release builds fall back to the
// debug key so `flutter run --release` still works locally; such builds
// cannot be uploaded to Google Play.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

// Values from --dart-define / --dart-define-from-file (release.json). Flutter
// passes them to Gradle base64-encoded.
val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as String?)
    .orEmpty()
    .split(",")
    .filter { it.isNotEmpty() }
    .map { String(Base64.getDecoder().decode(it)) }
    .associate { it.substringBefore("=") to it.substringAfter("=") }

// AdMob app ID. Defaults to Google's public sample app ID for local builds.
val admobAppId: String = dartDefines["ADMOB_APP_ID_ANDROID"]
    ?: "ca-app-pub-3940256099942544~3347511713"

// A Play bundle must never go out with the debug key, Google's sample ads or,
// by accident, no ads at all. `ADS_DISABLED=true` is the deliberate ad-free
// release. See docs/PRODUCTION_SETUP.md.
if (gradle.startParameter.taskNames.any { it.endsWith("bundleRelease") }) {
    val samplePublisher = "3940256099942544"
    val publisher = Regex("^ca-app-pub-(\\d+)[~/]\\d+$")
    fun publisherOf(key: String) = publisher.find(dartDefines[key].orEmpty())?.groupValues?.get(1)

    val problems = buildList {
        if (!hasReleaseKey) add("android/key.properties is missing (upload key)")
        if (dartDefines["ADS_DISABLED"] != "true") {
            val keys = listOf(
                "ADMOB_APP_ID_ANDROID",
                "ADMOB_REWARDED_ANDROID",
                "ADMOB_INTERSTITIAL_ANDROID",
            )
            val publishers = keys.map { key ->
                val id = publisherOf(key)
                if (id == null) add("$key is missing or malformed in release.json")
                if (id == samplePublisher) add("$key is one of Google's sample IDs")
                id
            }
            if (publishers.filterNotNull().toSet().size > 1) {
                add("the AdMob IDs in release.json belong to different publishers")
            }
        }
    }
    if (problems.isNotEmpty()) {
        throw GradleException(
            "Not a valid Play release:\n" + problems.joinToString("\n") { " - $it" } +
                "\nBuild with: flutter build appbundle --dart-define-from-file=release.json",
        )
    }
}

android {
    // Choose your permanent package name before the first Play upload; it
    // can never change afterwards. See docs/PRODUCTION_SETUP.md.
    namespace = "com.boomforge.game"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.boomforge.game"
        // google_mobile_ads requires API 24+.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAppId"] = admobAppId
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

// Firebase: add android/app/google-services.json from the Firebase console
// (docs/FIREBASE_SETUP.md). Without it the build still works and the game
// keeps local saves only.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}
