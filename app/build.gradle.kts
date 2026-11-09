import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

val signingFile = rootProject.file("key.properties")
val signing = Properties().apply { if (signingFile.isFile) signingFile.inputStream().use { load(it) } }

android {
    testOptions { unitTests.isIncludeAndroidResources = true }
    namespace = "com.green.note"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.green.note"
        minSdk = 24
        targetSdk = 36
        // Keep the promoted 2.0.0 build compatible with the same-version rollback package.
        versionCode = 192
        versionName = "2.0.0"
        ndk { abiFilters += "arm64-v8a" }
    }
    signingConfigs {
        if (signingFile.isFile) create("release") {
            storeFile = rootProject.file(signing.getProperty("storeFile"))
            storePassword = signing.getProperty("storePassword")
            keyAlias = signing.getProperty("keyAlias")
            keyPassword = signing.getProperty("keyPassword")
        }
    }
    buildTypes { release { signingConfig = signingConfigs.findByName("release") } }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
dependencies {
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("io.github.kyant0:backdrop:1.0.6")
    implementation("com.github.QWEA0:liquidglass:v2.0.11")
    implementation(platform("androidx.compose:compose-bom:2026.02.00"))
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.material3:material3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.mindrot:jbcrypt:0.4")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("io.coil-kt:coil-gif:2.7.0")
    implementation("androidx.exifinterface:exifinterface:1.4.2")
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-ui:1.8.0")
    implementation("androidx.work:work-runtime-ktx:2.10.1")
    implementation("com.google.zxing:core:3.5.4")
    implementation("com.google.android.material:material:1.13.0")
    implementation("org.jsoup:jsoup:1.21.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}

// A transitive runtime upgrade must not leave app bytecode compiled against an older Compose API.
val verifyComposeAlignment by tasks.registering {
    doLast {
        val report = mutableListOf<String>()
        val mismatches = mutableListOf<String>()
        for (variant in listOf("debug", "release")) {
            fun versions(suffix: String) = configurations.getByName(variant + suffix)
                .incoming.resolutionResult.allComponents.mapNotNull { it.moduleVersion }
                .filter { it.group.startsWith("androidx.compose.") }
                .associate { "${it.group}:${it.name}" to it.version }
            val compile = versions("CompileClasspath")
            val runtime = versions("RuntimeClasspath")
            for ((module, version) in compile.toSortedMap()) {
                val packaged = runtime[module]
                val line = "$variant $module compile=$version runtime=$packaged"
                report += line
                if (version != packaged) mismatches += line
            }
        }
        val output = layout.buildDirectory.file("reports/compose-alignment.txt").get().asFile
        output.parentFile.mkdirs()
        output.writeText(report.joinToString("\n"))
        check(mismatches.isEmpty()) { "Compose compile/runtime mismatch:\n" + mismatches.joinToString("\n") }
        logger.lifecycle("Compose compile/runtime alignment verified for debug and release")
    }
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(verifyComposeAlignment) }
