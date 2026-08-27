package com.navilive.android.data.location

import com.navilive.android.model.GeoPoint

/** Rodzaj identyfikatora radiowego wysyłanego do usługi geolokalizacyjnej. */
enum class RadioObservationKind {
    WifiAccessPoint,
    BluetoothBeacon,
}

/** Pojedynczy, lokalnie wykryty punkt dostępu albo beacon BLE. */
data class RadioObservation(
    val kind: RadioObservationKind,
    val identifier: String,
    val signalStrengthDbm: Int,
    val observedAtMs: Long,
)

/** Ograniczony czasowo zestaw obserwacji z jednego skanu. */
data class RadioObservationBatch(
    val observations: List<RadioObservation>,
    val capturedAtMs: Long,
) {
    val wifiObservations: List<RadioObservation>
        get() = observations.filter { it.kind == RadioObservationKind.WifiAccessPoint }

    val bluetoothBeaconObservations: List<RadioObservation>
        get() = observations.filter { it.kind == RadioObservationKind.BluetoothBeacon }
}

/** Odpowiedź beaconDB. Nie jest samodzielnym źródłem pozycji dla aplikacji. */
data class RadioLocationEstimate(
    val point: GeoPoint,
    val accuracyMeters: Float,
    val observationCount: Int,
    val wifiObservationCount: Int,
    val bluetoothBeaconObservationCount: Int,
    val timestampMs: Long,
)
