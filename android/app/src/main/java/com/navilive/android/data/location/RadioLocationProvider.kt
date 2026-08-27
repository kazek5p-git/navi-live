package com.navilive.android.data.location

/** Dostarcza krótki, opcjonalny zestaw lokalnych obserwacji radiowych. */
interface RadioLocationProvider {
    suspend fun scan(): RadioObservationBatch
}
