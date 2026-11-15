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
            // R8 fix: keep minify OFF here.
            // NOTE: if your GitHub workflow runs 'flutter build appbundle --obfuscate',
            // that flag forces R8 ON and ignores this. The 4 ML Kit libs below
            // make R8 pass even then.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // FIX for :app:minifyReleaseWithR8 -> Missing class Chinese/Korean/Japanese/Devanagari TextRecognizerOptions
    // google_mlkit_text_recognition references ALL 4, but only Latin is bundled.
    // Adding them gives R8 the real classes. You only use Latin (Ghana Card/Passport).
    implementation("com.google.mlkit:text-recognition-chinese:16.0.0")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.0")
    implementation("com.google.mlkit:text-recognition-korean:16.0.0")
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.0")
}
