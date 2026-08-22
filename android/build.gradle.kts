import com.android.build.gradle.BaseExtension

allprojects {
    repositories {
        if (System.getenv("PURE_LIVE_USE_CN_MIRRORS") == "1") {
            maven("https://maven.aliyun.com/repository/google")
            maven("https://maven.aliyun.com/repository/central")
            maven("https://maven.aliyun.com/repository/public")
        }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    afterEvaluate {
        if (project.name != "app") {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
                compileSdkVersion(37)
                defaultConfig.minSdk = 23

                if (namespace.isNullOrBlank()) {
                    namespace = project.group.toString()
                }
            }
        }
    }
}

subprojects {
    if (project.name != "app") {
        evaluationDependsOn(":app")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Disable release lintVital analysis across all modules. AGP(Lint) 9.x crashes
// with NoSuchMethodError (List.removeLast) on JDK 21 during lintVital analysis
// of library modules (e.g. ffmpeg_kit_extended_flutter).
subprojects {
    tasks.matching { it.name.startsWith("lintVital") }.configureEach {
        enabled = false
    }
}
