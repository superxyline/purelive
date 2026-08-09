import java.util.Properties // 添加Properties类的导入

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 加载local.properties文件
val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { stream ->
            load(stream) // 现在可以正确识别load方法
        }
    }
}

// 加载签名配置
val keystoreProperties = Properties().apply { // 同样添加了导入
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { stream ->
            load(stream) // 现在可以正确识别load方法
        }
    }
}

android {
    namespace = "com.mystyle.purelive"
    // flutter_secure_storage 11 需要 compileSdk 37
    compileSdk = 37
    ndkVersion = flutter.ndkVersion
    lint {
        disable.add("NullSafeMutableLiveData")
        // 对 release 构建也执行 lint 检查（abortOnError 保持 false，避免历史问题阻断打包）
        checkReleaseBuilds = true
        abortOnError = false
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // 自定义构建使用独立包名，可与原作者应用共存安装
        applicationId = "com.superxyline.purelive"
        minSdk = flutter.minSdkVersion 
        multiDexEnabled = true 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = "0.1.4.2"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"].toString()
            keyPassword = keystoreProperties["keyPassword"].toString()
            storeFile = file(keystoreProperties["storeFile"].toString())
            storePassword = keystoreProperties["storePassword"].toString()
        }
    }

    buildTypes {
       release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                  getDefaultProguardFile("proguard-android-optimize.txt"),
                  file("proguard-rules.pro")
              )
        }
       debug {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}    
