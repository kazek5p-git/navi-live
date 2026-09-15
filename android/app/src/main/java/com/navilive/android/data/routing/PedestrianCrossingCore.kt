package com.navilive.android.data.routing

import java.util.Locale

/** Odróżnia przejścia piesze od jawnie rowerowych elementów OSM. */
internal object PedestrianCrossingCore {

    private val allowedFootValues = setOf("yes", "designated", "official", "permissive")
    private val deniedValues = setOf("no", "false", "use_sidepath")

    fun isPedestrianCrossing(tags: Map<String, String>): Boolean {
        if (tags.isEmpty()) return false

        fun value(key: String): String? = tags[key]
            ?.trim()
            ?.lowercase(Locale.ROOT)
            ?.takeIf { it.isNotBlank() }

        val foot = value("foot")
        val crossingFoot = value("crossing:foot")
        if (foot in deniedValues || crossingFoot in deniedValues) return false

        val crossing = value("crossing")
        if (crossing in deniedValues) return false

        val explicitPedestrianAccess = foot in allowedFootValues ||
            crossingFoot in allowedFootValues
        val highway = value("highway")
        if (highway == "cycleway" && !explicitPedestrianAccess) return false
        if (crossing == "cycleway" && !explicitPedestrianAccess) return false

        val crossingCarriageway = value("crossing:carriageway")
        if (crossingCarriageway == "cycleway" && !explicitPedestrianAccess) return false
        return highway == "crossing" ||
            value("footway") == "crossing" ||
            crossing != null ||
            (crossingCarriageway != null && crossingCarriageway !in deniedValues)
    }
}
