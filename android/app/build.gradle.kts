plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.love_care_global"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.example.love_care_global"
        minSdk = 23
        targetSdk = 35
        versionCode = flutterVersionCode.toInteger()
        versionName = flutterVersionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // FIX for ML Kit R8 failure:
            // :app:minifyReleaseWithR8 -> Missing class Chinese/Korean/Japanese/Devanagari TextRecognizerOptions
            // ProGuard -dontwarn did NOT suppress this in AGP 8.x - it is a hard R8 error.
            // Turning minify OFF bypasses R8 completely. App will be a bit bigger,
            // but it WILL build. Re-enable minify only after ProGuard is proven to work.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
