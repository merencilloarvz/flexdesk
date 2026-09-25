import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Reads android/key.properties for release signing credentials. This file
// is gitignored — never hardcode passwords directly in this build script,
// since build.gradle IS committed to git.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.flexdesk.flexdesk"
     compileSdk {
        version = release(37) {
            minorApiLevel = 0
        }
    }
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications on API levels below 26.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.flexdesk.flexdesk"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // Opt-in for local on-device testing against a LAN backend:
    //   FLEXDESK_LAN_TESTING=1 flutter run --release --dart-define=FLEXDESK_API_BASE_URL=http://<ip>:8000/api/v1
    // Swaps in a network config that permits plain http. Without the env
    // var the release build uses the https-only config from src/main.
    if (System.getenv("FLEXDESK_LAN_TESTING") == "1") {
        logger.warn("FLEXDESK_LAN_TESTING=1: release build allows cleartext http. DO NOT SHIP.")
        sourceSets.getByName("release").res.srcDir("src/lanTesting/res")
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}