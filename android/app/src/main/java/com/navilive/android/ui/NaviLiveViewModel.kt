package com.navilive.android.ui

import android.app.Application
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.StringRes
import androidx.core.content.pm.PackageInfoCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.navilive.android.R
import com.navilive.android.data.FakeNaviLiveRepository
import com.navilive.android.data.location.LocationTrackerStore
import com.navilive.android.data.preferences.NaviLivePreferencesStore
import com.navilive.android.data.routing.OpenStreetRoutingRepository
import com.navilive.android.data.telemetry.NavigationTelemetryLogger
import com.navilive.android.data.update.GitHubUpdateRepository
import com.navilive.android.guidance.GuidanceFeedbackEngine
import com.navilive.android.i18n.localizedLanguageDisplayName
import com.navilive.android.model.ActiveNavigationState
import com.navilive.android.model.AppUpdatePhase
import com.navilive.android.model.AppUpdateState
import com.navilive.android.model.GeoPoint
import com.navilive.android.model.HeadingState
import com.navilive.android.model.LocationFix
import com.navilive.android.model.NaviLiveUiState
import com.navilive.android.model.Place
import com.navilive.android.model.RouteStep
import com.navilive.android.model.RouteSummary
import com.navilive.android.model.SettingsState
import com.navilive.android.model.SharedProductRules
import com.navilive.android.model.SpeechOutputMode
import com.navilive.android.model.UpdateChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import kotlin.math.roundToInt

private data class RouteSession(
    val destinationId: String,
    val destinationName: String,
    val destinationPoint: GeoPoint?,
    val steps: List<RouteStep>,
    val pathPoints: List<GeoPoint>,
    val currentStepIndex: Int = 0,
)

class NaviLiveViewModel(application: Application) : AndroidViewModel(application) {

    private val appContext = application.applicationContext
    private val fakeRepository = FakeNaviLiveRepository()
    private val seedPlaces = fakeRepository.getPlaces()
    private val defaultFavoriteIds = fakeRepository.getDefaultFavoriteIds()
    private val retiredDemoPlaceIds = fakeRepository.getRetiredDemoPlaceIds()
    private val defaultLastRoutePlaceId: String? = null
    private val routingRepository = OpenStreetRoutingRepository(appContext)
    private val preferencesStore = NaviLivePreferencesStore(
        context = appContext,
        defaultFavoriteIds = defaultFavoriteIds,
        defaultLastRoutePlaceId = defaultLastRoutePlaceId,
    )
    private val feedbackEngine = GuidanceFeedbackEngine(appContext)
    private val telemetryLogger = NavigationTelemetryLogger(appContext)
    private val updateRepository = GitHubUpdateRepository()

    private val headingSequence = listOf(
        HeadingState(
            instruction = string(R.string.heading_instruction_rotate_right),
            isAligned = false,
            arrowRotationDeg = 22f,
        ),
        HeadingState(
            instruction = string(R.string.heading_instruction_almost_aligned),
            isAligned = false,
            arrowRotationDeg = 7f,
        ),
        HeadingState(
            instruction = string(R.string.heading_instruction_aligned),
            isAligned = true,
            arrowRotationDeg = 0f,
        ),
    )

    private var headingIndex = 0
    private var searchJob: Job? = null
    private var reverseGeocodeJob: Job? = null
    private var updateCheckJob: Job? = null
    private var updateDownloadJob: Job? = null
    private val routeCache = mutableMapOf<String, RouteSummary>()
    private var lastReversePoint: GeoPoint? = null
    private var lastReverseTimestampMs: Long = 0L
    private var activeRouteSession: RouteSession? = null
    private var isNavigationLive = false
    private var isRouteRecalculating = false
    private var lastAutoRecalculateMs = 0L
    private var lastAnnouncedStepIndex = -1
    private var lastCountdownStepIndex = -1
    private var lastCountdownMilestoneMeters: Int? = null
    private var lastImmediateAnnouncedStepIndex = -1
    private var lastTrackingState: Boolean? = null
    private var lastTelemetryFixPoint: GeoPoint? = null
    private var lastTelemetryFixTimestampMs: Long = 0L
    private var hasPerformedStartupUpdateCheck = false

    private val _uiState = MutableStateFlow(
        NaviLiveUiState(
            currentLocationLabel = string(R.string.current_position_status_waiting_message),
            places = seedPlaces,
            searchResults = seedPlaces,
            favoriteIds = defaultFavoriteIds,
            lastRoutePlaceId = defaultLastRoutePlaceId,
            settingsState = synchronizeSpeechSettings(
                SettingsState(language = systemLanguageDisplayName()),
            ),
            diagnosticsState = telemetryLogger.snapshotState(),
            appUpdateState = initialAppUpdateState(),
            statusMessage = string(R.string.location_status_ready_title),
        ),
    )
    val uiState: StateFlow<NaviLiveUiState> = _uiState.asStateFlow()

    init {
        observePreferencesStore()
        observeLocationStore()
        refreshDiagnosticsState()
        refreshUpdateRuntimeState()
    }

    private fun observePreferencesStore() {
        viewModelScope.launch {
            preferencesStore.state.collect { persisted ->
                val currentVersionLabel = currentAppVersionLabel()
                val currentBuildLabel = currentAppBuildLabel()
                val sanitizedFavoriteIds = persisted.favoriteIds - retiredDemoPlaceIds
                val sanitizedLastRoutePlaceId = persisted.lastRoutePlaceId?.takeUnless { it in retiredDemoPlaceIds }
                val sanitizedDownloadedUpdate = sanitizePersistedDownloadedUpdate(
                    currentVersionLabel = currentVersionLabel,
                    apkPath = persisted.downloadedUpdateApkPath,
                    versionLabel = persisted.downloadedUpdateVersionLabel,
                )
                if (
                    sanitizedFavoriteIds != persisted.favoriteIds ||
                    sanitizedLastRoutePlaceId != persisted.lastRoutePlaceId
                ) {
                    preferencesStore.setFavoriteIds(sanitizedFavoriteIds)
                    preferencesStore.setLastRoutePlaceId(sanitizedLastRoutePlaceId)
                }
                if (
                    sanitizedDownloadedUpdate.apkPath != persisted.downloadedUpdateApkPath ||
                    sanitizedDownloadedUpdate.versionLabel != persisted.downloadedUpdateVersionLabel
                ) {
                    val stalePath = persisted.downloadedUpdateApkPath
                    if (
                        stalePath != null &&
                        stalePath != sanitizedDownloadedUpdate.apkPath &&
                        File(stalePath).exists()
                    ) {
                        File(stalePath).delete()
                    }
                    if (
                        sanitizedDownloadedUpdate.apkPath != null &&
                        sanitizedDownloadedUpdate.versionLabel != null
                    ) {
                        preferencesStore.setDownloadedUpdate(
                            apkPath = sanitizedDownloadedUpdate.apkPath,
                            versionLabel = sanitizedDownloadedUpdate.versionLabel,
                        )
                    } else {
                        preferencesStore.clearDownloadedUpdate()
                    }
                }
                _uiState.update { current ->
                    current.copy(
                        favoriteIds = sanitizedFavoriteIds,
                        lastRoutePlaceId = sanitizedLastRoutePlaceId,
                        settingsState = synchronizeSpeechSettings(persisted.settingsState),
                        appUpdateState = current.appUpdateState.copy(
                            currentVersionLabel = currentVersionLabel,
                            currentBuildLabel = currentBuildLabel,
                            downloadedApkPath = sanitizedDownloadedUpdate.apkPath,
                            downloadedVersionLabel = sanitizedDownloadedUpdate.versionLabel,
                            canRequestPackageInstalls = canRequestPackageInstalls(),
                            phase = when {
                                current.appUpdateState.phase == AppUpdatePhase.Downloading ->
                                    AppUpdatePhase.Downloading
                                sanitizedDownloadedUpdate.apkPath != null &&
                                    sanitizedDownloadedUpdate.versionLabel != null ->
                                    AppUpdatePhase.ReadyToInstall
                                current.appUpdateState.phase == AppUpdatePhase.ReadyToInstall ->
                                    AppUpdatePhase.Idle
                                else -> current.appUpdateState.phase
                            },
                            statusMessage = when {
                                current.appUpdateState.phase == AppUpdatePhase.Downloading ->
                                    current.appUpdateState.statusMessage
                                sanitizedDownloadedUpdate.apkPath != null &&
                                    sanitizedDownloadedUpdate.versionLabel != null ->
                                    string(
                                        R.string.format_update_ready_to_install,
                                        sanitizedDownloadedUpdate.versionLabel,
                                    )
                                current.appUpdateState.phase == AppUpdatePhase.ReadyToInstall ->
                                    string(R.string.update_status_idle_auto)
                                else -> current.appUpdateState.statusMessage
                            },
                        ),
                        hasCompletedOnboarding = persisted.hasCompletedOnboarding,
                        isPreferencesLoaded = true,
                    )
                }
            }
        }
    }

    private fun string(@StringRes resId: Int, vararg args: Any): String = appContext.getString(resId, *args)

    private fun systemLanguageDisplayName(): String =
        localizedLanguageDisplayName(appContext.resources.configuration)

    private fun initialAppUpdateState(): AppUpdateState {
        return AppUpdateState(
            currentVersionLabel = currentAppVersionLabel(),
            currentBuildLabel = currentAppBuildLabel(),
            statusMessage = string(R.string.update_status_idle_auto),
            canRequestPackageInstalls = canRequestPackageInstalls(),
        )
    }

    private fun currentPackageInfo() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        appContext.packageManager.getPackageInfo(
            appContext.packageName,
            PackageManager.PackageInfoFlags.of(0),
        )
    } else {
        @Suppress("DEPRECATION")
        appContext.packageManager.getPackageInfo(appContext.packageName, 0)
    }

    private fun currentAppVersionLabel(): String {
        val packageInfo = currentPackageInfo()
        val versionName = packageInfo.versionName?.takeIf { it.isNotBlank() }
        return versionName ?: currentAppBuildLabel()
    }

    private fun currentAppBuildLabel(): String {
        val packageInfo = currentPackageInfo()
        return PackageInfoCompat.getLongVersionCode(packageInfo).toString()
    }

    private fun canRequestPackageInstalls(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            appContext.packageManager.canRequestPackageInstalls()
    }

    private fun updatesDirectory(): File = File(appContext.filesDir, "debug/updates")

    private data class DownloadedUpdateSnapshot(
        val apkPath: String?,
        val versionLabel: String?,
    )

    private fun sanitizePersistedDownloadedUpdate(
        currentVersionLabel: String,
        apkPath: String?,
        versionLabel: String?,
    ): DownloadedUpdateSnapshot {
        val existingPath = apkPath?.takeIf { File(it).exists() }
        val existingVersion = versionLabel?.takeIf { it.isNotBlank() }
        val canInstall = existingPath != null &&
            existingVersion != null &&
            updateRepository.compareVersions(
                currentVersionLabel = currentVersionLabel,
                remoteVersionLabel = existingVersion,
            ) > 0
        return if (canInstall) {
            DownloadedUpdateSnapshot(
                apkPath = existingPath,
                versionLabel = existingVersion,
            )
        } else {
            DownloadedUpdateSnapshot(apkPath = null, versionLabel = null)
        }
    }

    private fun observeLocationStore() {
        viewModelScope.launch {
            LocationTrackerStore.state.collect { trackerState ->
                val fallbackLabel = trackerState.latestFix?.let(::formatCoordinateLabel)
                _uiState.update { current ->
                    val previousCoordinateLabel = current.locationState.latestFix?.let(::formatCoordinateLabel)
                    current.copy(
                        currentLocationLabel = when {
                            trackerState.latestFix == null && current.currentLocationLabel.isBlank() ->
                                string(R.string.current_position_status_waiting_message)
                            trackerState.latestFix == null -> current.currentLocationLabel
                            current.currentLocationLabel.isBlank() -> fallbackLabel ?: current.currentLocationLabel
                            current.currentLocationLabel == previousCoordinateLabel -> fallbackLabel ?: current.currentLocationLabel
                            else -> current.currentLocationLabel
                        },
                        locationState = current.locationState.copy(
                            latestFix = trackerState.latestFix,
                            isForegroundTracking = trackerState.isTracking,
                        ),
                    )
                }
                logTrackingStateChangeIfNeeded(trackerState.isTracking)
                maybeReverseGeocode(trackerState.latestFix)
                syncActiveNavigationWithLocation(trackerState.latestFix)
            }
        }
    }

    fun onLocationPermissionChanged(granted: Boolean) {
        telemetryLogger.log(
            type = "location_permission_changed",
            message = if (granted) "Location permission granted." else "Location permission revoked.",
            attributes = linkedMapOf("granted" to granted),
        )
        refreshDiagnosticsState()
        _uiState.update { current ->
            current.copy(
                locationState = current.locationState.copy(hasPermission = granted),
                statusMessage = if (granted) {
                    string(R.string.status_location_access_enabled)
                } else {
                    string(R.string.status_location_access_required)
                },
            )
        }
    }

    fun getPlace(placeId: String?): Place? {
        if (placeId == null) return null
        return _uiState.value.places.firstOrNull { it.id == placeId }
    }

    fun getFavorites(): List<Place> {
        val state = _uiState.value
        return state.places.filter { it.id in state.favoriteIds }
    }

    fun routeSummaryFor(placeId: String): RouteSummary {
        val cached = routeCache[placeId]
        val place = getPlace(placeId)
        return if (place == null) {
            RouteSummary(distanceMeters = 0, etaMinutes = 0)
        } else {
            normalizeSummary(
                place = place,
                summary = cached ?: RouteSummary(
                    distanceMeters = place.walkDistanceMeters,
                    etaMinutes = place.walkEtaMinutes,
                ),
            )
        }
    }

    fun updateSearchQuery(query: String) {
        _uiState.update { current ->
            current.copy(searchQuery = query)
        }
        searchJob?.cancel()
        if (query.isBlank()) {
            _uiState.update { current ->
                current.copy(
                    searchResults = current.places,
                    isLoadingSearch = false,
                )
            }
            return
        }

        searchJob = viewModelScope.launch {
            _uiState.update { current -> current.copy(isLoadingSearch = true) }
            delay(250)
            try {
                val currentPoint = _uiState.value.locationState.latestFix?.point
                val remote = routingRepository.searchPlaces(query, currentPoint)
                _uiState.update { current ->
                    val merged = mergeById(current.places, remote)
                    current.copy(
                        places = merged,
                        searchResults = remote.ifEmpty {
                            merged.filter {
                                it.name.contains(query, ignoreCase = true) ||
                                    it.address.contains(query, ignoreCase = true)
                            }
                        },
                        isLoadingSearch = false,
                        statusMessage = if (remote.isNotEmpty()) {
                            string(R.string.format_found_matching_places, remote.size)
                        } else {
                            string(R.string.status_no_online_match)
                        },
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                _uiState.update { current ->
                    current.copy(
                        isLoadingSearch = false,
                        statusMessage = string(R.string.status_search_service_unavailable),
                        searchResults = current.places.filter {
                            it.name.contains(query, ignoreCase = true) ||
                                it.address.contains(query, ignoreCase = true)
                        },
                    )
                }
            }
        }
    }

    fun completeOnboarding() {
        telemetryLogger.log(
            type = "onboarding_completed",
            message = "Onboarding completed.",
        )
        refreshDiagnosticsState()
        _uiState.update { current ->
            current.copy(
                hasCompletedOnboarding = true,
                statusMessage = string(R.string.status_setup_complete),
            )
        }
        viewModelScope.launch {
            preferencesStore.setOnboardingCompleted(true)
        }
    }

    fun setShowTutorialOnStartup(enabled: Boolean) {
        _uiState.update { current ->
            current.copy(
                settingsState = current.settingsState.copy(showTutorialOnStartup = enabled),
                statusMessage = string(
                    if (enabled) {
                        R.string.status_tutorial_on_start_enabled
                    } else {
                        R.string.status_tutorial_on_start_disabled
                    },
                ),
            )
        }
        viewModelScope.launch {
            preferencesStore.setShowTutorialOnStartup(enabled)
        }
    }

    fun toggleFavorite(placeId: String) {
        var favoriteIds = emptySet<String>()
        var added = false
        _uiState.update { current ->
            val next = current.favoriteIds.toMutableSet()
            if (placeId in next) {
                next.remove(placeId)
            } else {
                next.add(placeId)
                added = true
            }
            favoriteIds = next
            current.copy(
                favoriteIds = next,
                statusMessage = if (placeId in next) {
                    string(R.string.status_saved_to_favorites)
                } else {
                    string(R.string.status_removed_from_favorites)
                },
            )
        }
        telemetryLogger.log(
            type = "favorite_toggled",
            message = if (added) "Favorite added." else "Favorite removed.",
            attributes = linkedMapOf("place_id" to placeId, "is_favorite" to added),
        )
        refreshDiagnosticsState()
        viewModelScope.launch {
            preferencesStore.setFavoriteIds(favoriteIds)
        }
    }

    fun startRoute(placeId: String) {
        val place = getPlace(placeId) ?: return
        headingIndex = 0
        isNavigationLive = false
        telemetryLogger.beginSession(destinationId = place.id, destinationName = place.name)
        telemetryLogger.log(
            type = "route_requested",
            message = "Route requested.",
            attributes = linkedMapOf("place_id" to place.id, "place_name" to place.name),
        )
        refreshDiagnosticsState()
        _uiState.update { current ->
            current.copy(
                lastRoutePlaceId = place.id,
                statusMessage = string(R.string.format_preparing_route, place.name),
                headingState = headingSequence[headingIndex],
                isLoadingRoute = true,
            )
        }
        viewModelScope.launch {
            preferencesStore.setLastRoutePlaceId(place.id)
        }

        val currentPoint = _uiState.value.locationState.latestFix?.point
        val targetPoint = place.point
        if (currentPoint == null || targetPoint == null) {
            val fallback = fallbackRouteSummary(
                place = place,
                currentPoint = currentPoint,
                currentInstruction = string(R.string.format_continue_toward, place.name),
            )
            routeCache[place.id] = fallback
            applyRouteSummary(
                place = place,
                summary = fallback,
                spokenMessage = string(R.string.format_fallback_route_ready, place.name),
                statusMessage = string(R.string.format_fallback_route_ready, place.name),
            )
            return
        }

        viewModelScope.launch {
            try {
                val summary = routingRepository.buildWalkingRoute(currentPoint, targetPoint)
                routeCache[place.id] = summary
                applyRouteSummary(
                    place = place,
                    summary = summary,
                    spokenMessage = string(R.string.format_route_ready, place.name),
                    statusMessage = string(R.string.format_route_ready, place.name),
                )
            } catch (error: Exception) {
                val fallback = fallbackRouteSummary(
                    place = place,
                    currentPoint = currentPoint,
                    currentInstruction = string(R.string.format_continue_toward, place.name),
                )
                routeCache[place.id] = fallback
                applyRouteSummary(
                    place = place,
                    summary = fallback,
                    spokenMessage = string(R.string.format_fallback_route_ready, place.name),
                    statusMessage = string(R.string.status_route_service_unavailable),
                )
            }
        }
    }

    private fun applyRouteSummary(
        place: Place,
        summary: RouteSummary,
        spokenMessage: String,
        statusMessage: String,
        keepNavigationLive: Boolean = false,
    ) {
        val normalized = normalizeSummary(place, summary)
        activeRouteSession = RouteSession(
            destinationId = place.id,
            destinationName = place.name,
            destinationPoint = place.point,
            steps = normalized.steps,
            pathPoints = normalized.pathPoints,
        )
        isNavigationLive = keepNavigationLive
        resetNavigationAnnouncementState()
        isRouteRecalculating = false
        lastTelemetryFixPoint = null
        lastTelemetryFixTimestampMs = 0L

        if (keepNavigationLive) {
            speakNavigationNow(spokenMessage)
        } else {
            speakNow(spokenMessage)
        }
        vibrateShortIfEnabled()
        telemetryLogger.log(
            type = if (keepNavigationLive) "route_recalculated" else "route_loaded",
            message = statusMessage,
            attributes = linkedMapOf(
                "place_id" to place.id,
                "distance_m" to normalized.distanceMeters,
                "eta_min" to normalized.etaMinutes,
                "step_count" to normalized.steps.size,
                "path_point_count" to normalized.pathPoints.size,
            ),
        )
        refreshDiagnosticsState()
        _uiState.update { current ->
            current.copy(
                isLoadingRoute = false,
                statusMessage = statusMessage,
                activeNavigationState = buildActiveNavigationState(
                    session = activeRouteSession!!,
                    fix = current.locationState.latestFix,
                    previous = current.activeNavigationState.copy(isPaused = false),
                    isOffRoute = false,
                    isRecalculating = false,
                    offRouteDistanceMeters = null,
                ),
            )
        }
    }

    fun cycleHeadingInstruction() {
        headingIndex = (headingIndex + 1) % headingSequence.size
        _uiState.update { current ->
            current.copy(headingState = headingSequence[headingIndex])
        }
    }

    fun markHeadingAligned() {
        vibrateDoubleIfEnabled()
        speakNow(string(R.string.spoken_heading_aligned))
        telemetryLogger.log(
            type = "heading_aligned",
            message = "Heading aligned by user.",
        )
        refreshDiagnosticsState()
        _uiState.update { current ->
            current.copy(
                headingState = headingSequence.last(),
                statusMessage = string(R.string.status_heading_aligned),
            )
        }
    }

    fun beginActiveNavigation() {
        val session = activeRouteSession ?: return
        isNavigationLive = true
        resetNavigationAnnouncementState()
        telemetryLogger.log(
            type = "navigation_started",
            message = "Active navigation started.",
        )
        refreshDiagnosticsState()
        _uiState.update { current ->
            current.copy(
                statusMessage = string(R.string.status_active_guidance_started),
                activeNavigationState = current.activeNavigationState.copy(
                    isPaused = false,
                    isOffRoute = false,
                    isRecalculating = false,
                    offRouteDistanceMeters = null,
                ),
            )
        }
        announceNavigationStartInstruction(session)
        syncActiveNavigationWithLocation(_uiState.value.locationState.latestFix)
    }

    fun repeatCurrentInstruction() {
        val instruction = _uiState.value.activeNavigationState.currentInstruction
        speakNavigationNow(instruction)
        telemetryLogger.log(
            type = "instruction_repeated",
            message = "Current instruction repeated.",
            attributes = linkedMapOf("instruction" to instruction),
        )
        refreshDiagnosticsState()
        _uiState.update { current ->
            current.copy(statusMessage = string(R.string.status_repeating_instruction))
        }
    }

    fun togglePauseNavigation() {
        var pausedNow = false
        _uiState.update { current ->
            val paused = !current.activeNavigationState.isPaused
            pausedNow = paused
            if (paused) {
                speakNavigationNow(string(R.string.spoken_navigation_paused))
            } else {
                speakNavigationNow(string(R.string.spoken_navigation_resumed))
            }
            current.copy(
                activeNavigationState = current.activeNavigationState.copy(isPaused = paused),
                statusMessage = if (paused) {
                    string(R.string.status_navigation_paused)
                } else {
                    string(R.string.status_navigation_resumed)
                },
            )
        }
        if (!pausedNow) {
            syncActiveNavigationWithLocation(_uiState.value.locationState.latestFix)
        }
        telemetryLogger.log(
            type = if (pausedNow) "navigation_paused" else "navigation_resumed",
            message = if (pausedNow) string(R.string.status_navigation_paused) else string(R.string.status_navigation_resumed),
        )
        refreshDiagnosticsState()
    }

    fun recalculateRoute() {
        recalculateRouteInternal(autoTriggered = false)
    }

    fun stopNavigation() {
        telemetryLogger.endSession(reason = "stopped")
        refreshDiagnosticsState()
        activeRouteSession = null
        isNavigationLive = false
        isRouteRecalculating = false
        resetNavigationAnnouncementState()
        lastTelemetryFixPoint = null
        lastTelemetryFixTimestampMs = 0L
        _uiState.update { current ->
            current.copy(
                activeNavigationState = ActiveNavigationState(),
                statusMessage = string(R.string.status_navigation_stopped),
            )
        }
    }

    fun markArrived() {
        telemetryLogger.endSession(reason = "arrived")
        refreshDiagnosticsState()
        activeRouteSession = null
        isNavigationLive = false
        isRouteRecalculating = false
        resetNavigationAnnouncementState()
        lastTelemetryFixPoint = null
        lastTelemetryFixTimestampMs = 0L
        speakNavigationNow(string(R.string.spoken_arrived))
        vibrateDoubleIfEnabled()
        _uiState.update { current ->
            current.copy(
                statusMessage = string(R.string.status_arrived),
                activeNavigationState = current.activeNavigationState.copy(
                    isPaused = false,
                    isOffRoute = false,
                    isRecalculating = false,
                    offRouteDistanceMeters = null,
                ),
            )
        }
    }

    private fun recalculateRouteInternal(autoTriggered: Boolean) {
        val destination = getPlace(_uiState.value.lastRoutePlaceId)
        val currentPoint = _uiState.value.locationState.latestFix?.point
        val destinationPoint = destination?.point

        if (destination == null || currentPoint == null || destinationPoint == null) {
            _uiState.update { current ->
                current.copy(statusMessage = string(R.string.status_cannot_recalculate_yet))
            }
            return
        }
        if (isRouteRecalculating) return

        if (autoTriggered) {
            lastAutoRecalculateMs = System.currentTimeMillis()
        }
        isRouteRecalculating = true
        telemetryLogger.log(
            type = if (autoTriggered) "route_recalculate_auto_started" else "route_recalculate_manual_started",
            message = if (autoTriggered) "Automatic route recalculation started." else "Manual route recalculation started.",
        )
        refreshDiagnosticsState()
        _uiState.update { current ->
            current.copy(
                statusMessage = if (autoTriggered) {
                    string(R.string.spoken_off_route_auto)
                } else {
                    string(R.string.spoken_recalculating_route)
                },
                activeNavigationState = current.activeNavigationState.copy(
                    isRecalculating = true,
                    isOffRoute = current.activeNavigationState.isOffRoute || autoTriggered,
                ),
            )
        }

        viewModelScope.launch {
            try {
                val summary = routingRepository.buildWalkingRoute(currentPoint, destinationPoint)
                routeCache[destination.id] = summary
                applyRouteSummary(
                    place = destination,
                    summary = summary,
                    spokenMessage = string(R.string.spoken_route_recalculated),
                    statusMessage = if (autoTriggered) {
                        string(R.string.status_route_recalculated_after_deviation)
                    } else {
                        string(R.string.status_route_recalculated)
                    },
                    keepNavigationLive = isNavigationLive,
                )
            } catch (error: Exception) {
                isRouteRecalculating = false
                telemetryLogger.log(
                    type = "route_recalculate_failed",
                    message = "Route recalculation failed.",
                    attributes = linkedMapOf(
                        "auto_triggered" to autoTriggered,
                        "error" to (error.message ?: error.javaClass.simpleName),
                    ),
                )
                refreshDiagnosticsState()
                _uiState.update { current ->
                    current.copy(
                        statusMessage = if (autoTriggered) {
                            string(R.string.status_auto_recalculation_failed)
                        } else {
                            string(R.string.status_manual_recalculation_failed)
                        },
                        activeNavigationState = current.activeNavigationState.copy(
                            isRecalculating = false,
                        ),
                    )
                }
            }
        }
    }

    fun announceCurrentLocation() {
        val state = _uiState.value
        val accuracy = state.locationState.latestFix?.accuracyMeters
        val detail = when {
            !state.locationState.hasPermission -> string(R.string.location_announcement_disabled)
            accuracy == null -> string(R.string.location_announcement_unavailable)
            accuracy > 45f -> string(R.string.location_announcement_approximate)
            else -> string(R.string.location_announcement_ready)
        }
        val label = state.currentLocationLabel
        speakNow(string(R.string.format_current_position_announcement, detail, label))
        _uiState.update { current ->
            current.copy(statusMessage = detail)
        }
    }

    fun setVibration(enabled: Boolean) {
        _uiState.update { current ->
            current.copy(settingsState = current.settingsState.copy(vibrationEnabled = enabled))
        }
        viewModelScope.launch {
            preferencesStore.setVibrationEnabled(enabled)
        }
    }

    fun setAutoRecalculate(enabled: Boolean) {
        _uiState.update { current ->
            current.copy(settingsState = current.settingsState.copy(autoRecalculate = enabled))
        }
        viewModelScope.launch {
            preferencesStore.setAutoRecalculate(enabled)
        }
    }

    fun setJunctionAlerts(enabled: Boolean) {
        _uiState.update { current ->
            current.copy(settingsState = current.settingsState.copy(junctionAlerts = enabled))
        }
        viewModelScope.launch {
            preferencesStore.setJunctionAlerts(enabled)
        }
    }

    fun setTurnByTurnAnnouncements(enabled: Boolean) {
        _uiState.update { current ->
            current.copy(settingsState = current.settingsState.copy(turnByTurnAnnouncements = enabled))
        }
        viewModelScope.launch {
            preferencesStore.setTurnByTurnAnnouncements(enabled)
        }
    }

    fun setUpdateChannel(channel: UpdateChannel) {
        if (channel == _uiState.value.settingsState.updateChannel) {
            return
        }
        _uiState.update { current ->
            current.copy(
                settingsState = current.settingsState.copy(updateChannel = channel),
                appUpdateState = current.appUpdateState.copy(
                    phase = AppUpdatePhase.Idle,
                    latestVersionLabel = null,
                    latestReleaseName = null,
                    latestAssetName = null,
                    latestAssetDownloadUrl = null,
                    releaseNotes = "",
                    releasePageUrl = null,
                    downloadProgressPercent = null,
                    isAutoInstallRequested = false,
                    statusMessage = string(
                        if (channel == UpdateChannel.Beta) {
                            R.string.status_update_channel_beta_selected
                        } else {
                            R.string.status_update_channel_stable_selected
                        },
                    ),
                ),
            )
        }
        viewModelScope.launch {
            preferencesStore.setUpdateChannel(channel)
        }
        checkForAppUpdates(silent = true)
    }

    fun performStartupUpdateCheckIfNeeded() {
        if (hasPerformedStartupUpdateCheck || !_uiState.value.isPreferencesLoaded) {
            return
        }
        hasPerformedStartupUpdateCheck = true
        checkForAppUpdates(silent = true)
    }

    fun setSpeechOutputMode(mode: SpeechOutputMode) {
        val updated = synchronizeSpeechSettings(
            _uiState.value.settingsState.copy(speechOutputMode = mode),
        )
        _uiState.update { current ->
            current.copy(
                settingsState = updated,
                statusMessage = if (mode == SpeechOutputMode.ScreenReader) {
                    if (updated.isScreenReaderActive && !updated.activeScreenReaderName.isNullOrBlank()) {
                        string(R.string.format_status_screen_reader_selected, updated.activeScreenReaderName!!)
                    } else {
                        string(R.string.status_screen_reader_fallback_selected)
                    }
                } else if (!updated.isSelectedSystemTtsEngineAvailable) {
                    string(R.string.status_selected_system_tts_unavailable)
                } else if (!updated.activeSystemTtsEngineLabel.isNullOrBlank()) {
                    string(R.string.format_status_specific_system_tts_selected, updated.activeSystemTtsEngineLabel!!)
                } else {
                    string(R.string.status_system_voice_selected)
                },
            )
        }
        viewModelScope.launch {
            preferencesStore.setSpeechOutputMode(mode)
        }
    }

    fun setSystemTtsEnginePackage(packageName: String?) {
        val normalized = packageName?.takeIf { it.isNotBlank() }
        val updated = synchronizeSpeechSettings(
            _uiState.value.settingsState.copy(selectedSystemTtsEnginePackage = normalized),
        )
        val statusMessage = when {
            normalized == null -> string(R.string.status_default_system_tts_selected)
            !updated.isSelectedSystemTtsEngineAvailable -> string(R.string.status_selected_system_tts_unavailable)
            updated.activeSystemTtsEngineLabel.isNullOrBlank() -> string(R.string.status_system_voice_selected)
            else -> string(R.string.format_status_specific_system_tts_selected, updated.activeSystemTtsEngineLabel!!)
        }
        _uiState.update { current ->
            current.copy(
                settingsState = updated,
                statusMessage = statusMessage,
            )
        }
        viewModelScope.launch {
            preferencesStore.setSelectedSystemTtsEnginePackage(normalized)
        }
    }

    fun setSpeechRatePercent(percent: Int) {
        val normalized = percent.coerceIn(50, 200)
        val updated = synchronizeSpeechSettings(
            _uiState.value.settingsState.copy(speechRatePercent = normalized),
        )
        _uiState.update { current ->
            current.copy(
                settingsState = updated,
                statusMessage = string(R.string.format_status_speech_rate_updated, normalized),
            )
        }
        viewModelScope.launch {
            preferencesStore.setSpeechRatePercent(normalized)
        }
    }

    fun setSpeechVolumePercent(percent: Int) {
        val normalized = percent.coerceIn(0, 100)
        val updated = synchronizeSpeechSettings(
            _uiState.value.settingsState.copy(speechVolumePercent = normalized),
        )
        _uiState.update { current ->
            current.copy(
                settingsState = updated,
                statusMessage = string(R.string.format_status_speech_volume_updated, normalized),
            )
        }
        viewModelScope.launch {
            preferencesStore.setSpeechVolumePercent(normalized)
        }
    }

    fun previewSpeechOutput() {
        val updated = synchronizeSpeechSettings(_uiState.value.settingsState)
        _uiState.update { current ->
            current.copy(settingsState = updated)
        }
        speakNow(string(R.string.settings_voice_preview_sample))
        _uiState.update { current ->
            current.copy(statusMessage = string(R.string.status_voice_preview_played))
        }
    }

    fun refreshSpeechRuntimeState() {
        val updated = synchronizeSpeechSettings(_uiState.value.settingsState)
        _uiState.update { current ->
            current.copy(settingsState = updated)
        }
    }

    fun refreshUpdateRuntimeState() {
        _uiState.update { current ->
            val currentVersionLabel = currentAppVersionLabel()
            val downloadedPath = current.appUpdateState.downloadedApkPath
                ?.takeIf { File(it).exists() }
            current.copy(
                appUpdateState = current.appUpdateState.copy(
                    currentVersionLabel = currentVersionLabel,
                    currentBuildLabel = currentAppBuildLabel(),
                    downloadedApkPath = downloadedPath,
                    downloadedVersionLabel = downloadedVersionLabelOrNull(
                        current.appUpdateState.downloadedVersionLabel,
                        downloadedPath,
                    ),
                    canRequestPackageInstalls = canRequestPackageInstalls(),
                    statusMessage = when {
                        current.appUpdateState.phase == AppUpdatePhase.ReadyToInstall && downloadedPath != null ->
                            string(
                                R.string.format_update_ready_to_install,
                                current.appUpdateState.downloadedVersionLabel
                                    ?: current.appUpdateState.latestVersionLabel
                                    ?: currentVersionLabel,
                            )
                        current.appUpdateState.phase == AppUpdatePhase.Idle ->
                            string(R.string.update_status_idle_auto)
                        else -> current.appUpdateState.statusMessage
                    },
                ),
            )
        }
    }

    fun checkForAppUpdates(silent: Boolean = false) {
        updateCheckJob?.cancel()
        updateCheckJob = viewModelScope.launch {
            val currentVersion = currentAppVersionLabel()
            val currentBuild = currentAppBuildLabel()
            val updateChannel = _uiState.value.settingsState.updateChannel
            if (!silent) {
                _uiState.update { current ->
                    current.copy(
                        appUpdateState = current.appUpdateState.copy(
                            currentVersionLabel = currentVersion,
                            currentBuildLabel = currentBuild,
                            phase = AppUpdatePhase.Checking,
                            statusMessage = string(R.string.update_status_checking),
                            downloadProgressPercent = null,
                            canRequestPackageInstalls = canRequestPackageInstalls(),
                            isAutoInstallRequested = false,
                        ),
                    )
                }
            }
            try {
                val release = updateRepository.fetchLatestRelease(updateChannel)
                val isRemoteNewer = updateRepository.compareVersions(
                    currentVersionLabel = currentVersion,
                    remoteVersionLabel = release.versionLabel,
                ) > 0
                _uiState.update { current ->
                    val downloadedPath = current.appUpdateState.downloadedApkPath
                        ?.takeIf { File(it).exists() }
                    val alreadyDownloaded = downloadedPath != null &&
                        current.appUpdateState.downloadedVersionLabel == release.versionLabel
                    current.copy(
                        appUpdateState = current.appUpdateState.copy(
                            currentVersionLabel = currentVersion,
                            currentBuildLabel = currentBuild,
                            latestVersionLabel = release.versionLabel,
                            latestReleaseName = release.releaseName,
                            latestAssetName = release.asset.name,
                            latestAssetDownloadUrl = release.asset.downloadUrl,
                            releaseNotes = release.body,
                            releasePageUrl = release.htmlUrl,
                            phase = when {
                                alreadyDownloaded -> AppUpdatePhase.ReadyToInstall
                                isRemoteNewer -> AppUpdatePhase.Available
                                else -> AppUpdatePhase.UpToDate
                            },
                            downloadedApkPath = downloadedPath,
                            canRequestPackageInstalls = canRequestPackageInstalls(),
                            statusMessage = when {
                                alreadyDownloaded -> string(
                                    R.string.format_update_ready_to_install,
                                    release.versionLabel,
                                )
                                isRemoteNewer -> string(
                                    R.string.format_update_available,
                                    release.versionLabel,
                                )
                                else -> string(
                                    R.string.format_update_up_to_date,
                                    currentVersion,
                                )
                            },
                        ),
                    )
                }
            } catch (error: Exception) {
                if (!silent) {
                    _uiState.update { current ->
                        current.copy(
                            appUpdateState = current.appUpdateState.copy(
                                currentVersionLabel = currentVersion,
                                currentBuildLabel = currentBuild,
                                phase = AppUpdatePhase.Error,
                                isAutoInstallRequested = false,
                                statusMessage = string(
                                    R.string.format_update_check_failed,
                                    error.message ?: error.javaClass.simpleName,
                                ),
                            ),
                        )
                    }
                }
            }
        }
    }

    fun downloadAndInstallAvailableUpdate() {
        downloadAvailableUpdate(autoInstallAfterDownload = true)
    }

    fun downloadAvailableUpdate(autoInstallAfterDownload: Boolean = false) {
        val updateState = _uiState.value.appUpdateState
        val assetUrl = updateState.latestAssetDownloadUrl ?: return
        val assetName = updateState.latestAssetName ?: "navi-live-update.apk"
        val versionLabel = updateState.latestVersionLabel ?: return
        updateDownloadJob?.cancel()
        updateDownloadJob = viewModelScope.launch {
            _uiState.update { current ->
                current.copy(
                    appUpdateState = current.appUpdateState.copy(
                        phase = AppUpdatePhase.Downloading,
                        statusMessage = string(R.string.format_update_downloading, versionLabel),
                        downloadProgressPercent = 0,
                        isAutoInstallRequested = autoInstallAfterDownload,
                    ),
                )
            }
            try {
                val sanitizedVersion = versionLabel.replace(Regex("""[^0-9A-Za-z._-]"""), "_")
                val baseName = assetName.substringBeforeLast(".apk", assetName)
                val destination = File(
                    updatesDirectory(),
                    "${baseName}_$sanitizedVersion.apk",
                )
                val downloaded = updateRepository.downloadReleaseAsset(
                    asset = com.navilive.android.data.update.GitHubReleaseAsset(
                        name = assetName,
                        downloadUrl = assetUrl,
                        sizeBytes = 0L,
                    ),
                    destination = destination,
                    onProgress = { progress ->
                        _uiState.update { current ->
                            current.copy(
                                appUpdateState = current.appUpdateState.copy(
                                    phase = AppUpdatePhase.Downloading,
                                    downloadProgressPercent = progress,
                                    isAutoInstallRequested = autoInstallAfterDownload,
                                    statusMessage = if (progress == null) {
                                        string(R.string.format_update_downloading, versionLabel)
                                    } else {
                                        string(R.string.format_update_downloading_progress, progress)
                                    },
                                ),
                            )
                        }
                    },
                )
                _uiState.update { current ->
                    current.copy(
                        appUpdateState = current.appUpdateState.copy(
                            phase = AppUpdatePhase.ReadyToInstall,
                            downloadedApkPath = downloaded.absolutePath,
                            downloadedVersionLabel = versionLabel,
                            downloadProgressPercent = 100,
                            canRequestPackageInstalls = canRequestPackageInstalls(),
                            isAutoInstallRequested = autoInstallAfterDownload,
                            statusMessage = string(
                                R.string.format_update_ready_to_install,
                                versionLabel,
                            ),
                        ),
                    )
                }
                preferencesStore.setDownloadedUpdate(
                    apkPath = downloaded.absolutePath,
                    versionLabel = versionLabel,
                )
            } catch (error: Exception) {
                _uiState.update { current ->
                    current.copy(
                        appUpdateState = current.appUpdateState.copy(
                            phase = AppUpdatePhase.Error,
                            downloadProgressPercent = null,
                            isAutoInstallRequested = false,
                            statusMessage = string(
                                R.string.format_update_download_failed,
                                error.message ?: error.javaClass.simpleName,
                            ),
                        ),
                    )
                }
            }
        }
    }

    fun markUpdateInstallStarted() {
        val versionLabel = _uiState.value.appUpdateState.downloadedVersionLabel
            ?: _uiState.value.appUpdateState.latestVersionLabel
            ?: currentAppVersionLabel()
        _uiState.update { current ->
            current.copy(
                appUpdateState = current.appUpdateState.copy(
                    phase = AppUpdatePhase.ReadyToInstall,
                    canRequestPackageInstalls = canRequestPackageInstalls(),
                    isAutoInstallRequested = false,
                    statusMessage = if (canRequestPackageInstalls()) {
                        string(R.string.format_update_install_started, versionLabel)
                    } else {
                        string(R.string.update_status_install_permission_required)
                    },
                ),
            )
        }
    }

    fun clearAutoInstallRequest() {
        _uiState.update { current ->
            current.copy(
                appUpdateState = current.appUpdateState.copy(
                    isAutoInstallRequested = false,
                ),
            )
        }
    }

    fun requestAutoInstallForDownloadedUpdate() {
        _uiState.update { current ->
            current.copy(
                appUpdateState = current.appUpdateState.copy(
                    isAutoInstallRequested = true,
                ),
            )
        }
    }

    fun exportDiagnostics() {
        viewModelScope.launch {
            try {
                telemetryLogger.log(
                    type = "telemetry_export_requested",
                    message = "Telemetry export requested.",
                )
                val file = telemetryLogger.exportToFile()
                refreshDiagnosticsState()
                _uiState.update { current ->
                    current.copy(statusMessage = string(R.string.format_telemetry_exported, file.name))
                }
            } catch (error: Exception) {
                _uiState.update { current ->
                    current.copy(statusMessage = string(R.string.status_telemetry_export_failed))
                }
            }
        }
    }

    fun clearDiagnostics() {
        telemetryLogger.clear()
        lastTelemetryFixPoint = null
        lastTelemetryFixTimestampMs = 0L
        refreshDiagnosticsState()
        _uiState.update { current ->
            current.copy(statusMessage = string(R.string.status_telemetry_cleared))
        }
    }

    private fun fallbackRouteSummary(
        place: Place,
        currentPoint: GeoPoint?,
        currentInstruction: String,
    ): RouteSummary {
        val arrivalInstruction = string(R.string.generic_arriving_destination)
        val steps = listOf(
            RouteStep(
                instruction = currentInstruction,
                distanceMeters = place.walkDistanceMeters.coerceAtLeast(25),
                maneuverPoint = currentPoint,
            ),
            RouteStep(
                instruction = arrivalInstruction,
                distanceMeters = 0,
                maneuverPoint = place.point,
            ),
        )
        val pathPoints = buildList {
            if (currentPoint != null) add(currentPoint)
            if (place.point != null) add(place.point)
        }
        return RouteSummary(
            distanceMeters = place.walkDistanceMeters,
            etaMinutes = place.walkEtaMinutes,
            currentInstruction = steps.first().instruction,
            nextInstruction = steps.getOrNull(1)?.instruction ?: string(R.string.generic_follow_route_guidance),
            steps = steps,
            pathPoints = pathPoints,
        )
    }

    private fun normalizeSummary(place: Place, summary: RouteSummary): RouteSummary {
        if (summary.steps.isNotEmpty()) {
            return summary
        }
        val currentInstruction = summary.currentInstruction.ifBlank { string(R.string.format_continue_toward, place.name) }
        val nextInstruction = summary.nextInstruction.ifBlank { string(R.string.generic_arriving_destination) }
        val currentPoint = _uiState.value.locationState.latestFix?.point
        val steps = listOf(
            RouteStep(
                instruction = currentInstruction,
                distanceMeters = (summary.distanceMeters / 2).coerceAtLeast(25),
                maneuverPoint = currentPoint,
            ),
            RouteStep(
                instruction = nextInstruction,
                distanceMeters = 0,
                maneuverPoint = place.point,
            ),
        )
        val pathPoints = summary.pathPoints.ifEmpty {
            buildList {
                if (currentPoint != null) add(currentPoint)
                if (place.point != null) add(place.point)
            }
        }
        return summary.copy(
            currentInstruction = currentInstruction,
            nextInstruction = nextInstruction,
            steps = steps,
            pathPoints = pathPoints,
        )
    }

    private fun syncActiveNavigationWithLocation(fix: LocationFix?) {
        if (fix == null || !isNavigationLive) return
        val session = activeRouteSession ?: return
        val currentState = _uiState.value.activeNavigationState
        if (currentState.isPaused) return

        val deviationMeters = routeDeviationMeters(session.pathPoints, fix.point)
        if (NavigationScenarioCore.shouldTriggerOffRoute(deviationMeters, fix.accuracyMeters)) {
            handleOffRoute(session, fix, requireNotNull(deviationMeters))
            return
        }

        val nextStepIndex = resolveStepIndex(session, fix)
        val updatedSession = if (nextStepIndex != session.currentStepIndex) {
            session.copy(currentStepIndex = nextStepIndex)
        } else {
            session
        }
        activeRouteSession = updatedSession
        val wasOffRoute = currentState.isOffRoute
        var updatedState: ActiveNavigationState? = null
        _uiState.update { current ->
            updatedState = buildActiveNavigationState(
                session = updatedSession,
                fix = fix,
                previous = current.activeNavigationState,
                isOffRoute = false,
                isRecalculating = false,
                offRouteDistanceMeters = null,
            )
            current.copy(
                statusMessage = if (wasOffRoute) string(R.string.status_back_on_route) else current.statusMessage,
                activeNavigationState = updatedState!!,
            )
        }
        val freshState = updatedState ?: return
        logNavigationFixIfNeeded(updatedSession, fix, deviationMeters)

        if (nextStepIndex != session.currentStepIndex) {
            announceStepChange(updatedSession)
        } else {
            val announcedCountdown = maybeAnnounceCountdownInstruction(updatedSession, freshState)
            if (!announcedCountdown) {
                maybeAnnounceImmediateInstruction(updatedSession, freshState, fix)
            }
        }
    }

    private fun handleOffRoute(
        session: RouteSession,
        fix: LocationFix,
        deviationMeters: Int,
    ) {
        val alreadyOffRoute = _uiState.value.activeNavigationState.isOffRoute
        _uiState.update { current ->
            current.copy(
                statusMessage = string(R.string.status_off_route_recalculate),
                activeNavigationState = buildActiveNavigationState(
                    session = session,
                    fix = fix,
                    previous = current.activeNavigationState,
                    isOffRoute = true,
                    isRecalculating = current.activeNavigationState.isRecalculating,
                    offRouteDistanceMeters = deviationMeters,
                ),
            )
        }
        if (!alreadyOffRoute) {
            vibrateDoubleIfEnabled()
            speakNavigationNow(string(R.string.navigation_status_off_route_title))
            telemetryLogger.log(
                type = "off_route_detected",
                message = "Off-route detected.",
                attributes = linkedMapOf(
                    "deviation_m" to deviationMeters,
                    "accuracy_m" to fix.accuracyMeters,
                    "step_index" to session.currentStepIndex,
                ),
            )
            refreshDiagnosticsState()
        }
        if (_uiState.value.settingsState.autoRecalculate && shouldAutoRecalculate()) {
            recalculateRouteInternal(autoTriggered = true)
        }
    }

    private fun shouldAutoRecalculate(): Boolean {
        return NavigationScenarioCore.shouldAllowAutoRecalculate(
            isRouteRecalculating = isRouteRecalculating,
            elapsedSinceLastRecalculateMs = System.currentTimeMillis() - lastAutoRecalculateMs,
        )
    }

    private fun resolveStepIndex(session: RouteSession, fix: LocationFix): Int {
        var index = session.currentStepIndex
        while (index < session.steps.lastIndex) {
            val nextManeuver = session.steps[index + 1].maneuverPoint ?: break
            if (
                NavigationScenarioCore.shouldAdvanceStep(
                    distanceToManeuverMeters = distanceMeters(fix.point, nextManeuver),
                    accuracyMeters = fix.accuracyMeters,
                )
            ) {
                index += 1
            } else {
                break
            }
        }
        return index
    }

    private fun buildActiveNavigationState(
        session: RouteSession,
        fix: LocationFix?,
        previous: ActiveNavigationState,
        isOffRoute: Boolean,
        isRecalculating: Boolean,
        offRouteDistanceMeters: Int?,
    ): ActiveNavigationState {
        val currentIndex = session.currentStepIndex.coerceIn(0, session.steps.lastIndex)
        val currentStep = session.steps[currentIndex]
        val nextStep = session.steps.getOrNull(currentIndex + 1)
        val distanceToNext = when {
            nextStep?.maneuverPoint != null && fix != null ->
                distanceMeters(fix.point, nextStep.maneuverPoint).roundToInt().coerceAtLeast(1)
            nextStep != null && nextStep.distanceMeters > 0 ->
                nextStep.distanceMeters
            session.destinationPoint != null && fix != null ->
                distanceMeters(fix.point, session.destinationPoint).roundToInt().coerceAtLeast(1)
            else -> currentStep.distanceMeters.coerceAtLeast(1)
        }
        val remainingFromSteps = session.steps.drop(currentIndex).sumOf { it.distanceMeters }
        val remainingFromDestination = if (fix != null && session.destinationPoint != null) {
            distanceMeters(fix.point, session.destinationPoint).roundToInt()
        } else {
            0
        }
        return ActiveNavigationState(
            currentInstruction = currentStep.instruction,
            nextInstruction = nextStep?.instruction ?: string(R.string.generic_destination_ahead),
            distanceToNextMeters = distanceToNext,
            remainingDistanceMeters = maxOf(remainingFromSteps, remainingFromDestination),
            progressLabel = string(R.string.format_progress_step, currentIndex + 1, session.steps.size),
            isPaused = previous.isPaused,
            isOffRoute = isOffRoute,
            isRecalculating = isRecalculating,
            offRouteDistanceMeters = offRouteDistanceMeters,
        )
    }

    private fun announceStepChange(session: RouteSession) {
        if (session.currentStepIndex <= lastAnnouncedStepIndex) return
        lastAnnouncedStepIndex = session.currentStepIndex
        if (_uiState.value.settingsState.turnByTurnAnnouncements) {
            if (session.currentStepIndex != lastImmediateAnnouncedStepIndex) {
                speakNavigationNow(
                    string(
                        R.string.format_navigation_immediate_instruction,
                        session.steps[session.currentStepIndex].instruction,
                    ),
                )
                lastImmediateAnnouncedStepIndex = session.currentStepIndex
            }
        }
        vibrateShortIfEnabled()
        telemetryLogger.log(
            type = "step_advanced",
            message = "Advanced to next route step.",
            attributes = linkedMapOf(
                "step_index" to session.currentStepIndex,
                "step_count" to session.steps.size,
                "instruction" to session.steps[session.currentStepIndex].instruction,
            ),
        )
        refreshDiagnosticsState()
    }

    private fun maybeAnnounceCountdownInstruction(
        session: RouteSession,
        state: ActiveNavigationState,
    ): Boolean {
        if (!_uiState.value.settingsState.turnByTurnAnnouncements) return false
        val upcomingStepIndex = session.currentStepIndex + 1
        val upcomingStep = session.steps.getOrNull(upcomingStepIndex) ?: return false
        val distanceToNext = state.distanceToNextMeters
        val milestoneMeters = NavigationScenarioCore.countdownMilestoneMeters(distanceToNext) ?: return false

        if (upcomingStepIndex != lastCountdownStepIndex) {
            lastCountdownStepIndex = upcomingStepIndex
            lastCountdownMilestoneMeters = null
        }
        val lastMilestone = lastCountdownMilestoneMeters
        if (lastMilestone != null && milestoneMeters >= lastMilestone) return false

        lastCountdownMilestoneMeters = milestoneMeters
        speakNavigationNow(
            string(
                R.string.format_navigation_upcoming_instruction,
                milestoneMeters,
                upcomingStep.instruction,
            ),
        )
        vibrateShortIfEnabled()
        telemetryLogger.log(
            type = "countdown_instruction_announced",
            message = "Countdown instruction announced.",
            attributes = linkedMapOf(
                "step_index" to upcomingStepIndex,
                "countdown_m" to milestoneMeters,
                "instruction" to upcomingStep.instruction,
            ),
        )
        refreshDiagnosticsState()
        return true
    }

    private fun maybeAnnounceImmediateInstruction(
        session: RouteSession,
        state: ActiveNavigationState,
        fix: LocationFix,
    ): Boolean {
        if (!_uiState.value.settingsState.turnByTurnAnnouncements) return false
        val upcomingStepIndex = session.currentStepIndex + 1
        val upcomingStep = session.steps.getOrNull(upcomingStepIndex) ?: return false
        if (upcomingStepIndex == lastImmediateAnnouncedStepIndex) return false
        val distanceToNext = state.distanceToNextMeters
        if (
            distanceToNext <= 0 ||
            distanceToNext > NavigationScenarioCore.immediateAnnouncementThresholdMeters(fix.accuracyMeters)
        ) {
            return false
        }

        lastImmediateAnnouncedStepIndex = upcomingStepIndex
        speakNavigationNow(
            string(
                R.string.format_navigation_immediate_instruction,
                upcomingStep.instruction,
            ),
        )
        vibrateShortIfEnabled()
        telemetryLogger.log(
            type = "immediate_instruction_announced",
            message = "Immediate instruction announced.",
            attributes = linkedMapOf(
                "step_index" to upcomingStepIndex,
                "distance_to_next_m" to distanceToNext,
                "instruction" to upcomingStep.instruction,
            ),
        )
        refreshDiagnosticsState()
        return true
    }

    private fun logTrackingStateChangeIfNeeded(isTracking: Boolean) {
        if (lastTrackingState == isTracking) return
        lastTrackingState = isTracking
        telemetryLogger.log(
            type = "tracking_state_changed",
            message = if (isTracking) "Foreground tracking started." else "Foreground tracking stopped.",
            attributes = linkedMapOf("is_tracking" to isTracking),
        )
        refreshDiagnosticsState()
    }

    private fun logNavigationFixIfNeeded(
        session: RouteSession,
        fix: LocationFix,
        deviationMeters: Int?,
    ) {
        val movedEnough = lastTelemetryFixPoint == null ||
            distanceMeters(lastTelemetryFixPoint!!, fix.point) >= 12.0
        val staleEnough = fix.timestampMs - lastTelemetryFixTimestampMs >= 6_000L
        if (!movedEnough && !staleEnough) return

        val state = _uiState.value.activeNavigationState
        telemetryLogger.log(
            type = "navigation_fix",
            message = "Navigation fix sampled.",
            attributes = linkedMapOf(
                "lat" to fix.point.latitude,
                "lon" to fix.point.longitude,
                "accuracy_m" to fix.accuracyMeters,
                "step_index" to session.currentStepIndex,
                "step_count" to session.steps.size,
                "distance_to_next_m" to state.distanceToNextMeters,
                "remaining_distance_m" to state.remainingDistanceMeters,
                "deviation_m" to deviationMeters,
            ),
        )
        lastTelemetryFixPoint = fix.point
        lastTelemetryFixTimestampMs = fix.timestampMs
        refreshDiagnosticsState()
    }

    private fun refreshDiagnosticsState() {
        val diagnosticsState = telemetryLogger.snapshotState()
        _uiState.update { current ->
            current.copy(diagnosticsState = diagnosticsState)
        }
    }

    private fun downloadedVersionLabelOrNull(
        versionLabel: String?,
        downloadedPath: String?,
    ): String? {
        return if (downloadedPath != null && File(downloadedPath).exists()) versionLabel else null
    }

    private fun resetNavigationAnnouncementState() {
        lastAnnouncedStepIndex = -1
        lastCountdownStepIndex = -1
        lastCountdownMilestoneMeters = null
        lastImmediateAnnouncedStepIndex = -1
    }

    private fun announceNavigationStartInstruction(session: RouteSession) {
        if (!_uiState.value.settingsState.turnByTurnAnnouncements) return
        val instruction = session.steps
            .getOrNull(session.currentStepIndex)
            ?.instruction
            ?.takeIf { it.isNotBlank() }
            ?: string(R.string.generic_follow_route_guidance)
        lastAnnouncedStepIndex = session.currentStepIndex
        speakNavigationNow(instruction)
        vibrateShortIfEnabled()
        telemetryLogger.log(
            type = "navigation_instruction_announced",
            message = "Initial navigation instruction announced.",
            attributes = linkedMapOf(
                "step_index" to session.currentStepIndex,
                "instruction" to instruction,
            ),
        )
        refreshDiagnosticsState()
    }

    private fun synchronizeSpeechSettings(settings: SettingsState): SettingsState {
        val normalized = settings.copy(
            language = systemLanguageDisplayName(),
            speechRatePercent = settings.speechRatePercent.coerceIn(50, 200),
            speechVolumePercent = settings.speechVolumePercent.coerceIn(0, 100),
        )
        feedbackEngine.updateSpeechPreferences(
            outputMode = normalized.speechOutputMode,
            systemTtsEnginePackage = normalized.selectedSystemTtsEnginePackage,
            ratePercent = normalized.speechRatePercent,
            volumePercent = normalized.speechVolumePercent,
        )
        val runtime = feedbackEngine.snapshotSpeechRuntimeStatus()
        val isSelectedEngineAvailable = normalized.selectedSystemTtsEnginePackage == null ||
            runtime.availableSystemTtsEngines.any { it.packageName == normalized.selectedSystemTtsEnginePackage }
        return normalized.copy(
            isScreenReaderActive = runtime.isScreenReaderActive,
            activeScreenReaderName = runtime.activeScreenReaderName,
            availableSystemTtsEngines = runtime.availableSystemTtsEngines,
            defaultSystemTtsEngineLabel = runtime.defaultSystemTtsEngineLabel,
            activeSystemTtsEngineLabel = runtime.activeSystemTtsEngineLabel,
            isSelectedSystemTtsEngineAvailable = isSelectedEngineAvailable,
        )
    }

    private fun mergeById(existing: List<Place>, incoming: List<Place>): List<Place> {
        val byId = linkedMapOf<String, Place>()
        existing.forEach { byId[it.id] = it }
        incoming.forEach { byId[it.id] = it }
        return byId.values.toList()
    }

    private fun maybeReverseGeocode(fix: LocationFix?) {
        if (fix == null) return

        val now = System.currentTimeMillis()
        val lastPoint = lastReversePoint
        val movedEnough = lastPoint == null || distanceMeters(lastPoint, fix.point) >= 35
        val staleEnough = now - lastReverseTimestampMs >= 25_000
        if (!movedEnough && !staleEnough) return

        reverseGeocodeJob?.cancel()
        reverseGeocodeJob = viewModelScope.launch {
            try {
                val readable = routingRepository.reverseGeocode(fix.point)
                lastReversePoint = fix.point
                lastReverseTimestampMs = System.currentTimeMillis()
                _uiState.update { current ->
                    current.copy(currentLocationLabel = readable)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                lastReversePoint = fix.point
                lastReverseTimestampMs = System.currentTimeMillis()
                _uiState.update { current ->
                    current.copy(currentLocationLabel = formatCoordinateLabel(fix))
                }
            }
        }
    }

    private fun speakNow(text: String) {
        feedbackEngine.speak(text)
    }

    private fun speakNavigationNow(text: String) {
        feedbackEngine.speakNavigation(text)
    }

    private fun vibrateShortIfEnabled() {
        if (_uiState.value.settingsState.vibrationEnabled) {
            feedbackEngine.vibrateShort()
        }
    }

    private fun vibrateDoubleIfEnabled() {
        if (_uiState.value.settingsState.vibrationEnabled) {
            feedbackEngine.vibrateDouble()
        }
    }

    private fun formatCoordinateLabel(fix: LocationFix): String {
        return string(
            R.string.format_coordinates_label,
            "%.5f".format(fix.point.latitude),
            "%.5f".format(fix.point.longitude),
        )
    }

    private fun routeDeviationMeters(pathPoints: List<GeoPoint>, point: GeoPoint): Int? {
        if (pathPoints.size < 3) return null
        var minimumMeters = Double.MAX_VALUE
        for (index in 0 until pathPoints.lastIndex) {
            val candidate = pointToSegmentDistanceMeters(
                point = point,
                start = pathPoints[index],
                end = pathPoints[index + 1],
            )
            if (candidate < minimumMeters) {
                minimumMeters = candidate
            }
        }
        return minimumMeters.roundToInt()
    }

    private fun pointToSegmentDistanceMeters(
        point: GeoPoint,
        start: GeoPoint,
        end: GeoPoint,
    ): Double {
        val latitudeReference = Math.toRadians((point.latitude + start.latitude + end.latitude) / 3.0)
        val earthRadius = 6_371_000.0

        fun project(geoPoint: GeoPoint): Pair<Double, Double> {
            val x = Math.toRadians(geoPoint.longitude) * earthRadius * kotlin.math.cos(latitudeReference)
            val y = Math.toRadians(geoPoint.latitude) * earthRadius
            return x to y
        }

        val (px, py) = project(point)
        val (sx, sy) = project(start)
        val (ex, ey) = project(end)
        val dx = ex - sx
        val dy = ey - sy
        if (dx == 0.0 && dy == 0.0) {
            return kotlin.math.hypot(px - sx, py - sy)
        }

        val t = (((px - sx) * dx) + ((py - sy) * dy)) / ((dx * dx) + (dy * dy))
        val clamped = t.coerceIn(0.0, 1.0)
        val nearestX = sx + (clamped * dx)
        val nearestY = sy + (clamped * dy)
        return kotlin.math.hypot(px - nearestX, py - nearestY)
    }

    private fun distanceMeters(a: GeoPoint, b: GeoPoint): Double {
        val earthRadius = 6_371_000.0
        val lat1 = Math.toRadians(a.latitude)
        val lon1 = Math.toRadians(a.longitude)
        val lat2 = Math.toRadians(b.latitude)
        val lon2 = Math.toRadians(b.longitude)
        val dLat = lat2 - lat1
        val dLon = lon2 - lon1
        val h =
            kotlin.math.sin(dLat / 2).let { it * it } +
                kotlin.math.cos(lat1) * kotlin.math.cos(lat2) *
                kotlin.math.sin(dLon / 2).let { it * it }
        return 2 * earthRadius * kotlin.math.asin(kotlin.math.sqrt(h))
    }

    override fun onCleared() {
        feedbackEngine.shutdown()
        super.onCleared()
    }
}
