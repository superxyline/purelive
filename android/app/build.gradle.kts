import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    // END: FlutterFire Configuration
    // AGP 9 provides Built-in Kotlin; the standalone Kotlin Gradle Plugin is no longer applied.
    id("dev.flutter.flutter-gradle-plugin")
}


// 加载签名配置
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use(::load)
    }
}
val releaseStoreFile = keystoreProperties.getProperty("storeFile")?.let(::file)
val hasReleaseSigning = listOf("keyAlias", "keyPassword", "storePassword").all {
    !keystoreProperties.getProperty(it).isNullOrBlank()
} && releaseStoreFile?.isFile == true
val requireReleaseSigning =
    providers.gradleProperty("pureLive.requireReleaseSigning").orNull.toBoolean() ||
        providers.gradleProperty("pureLiveRequireReleaseSigning").orNull.toBoolean()
if (requireReleaseSigning && !hasReleaseSigning) {
    throw GradleException("Release signing is required but android/key.properties is incomplete.")
}

extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.superxyline.purelive"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion
    lint {
        disable.add("NullSafeMutableLiveData")
        checkReleaseBuilds = true
        abortOnError = true
    }
    compileOptions {
        // core library desugaring 支持 Java 8+ API
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        // 正式包名（用户最终选定）：后续任何改动/构建一律使用 com.superxyline.purelive。
        applicationId = "com.superxyline.purelive"
        minSdk = flutter.minSdkVersion 
        multiDexEnabled = true 
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "纯粹直播（纯净版）"
        // ABI 打包策略（配合 gradle.properties 的 disable-abi-filtering=true）：
        // 默认仅 arm64-v8a。需要其它平台时用 -PtargetAbi 覆盖，
        // 并与 --target-platform 配套，例如：
        //   flutter build apk --release --target-platform android-x64 -PtargetAbi=x86_64
        val targetAbi = (project.findProperty("targetAbi") as? String)
            ?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
        ndk { abiFilters.addAll(targetAbi ?: listOf("arm64-v8a")) }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
       release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("Release key not configured; using the local debug key for a test-only formal-package build.")
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                  getDefaultProguardFile("proguard-android-optimize.txt"),
                  file("proguard-rules.pro")
              )
        }
       debug {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}    

