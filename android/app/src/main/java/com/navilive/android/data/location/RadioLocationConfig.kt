package com.navilive.android.data.location

/** Limity pomocniczego skanowania radiowego; GPS pozostaje źródłem nadrzędnym. */
internal object RadioLocationConfig {
    const val scanWindowMs = 2_000L
    const val wifiResultMaxAgeMs = 30_000L
    const val maximumWifiObservations = 20
    const val maximumBluetoothBeaconObservations = 20
    const val minimumObservationsForLookup = 2
    const val lookupTimeoutMs = 4_000L
    const val lookupCacheTtlMs = 120_000L
    const val attemptCooldownMs = 120_000L
    const val maximumAcceptedAccuracyMeters = 250f
    const val maximumGpsRadioAgreementMeters = 120.0
    const val maximumFusionShiftMeters = 45.0
    const val maximumEstimateAgeMs = 180_000L
}
