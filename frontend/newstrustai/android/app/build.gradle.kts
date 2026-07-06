plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.newstrustai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Must match the package_name in google-services.json and the Firebase
        // Android app registration (com.example.fyp_proj) so Google Sign-In's
        // package + SHA-1 validation succeeds. namespace stays as the code package.
        applicationId = "com.example.fyp_proj"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug key — fine for sideloading / sharing (not Play Store).
            signingConfig = signingConfigs.getByName("debug")
            // Disable R8 minification/shrinking: google_mlkit_text_recognition
            // references optional CJK/Devanagari recognizers that aren't bundled,
            // which makes R8 fail. Skipping shrinking avoids that and makes the
            // release build behave like the (working) debug build.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
