//
//  `String(localized:)` without Android. No Swift twin: on iOS the flow
//  localizes in place, because Foundation resolves a catalog anywhere. Here
//  the flow is plain Kotlin (it runs in a JVM unit test), so what it says is a
//  KEY and its arguments, and the screen resolves them (`ui/L10n.kt`, `tr`).
//
//  The key is the catalog's: the English base string itself, or a dotted key
//  whose English is its `defaultValue` — exactly the two shapes Swift's
//  `String(localized:)` takes. A composition (`"\(name) · \(display)"` on
//  iOS, never looked up) has no key; its parts are resolved one by one.
//

package com.dredfit.workout

import com.dredfit.core.LoadUnit
import com.dredfit.core.SessionExercise
import com.dredfit.core.SessionProbe

data class Words(
    /** The catalog key; null for a composition of other words. */
    val key: String?,
    /** The English text with its `%lld` / `%@` placeholders: the key, the
     *  dotted key's default value, or the joining pattern of a composition. */
    val format: String,
    /** Numbers, strings and further `Words`, in placeholder order. */
    val args: List<Any> = emptyList(),
) {
    /** The base string, arguments filled in — what an English device shows,
     *  and what a test compares against. */
    val english: String
        get() = if (isNarrowList) args.joinToString(", ") { if (it is Words) it.english else it.toString() }
        else fill(format) { arg -> if (arg is Words) arg.english else arg.toString() }

    /** `.formatted(.list(type: .and, width: .narrow))`: the screen joins the
     *  items the locale's own way; English's narrow list is commas alone. */
    val isNarrowList: Boolean get() = key == null && format == NARROW_LIST

    /** Fills the placeholders, each argument rendered by `render`; `%1$@`
     *  takes its argument by position, as Foundation does. */
    fun fill(format: String, render: (Any) -> String): String {
        var next = 0
        return PLACEHOLDER.replace(format) { m ->
            if (m.value == "%%") return@replace "%"
            val position = m.groupValues[1].takeIf { it.isNotEmpty() }?.dropLast(1)?.toInt()?.minus(1)
            val index = position ?: next++
            args.getOrNull(index)?.let(render) ?: m.value
        }
    }

    override fun toString(): String = english

    companion object {
        private val PLACEHOLDER = Regex("%%|%(\\d+\\$)?(lld|ld|d|@)")
        private const val NARROW_LIST = "\u0000narrow-list"

        /** A list of names the locale joins — see `isNarrowList`. */
        fun narrowList(items: List<Words>): Words = Words(null, NARROW_LIST, items)

        /** `String(localized: "English \(arg)")`: the key IS the English. */
        fun of(key: String, vararg args: Any): Words = Words(key, key, args.toList())

        /** `String(localized: "dotted.key", defaultValue: "English")`. */
        fun keyed(key: String, default: String, vararg args: Any): Words = Words(key, default, args.toList())

        /** A plain interpolation iOS never looks up: its parts are. */
        fun join(format: String, vararg args: Any): Words = Words(null, format, args.toList())

        /** An exercise's name — an English core catalog key, as the engine
         *  stores it (`Library.name`). */
        fun name(name: String): Words = of(name)

        /** `SessionExercise.display` with its two words translatable —
         *  `displayOf` in ui/L10n.kt assembles the same shape. */
        fun display(ex: SessionExercise): Words = display(head(ex), ex.unit, ex.perSide)

        /** "3×12" or "40-35-35": the numbers of `display`, without its words. */
        fun head(ex: SessionExercise): String = ex.loads?.joinToString("-") ?: "${ex.sets}×${ex.load}"

        /** `SessionProbe.display`: one set, so no "N×". */
        fun display(probe: SessionProbe): Words = display("${probe.load}", probe.unit, probe.perSide)

        /** `display` from its parts — the widget snapshot keeps the parts, so
         *  the words are read in the language of the moment it is drawn. */
        fun display(head: String, unit: LoadUnit, perSide: Boolean): Words {
            val sec = if (unit == LoadUnit.hold) " %@" else ""
            val side = if (perSide) " %@" else ""
            val args = buildList<Any> {
                if (unit == LoadUnit.hold) add(of("sec"))
                if (perSide) add(of("per side"))
            }
            return Words(null, "$head$sec$side", args)
        }
    }
}
