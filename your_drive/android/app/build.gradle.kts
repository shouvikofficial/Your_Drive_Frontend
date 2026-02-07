plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle plugin (must stay last)
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.your_drive"

    // ✅ Updated SDK versions
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.your_drive"

        // ✅ Minimum + target must align with compileSdk
        minSdk = flutter.minSdkVersion
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
