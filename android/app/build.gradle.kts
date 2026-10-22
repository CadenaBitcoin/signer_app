plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.app.cadenabitcoin"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // The application ID of the app published on Google Play (Issue #72). It is deliberately
        // different from the Kotlin namespace above: the namespace names the source package
        // (R class, MainActivity) and stays; only the application ID is the app's identity on
        // devices and in Google Play. iOS has its own identifiers (ios/Flutter/Flavor-*.xcconfig).
        applicationId = "com.cadenabitcoin.mobile.signer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Application identity. The flavor selects ONLY the platform identity (application
    // ID and launcher label). The environment (backend, network) is selected by
    // config/build/<environment>.json, and lib/config/build_config.dart fails the build
    // unless the flavor and APP_ENV agree. There is deliberately no default flavor:
    // build with `--flavor staging|production`. See docs/BUILD_CONFIGURATION.md.
    //
    // The per-flavor cmake argument is NOT functional (the CMake project is the empty
    // one Flutter adds only to make AGP download the NDK). Without a difference between
    // the flavors, AGP shares ONE native-build task between them and ties it to a single
    // flavor, so `assembleProductionRelease` would also run the staging Dart compile with
    // the production defines, which the flavor/environment check rightly rejects.
    flavorDimensions += "environment"
    productFlavors {
        // Keeps the existing production identity: defaultConfig's applicationId.
        create("production") {
            dimension = "environment"
            manifestPlaceholders["appLabel"] = "Cadena Bitcoin"
            externalNativeBuild { cmake { arguments("-DCADENA_FLAVOR=production") } }
        }
        // A separate application that installs next to production.
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            manifestPlaceholders["appLabel"] = "Cadena Signer STAGING"
            externalNativeBuild { cmake { arguments("-DCADENA_FLAVOR=staging") } }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // add dependency to enable Device Intelligence
    implementation("com.sumsub.sns:idensic-mobile-sdk-fisherman:1.42.0")
}