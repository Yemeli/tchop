plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cm.tchop.app"
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
        applicationId = "cm.tchop.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One codebase, four role-specific binaries. Each flavor gets its own
    // applicationId suffix and OS-visible app name; the Dart entrypoint is
    // chosen with `-t lib/main_<flavor>.dart`.
    //
    //   flutter run   --flavor customer -t lib/main_customer.dart
    //   flutter build apk --flavor driver -t lib/main_driver.dart --split-per-abi
    flavorDimensions += "role"
    productFlavors {
        create("customer") {
            dimension = "role"
            applicationIdSuffix = ".customer"
            versionNameSuffix = "-customer"
            resValue("string", "app_name", "Tchop")
        }
        create("driver") {
            dimension = "role"
            applicationIdSuffix = ".driver"
            versionNameSuffix = "-driver"
            resValue("string", "app_name", "Tchop Driver")
        }
        create("kitchen") {
            dimension = "role"
            applicationIdSuffix = ".kitchen"
            versionNameSuffix = "-kitchen"
            resValue("string", "app_name", "Tchop Kitchen")
        }
        create("manager") {
            dimension = "role"
            applicationIdSuffix = ".manager"
            versionNameSuffix = "-manager"
            resValue("string", "app_name", "Tchop Manager")
        }
    }

    buildTypes {
        release {
            // TODO: configure signing with key.properties for store releases.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
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
