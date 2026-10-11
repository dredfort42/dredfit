//
//  A class the connected suite leaves out (`notAnnotation` in
//  build.gradle.kts): the screenshot walk, run by hand, and the walks that
//  need POST_NOTIFICATIONS never granted, which every other class grants.
//
//  An annotation, not a `notClass` list: AGP handed the runner only the first
//  name of "A,B,C" (`am instrument … -e notClass A`), so the classes after
//  the comma ran in the suite after all (connected run, 09.10.2026).
//
//  Run one alone with the exclusion swapped for a harmless one:
//
//    ./gradlew :app:connectedDebugAndroidTest \
//      -Pandroid.testInstrumentationRunnerArguments.class=com.dredfit.ReminderDeniedTest \
//      -Pandroid.testInstrumentationRunnerArguments.notAnnotation=org.junit.Ignore
//

package com.dredfit

@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS)
annotation class RunsAlone
