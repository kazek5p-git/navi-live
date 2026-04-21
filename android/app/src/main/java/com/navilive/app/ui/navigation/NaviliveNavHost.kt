package com.navilive.app.ui.navigation

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.navilive.app.R
import com.navilive.app.data.location.LocationForegroundService
import com.navilive.app.ui.NaviliveViewModel
import com.navilive.app.ui.screens.ActiveNavigationScreen
import com.navilive.app.ui.screens.ArrivalScreen
import com.navilive.app.ui.screens.BootstrapScreen
import com.navilive.app.ui.screens.CurrentPositionScreen
import com.navilive.app.ui.screens.FavoritesScreen
import com.navilive.app.ui.screens.HeadingAlignScreen
import com.navilive.app.ui.screens.NotFoundScreen
import com.navilive.app.ui.screens.OnboardingScreen
import com.navilive.app.ui.screens.PermissionsScreen
import com.navilive.app.ui.screens.PlaceDetailsScreen
import com.navilive.app.ui.screens.RouteSummaryScreen
import com.navilive.app.ui.screens.SearchScreen
import com.navilive.app.ui.screens.SettingsScreen
import com.navilive.app.ui.screens.StartScreen
import java.io.File

@Composable
fun NaviliveNavHost(viewModel: NaviliveViewModel) {
    val navController = rememberNavController()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val uiState = viewModel.uiState.collectAsStateWithLifecycle()

    var hasLocationPermission by remember {
        mutableStateOf(checkLocationPermission(context))
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        hasLocationPermission = checkLocationPermission(context)
        viewModel.onLocationPermissionChanged(hasLocationPermission)
        if (hasLocationPermission) {
            ContextCompat.startForegroundService(context, LocationForegroundService.startIntent(context))
            if (navController.currentBackStackEntry?.destination?.route == Routes.Permissions) {
                navController.navigate(Routes.Start) {
                    popUpTo(Routes.Bootstrap) { inclusive = true }
                    launchSingleTop = true
                }
            }
        }
    }

    LaunchedEffect(hasLocationPermission) {
        viewModel.onLocationPermissionChanged(hasLocationPermission)
        if (hasLocationPermission) {
            ContextCompat.startForegroundService(context, LocationForegroundService.startIntent(context))
        } else {
            context.startService(LocationForegroundService.stopIntent(context))
        }
    }

    NavHost(
        navController = navController,
        startDestination = Routes.Bootstrap,
    ) {
        composable(Routes.Bootstrap) {
            LaunchedEffect(
                uiState.value.isPreferencesLoaded,
                uiState.value.hasCompletedOnboarding,
                hasLocationPermission,
            ) {
                if (!uiState.value.isPreferencesLoaded) return@LaunchedEffect
                val destination = when {
                    !uiState.value.hasCompletedOnboarding -> Routes.Onboarding
                    !hasLocationPermission -> Routes.Permissions
                    else -> Routes.Start
                }
                navController.navigate(destination) {
                    popUpTo(Routes.Bootstrap) { inclusive = true }
                    launchSingleTop = true
                }
            }
            BootstrapScreen()
        }

        composable(Routes.Onboarding) {
            OnboardingScreen(
                onContinue = {
                    viewModel.completeOnboarding()
                    val destination = if (hasLocationPermission) Routes.Start else Routes.Permissions
                    navController.navigate(destination) {
                        popUpTo(Routes.Bootstrap) { inclusive = true }
                        launchSingleTop = true
                    }
                },
            )
        }

        composable(Routes.Permissions) {
            PermissionsScreen(
                hasLocationPermission = hasLocationPermission,
                onGrantPermission = {
                    if (hasLocationPermission) {
                        navController.navigate(Routes.Start) {
                            popUpTo(Routes.Bootstrap) { inclusive = true }
                            launchSingleTop = true
                        }
                    } else {
                        permissionLauncher.launch(locationPermissionsForRequest())
                    }
                },
                onContinueWithoutPermission = {
                    navController.navigate(Routes.Start) {
                        popUpTo(Routes.Bootstrap) { inclusive = true }
                        launchSingleTop = true
                    }
                },
            )
        }

        composable(Routes.Start) {
            val quickFavorites = viewModel.getFavorites()
            val resumeLastRoutePlaceId = uiState.value.lastRoutePlaceId?.takeIf { placeId ->
                viewModel.getPlace(placeId) != null
            }
            StartScreen(
                currentLocation = uiState.value.currentLocationLabel,
                statusMessage = uiState.value.statusMessage,
                lastRoutePlaceId = resumeLastRoutePlaceId,
                quickFavorites = quickFavorites,
                accuracyMeters = uiState.value.locationState.latestFix?.accuracyMeters,
                hasLocationPermission = uiState.value.locationState.hasPermission,
                isForegroundTracking = uiState.value.locationState.isForegroundTracking,
                onSearch = { navController.navigate(Routes.Search) },
                onCurrentPosition = { navController.navigate(Routes.CurrentPosition) },
                onFavorites = { navController.navigate(Routes.Favorites) },
                onResumeLastRoute = { placeId ->
                    navController.navigate(Routes.routeSummary(placeId))
                },
                onOpenQuickFavorite = { placeId ->
                    navController.navigate(Routes.routeSummary(placeId))
                },
                onSettings = { navController.navigate(Routes.Settings) },
                onGrantLocationPermission = {
                    permissionLauncher.launch(locationPermissionsForRequest())
                },
                onToggleTracking = {
                    if (!uiState.value.locationState.hasPermission) {
                        permissionLauncher.launch(locationPermissionsForRequest())
                    } else if (uiState.value.locationState.isForegroundTracking) {
                        context.startService(LocationForegroundService.stopIntent(context))
                    } else {
                        ContextCompat.startForegroundService(
                            context,
                            LocationForegroundService.startIntent(context),
                        )
                    }
                },
            )
        }

        composable(Routes.Search) {
            SearchScreen(
                query = uiState.value.searchQuery,
                results = uiState.value.searchResults,
                isLoading = uiState.value.isLoadingSearch,
                onQueryChange = viewModel::updateSearchQuery,
                onSelectPlace = { placeId ->
                    navController.navigate(Routes.placeDetails(placeId))
                },
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = Routes.PlaceDetailsPattern,
            arguments = listOf(navArgument("placeId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val placeId = backStackEntry.arguments?.getString("placeId")
            val place = viewModel.getPlace(placeId)
            if (place == null) {
                NotFoundScreen(onBack = { navController.popBackStack() })
            } else {
                PlaceDetailsScreen(
                    place = place,
                    isFavorite = place.id in uiState.value.favoriteIds,
                    onShowRoute = { navController.navigate(Routes.routeSummary(place.id)) },
                    onToggleFavorite = { viewModel.toggleFavorite(place.id) },
                    onBack = { navController.popBackStack() },
                )
            }
        }

        composable(
            route = Routes.RouteSummaryPattern,
            arguments = listOf(navArgument("placeId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val placeId = backStackEntry.arguments?.getString("placeId")
            val place = viewModel.getPlace(placeId)
            if (place == null) {
                NotFoundScreen(onBack = { navController.popBackStack() })
            } else {
                RouteSummaryScreen(
                    place = place,
                    summary = viewModel.routeSummaryFor(place.id),
                    isFavorite = place.id in uiState.value.favoriteIds,
                    isLoadingRoute = uiState.value.isLoadingRoute,
                    onSaveFavorite = { viewModel.toggleFavorite(place.id) },
                    onStartRoute = {
                        viewModel.startRoute(place.id)
                        navController.navigate(Routes.headingAlign(place.id))
                    },
                    onBack = { navController.popBackStack() },
                )
            }
        }

        composable(
            route = Routes.HeadingAlignPattern,
            arguments = listOf(navArgument("placeId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val placeId = backStackEntry.arguments?.getString("placeId")
            val place = viewModel.getPlace(placeId)
            if (place == null) {
                NotFoundScreen(onBack = { navController.popBackStack() })
            } else {
                HeadingAlignScreen(
                    place = place,
                    headingState = uiState.value.headingState,
                    onCheckHeading = viewModel::cycleHeadingInstruction,
                    onProceed = {
                        viewModel.markHeadingAligned()
                        viewModel.beginActiveNavigation()
                        navController.navigate(Routes.activeNavigation(place.id))
                    },
                    onSkip = {
                        viewModel.beginActiveNavigation()
                        navController.navigate(Routes.activeNavigation(place.id))
                    },
                    onBack = { navController.popBackStack() },
                )
            }
        }

        composable(
            route = Routes.ActiveNavigationPattern,
            arguments = listOf(navArgument("placeId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val placeId = backStackEntry.arguments?.getString("placeId")
            val place = viewModel.getPlace(placeId)
            if (place == null) {
                NotFoundScreen(onBack = { navController.popBackStack() })
            } else {
                ActiveNavigationScreen(
                    place = place,
                    state = uiState.value.activeNavigationState,
                    hasLocationPermission = uiState.value.locationState.hasPermission,
                    accuracyMeters = uiState.value.locationState.latestFix?.accuracyMeters,
                    onPauseResume = viewModel::togglePauseNavigation,
                    onRepeatInstruction = viewModel::repeatCurrentInstruction,
                    onRecalculate = viewModel::recalculateRoute,
                    onArrived = {
                        viewModel.markArrived()
                        navController.navigate(Routes.arrival(place.id))
                    },
                    onStop = {
                        viewModel.stopNavigation()
                        navController.popBackStack(Routes.Start, false)
                    },
                )
            }
        }

        composable(
            route = Routes.ArrivalPattern,
            arguments = listOf(navArgument("placeId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val placeId = backStackEntry.arguments?.getString("placeId")
            val place = viewModel.getPlace(placeId)
            if (place == null) {
                NotFoundScreen(onBack = { navController.popBackStack() })
            } else {
                ArrivalScreen(
                    place = place,
                    onFinish = { navController.popBackStack(Routes.Start, false) },
                    onReverseRoute = { navController.navigate(Routes.routeSummary(place.id)) },
                    onSaveFavorite = { viewModel.toggleFavorite(place.id) },
                )
            }
        }

        composable(Routes.CurrentPosition) {
            CurrentPositionScreen(
                currentLocation = uiState.value.currentLocationLabel,
                accuracyMeters = uiState.value.locationState.latestFix?.accuracyMeters,
                hasLocationPermission = uiState.value.locationState.hasPermission,
                quickFavorites = viewModel.getFavorites(),
                onReadLocation = viewModel::announceCurrentLocation,
                onSearch = { navController.navigate(Routes.Search) },
                onPickFavorite = { placeId ->
                    navController.navigate(Routes.routeSummary(placeId))
                },
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.Favorites) {
            FavoritesScreen(
                favorites = viewModel.getFavorites(),
                onSelectFavorite = { placeId ->
                    navController.navigate(Routes.routeSummary(placeId))
                },
                onRemoveFavorite = viewModel::toggleFavorite,
                onAddFavorite = { navController.navigate(Routes.Search) },
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.Settings) {
            DisposableEffect(lifecycleOwner) {
                val observer = LifecycleEventObserver { _, event ->
                    if (event == Lifecycle.Event.ON_RESUME) {
                        viewModel.refreshSpeechRuntimeState()
                        viewModel.refreshUpdateRuntimeState()
                    }
                }
                lifecycleOwner.lifecycle.addObserver(observer)
                onDispose {
                    lifecycleOwner.lifecycle.removeObserver(observer)
                }
            }
            LaunchedEffect(Unit) {
                viewModel.refreshSpeechRuntimeState()
                viewModel.refreshUpdateRuntimeState()
            }
            SettingsScreen(
                state = uiState.value.settingsState,
                updateState = uiState.value.appUpdateState,
                diagnosticsState = uiState.value.diagnosticsState,
                onVibrationChange = viewModel::setVibration,
                onAutoRecalculateChange = viewModel::setAutoRecalculate,
                onJunctionAlertChange = viewModel::setJunctionAlerts,
                onTurnByTurnChange = viewModel::setTurnByTurnAnnouncements,
                onSpeechOutputModeChange = viewModel::setSpeechOutputMode,
                onSystemTtsEngineChange = viewModel::setSystemTtsEnginePackage,
                onOpenSystemTtsSettings = {
                    openSystemTtsSettings(context)
                },
                onSpeechRateChange = viewModel::setSpeechRatePercent,
                onSpeechVolumeChange = viewModel::setSpeechVolumePercent,
                onPreviewSpeech = viewModel::previewSpeechOutput,
                onCheckForUpdates = viewModel::checkForAppUpdates,
                onDownloadUpdate = viewModel::downloadAvailableUpdate,
                onInstallDownloadedUpdate = { apkPath ->
                    if (installDownloadedApk(context, apkPath)) {
                        viewModel.markUpdateInstallStarted()
                    }
                },
                onOpenReleasePage = { releaseUrl ->
                    openExternalUrl(context, releaseUrl)
                },
                onOpenUnknownSourcesSettings = {
                    openUnknownAppSourcesSettings(context)
                },
                onExportDiagnostics = viewModel::exportDiagnostics,
                onClearDiagnostics = viewModel::clearDiagnostics,
                onShareDiagnostics = uiState.value.diagnosticsState.lastExportPath?.let { exportPath ->
                    {
                        shareDiagnosticsFile(context, exportPath)
                    }
                },
                onBack = { navController.popBackStack() },
            )
        }
    }
}

private fun checkLocationPermission(context: Context): Boolean {
    val fine = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_FINE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED
    val coarse = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_COARSE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED
    return fine || coarse
}

private fun locationPermissionsForRequest(): Array<String> {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.POST_NOTIFICATIONS,
        )
    } else {
        arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
    }
}

private fun shareDiagnosticsFile(context: Context, exportPath: String) {
    val exportFile = File(exportPath)
    if (!exportFile.exists()) return
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        exportFile,
    )
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "application/json"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.share_telemetry_subject))
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, context.getString(R.string.share_telemetry_chooser)).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    })
}

private fun openSystemTtsSettings(context: Context) {
    val intents = listOf(
        Intent("com.android.settings.TTS_SETTINGS"),
        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS),
        Intent(Settings.ACTION_SETTINGS),
    )
    val packageManager = context.packageManager
    val launchIntent = intents.firstOrNull { intent ->
        intent.resolveActivity(packageManager) != null
    }?.apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    } ?: return
    context.startActivity(launchIntent)
}

private fun openUnknownAppSourcesSettings(context: Context) {
    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}"),
        )
    } else {
        Intent(Settings.ACTION_SECURITY_SETTINGS)
    }.apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    context.startActivity(intent)
}

private fun openExternalUrl(context: Context, url: String) {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    if (intent.resolveActivity(context.packageManager) != null) {
        context.startActivity(intent)
    }
}

private fun installDownloadedApk(context: Context, apkPath: String): Boolean {
    val apkFile = File(apkPath)
    if (!apkFile.exists()) return false
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        apkFile,
    )
    val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
        data = uri
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
        putExtra(Intent.EXTRA_RETURN_RESULT, false)
    }
    val fallbackIntent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, "application/vnd.android.package-archive")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    val launchIntent = listOf(installIntent, fallbackIntent).firstOrNull { intent ->
        intent.resolveActivity(context.packageManager) != null
    } ?: return false
    context.startActivity(launchIntent)
    return true
}
