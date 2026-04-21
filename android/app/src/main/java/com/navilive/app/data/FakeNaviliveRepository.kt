package com.navilive.app.data

import com.navilive.app.model.Place

class FakeNaviliveRepository {

    private val places = emptyList<Place>()

    private val retiredDemoPlaceIds = setOf(
        "gray_inn_road_46",
        "felsberg_2",
        "st_pancras_station",
        "moorfields_eye",
        "kings_cross",
        "home",
        "work",
    )

    fun getPlaces(): List<Place> = places

    fun getDefaultFavoriteIds(): Set<String> = emptySet()

    fun getRetiredDemoPlaceIds(): Set<String> = retiredDemoPlaceIds
}
