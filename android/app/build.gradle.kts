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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // The frames for comparing with the iOS store shots are taken on
        // request (`adb shell am instrument -e class com.dredfit.ScreenshotWalk
        // -e screens <prefix> …`), never as part of the suite.
        testInstrumentationRunnerArguments["notClass"] = "com.dredfit.ScreenshotWalk"
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
    // FileProvider (the share card's content:// URI) and WindowCompat — used
    // directly, so declared rather than borrowed from activity's graph.
    implementation(libs.androidx.core)

    // The JUnit 5 flavour by name: AGP does not pick kotlin-test's variant
    // from the test framework the way the plain JVM plugin does.
    testImplementation(kotlin("test-junit5"))
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)

    // The Compose UI suite (androidTest) — the counterpart of
    // ios/DredfitUITests, JUnit 4 because the instrumentation runner is.
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    // ui-test-junit4 brings espresso-core 3.5.0, which calls
    // InputManager.getInstance — gone from Android 17 (API 37): every
    // Compose test failed in its first idle wait (09.10.2026).
    androidTestImplementation(libs.androidx.test.espresso.core)
    // Stubs the system pickers (export/import) and the share sheet, so a
    // test can see the intent go out without a picker it cannot drive.
    androidTestImplementation(libs.androidx.test.espresso.intents)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}

tasks.withType<Test>().configureEach {
    // LifeBenefitTest and SetsNoticeTest read iOS files in place, never a
    // copy — the String Catalogs and the Swift sources that ask for their
    // keys — and SetsNoticeTest scans this module's own Kotlin sources. As
    // declared inputs, an edit to any of them reruns the suites instead of
    // leaving an up-to-date green from before it.
    inputs.files(
        rootProject.file("../ios/Dredfit/Localizable.xcstrings"),
        rootProject.file("../ios/DredfitWidgets/Localizable.xcstrings"),
        rootProject.file("../ios/DredfitCore/Sources/DredfitCore/Resources/Localizable.xcstrings"),
    ).withPropertyName("iosCatalogs").withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.files(
        fileTree(rootProject.file("../ios/Dredfit")) { include("**/*.swift") },
        fileTree(rootProject.file("../ios/DredfitWidgets")) { include("**/*.swift") },
        fileTree("src/main/kotlin") { include("**/*.kt") },
    ).withPropertyName("scannedSources").withPathSensitivity(PathSensitivity.RELATIVE)
    testLogging {
        events("failed")
        exceptionFormat = TestExceptionFormat.FULL
    }
}
