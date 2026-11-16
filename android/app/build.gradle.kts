plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Release 签名配置 ─────────────────────────────────────────────
// 密码/别名优先从环境变量读取（CI），回退到本地 keystore.properties（不提交）。
// CI（GitHub Actions）需提供：GLINT_KEYSTORE_BASE64（jks 的 base64）、
// GLINT_KEYSTORE_PASSWORD、GLINT_KEY_ALIAS。
import java.util.Properties

val keystoreProperties = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val ksStoreFile = System.getenv("GLINT_KEYSTORE_FILE")?.let { file(it) }
    ?: file("../keystore/glint-reader-release.jks").takeIf { it.exists() }
val ksStorePass = System.getenv("GLINT_KEYSTORE_PASSWORD")
    ?: keystoreProperties.getProperty("storePassword")
val ksKeyAlias = System.getenv("GLINT_KEY_ALIAS")
    ?: keystoreProperties.getProperty("keyAlias")
val ksKeyPass = System.getenv("GLINT_KEY_PASSWORD")
    ?: keystoreProperties.getProperty("keyPassword")

android {
    signingConfigs {
        if (ksStoreFile != null && ksStorePass != null && ksKeyAlias != null) {
            create("release") {
                storeFile = ksStoreFile
                storePassword = ksStorePass
                keyAlias = ksKeyAlias
                keyPassword = ksKeyPass ?: ksStorePass
            }
        }
    }
    namespace = "com.example.glint_reader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.glint_reader"
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
            // 有 release 签名配置则使用（固定 keystore，保证跨次构建签名一致、
            // 应用内更新可直接覆盖安装）；否则回退 debug 签名便于本地运行。
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }

    // url_launcher_android 的源码在部分 lint 版本上触发 lintVital 崩溃
    //（NoSuchMethodError JavaDocParser.parseDataItem），release 构建跳过 lint 检查。
    lint {
        checkReleaseBuilds = false
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
