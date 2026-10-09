import org.gradle.api.tasks.testing.logging.TestExceptionFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// A plain JVM module, no Android plugin: `./gradlew :core:test` runs on any
// machine without an emulator, the way `swift test` does for DredfitCore.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        allWarningsAsErrors.set(true)
    }
}

sourceSets {
    test {
        // golden.json and reference-manifest.json are read from the Swift
        // package's fixtures — the one copy, guarded by ManifestTest. A copy
        // here is exactly what the manifest must not allow.
        resources.srcDir("../../ios/DredfitCore/Tests/DredfitCoreTests/Fixtures")
    }
}

dependencies {
    // The iOS state file is read through the JSON tree: no compiler plugin,
    // no generated serializers.
    api(libs.kotlinx.serialization.json)

    testImplementation(kotlin("test"))
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
    testLogging {
        events("failed")
        exceptionFormat = TestExceptionFormat.FULL
    }
}
