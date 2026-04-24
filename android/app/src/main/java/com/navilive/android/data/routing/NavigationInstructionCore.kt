package com.navilive.android.data.routing

import com.navilive.android.model.SharedProductRules

internal data class NavigationInstructionDescriptor(
    val strategy: Strategy,
    val roadName: String? = null,
    val normalizedModifier: String? = null,
) {
    enum class Strategy {
        DepartNamed,
        Arrive,
        TurnNamed,
        TurnGenericNamed,
        TurnBareModifier,
        ContinueNamed,
        ProceedTowardNamed,
    }

    fun paritySignature(): String {
        val road = roadName ?: "-"
        val modifier = normalizedModifier ?: "-"
        return "${strategy.name}|$road|$modifier"
    }
}

internal object NavigationInstructionCore {

    fun describe(
        maneuverType: String,
        modifier: String?,
        roadName: String?,
    ): NavigationInstructionDescriptor {
        val normalizedRoad = roadName?.trim().orEmpty().ifBlank { null }
        val normalizedModifier = modifier
            ?.let(SharedProductRules.Instructions::normalizeModifier)
            ?.takeIf { it in SharedProductRules.Instructions.supportedModifiers }

        return when (maneuverType) {
            "depart" -> NavigationInstructionDescriptor(
                strategy = NavigationInstructionDescriptor.Strategy.DepartNamed,
                roadName = normalizedRoad,
            )
            "arrive" -> NavigationInstructionDescriptor(
                strategy = NavigationInstructionDescriptor.Strategy.Arrive,
            )
            "turn" -> when {
                normalizedRoad != null && normalizedModifier != null ->
                    NavigationInstructionDescriptor(
                        strategy = NavigationInstructionDescriptor.Strategy.TurnNamed,
                        roadName = normalizedRoad,
                        normalizedModifier = normalizedModifier,
                    )
                normalizedRoad != null ->
                    NavigationInstructionDescriptor(
                        strategy = NavigationInstructionDescriptor.Strategy.TurnGenericNamed,
                        roadName = normalizedRoad,
                    )
                normalizedModifier != null ->
                    NavigationInstructionDescriptor(
                        strategy = NavigationInstructionDescriptor.Strategy.TurnBareModifier,
                        normalizedModifier = normalizedModifier,
                    )
                else ->
                    NavigationInstructionDescriptor(
                        strategy = NavigationInstructionDescriptor.Strategy.TurnGenericNamed,
                    )
            }
            "new name", "continue" -> NavigationInstructionDescriptor(
                strategy = NavigationInstructionDescriptor.Strategy.ContinueNamed,
                roadName = normalizedRoad,
            )
            else -> NavigationInstructionDescriptor(
                strategy = NavigationInstructionDescriptor.Strategy.ProceedTowardNamed,
                roadName = normalizedRoad,
            )
        }
    }
}
