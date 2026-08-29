package com.navilive.android.data.location

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Udostępnia stabilny azymut urządzenia bez wymagania dostępu do lokalizacji. */
internal class HeadingTracker(context: Context) : SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private val rotationVectorSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val magnetometer = sensorManager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
    private val _headingDegrees = MutableStateFlow<Double?>(null)
    private var gravityValues: FloatArray? = null
    private var magneticValues: FloatArray? = null
    private var filteredHeadingDegrees: Double? = null
    private var isStarted = false

    val headingDegrees: StateFlow<Double?> = _headingDegrees.asStateFlow()

    fun start() {
        if (isStarted) return
        val manager = sensorManager ?: return
        val registered = if (rotationVectorSensor != null) {
            manager.registerListener(this, rotationVectorSensor, SensorManager.SENSOR_DELAY_UI)
        } else {
            val gravityRegistered = accelerometer?.let {
                manager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
            } ?: false
            val magneticRegistered = magnetometer?.let {
                manager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
            } ?: false
            gravityRegistered || magneticRegistered
        }
        isStarted = registered
    }

    fun stop() {
        if (isStarted) {
            sensorManager?.unregisterListener(this)
        }
        isStarted = false
        gravityValues = null
        magneticValues = null
        filteredHeadingDegrees = null
        _headingDegrees.value = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        val rawHeading = when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> headingFromRotationVector(event.values)
            Sensor.TYPE_ACCELEROMETER -> {
                gravityValues = event.values.clone()
                headingFromGravityAndMagnetic()
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                magneticValues = event.values.clone()
                headingFromGravityAndMagnetic()
            }
            else -> null
        } ?: return

        val filtered = HeadingFilterCore.smooth(filteredHeadingDegrees, rawHeading)
        filteredHeadingDegrees = filtered
        _headingDegrees.value = filtered
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun headingFromRotationVector(values: FloatArray): Double? {
        if (values.size < 3) return null
        val rotationMatrix = FloatArray(9)
        val orientation = FloatArray(3)
        SensorManager.getRotationMatrixFromVector(rotationMatrix, values)
        SensorManager.getOrientation(rotationMatrix, orientation)
        return normalizeDegrees(Math.toDegrees(orientation[0].toDouble()))
    }

    private fun headingFromGravityAndMagnetic(): Double? {
        val gravity = gravityValues ?: return null
        val magnetic = magneticValues ?: return null
        val rotationMatrix = FloatArray(9)
        val inclinationMatrix = FloatArray(9)
        if (!SensorManager.getRotationMatrix(rotationMatrix, inclinationMatrix, gravity, magnetic)) {
            return null
        }
        val orientation = FloatArray(3)
        SensorManager.getOrientation(rotationMatrix, orientation)
        return normalizeDegrees(Math.toDegrees(orientation[0].toDouble()))
    }

    private fun normalizeDegrees(value: Double): Double {
        if (!value.isFinite()) return 0.0
        return ((value % 360.0) + 360.0) % 360.0
    }
}

/** Filtruje azymut po okręgu, dzięki czemu 359° i 1° są traktowane jako sąsiednie. */
internal object HeadingFilterCore {
    fun smooth(previousDegrees: Double?, incomingDegrees: Double, alpha: Double = 0.22): Double {
        val incoming = normalize(incomingDegrees)
        val previous = previousDegrees?.takeIf { it.isFinite() }?.let(::normalize)
            ?: return incoming
        val shortestDelta = ((incoming - previous + 540.0) % 360.0) - 180.0
        return normalize(previous + shortestDelta * alpha.coerceIn(0.0, 1.0))
    }

    private fun normalize(value: Double): Double {
        return ((value % 360.0) + 360.0) % 360.0
    }
}
