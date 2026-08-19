import java.io.FileInputStream
import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties()
if (releaseKeyPropertiesFile.exists()) {
    FileInputStream(releaseKeyPropertiesFile).use(releaseKeyProperties::load)
}

val isReleaseTaskRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("release", ignoreCase = true)
}

android {
    namespace = "com.etiketly.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            if (releaseKeyPropertiesFile.exists()) {
                val storeFileValue =
                    releaseKeyProperties.getProperty("storeFile")?.trim()
                val storePasswordValue =
                    releaseKeyProperties.getProperty("storePassword")?.trim()
                val keyAliasValue =
                    releaseKeyProperties.getProperty("keyAlias")?.trim()
                val keyPasswordValue =
                    releaseKeyProperties.getProperty("keyPassword")?.trim()

                if (
                    storeFileValue.isNullOrEmpty() ||
                    storePasswordValue.isNullOrEmpty() ||
                    keyAliasValue.isNullOrEmpty() ||
                    keyPasswordValue.isNullOrEmpty()
                ) {
                    throw GradleException(
                        "android/key.properties is missing one or more required values. " +
                            "Copy android/key.properties.example and fill in storeFile, storePassword, keyAlias, and keyPassword.",
                    )
                }

                storeFile = rootProject.file(storeFileValue)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            } else if (isReleaseTaskRequested) {
                throw GradleException(
                    "Missing android/key.properties. Copy android/key.properties.example to android/key.properties " +
                        "and point it to your upload keystore before running a release build.",
                )
            }
        }
    }

    defaultConfig {
        applicationId = "com.etiketly.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    implementation("com.google.mlkit:text-recognition-chinese:16.0.0")
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.0")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.0")
    implementation("com.google.mlkit:text-recognition-korean:16.0.0")
}
