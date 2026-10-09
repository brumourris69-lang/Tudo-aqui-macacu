plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Preserve unflavored production builds and their existing artifact names.
val searchLocalRequested = gradle.startParameter.taskNames.any {
    it.contains("SearchLocal", ignoreCase = true)
} || providers.gradleProperty("search-local").orNull == "true"

android {
    namespace = "br.com.tudoaquimacacu.tudo_aqui_macacu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "br.com.tudoaquimacacu.tudo_aqui_macacu"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    if (searchLocalRequested) {
        flavorDimensions += "environment"
        productFlavors {
            create("searchLocal") {
                dimension = "environment"
                applicationIdSuffix = ".searchlocal"
                versionNameSuffix = "-local"
            }
        }
    }
}

// A local variant has no google-services.json and must never consume the root
// production configuration. Firebase is initialized explicitly with demo IDs.
tasks.configureEach {
    if (name.contains("SearchLocal") && name.endsWith("GoogleServices")) enabled = false
}
if (searchLocalRequested) {
    androidComponents {
        beforeVariants(selector().withFlavor("environment" to "searchLocal")) {
            if (it.buildType != "debug") it.enable = false
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
