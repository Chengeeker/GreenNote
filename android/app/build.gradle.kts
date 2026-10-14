import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.green.note"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.green.note"
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
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            val keyPropertiesFile = rootProject.file("key.properties")
            val keyProperties = Properties()
            if (keyPropertiesFile.exists()) {
                keyPropertiesFile.inputStream().use { input -> keyProperties.load(input) }
            }
            val keyPath = keyProperties.getProperty("storeFile")
                ?: throw GradleException("Release signing key is not configured")
            signingConfig = signingConfigs.create("release") {
                storeFile = file(keyPath)
                storePassword = keyProperties.getProperty("storePassword")
                    ?: throw GradleException("Release signing password is not configured")
                keyAlias = keyProperties.getProperty("keyAlias")
                    ?: throw GradleException("Release signing alias is not configured")
                keyPassword = keyProperties.getProperty("keyPassword")
                    ?: throw GradleException("Release key password is not configured")
            }
            isMinifyEnabled = false
            isShrinkResources = false
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
