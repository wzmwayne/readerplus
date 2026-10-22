plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "wzmwayne.reader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        // 固定签名：使用仓库内自带的 debug.keystore，保证每次构建签名一致。
        // 默认行为是每台机器各自生成 debug.keystore，CI 容器每次都是新的 → 签名每次都变。
        // 注意：这是调试密钥，正式分发前需替换为自己的发布密钥。
        create("fixed") {
            storeFile = file("../debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // ABI 集合：-Pabi=arm64 只 arm64-v8a；multi=arm64+v7a（默认）；all=四套全含（通用包用）。
    // 注意 Flutter 的 --target-platform 只影响 Flutter 自身的 libapp.so，
    // 依赖 AAR 里的 jni 库必须靠这里的 abiFilters 过滤，否则会把 x86/x86_64 一起打进包（+41MB）。
    val abiSelection: List<String> =
        when (val abi = (project.findProperty("abi") as String?) ?: "multi") {
            "arm64" -> listOf("arm64-v8a")
            "multi" -> listOf("arm64-v8a", "armeabi-v7a")
            "all" -> listOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
            // 交给 --split-per-abi，这里不设 abiFilters
            "split" -> emptyList<String>()
            else -> error("未知的 -Pabi=$abi（可选 arm64 / multi / all）")
        }

    defaultConfig {
        applicationId = "wzmwayne.reader"
        // -Pabi=split 时由 Flutter 的 --split-per-abi 接管 ABI，
        // 此时不能再设 ndk.abiFilters（Gradle 明确禁止两者并存）。
        if (abiSelection.isNotEmpty) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(abiSelection)
            }
        }
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
        debug {
            signingConfig = signingConfigs.getByName("fixed")
        }
        release {
            // 发行版沿用调试密钥（Flutter 模板默认行为），仅用于自测分发；
            // 正式发布请替换为自己的发布密钥。
            signingConfig = signingConfigs.getByName("fixed")
        }
        // Flutter 插件会创建 profile 变体，默认同样落在自动生成的 debug.keystore 上，
        // 这里一并固定，保证任何构建类型的签名都一致。
        maybeCreate("profile").signingConfig = signingConfigs.getByName("fixed")
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
