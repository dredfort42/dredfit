import org.gradle.api.tasks.testing.logging.TestExceptionFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// The Compose app. AGP 9 compiles Kotlin itself (built-in Kotlin), so there
// is no separate kotlin-android plugin; the Compose compiler plugin is
// Kotlin's own and moves with the Kotlin version.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.dredfit"
    compileSdk = 37

    defaultConfig {
        // iOS ships as com.dredfit.Dredfit; an application id is lower case
        // by convention and is never shown to a person.
        applicationId = "com.dredfit.dredfit"
        // Android 10 — the owner's floor (android/CLAUDE.md).
        minSdk = 29
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    androidResources {
        // The seven languages of the String Catalogs, declared to the system
        // so the per-app language setting (Android 13+) offers exactly them.
        generateLocaleConfig = true
    }

    testOptions {
        unitTests.all { it.useJUnitPlatform() }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        allWarningsAsErrors.set(true)
    }
}

dependencies {
    implementation(project(":core"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.activity.compose)

    testImplementation(kotlin("test"))
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.withType<Test>().configureEach {
    testLogging {
        events("failed")
        exceptionFormat = TestExceptionFormat.FULL
    }
}
