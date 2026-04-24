package com.navilive.android.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.AssistantDirection
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.BookmarkAdd
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocationSearching
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.navilive.android.R
import com.navilive.android.model.ActiveNavigationState
import com.navilive.android.model.AnnouncementCadenceMode
import com.navilive.android.model.AppUpdatePhase
import com.navilive.android.model.AppUpdateState
import com.navilive.android.model.DiagnosticsState
import com.navilive.android.model.HeadingState
import com.navilive.android.model.Place
import com.navilive.android.model.RouteSummary
import com.navilive.android.model.SettingsState
import com.navilive.android.model.SpeechOutputMode
import com.navilive.android.model.UpdateChannel
import java.math.BigDecimal
import kotlin.math.roundToInt

private enum class BannerTone {
    Info,
    Success,
    Warning,
    Critical,
}

private data class StatusPresentation(
    val title: String,
    val message: String,
    val tone: BannerTone,
)

private val WarningContainer = Color(0xFFFFEDC2)
private val OnWarningContainer = Color(0xFF3B2F04)
private val SuccessContainer = Color(0xFFDDF4E0)
private val OnSuccessContainer = Color(0xFF14311A)
private const val SupportBaseUrl = "https://paypal.me/KazimierzParzych"
private val SupportQuickAmounts = listOf(5, 10, 20, 50)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScreenScaffold(
    title: String,
    showBack: Boolean,
    onBack: (() -> Unit)? = null,
    actions: @Composable (() -> Unit)? = null,
    content: @Composable (Modifier) -> Unit,
) {
    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    if (showBack && onBack != null) {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.action_back))
                        }
                    }
                },
                actions = { actions?.invoke() },
            )
        },
    ) { innerPadding ->
        content(
            Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 16.dp, vertical = 12.dp),
        )
    }
}

@Composable
fun StartScreen(
    currentLocation: String,
    statusMessage: String,
    lastRoutePlaceId: String?,
    quickFavorites: List<Place>,
    accuracyMeters: Float?,
    hasLocationPermission: Boolean,
    isForegroundTracking: Boolean,
    onSearch: () -> Unit,
    onCurrentPosition: () -> Unit,
    onFavorites: () -> Unit,
    onResumeLastRoute: (String) -> Unit,
    onOpenQuickFavorite: (String) -> Unit,
    onSettings: () -> Unit,
    onGrantLocationPermission: () -> Unit,
    onToggleTracking: () -> Unit,
) {
    val locationStatus = locationStatus(
        hasLocationPermission = hasLocationPermission,
        accuracyMeters = accuracyMeters,
        isForegroundTracking = isForegroundTracking,
        currentLocation = currentLocation,
    )

    ScreenScaffold(
        title = stringResource(R.string.app_name),
        showBack = false,
        actions = {
            IconButton(onClick = onSettings) {
                Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.action_settings))
            }
        },
    ) { modifier ->
        Column(
            modifier = modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            StatusCard(
                title = locationStatus.title,
                message = locationStatus.message,
                tone = locationStatus.tone,
            )

            FilledTonalButton(
                onClick = if (hasLocationPermission) onToggleTracking else onGrantLocationPermission,
                modifier = Modifier.fillMaxWidth(),
            ) {
                val label = when {
                    !hasLocationPermission -> stringResource(R.string.start_button_grant_location_access)
                    isForegroundTracking -> stringResource(R.string.start_button_stop_live_tracking)
                    else -> stringResource(R.string.start_button_start_live_tracking)
                }
                Text(label)
            }

            PrimaryActionButton(
                label = stringResource(R.string.start_primary_search),
                icon = Icons.Filled.Search,
                onClick = onSearch,
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SecondaryActionButton(
                    label = stringResource(R.string.start_current_position),
                    icon = Icons.Filled.Map,
                    onClick = onCurrentPosition,
                    modifier = Modifier.weight(1f),
                )
                SecondaryActionButton(
                    label = stringResource(R.string.start_favorites),
                    icon = Icons.Filled.Favorite,
                    onClick = onFavorites,
                    modifier = Modifier.weight(1f),
                )
            }

            if (lastRoutePlaceId != null) {
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        SectionHeading(stringResource(R.string.start_last_route_title))
                        Text(
                            text = statusMessage,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        PrimaryActionButton(
                            label = stringResource(R.string.start_resume_last_route),
                            icon = Icons.Filled.Navigation,
                            onClick = { onResumeLastRoute(lastRoutePlaceId) },
                        )
                    }
                }
            }

            if (quickFavorites.isNotEmpty()) {
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        SectionHeading(stringResource(R.string.start_quick_favorites_title))
                        quickFavorites.take(3).forEach { place ->
                            OutlinedButton(
                                onClick = { onOpenQuickFavorite(place.id) },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Icon(
                                    imageVector = if (place.id == "home") Icons.Filled.Home else Icons.Filled.Favorite,
                                    contentDescription = null,
                                )
                                Spacer(Modifier.width(8.dp))
                                Column(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalArrangement = Arrangement.spacedBy(2.dp),
                                ) {
                                    Text(place.name, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        text = place.address,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun BootstrapScreen() {
    ScreenScaffold(title = stringResource(R.string.app_name), showBack = false) { modifier ->
        Column(
            modifier = modifier,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            StatusCard(
                title = stringResource(R.string.bootstrap_loading_title),
                message = stringResource(R.string.bootstrap_loading_message),
                tone = BannerTone.Info,
            )
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
fun OnboardingScreen(
    onContinue: () -> Unit,
) {
    ScreenScaffold(title = stringResource(R.string.onboarding_title), showBack = false) { modifier ->
        Column(
            modifier = modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            StatusCard(
                title = stringResource(R.string.onboarding_status_title),
                message = stringResource(R.string.onboarding_status_message),
                tone = BannerTone.Success,
            )

            TutorialOverviewCards()

            Spacer(modifier = Modifier.weight(1f, fill = false))

            PrimaryActionButton(
                label = stringResource(R.string.onboarding_continue),
                icon = Icons.Filled.Navigation,
                onClick = onContinue,
            )
        }
    }
}

@Composable
fun TutorialScreen(
    showOnStartup: Boolean,
    onShowOnStartupChange: (Boolean) -> Unit,
    onDone: () -> Unit,
    onBack: () -> Unit,
) {
    BackHandler(onBack = onBack)

    ScreenScaffold(
        title = stringResource(R.string.tutorial_navigation_title),
        showBack = true,
        onBack = onBack,
    ) { modifier ->
        Column(
            modifier = modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            StatusCard(
                title = stringResource(R.string.tutorial_status_title),
                message = stringResource(R.string.tutorial_status_message),
                tone = BannerTone.Info,
            )

            TutorialOverviewCards()
            TutorialStartupCard(
                showOnStartup = showOnStartup,
                onShowOnStartupChange = onShowOnStartupChange,
            )

            Spacer(modifier = Modifier.weight(1f, fill = false))

            PrimaryActionButton(
                label = stringResource(R.string.tutorial_done),
                icon = Icons.Filled.Navigation,
                onClick = onDone,
            )
        }
    }
}

@Composable
fun HelpPrivacyScreen(
    showTutorialOnStartup: Boolean,
    onShowTutorialOnStartupChange: (Boolean) -> Unit,
    onOpenTutorial: () -> Unit,
    onOpenSupportUrl: (String) -> Unit,
    onBack: () -> Unit,
) {
    ScreenScaffold(
        title = stringResource(R.string.settings_help_privacy_title),
        showBack = true,
        onBack = onBack,
    ) { modifier ->
        Column(
            modifier = modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            StatusCard(
                title = stringResource(R.string.settings_help_privacy_title),
                message = stringResource(R.string.settings_help_privacy_status_message),
                tone = BannerTone.Info,
            )
            TutorialSettingsCard(
                showOnStartup = showTutorialOnStartup,
                onShowOnStartupChange = onShowTutorialOnStartupChange,
                onOpenTutorial = onOpenTutorial,
            )
            SupportDevelopmentCard(
                onOpenSupportUrl = onOpenSupportUrl,
            )
            PrivacyInfoCard()
        }
    }
}

@Composable
fun PermissionsScreen(
    hasLocationPermission: Boolean,
    onGrantPermission: () -> Unit,
    onContinueWithoutPermission: () -> Unit,
) {
    val status = if (hasLocationPermission) {
        StatusPresentation(
            title = stringResource(R.string.permissions_ready_title),
            message = stringResource(R.string.permissions_ready_message),
            tone = BannerTone.Success,
        )
    } else {
        StatusPresentation(
            title = stringResource(R.string.permissions_request_title),
            message = stringResource(R.string.permissions_request_message),
            tone = BannerTone.Warning,
        )
    }

    ScreenScaffold(title = stringResource(R.string.permissions_title), showBack = false) { modifier ->
        Column(
            modifier = modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            StatusCard(
                title = status.title,
                message = status.message,
                tone = status.tone,
            )

            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    SectionHeading(stringResource(R.string.permissions_why_it_matters_title))
                    LabelValue(stringResource(R.string.permissions_current_position_label), stringResource(R.string.permissions_current_position_message))
                    LabelValue(stringResource(R.string.permissions_live_tracking_label), stringResource(R.string.permissions_live_tracking_message))
                    LabelValue(stringResource(R.string.permissions_recalculation_label), stringResource(R.string.permissions_recalculation_message))
                }
            }

            PrimaryActionButton(
                label = if (hasLocationPermission) {
                    stringResource(R.string.permissions_open_start_screen)
                } else {
                    stringResource(R.string.permissions_grant_location_access)
                },
                icon = Icons.Filled.LocationSearching,
                onClick = onGrantPermission,
            )

            SecondaryActionButton(
                label = stringResource(R.string.permissions_continue_for_now),
                icon = Icons.Filled.Navigation,
                onClick = onContinueWithoutPermission,
            )
        }
    }
}

@Composable
fun SearchScreen(
    query: String,
    results: List<Place>,
    isLoading: Boolean,
    onQueryChange: (String) -> Unit,
    onSelectPlace: (String) -> Unit,
    onBack: () -> Unit,
) {
    ScreenScaffold(title = stringResource(R.string.search_title), showBack = true, onBack = onBack) { modifier ->
        LazyColumn(
            modifier = modifier,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(bottom = 16.dp),
        ) {
            item {
                StatusCard(
                    title = stringResource(R.string.search_status_title),
                    message = stringResource(R.string.search_status_message),
                    tone = BannerTone.Info,
                )
            }
            item {
                OutlinedTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    modifier = Modifier.fillMaxWidth(),
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    label = { Text(stringResource(R.string.search_field_label)) },
                    supportingText = { Text(stringResource(R.string.search_field_supporting)) },
                    singleLine = true,
                )
            }
            if (isLoading) {
                item { LinearProgressIndicator(modifier = Modifier.fillMaxWidth()) }
            }
            item {
                SectionHeading(
                    if (query.isBlank()) {
                        stringResource(R.string.search_suggested_places)
                    } else {
                        stringResource(R.string.search_results)
                    },
                )
            }
            if (results.isEmpty()) {
                item {
                    EmptyStateCard(
                        title = if (query.isBlank()) {
                            stringResource(R.string.search_empty_start_title)
                        } else {
                            stringResource(R.string.search_empty_results_title)
                        },
                        message = if (query.isBlank()) {
                            stringResource(R.string.search_empty_start_message)
                        } else {
                            stringResource(R.string.search_empty_results_message)
                        },
                    )
                }
            } else {
                items(results, key = { it.id }) { place ->
                    ElevatedCard(
                        onClick = { onSelectPlace(place.id) },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(place.name, fontWeight = FontWeight.SemiBold)
                            Text(place.address, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(placeTimingLabel(place), style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun PlaceDetailsScreen(
    place: Place,
    isFavorite: Boolean,
    onShowRoute: () -> Unit,
    onToggleFavorite: () -> Unit,
    onBack: () -> Unit,
) {
    ScreenScaffold(title = stringResource(R.string.place_details_title), showBack = true, onBack = onBack) { modifier ->
        Column(
            modifier = modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            StatusCard(
                title = stringResource(R.string.place_details_status_title),
                message = stringResource(R.string.place_details_status_message),
                tone = BannerTone.Info,
            )

            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        text = place.name,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.semantics { heading() },
                    )
                    LabelValue(stringResource(R.string.label_address), place.address)
                    LabelValue(stringResource(R.string.label_walking_estimate), placeTimingLabel(place))
                    place.phone?.let { LabelValue(stringResource(R.string.label_phone), it) }
                    place.website?.let { LabelValue(stringResource(R.string.label_website), it) }
                }
            }

            HelperMapCard(
                title = stringResource(R.string.helper_map_title),
                subtitle = stringResource(R.string.place_details_helper_map_message),
            )

            PrimaryActionButton(
                label = stringResource(R.string.place_details_show_route),
                icon = Icons.AutoMirrored.Filled.AssistantDirection,
                onClick = onShowRoute,
            )

            SecondaryActionButton(
                label = if (isFavorite) {
                    stringResource(R.string.common_remove_from_favorites)
                } else {
                    stringResource(R.string.common_save_favorite)
                },
                icon = if (isFavorite) Icons.Filled.Favorite else Icons.Filled.BookmarkAdd,
                onClick = onToggleFavorite,
            )
        }
    }
}

@Composable
fun RouteSummaryScreen(
    place: Place,
    summary: RouteSummary,
    isFavorite: Boolean,
    isLoadingRoute: Boolean,
    onSaveFavorite: () -> Unit,
    onStartRoute: () -> Unit,
    onBack: () -> Unit,
) {
    ScreenScaffold(title = stringResource(R.string.route_summary_title), showBack = true, onBack = onBack) { modifier ->
        Column(
            modifier = modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            StatusCard(
                title = stringResource(R.string.route_summary_status_title),
                message = stringResource(R.string.route_summary_status_message),
                tone = BannerTone.Success,
            )

            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        text = place.name,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(place.address, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    HorizontalDivider()
                    LabelValue(stringResource(R.string.label_travel_time), stringResource(R.string.format_eta_minutes, summary.etaMinutes))
                    LabelValue(stringResource(R.string.label_distance), stringResource(R.string.format_distance_meters, summary.distanceMeters))
                    LabelValue(stringResource(R.string.label_mode), summary.modeLabel)
                }
            }

            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SectionHeading(stringResource(R.string.route_summary_guidance_preview))
                    summary.steps.take(3).forEachIndexed { index, step ->
                        Text(
                            text = stringResource(R.string.format_step_preview, index + 1, step.instruction),
                            color = if (index == 0) {
                                MaterialTheme.colorScheme.onSurface
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    }
                }
            }

            SecondaryActionButton(
                label = if (isFavorite) {
                    stringResource(R.string.route_summary_favorite_saved)
                } else {
                    stringResource(R.string.common_save_favorite)
                },
                icon = if (isFavorite) Icons.Filled.Favorite else Icons.Filled.BookmarkAdd,
                onClick = onSaveFavorite,
            )

            PrimaryActionButton(
                label = if (isLoadingRoute) {
                    stringResource(R.string.route_summary_preparing_route)
                } else {
                    stringResource(R.string.route_summary_start_route)
                },
                icon = Icons.Filled.Navigation,
                enabled = !isLoadingRoute,
                onClick = onStartRoute,
            )

            HelperMapCard(
                title = stringResource(R.string.helper_map_title),
                subtitle = stringResource(R.string.route_summary_helper_map_message),
            )
        }
    }
}

@Composable
fun HeadingAlignScreen(
    place: Place,
    headingState: HeadingState,
    onCheckHeading: () -> Unit,
    onProceed: () -> Unit,
    onSkip: () -> Unit,
    onBack: () -> Unit,
) {
    val status = if (headingState.isAligned) {
        StatusPresentation(
            title = stringResource(R.string.heading_confirmed_title),
            message = stringResource(R.string.heading_confirmed_message),
            tone = BannerTone.Success,
        )
    } else {
        StatusPresentation(
            title = stringResource(R.string.heading_set_title),
            message = headingState.instruction,
            tone = BannerTone.Warning,
        )
    }

    ScreenScaffold(title = stringResource(R.string.heading_title), showBack = true, onBack = onBack) { modifier ->
        Column(
            modifier = modifier,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            StatusCard(status.title, status.message, status.tone)

            Text(
                text = stringResource(R.string.heading_destination, place.name),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.semantics { heading() },
            )

            Surface(
                modifier = Modifier.size(220.dp),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Filled.Navigation,
                        contentDescription = null,
                        modifier = Modifier
                            .size(104.dp)
                            .rotate(headingState.arrowRotationDeg),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }

            Text(
                text = headingState.instruction,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium,
            )

            Spacer(modifier = Modifier.weight(1f))

            SecondaryActionButton(
                label = stringResource(R.string.heading_check_alignment),
                icon = Icons.Filled.LocationSearching,
                onClick = onCheckHeading,
            )

            PrimaryActionButton(
                label = stringResource(R.string.heading_start_walking),
                icon = Icons.AutoMirrored.Filled.DirectionsWalk,
                enabled = headingState.isAligned,
                onClick = onProceed,
            )

            TextButton(onClick = onSkip) {
                Text(stringResource(R.string.heading_skip))
            }
        }
    }
}

@Composable
fun ActiveNavigationScreen(
    place: Place,
    state: ActiveNavigationState,
    hasLocationPermission: Boolean,
    accuracyMeters: Float?,
    onPauseResume: () -> Unit,
    onRepeatInstruction: () -> Unit,
    onRecalculate: () -> Unit,
    onArrived: () -> Unit,
    onStop: () -> Unit,
) {
    val status = navigationStatus(
        state = state,
        hasLocationPermission = hasLocationPermission,
        accuracyMeters = accuracyMeters,
    )

    ScreenScaffold(title = stringResource(R.string.active_navigation_title), showBack = false) { modifier ->
        Column(
            modifier = modifier,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            StatusCard(status.title, status.message, status.tone)

            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        text = stringResource(R.string.active_navigation_to_destination, place.name),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(
                        text = state.progressLabel,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = state.currentInstruction,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(state.nextInstruction, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    LabelValue(
                        stringResource(R.string.active_navigation_distance_to_next),
                        stringResource(R.string.format_distance_meters, state.distanceToNextMeters),
                    )
                    LabelValue(
                        stringResource(R.string.active_navigation_remaining_distance),
                        stringResource(R.string.format_distance_meters, state.remainingDistanceMeters),
                    )
                    state.offRouteDistanceMeters?.let { deviation ->
                        LabelValue(
                            stringResource(R.string.active_navigation_distance_from_route),
                            stringResource(R.string.format_distance_meters, deviation),
                        )
                    }
                }
            }

            FilledTonalButton(
                onClick = onRecalculate,
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isRecalculating,
            ) {
                Icon(Icons.Filled.Refresh, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(
                    when {
                        state.isRecalculating -> stringResource(R.string.active_navigation_recalculating)
                        state.isOffRoute -> stringResource(R.string.active_navigation_recalculate)
                        else -> stringResource(R.string.active_navigation_need_new_route)
                    },
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SecondaryActionButton(
                    label = if (state.isPaused) stringResource(R.string.common_resume) else stringResource(R.string.common_pause),
                    icon = if (state.isPaused) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                    onClick = onPauseResume,
                    modifier = Modifier.weight(1f),
                )
                SecondaryActionButton(
                    label = stringResource(R.string.common_repeat),
                    icon = Icons.AutoMirrored.Filled.VolumeUp,
                    onClick = onRepeatInstruction,
                    modifier = Modifier.weight(1f),
                )
            }

            OutlinedButton(
                onClick = onArrived,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.active_navigation_arrived))
            }

            PrimaryActionButton(
                label = stringResource(R.string.active_navigation_stop),
                icon = Icons.Filled.Stop,
                onClick = onStop,
            )
        }
    }
}

@Composable
fun CurrentPositionScreen(
    currentLocation: String,
    accuracyMeters: Float?,
    hasLocationPermission: Boolean,
    quickFavorites: List<Place>,
    onReadLocation: () -> Unit,
    onSearch: () -> Unit,
    onPickFavorite: (String) -> Unit,
    onBack: () -> Unit,
) {
    val status = currentPositionStatus(hasLocationPermission, accuracyMeters)

    ScreenScaffold(title = stringResource(R.string.current_position_title), showBack = true, onBack = onBack) { modifier ->
        Column(
            modifier = modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            StatusCard(status.title, status.message, status.tone)

            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SectionHeading(stringResource(R.string.current_position_current_address))
                    Text(currentLocation)
                    accuracyMeters?.let { accuracy ->
                        Text(
                            text = stringResource(R.string.current_position_accuracy, accuracy.toInt()),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            PrimaryActionButton(
                label = stringResource(R.string.current_position_read_aloud),
                    icon = Icons.AutoMirrored.Filled.VolumeUp,
                onClick = onReadLocation,
            )

            SecondaryActionButton(
                label = stringResource(R.string.current_position_search_destination),
                icon = Icons.Filled.Search,
                onClick = onSearch,
            )

            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    SectionHeading(stringResource(R.string.common_favorites))
                    if (quickFavorites.isEmpty()) {
                        EmptyStateCard(
                            title = stringResource(R.string.current_position_no_favorites_title),
                            message = stringResource(R.string.current_position_no_favorites_message),
                        )
                    } else {
                        quickFavorites.take(4).forEach { place ->
                            OutlinedButton(
                                onClick = { onPickFavorite(place.id) },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Icon(
                                    imageVector = if (place.id == "home") Icons.Filled.Home else Icons.Filled.Favorite,
                                    contentDescription = null,
                                )
                                Spacer(Modifier.width(8.dp))
                                Column(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalArrangement = Arrangement.spacedBy(2.dp),
                                ) {
                                    Text(place.name, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        text = place.address,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun FavoritesScreen(
    favorites: List<Place>,
    onSelectFavorite: (String) -> Unit,
    onRemoveFavorite: (String) -> Unit,
    onAddFavorite: () -> Unit,
    onBack: () -> Unit,
) {
    ScreenScaffold(title = stringResource(R.string.favorites_title), showBack = true, onBack = onBack) { modifier ->
        LazyColumn(
            modifier = modifier,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(bottom = 16.dp),
        ) {
            item {
                StatusCard(
                    title = stringResource(R.string.favorites_status_title),
                    message = stringResource(R.string.favorites_status_message),
                    tone = BannerTone.Info,
                )
            }
            item {
                FilledTonalButton(
                    onClick = onAddFavorite,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Filled.BookmarkAdd, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.favorites_add_from_search))
                }
            }
            if (favorites.isEmpty()) {
                item {
                    EmptyStateCard(
                        title = stringResource(R.string.favorites_empty_title),
                        message = stringResource(R.string.favorites_empty_message),
                    )
                }
            } else {
                items(favorites, key = { it.id }) { place ->
                    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Text(place.name, fontWeight = FontWeight.SemiBold)
                            Text(place.address, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(placeTimingLabel(place))
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                SecondaryActionButton(
                                    label = stringResource(R.string.favorites_route),
                                    icon = Icons.Filled.Navigation,
                                    onClick = { onSelectFavorite(place.id) },
                                    modifier = Modifier.weight(1f),
                                )
                                SecondaryActionButton(
                                    label = stringResource(R.string.favorites_remove),
                                    icon = Icons.Filled.Stop,
                                    onClick = { onRemoveFavorite(place.id) },
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsScreen(
    state: SettingsState,
    updateState: AppUpdateState,
    diagnosticsState: DiagnosticsState,
    onOpenHelpPrivacy: () -> Unit,
    onVibrationChange: (Boolean) -> Unit,
    onAutoRecalculateChange: (Boolean) -> Unit,
    onJunctionAlertChange: (Boolean) -> Unit,
    onTurnByTurnChange: (Boolean) -> Unit,
    onAnnouncementCadenceModeChange: (AnnouncementCadenceMode) -> Unit,
    onUpdateChannelChange: (UpdateChannel) -> Unit,
    onSpeechOutputModeChange: (SpeechOutputMode) -> Unit,
    onSystemTtsEngineChange: (String?) -> Unit,
    onOpenSystemTtsSettings: () -> Unit,
    onSpeechRateChange: (Int) -> Unit,
    onSpeechVolumeChange: (Int) -> Unit,
    onPreviewSpeech: () -> Unit,
    onPrimaryUpdateAction: () -> Unit,
    onOpenReleasePage: (String) -> Unit,
    onExportDiagnostics: () -> Unit,
    onClearDiagnostics: () -> Unit,
    onShareDiagnostics: (() -> Unit)?,
    onBack: () -> Unit,
) {
    ScreenScaffold(title = stringResource(R.string.settings_title), showBack = true, onBack = onBack) { modifier ->
        Column(
            modifier = modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            StatusCard(
                title = stringResource(R.string.settings_status_title),
                message = stringResource(R.string.settings_status_message),
                tone = BannerTone.Info,
            )

            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    SectionHeading(stringResource(R.string.settings_help_privacy_title))
                    Text(
                        text = stringResource(R.string.settings_help_privacy_summary),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    FilledTonalButton(
                        onClick = onOpenHelpPrivacy,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(stringResource(R.string.settings_help_privacy_open_button))
                    }
                }
            }

            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    SectionHeading(stringResource(R.string.settings_language_title))
                    LabelValue(
                        stringResource(R.string.settings_language_detected_label),
                        value = state.language,
                    )
                    Text(
                        text = stringResource(R.string.settings_language_detected_message),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            VoiceOutputSettingsCard(
                state = state,
                onSpeechOutputModeChange = onSpeechOutputModeChange,
                onSystemTtsEngineChange = onSystemTtsEngineChange,
                onOpenSystemTtsSettings = onOpenSystemTtsSettings,
                onPreviewSpeech = onPreviewSpeech,
            )

            VoiceSliderCard(
                title = stringResource(R.string.settings_speech_rate_title),
                description = stringResource(R.string.settings_speech_rate_message),
                value = state.speechRatePercent,
                valueRange = 50f..200f,
                steps = 29,
                enabled = state.speechOutputMode == SpeechOutputMode.System,
                disabledMessage = stringResource(R.string.settings_speech_controls_disabled_message),
                onCommit = onSpeechRateChange,
            )

            VoiceSliderCard(
                title = stringResource(R.string.settings_speech_volume_title),
                description = stringResource(R.string.settings_speech_volume_message),
                value = state.speechVolumePercent,
                valueRange = 0f..100f,
                steps = 19,
                enabled = state.speechOutputMode == SpeechOutputMode.System,
                disabledMessage = stringResource(R.string.settings_speech_controls_disabled_message),
                onCommit = onSpeechVolumeChange,
            )

            SettingsToggleCard(
                title = stringResource(R.string.settings_voice_title),
                description = stringResource(R.string.settings_voice_message),
                checked = state.turnByTurnAnnouncements,
                onCheckedChange = onTurnByTurnChange,
            )

            AnnouncementCadenceCard(
                selectedMode = state.announcementCadenceMode,
                enabled = state.turnByTurnAnnouncements,
                onModeChange = onAnnouncementCadenceModeChange,
            )

            SettingsToggleCard(
                title = stringResource(R.string.settings_vibration_title),
                description = stringResource(R.string.settings_vibration_message),
                checked = state.vibrationEnabled,
                onCheckedChange = onVibrationChange,
            )

            SettingsToggleCard(
                title = stringResource(R.string.settings_auto_recalculate_title),
                description = stringResource(R.string.settings_auto_recalculate_message),
                checked = state.autoRecalculate,
                onCheckedChange = onAutoRecalculateChange,
            )

            SettingsToggleCard(
                title = stringResource(R.string.settings_junction_alerts_title),
                description = stringResource(R.string.settings_junction_alerts_message),
                checked = state.junctionAlerts,
                onCheckedChange = onJunctionAlertChange,
            )

            AppUpdateCard(
                settingsState = state,
                updateState = updateState,
                onUpdateChannelChange = onUpdateChannelChange,
                onPrimaryUpdateAction = onPrimaryUpdateAction,
                onOpenReleasePage = onOpenReleasePage,
            )

            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    SectionHeading(stringResource(R.string.settings_debug_telemetry_title))
                    LabelValue(stringResource(R.string.settings_buffered_events), diagnosticsState.eventCount.toString())
                    LabelValue(stringResource(R.string.settings_active_session), diagnosticsState.activeSessionLabel)
                    LabelValue(stringResource(R.string.settings_last_event), diagnosticsState.lastEventLabel)
                    diagnosticsState.lastExportPath?.let { exportPath ->
                        LabelValue(stringResource(R.string.settings_last_export), exportPath)
                    }
                    FilledTonalButton(
                        onClick = onExportDiagnostics,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Filled.FileDownload, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.settings_export_telemetry))
                    }
                    if (diagnosticsState.lastExportPath != null && onShareDiagnostics != null) {
                        OutlinedButton(
                            onClick = onShareDiagnostics,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(Icons.Filled.Share, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.settings_share_last_export))
                        }
                    }
                    OutlinedButton(
                        onClick = onClearDiagnostics,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Filled.Delete, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.settings_clear_telemetry))
                    }
                }
            }
        }
    }
}

@Composable
private fun AnnouncementCadenceCard(
    selectedMode: AnnouncementCadenceMode,
    enabled: Boolean,
    onModeChange: (AnnouncementCadenceMode) -> Unit,
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(stringResource(R.string.settings_announcement_cadence_title))
            Text(
                text = stringResource(R.string.settings_announcement_cadence_message),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SelectableOptionRow(
                title = stringResource(R.string.settings_announcement_cadence_distance_title),
                description = stringResource(R.string.settings_announcement_cadence_distance_message),
                selected = selectedMode == AnnouncementCadenceMode.Distance,
                onSelect = {
                    if (enabled) {
                        onModeChange(AnnouncementCadenceMode.Distance)
                    }
                },
            )
            SelectableOptionRow(
                title = stringResource(R.string.settings_announcement_cadence_time_title),
                description = stringResource(R.string.settings_announcement_cadence_time_message),
                selected = selectedMode == AnnouncementCadenceMode.Time,
                onSelect = {
                    if (enabled) {
                        onModeChange(AnnouncementCadenceMode.Time)
                    }
                },
            )
            if (!enabled) {
                Text(
                    text = stringResource(R.string.settings_announcement_cadence_disabled_message),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun TutorialOverviewCards() {
    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {},
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(stringResource(R.string.onboarding_how_it_works_title))
            LabelValue(stringResource(R.string.onboarding_search_label), stringResource(R.string.onboarding_search_message))
            LabelValue(stringResource(R.string.onboarding_align_label), stringResource(R.string.onboarding_align_message))
            LabelValue(stringResource(R.string.onboarding_navigate_label), stringResource(R.string.onboarding_navigate_message))
        }
    }

    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {},
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SectionHeading(stringResource(R.string.onboarding_expect_title))
            Text(
                text = stringResource(R.string.onboarding_expect_message),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun TutorialStartupCard(
    showOnStartup: Boolean,
    onShowOnStartupChange: (Boolean) -> Unit,
) {
    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {},
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(stringResource(R.string.tutorial_startup_section_title))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.tutorial_show_on_start_title),
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(12.dp))
                Switch(
                    checked = showOnStartup,
                    onCheckedChange = onShowOnStartupChange,
                )
            }
            Text(
                text = stringResource(R.string.tutorial_show_on_start_message),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun TutorialSettingsCard(
    showOnStartup: Boolean,
    onShowOnStartupChange: (Boolean) -> Unit,
    onOpenTutorial: () -> Unit,
) {
    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {},
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(stringResource(R.string.tutorial_navigation_title))
            Text(
                text = stringResource(R.string.settings_help_privacy_tutorial_message),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            FilledTonalButton(
                onClick = onOpenTutorial,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.settings_help_privacy_tutorial_open_button))
            }
            HorizontalDivider()
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.tutorial_show_on_start_title),
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(12.dp))
                Switch(
                    checked = showOnStartup,
                    onCheckedChange = onShowOnStartupChange,
                )
            }
            Text(
                text = stringResource(R.string.tutorial_show_on_start_message),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SupportDevelopmentCard(
    onOpenSupportUrl: (String) -> Unit,
) {
    val clipboardManager = LocalClipboardManager.current
    var customAmountInput by remember { mutableStateOf("") }
    var localStatusMessage by remember { mutableStateOf<String?>(null) }
    val copySuccessMessage = stringResource(R.string.settings_support_copy_success)
    val invalidAmountMessage = stringResource(R.string.settings_support_custom_invalid)

    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(stringResource(R.string.settings_support_section_title))
            Text(
                text = stringResource(R.string.settings_support_body),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = stringResource(R.string.settings_support_amounts_description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SupportQuickAmounts.chunked(2).forEach { amountRow ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    amountRow.forEach { amount ->
                        Button(
                            onClick = {
                                localStatusMessage = null
                                onOpenSupportUrl(supportUrlForAmount(amount.toString()))
                            },
                            modifier = Modifier.weight(1f),
                        ) {
                            Text(stringResource(R.string.format_settings_support_amount_button, amount))
                        }
                    }
                    if (amountRow.size == 1) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
            Text(
                text = stringResource(R.string.settings_support_custom_title),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            OutlinedTextField(
                value = customAmountInput,
                onValueChange = { customAmountInput = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = {
                    Text(stringResource(R.string.settings_support_custom_placeholder))
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            )
            FilledTonalButton(
                onClick = {
                    val normalizedAmount = normalizeSupportAmount(customAmountInput)
                    if (normalizedAmount == null) {
                        localStatusMessage = invalidAmountMessage
                    } else {
                        localStatusMessage = null
                        onOpenSupportUrl(supportUrlForAmount(normalizedAmount))
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.settings_support_custom_button))
            }
            OutlinedButton(
                onClick = {
                    localStatusMessage = null
                    onOpenSupportUrl(SupportBaseUrl)
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.settings_support_other_currency_button))
            }
            TextButton(
                onClick = {
                    clipboardManager.setText(AnnotatedString(SupportBaseUrl))
                    localStatusMessage = copySuccessMessage
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.settings_support_copy_link))
            }
            localStatusMessage?.takeIf { it.isNotBlank() }?.let { message ->
                Text(
                    text = message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun PrivacyInfoCard() {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(stringResource(R.string.settings_privacy_section_title))
            PrivacyInfoBlock(
                title = stringResource(R.string.settings_privacy_local_title),
                body = stringResource(R.string.settings_privacy_local_body),
            )
            HorizontalDivider()
            PrivacyInfoBlock(
                title = stringResource(R.string.settings_privacy_online_title),
                body = stringResource(R.string.settings_privacy_online_body),
            )
            HorizontalDivider()
            PrivacyInfoBlock(
                title = stringResource(R.string.settings_privacy_telemetry_title),
                body = stringResource(R.string.settings_privacy_telemetry_body),
            )
        }
    }
}

@Composable
private fun PrivacyInfoBlock(
    title: String,
    body: String,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = body,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun normalizeSupportAmount(input: String): String? {
    val normalized = input.trim().replace(',', '.')
    if (!normalized.matches(Regex("\\d+(\\.\\d{1,2})?"))) {
        return null
    }
    val amount = normalized.toBigDecimalOrNull() ?: return null
    if (amount <= BigDecimal.ZERO) {
        return null
    }
    return amount.stripTrailingZeros().toPlainString()
}

private fun supportUrlForAmount(amount: String): String = "$SupportBaseUrl/${amount}PLN"

@Composable
fun ArrivalScreen(
    place: Place,
    onFinish: () -> Unit,
    onReverseRoute: () -> Unit,
    onSaveFavorite: () -> Unit,
) {
    ScreenScaffold(title = stringResource(R.string.arrival_title), showBack = false) { modifier ->
        Column(
            modifier = modifier,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Surface(
                modifier = Modifier.size(132.dp),
                shape = CircleShape,
                color = SuccessContainer,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Filled.CheckCircle,
                        contentDescription = null,
                        modifier = Modifier.size(72.dp),
                        tint = OnSuccessContainer,
                    )
                }
            }

            Text(
                text = stringResource(R.string.arrival_message),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )
            Text(place.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Text(place.address, color = MaterialTheme.colorScheme.onSurfaceVariant)

            Spacer(modifier = Modifier.weight(1f))

            PrimaryActionButton(
                label = stringResource(R.string.arrival_finish),
                icon = Icons.Filled.CheckCircle,
                onClick = onFinish,
            )

            SecondaryActionButton(
                label = stringResource(R.string.arrival_reverse_route),
                icon = Icons.Filled.Navigation,
                onClick = onReverseRoute,
            )

            SecondaryActionButton(
                label = stringResource(R.string.common_save_favorite),
                icon = Icons.Filled.Favorite,
                onClick = onSaveFavorite,
            )
        }
    }
}

@Composable
fun NotFoundScreen(onBack: () -> Unit) {
    ScreenScaffold(title = stringResource(R.string.not_found_title), showBack = true, onBack = onBack) { modifier ->
        Box(modifier = modifier, contentAlignment = Alignment.Center) {
            EmptyStateCard(
                title = stringResource(R.string.not_found_message_title),
                message = stringResource(R.string.not_found_message_body),
            )
        }
    }
}

@Composable
private fun PrimaryActionButton(
    label: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Button(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .height(58.dp),
        enabled = enabled,
    ) {
        Icon(icon, contentDescription = null)
        Spacer(Modifier.width(8.dp))
        Text(label)
    }
}

@Composable
private fun SecondaryActionButton(
    label: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.height(56.dp),
    ) {
        Icon(icon, contentDescription = null)
        Spacer(Modifier.width(8.dp))
        Text(label)
    }
}

@Composable
private fun StatusCard(
    title: String,
    message: String,
    tone: BannerTone,
    modifier: Modifier = Modifier,
) {
    val (container, content) = bannerColors(tone)
    Card(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        colors = CardDefaults.cardColors(
            containerColor = container,
            contentColor = content,
        ),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )
            Text(message, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun SectionHeading(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.semantics { heading() },
    )
}

@Composable
private fun LabelValue(label: String, value: String) {
    Column(
        verticalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier.clearAndSetSemantics {
            contentDescription = "$label. $value"
        },
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
private fun HelperMapCard(
    title: String,
    subtitle: String,
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            SectionHeading(title)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(124.dp)
                    .background(
                        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f),
                        shape = MaterialTheme.shapes.medium,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Map, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun EmptyStateCard(
    title: String,
    message: String,
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(title, fontWeight = FontWeight.Bold)
            Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun VoiceOutputSettingsCard(
    state: SettingsState,
    onSpeechOutputModeChange: (SpeechOutputMode) -> Unit,
    onSystemTtsEngineChange: (String?) -> Unit,
    onOpenSystemTtsSettings: () -> Unit,
    onPreviewSpeech: () -> Unit,
) {
    val sourceMessage = when (state.speechOutputMode) {
        SpeechOutputMode.System -> stringResource(R.string.settings_speech_source_system_status)
        SpeechOutputMode.ScreenReader -> {
            val screenReaderName = state.activeScreenReaderName
            if (state.isScreenReaderActive && !screenReaderName.isNullOrBlank()) {
                stringResource(
                    R.string.format_settings_speech_source_screen_reader_active,
                    screenReaderName,
                )
            } else {
                stringResource(R.string.settings_speech_source_screen_reader_fallback)
            }
        }
    }

    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(stringResource(R.string.settings_speech_source_title))
            Text(
                text = stringResource(R.string.settings_speech_source_message),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SpeechSourceOptionRow(
                title = stringResource(R.string.settings_speech_source_system_title),
                description = stringResource(R.string.settings_speech_source_system_message),
                selected = state.speechOutputMode == SpeechOutputMode.System,
                onSelect = { onSpeechOutputModeChange(SpeechOutputMode.System) },
            )
            SpeechSourceOptionRow(
                title = stringResource(R.string.settings_speech_source_screen_reader_title),
                description = stringResource(R.string.settings_speech_source_screen_reader_message),
                selected = state.speechOutputMode == SpeechOutputMode.ScreenReader,
                onSelect = { onSpeechOutputModeChange(SpeechOutputMode.ScreenReader) },
            )
            LabelValue(stringResource(R.string.settings_speech_source_active_label), sourceMessage)
            SystemTtsEnginePicker(
                state = state,
                onSystemTtsEngineChange = onSystemTtsEngineChange,
                onOpenSystemTtsSettings = onOpenSystemTtsSettings,
            )
            FilledTonalButton(
                onClick = onPreviewSpeech,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.AutoMirrored.Filled.VolumeUp, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.settings_speech_preview_button))
            }
        }
    }
}

@Composable
private fun SpeechSourceOptionRow(
    title: String,
    description: String,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RadioButton(selected = selected, onClick = onSelect)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(
                text = description,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SystemTtsEnginePicker(
    state: SettingsState,
    onSystemTtsEngineChange: (String?) -> Unit,
    onOpenSystemTtsSettings: () -> Unit,
) {
    val defaultEngineTitle = state.defaultSystemTtsEngineLabel?.takeIf { it.isNotBlank() }?.let { label ->
        stringResource(R.string.format_settings_system_tts_default_with_name, label)
    } ?: stringResource(R.string.settings_system_tts_default_title)

    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(stringResource(R.string.settings_system_tts_title))
            Text(
                text = stringResource(R.string.settings_system_tts_message),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SelectableOptionRow(
                title = defaultEngineTitle,
                description = stringResource(R.string.settings_system_tts_default_message),
                selected = state.selectedSystemTtsEnginePackage == null,
                onSelect = { onSystemTtsEngineChange(null) },
            )
            if (state.availableSystemTtsEngines.isEmpty()) {
                Text(
                    text = stringResource(R.string.settings_system_tts_none_detected),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                state.availableSystemTtsEngines.forEach { engine ->
                    SelectableOptionRow(
                        title = engine.displayName,
                        description = engine.packageName ?: "",
                        selected = state.selectedSystemTtsEnginePackage == engine.packageName,
                        onSelect = { onSystemTtsEngineChange(engine.packageName) },
                    )
                }
            }
            state.activeSystemTtsEngineLabel?.takeIf { it.isNotBlank() }?.let { activeLabel ->
                LabelValue(
                    stringResource(R.string.settings_system_tts_active_label),
                    activeLabel,
                )
            }
            if (!state.isSelectedSystemTtsEngineAvailable) {
                Text(
                    text = stringResource(R.string.settings_system_tts_unavailable_message),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            OutlinedButton(
                onClick = onOpenSystemTtsSettings,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Filled.Settings, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.settings_system_tts_open_settings))
            }
        }
    }
}

@Composable
private fun SelectableOptionRow(
    title: String,
    description: String,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RadioButton(selected = selected, onClick = onSelect)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(title, fontWeight = FontWeight.SemiBold)
            if (description.isNotBlank()) {
                Text(
                    text = description,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun VoiceSliderCard(
    title: String,
    description: String,
    value: Int,
    valueRange: ClosedFloatingPointRange<Float>,
    steps: Int,
    enabled: Boolean,
    disabledMessage: String,
    onCommit: (Int) -> Unit,
) {
    var sliderValue by remember(value) { mutableFloatStateOf(value.toFloat()) }
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, fontWeight = FontWeight.SemiBold)
                Text(
                    text = stringResource(R.string.format_percent_value, sliderValue.roundToInt()),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                text = description,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Slider(
                value = sliderValue,
                onValueChange = { incoming ->
                    sliderValue = normalizeSliderValue(incoming, valueRange)
                },
                onValueChangeFinished = {
                    onCommit(sliderValue.roundToInt())
                },
                valueRange = valueRange,
                steps = steps,
                enabled = enabled,
            )
            if (!enabled) {
                Text(
                    text = disabledMessage,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun normalizeSliderValue(
    value: Float,
    valueRange: ClosedFloatingPointRange<Float>,
): Float {
    val rounded = (value / 5f).roundToInt() * 5f
    return rounded.coerceIn(valueRange.start, valueRange.endInclusive)
}

@Composable
private fun SettingsToggleCard(
    title: String,
    description: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, fontWeight = FontWeight.SemiBold)
                Switch(checked = checked, onCheckedChange = onCheckedChange)
            }
            Text(description, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun AppUpdateCard(
    settingsState: SettingsState,
    updateState: AppUpdateState,
    onUpdateChannelChange: (UpdateChannel) -> Unit,
    onPrimaryUpdateAction: () -> Unit,
    onOpenReleasePage: (String) -> Unit,
) {
    val latestVersionLabel = updateState.latestVersionLabel
        ?: updateState.downloadedVersionLabel
        ?: stringResource(R.string.settings_updates_not_checked)
    val action = updatePrimaryActionPresentation(updateState)

    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(stringResource(R.string.settings_updates_title))
            Text(
                text = stringResource(R.string.settings_updates_message),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            LabelValue(
                label = stringResource(R.string.settings_updates_current_version),
                value = updateState.currentVersionLabel,
            )
            LabelValue(
                label = stringResource(R.string.settings_updates_current_build),
                value = updateState.currentBuildLabel,
            )
            LabelValue(
                label = stringResource(R.string.settings_updates_latest_version),
                value = latestVersionLabel,
            )
            UpdateChannelCard(
                selectedChannel = settingsState.updateChannel,
                onUpdateChannelChange = onUpdateChannelChange,
            )
            updateState.latestAssetName?.let { assetName ->
                LabelValue(
                    label = stringResource(R.string.settings_updates_asset),
                    value = assetName,
                )
            }
            updateState.latestReleaseName?.takeIf { it.isNotBlank() }?.let { releaseName ->
                LabelValue(
                    label = stringResource(R.string.settings_updates_release_name),
                    value = releaseName,
                )
            }
            Text(
                text = updateState.statusMessage,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
            if (updateState.phase == AppUpdatePhase.Downloading) {
                val progress = (updateState.downloadProgressPercent ?: 0).coerceIn(0, 100)
                LabelValue(
                    label = stringResource(R.string.settings_updates_progress),
                    value = stringResource(R.string.format_percent_value, progress),
                )
                LinearProgressIndicator(
                    progress = progress / 100f,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            if (updateState.latestVersionLabel != null) {
                HorizontalDivider()
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = stringResource(R.string.settings_updates_release_notes),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = updateState.releaseNotes.ifBlank {
                            stringResource(R.string.settings_updates_release_notes_empty)
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 8,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            FilledTonalButton(
                onClick = onPrimaryUpdateAction,
                modifier = Modifier.fillMaxWidth(),
                enabled = action.enabled,
            ) {
                Icon(action.icon, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(action.label)
            }
            updateState.releasePageUrl?.let { releaseUrl ->
                OutlinedButton(
                    onClick = { onOpenReleasePage(releaseUrl) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Filled.Share, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.settings_updates_open_release))
                }
            }
        }
    }
}

@Composable
private fun UpdateChannelCard(
    selectedChannel: UpdateChannel,
    onUpdateChannelChange: (UpdateChannel) -> Unit,
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionHeading(stringResource(R.string.settings_updates_channel_title))
            Text(
                text = stringResource(R.string.settings_updates_channel_description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SelectableOptionRow(
                title = stringResource(R.string.settings_updates_channel_stable_title),
                description = stringResource(R.string.settings_updates_channel_stable_message),
                selected = selectedChannel == UpdateChannel.Stable,
                onSelect = { onUpdateChannelChange(UpdateChannel.Stable) },
            )
            SelectableOptionRow(
                title = stringResource(R.string.settings_updates_channel_beta_title),
                description = stringResource(R.string.settings_updates_channel_beta_message),
                selected = selectedChannel == UpdateChannel.Beta,
                onSelect = { onUpdateChannelChange(UpdateChannel.Beta) },
            )
        }
    }
}

private data class UpdatePrimaryActionPresentation(
    val label: String,
    val icon: ImageVector,
    val enabled: Boolean,
)

@Composable
private fun updatePrimaryActionPresentation(updateState: AppUpdateState): UpdatePrimaryActionPresentation {
    return when (updateState.phase) {
        AppUpdatePhase.Checking -> UpdatePrimaryActionPresentation(
            label = stringResource(R.string.settings_updates_checking_action),
            icon = Icons.Filled.Refresh,
            enabled = false,
        )
        AppUpdatePhase.Downloading -> UpdatePrimaryActionPresentation(
            label = stringResource(R.string.settings_updates_downloading_action),
            icon = Icons.Filled.FileDownload,
            enabled = false,
        )
        AppUpdatePhase.Available -> UpdatePrimaryActionPresentation(
            label = stringResource(R.string.settings_updates_download_install),
            icon = Icons.Filled.FileDownload,
            enabled = true,
        )
        AppUpdatePhase.ReadyToInstall -> UpdatePrimaryActionPresentation(
            label = stringResource(
                if (updateState.canRequestPackageInstalls) {
                    R.string.settings_updates_install
                } else {
                    R.string.settings_updates_allow_installs
                },
            ),
            icon = if (updateState.canRequestPackageInstalls) {
                Icons.Filled.CheckCircle
            } else {
                Icons.Filled.Settings
            },
            enabled = true,
        )
        else -> UpdatePrimaryActionPresentation(
            label = stringResource(R.string.settings_updates_check),
            icon = Icons.Filled.Refresh,
            enabled = true,
        )
    }
}

@Composable
private fun bannerColors(tone: BannerTone): Pair<Color, Color> {
    val colors = MaterialTheme.colorScheme
    return when (tone) {
        BannerTone.Info -> colors.secondaryContainer to colors.onSecondaryContainer
        BannerTone.Success -> SuccessContainer to OnSuccessContainer
        BannerTone.Warning -> WarningContainer to OnWarningContainer
        BannerTone.Critical -> colors.errorContainer to colors.onErrorContainer
    }
}

@Composable
private fun locationStatus(
    hasLocationPermission: Boolean,
    accuracyMeters: Float?,
    isForegroundTracking: Boolean,
    currentLocation: String,
): StatusPresentation {
    return when {
        !hasLocationPermission -> StatusPresentation(
            title = stringResource(R.string.location_status_permission_needed_title),
            message = stringResource(R.string.location_status_permission_needed_message),
            tone = BannerTone.Warning,
        )
        !isForegroundTracking -> StatusPresentation(
            title = stringResource(R.string.location_status_tracking_off_title),
            message = stringResource(R.string.location_status_tracking_off_message),
            tone = BannerTone.Info,
        )
        accuracyMeters == null -> StatusPresentation(
            title = stringResource(R.string.location_status_waiting_gps_title),
            message = stringResource(R.string.location_status_waiting_gps_message),
            tone = BannerTone.Warning,
        )
        accuracyMeters > 45f -> StatusPresentation(
            title = stringResource(R.string.location_status_gps_weak_title),
            message = stringResource(R.string.location_status_gps_weak_message),
            tone = BannerTone.Warning,
        )
        else -> StatusPresentation(
            title = stringResource(R.string.location_status_ready_title),
            message = currentLocation,
            tone = BannerTone.Success,
        )
    }
}

@Composable
private fun currentPositionStatus(
    hasLocationPermission: Boolean,
    accuracyMeters: Float?,
): StatusPresentation {
    return when {
        !hasLocationPermission -> StatusPresentation(
            title = stringResource(R.string.current_position_status_blocked_title),
            message = stringResource(R.string.current_position_status_blocked_message),
            tone = BannerTone.Warning,
        )
        accuracyMeters == null -> StatusPresentation(
            title = stringResource(R.string.current_position_status_waiting_title),
            message = stringResource(R.string.current_position_status_waiting_message),
            tone = BannerTone.Info,
        )
        accuracyMeters > 45f -> StatusPresentation(
            title = stringResource(R.string.current_position_status_approximate_title),
            message = stringResource(R.string.current_position_status_approximate_message),
            tone = BannerTone.Warning,
        )
        else -> StatusPresentation(
            title = stringResource(R.string.current_position_status_ready_title),
            message = stringResource(R.string.current_position_status_ready_message),
            tone = BannerTone.Success,
        )
    }
}

@Composable
private fun navigationStatus(
    state: ActiveNavigationState,
    hasLocationPermission: Boolean,
    accuracyMeters: Float?,
): StatusPresentation {
    return when {
        !hasLocationPermission -> StatusPresentation(
            title = stringResource(R.string.navigation_status_permission_lost_title),
            message = stringResource(R.string.navigation_status_permission_lost_message),
            tone = BannerTone.Critical,
        )
        state.isRecalculating -> StatusPresentation(
            title = stringResource(R.string.navigation_status_recalculating_title),
            message = stringResource(R.string.navigation_status_recalculating_message),
            tone = BannerTone.Warning,
        )
        state.isOffRoute -> StatusPresentation(
            title = stringResource(R.string.navigation_status_off_route_title),
            message = stringResource(R.string.navigation_status_off_route_message),
            tone = BannerTone.Critical,
        )
        accuracyMeters != null && accuracyMeters > 45f -> StatusPresentation(
            title = stringResource(R.string.navigation_status_gps_weak_title),
            message = stringResource(R.string.navigation_status_gps_weak_message),
            tone = BannerTone.Warning,
        )
        state.isPaused -> StatusPresentation(
            title = stringResource(R.string.navigation_status_paused_title),
            message = stringResource(R.string.navigation_status_paused_message),
            tone = BannerTone.Info,
        )
        else -> StatusPresentation(
            title = stringResource(R.string.navigation_status_active_title),
            message = stringResource(R.string.navigation_status_active_message),
            tone = BannerTone.Success,
        )
    }
}

@Composable
private fun placeTimingLabel(place: Place): String {
    return if (place.walkDistanceMeters > 0) {
        stringResource(R.string.format_walk_time_and_distance, place.walkEtaMinutes, place.walkDistanceMeters)
    } else {
        stringResource(R.string.format_walk_time_only, place.walkEtaMinutes)
    }
}
