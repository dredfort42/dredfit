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
        // One place for both (gradle.properties says why each counts as it
        // does); scripts/check_version.py reads the same two lines.
        versionCode = providers.gradleProperty("dredfit.versionCode").get().toInt()
        versionName = providers.gradleProperty("dredfit.versionName").get()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // The frames for comparing with the iOS store shots are taken on
        // request (`adb shell am instrument -e class com.dredfit.ScreenshotWalk
        // -e screens <prefix> …`), never as part of the suite. The refused-
        // notification walk and the refused reminder need a permission never
        // granted, which the suite grants, so each runs alone. All three are
        // @RunsAlone (androidTest RunsAlone.kt says why not a notClass list).
        testInstrumentationRunnerArguments["notAnnotation"] = "com.dredfit.RunsAlone"
        // About's "Rate on Google Play" and "Recommend Dredfit" point at the
        // Play listing, which does not exist yet: a link to a missing page is
        // worse than no link. Flip to true once the listing is live
        // (AboutLinksTest pins the default; owner decision 09.10.2026).
        buildConfigField("boolean", "PLAY_LISTING_LIVE", "false")
    }

    // The Play upload key, handed in by android/tools/build-release.sh through
    // the environment and nowhere else: the password never sits in a file, a
    // Gradle property or a command line that `ps` shows. Without it the
    // release build stays unsigned — CI's, and every machine's but the
    // owner's.
    val uploadKeystore = providers.environmentVariable("DREDFIT_UPLOAD_KEYSTORE").orNull
    if (uploadKeystore != null) {
        signingConfigs.create("upload") {
            storeFile = file(uploadKeystore)
            storePassword = providers.environmentVariable("DREDFIT_UPLOAD_PASSWORD").orNull
                ?: error("DREDFIT_UPLOAD_KEYSTORE is set, DREDFIT_UPLOAD_PASSWORD is not")
            keyAlias = providers.environmentVariable("DREDFIT_UPLOAD_KEY_ALIAS").orNull
                ?: error("DREDFIT_UPLOAD_KEYSTORE is set, DREDFIT_UPLOAD_KEY_ALIAS is not")
            // A PKCS12 store (keytool's default, and the upload key's type)
            // has one password for the store and its key.
            keyPassword = storePassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload")
            // R8: the bundle drops from 12.5 MB to 6.4 MB (Health Connect
            // brings Guava and protobuf), and Compose runs as Google measures
            // it only optimized. Nothing here reflects on its own classes —
            // JSON is read through the tree, never by generated serializers,
            // strings by R ids (l10n/) — and the libraries that do ship their
            // keep rules; proguard-rules.pro repairs the two that predate R8's
            // full mode. android/README.md "Releasing" has the smoke that
            // proved the shrunk build.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
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
    // Play In-App Review: the review card after a milestone, iOS's StoreKit
    // `requestReview`. The ONE third-party SDK, approved by the owner
    // (09.10.2026, android/README.md); it adds no permission. Nothing else
    // from Play Core or Play services is declared here.
    implementation(libs.play.review)
    // Play review brings fragment 1.1.0 (play-services-basement); the
    // activity-result launchers need 1.3.0+, or the release lint fails.
    implementation(libs.androidx.fragment)
    // The home-screen widget (widgets/), iOS's DredfitWidgets: Glance draws
    // RemoteViews from composables. AndroidX on Google Maven, no network.
    implementation(libs.androidx.glance.appwidget)
    // Glance's sessions run on WorkManager. Named here because DredfitApp is
    // its Configuration.Provider: started on demand (the first widget draw),
    // not by androidx.startup in every process (AndroidManifest.xml).
    implementation(libs.androidx.work.runtime)
    // Health Connect (health/), iOS's HealthKit: on-device IPC to the
    // platform service (Android 14+) or the Health Connect app (10–13). It
    // brings Guava and its own protobuf runtime, and adds an exported
    // `HealthDataSdkService` the provider binds to — no permission, no network.
    implementation(libs.androidx.health.connect)
    // The store's Health calls are `suspend` (AppStoreHealth.kt) — used
    // directly, so declared rather than borrowed from Compose's graph.
    implementation(libs.kotlinx.coroutines.core)

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
    // The widget's composables per state (`runGlanceAppWidgetUnitTest`), on
    // the device: its environment calls android.os.Bundle and Log, which the
    // JVM unit tests' stub android.jar throws on, and the words need the
    // real resources to be read in en and ru.
    androidTestImplementation(libs.androidx.glance.appwidget.testing)
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
        // The Android-only catalog beside them: SetsNoticeTest holds its keys too.
        file("Localizable.xcstrings"),
    ).withPropertyName("iosCatalogs").withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.files(
        fileTree(rootProject.file("../ios/Dredfit")) { include("**/*.swift") },
        fileTree(rootProject.file("../ios/DredfitWidgets")) { include("**/*.swift") },
        fileTree("src/main/kotlin") { include("**/*.kt") },
    ).withPropertyName("scannedSources").withPathSensitivity(PathSensitivity.RELATIVE)
    // ReminderTriggerTest and HealthPermissionsTest read the manifests in place.
    inputs.files("src/main/AndroidManifest.xml", "src/debug/AndroidManifest.xml").withPropertyName("manifests")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    testLogging {
        events("failed")
        exceptionFormat = TestExceptionFormat.FULL
    }
}
