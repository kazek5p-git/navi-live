package com.navilive.app.ui.navigation

object Routes {
    const val Bootstrap = "bootstrap"
    const val Onboarding = "onboarding"
    const val Permissions = "permissions"
    const val Start = "start"
    const val Search = "search"
    const val CurrentPosition = "current_position"
    const val Favorites = "favorites"
    const val Settings = "settings"
    const val PlaceDetailsPattern = "place/{placeId}"
    const val RouteSummaryPattern = "route_summary/{placeId}"
    const val HeadingAlignPattern = "heading_align/{placeId}"
    const val ActiveNavigationPattern = "active_navigation/{placeId}"
    const val ArrivalPattern = "arrival/{placeId}"

    fun placeDetails(placeId: String): String = "place/$placeId"
    fun routeSummary(placeId: String): String = "route_summary/$placeId"
    fun headingAlign(placeId: String): String = "heading_align/$placeId"
    fun activeNavigation(placeId: String): String = "active_navigation/$placeId"
    fun arrival(placeId: String): String = "arrival/$placeId"
}
