plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// CI 가 android/key.properties 를 주입하면 release 빌드를 고정 keystore 로 서명한다.
// 파일이 없는 로컬 환경에서는 아래 buildTypes.release 의 폴백에 따라 debug 키로 빌드되므로
// `flutter run --release` 가 그대로 동작한다.
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.planbook.planbook"
    // flutter_secure_storage(v11) 는 Android SDK 37 이상으로 컴파일할 것을
    // 요구한다(:app:checkReleaseAarMetadata 가 강제). flutter.compileSdkVersion
    // 기본값(36)보다 명시적으로 올려야 한다. compileSdk 를 올리는 것은
    // minSdk/targetSdk 와 무관하게 항상 하위 호환이다.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.planbook.planbook"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // key.properties 가 없을 때는 아예 만들지 않는다. 값이 전부 null 인
        // 껍데기 서명 설정을 남겨두면 AGP 가 이를 검증하려다 실패할 수 있다.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // key.properties 가 있으면 고정 release 키로 서명하고,
            // 없으면 debug 키로 폴백해서 로컬에서도 `flutter run --release` 가 돌게 한다.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
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
