// The plugins every module may apply, declared once here so the version comes
// from the one catalog and resolves once for the whole build.
plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.android.application) apply false
}
