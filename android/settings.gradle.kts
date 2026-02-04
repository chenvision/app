pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 👇👇👇 修改后的镜像配置 👇👇👇
        // 1. 阿里云 Google 镜像 (最优先)
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        // 2. 阿里云 Public 镜像 (包含 JCenter 和 Central，比单独的 jcenter 稳)
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        // 3. 阿里云 Gradle 插件镜像
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        
        // 4. 官方源作为兜底 (万一阿里云没有，尝试去官方下)
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")