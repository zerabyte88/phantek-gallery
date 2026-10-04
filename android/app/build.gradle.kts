import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Signing ─────────────────────────────────────────────────────────────────
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.phantek.virgo.spica"
    compileSdk = 37          // API 37 – required to build against Android 16 APIs
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias     = keystoreProperties["keyAlias"]     as String
                keyPassword  = keystoreProperties["keyPassword"]  as String
                val rawPath = keystoreProperties["storeFile"] as String
                val candidate = file(rawPath)
                storeFile = if (candidate.exists()) candidate else rootProject.file(rawPath)
                storePassword = keystoreProperties["storePassword"] as String
            } else {
                // Consistent release signing fallback so all builds share the exact same key
                val defaultKeystore = file("phantek.jks")
                if (defaultKeystore.exists()) {
                    storeFile     = defaultKeystore
                    storePassword = "phantek123"
                    keyAlias      = "phantek"
                    keyPassword   = "phantek123"
                }
            }
        }
    }

    defaultConfig {
        applicationId   = "com.phantek.virgo.spica"
        minSdk = flutter.minSdkVersion          // Android 5.0 – covers all relevant media APIs
        targetSdk       = 36          // Android 16
        versionCode     = flutter.versionCode
        versionName     = flutter.versionName

        // Needed for photo_manager / media_kit native bridge
        multiDexEnabled = true
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix   = "-debug"
        }
        release {
            isMinifyEnabled   = false  // keep false – media paths must not be obfuscated
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
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
