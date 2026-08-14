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
        // 提速：release 构建跳过 lint 检查（lintVital 每次全量分析耗时 10+ 分钟，
        // 且 abortOnError=false 下发现问题也不会阻断构建，纯属拖慢；需要时手动跑 ./gradlew lint）
        checkReleaseBuilds = false
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
        versionName = flutter.versionName
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
            // 提速：关闭 R8 混淆与资源收缩（Flutter 的 Dart 代码在 libapp.so 中，R8 仅处理少量 Java/Kotlin 层，
            // 收益极小但每次全量执行耗时 1-3 分钟；关闭后 APK 略大、功能无影响）
            isMinifyEnabled = false
            isShrinkResources = false
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
