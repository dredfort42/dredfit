//
//  `@Observable` for a plain Kotlin object. The store and the workout flow
//  import no Compose — they run in JVM tests — so a screen cannot see their
//  fields change. This wrapper gives them one snapshot-state counter: every
//  read goes through `getValue`, which reads the counter, so the scope that
//  read the object (a composable body or a content lambda alike) is the scope
//  that recomposes when `changed()` bumps it.
//
//  Read it as a delegated local — `val flow by observed` — and never copy the
//  object out into a plain local that a lambda then captures: that lambda
//  would hold the object without the read, and a skipped parent would leave
//  it showing an old value.
//

package com.dredfit.ui

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import kotlin.reflect.KProperty

@Stable
class Observed<T : Any>(private val target: T) {
    private var version by mutableIntStateOf(0)

    /** The object, read as a state read. */
    val value: T get() {
        // The read is the point: it subscribes the reading scope.
        check(version >= 0)
        return target
    }

    operator fun getValue(thisRef: Any?, property: KProperty<*>): T = value

    /** Something about the object changed: every scope that read it redraws. */
    fun changed() {
        version += 1
    }

    /** A tap: the change, then the redraw — one call, so no caller makes one
     *  without the other. */
    fun act(change: T.() -> Unit) {
        target.change()
        changed()
    }
}
