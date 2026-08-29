import Combine
import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject {
  @Published private(set) var authorizationStatus: CLAuthorizationStatus
  @Published private(set) var latestFix: LocationFix?
  @Published private(set) var headingDegrees: Double?
  @Published private(set) var isUpdating = false

  private let manager: CLLocationManager
  private let stabilizer = LocationFixStabilizer()
  private var allowsBackgroundGuidance = false

  override init() {
    let manager = CLLocationManager()
    self.manager = manager
    authorizationStatus = manager.authorizationStatus
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = 3
    manager.activityType = .fitness
    manager.pausesLocationUpdatesAutomatically = false
    manager.headingFilter = 5
    manager.allowsBackgroundLocationUpdates = false
  }

  var hasPermission: Bool {
    authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
  }

  func requestPermission() {
    manager.requestWhenInUseAuthorization()
  }

  func startUpdates() {
    guard hasPermission else { return }
    isUpdating = true
    updateBackgroundLocationAccess()
    manager.startUpdatingLocation()
    if CLLocationManager.headingAvailable() {
      manager.startUpdatingHeading()
    }
  }

  func stopUpdates() {
    manager.stopUpdatingLocation()
    manager.stopUpdatingHeading()
    stabilizer.reset()
    latestFix = nil
    headingDegrees = nil
    allowsBackgroundGuidance = false
    updateBackgroundLocationAccess()
    isUpdating = false
  }

  func prepareForActiveNavigation() {
    allowsBackgroundGuidance = true
    if authorizationStatus == .authorizedWhenInUse {
      manager.requestAlwaysAuthorization()
    }
    updateBackgroundLocationAccess()
  }

  func finishActiveNavigation() {
    allowsBackgroundGuidance = false
    updateBackgroundLocationAccess()
  }

  private func updateBackgroundLocationAccess() {
    manager.allowsBackgroundLocationUpdates =
      allowsBackgroundGuidance && authorizationStatus == .authorizedAlways
  }
}

extension LocationService: CLLocationManagerDelegate {
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      authorizationStatus = manager.authorizationStatus
      updateBackgroundLocationAccess()
      if hasPermission && isUpdating {
        startUpdates()
      }
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    guard CLLocationCoordinate2DIsValid(location.coordinate),
          location.horizontalAccuracy.isFinite,
          location.horizontalAccuracy >= 0 else { return }
    Task { @MainActor in
      guard isUpdating else { return }
      let rawFix = LocationFix(
        point: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
        accuracyMeters: location.horizontalAccuracy,
        timestamp: location.timestamp,
        courseDegrees: location.course >= 0 ? location.course : nil,
        speedMetersPerSecond: location.speed >= 0 ? location.speed : nil
      )
      guard let stabilizedFix = stabilizer.stabilize(rawFix) else { return }
      latestFix = stabilizedFix
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    Task { @MainActor in
      guard isUpdating else { return }
      headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }
  }
}

final class LocationFixStabilizer {
  private var stableFix: LocationFix?

  func reset() {
    stableFix = nil
  }

  func stabilize(_ rawFix: LocationFix) -> LocationFix? {
    guard rawFix.accuracyMeters.isFinite, rawFix.accuracyMeters >= 0 else { return nil }
    let normalizedFix = rawFix
    guard let previous = stableFix else {
      stableFix = normalizedFix
      return normalizedFix
    }

    let elapsedSeconds = normalizedFix.timestamp.timeIntervalSince(previous.timestamp)
    guard elapsedSeconds > 0 else { return nil }
    if elapsedSeconds * 1000 > Double(SharedProductRules.Navigation.locationStabilizationStaleResetMs) {
      stableFix = normalizedFix
      return normalizedFix
    }

    if normalizedFix.accuracyMeters > SharedProductRules.Navigation.locationStabilizationMaxUsableAccuracyMeters {
      return holdPreviousPoint(previous, incoming: normalizedFix)
    }

    let distanceMeters = previous.point.distance(to: normalizedFix.point)
    if distanceMeters <= stationaryThresholdMeters(previous: previous, incoming: normalizedFix) {
      return holdPreviousPoint(previous, incoming: normalizedFix)
    }

    let jumpDistanceThreshold = max(
      SharedProductRules.Navigation.locationStabilizationJumpDistanceMinMeters,
      (previous.accuracyMeters + normalizedFix.accuracyMeters) *
        SharedProductRules.Navigation.locationStabilizationJumpAccuracyMultiplier
    )
    let speedMetersPerSecond = distanceMeters / elapsedSeconds
    if speedMetersPerSecond > SharedProductRules.Navigation.locationStabilizationMaxWalkingSpeedMetersPerSecond,
       distanceMeters > jumpDistanceThreshold {
      return holdPreviousPoint(previous, incoming: normalizedFix)
    }

    let stabilized: LocationFix
    if distanceMeters <= SharedProductRules.Navigation.locationStabilizationSmoothingMaxDistanceMeters {
      stabilized = smooth(previous: previous, incoming: normalizedFix)
    } else {
      stabilized = normalizedFix
    }
    stableFix = stabilized
    return stabilized
  }

  private func holdPreviousPoint(_ previous: LocationFix, incoming: LocationFix) -> LocationFix {
    let held = LocationFix(
      point: previous.point,
      accuracyMeters: incoming.accuracyMeters,
      timestamp: incoming.timestamp,
      courseDegrees: incoming.courseDegrees ?? previous.courseDegrees,
      speedMetersPerSecond: incoming.speedMetersPerSecond ?? previous.speedMetersPerSecond
    )
    stableFix = held
    return held
  }

  private func stationaryThresholdMeters(previous: LocationFix, incoming: LocationFix) -> Double {
    let accuracyWeighted = max(previous.accuracyMeters, incoming.accuracyMeters) *
      SharedProductRules.Navigation.locationStabilizationStationaryAccuracyMultiplier
    return min(
      max(
        SharedProductRules.Navigation.locationStabilizationStationaryDistanceMeters,
        accuracyWeighted
      ),
      SharedProductRules.Navigation.locationStabilizationStationaryMaxDistanceMeters
    )
  }

  private func smooth(previous: LocationFix, incoming: LocationFix) -> LocationFix {
    let alpha = incoming.accuracyMeters <= previous.accuracyMeters
      ? SharedProductRules.Navigation.locationStabilizationSmoothingAlphaWhenAccuracyImproves
      : SharedProductRules.Navigation.locationStabilizationSmoothingAlphaWhenAccuracyWorsens
    let point = GeoPoint(
      latitude: previous.point.latitude + (incoming.point.latitude - previous.point.latitude) * alpha,
      longitude: previous.point.longitude + (incoming.point.longitude - previous.point.longitude) * alpha
    )
    return LocationFix(
      point: point,
      accuracyMeters: incoming.accuracyMeters,
      timestamp: incoming.timestamp,
      courseDegrees: incoming.courseDegrees ?? previous.courseDegrees,
      speedMetersPerSecond: incoming.speedMetersPerSecond ?? previous.speedMetersPerSecond
    )
  }
}
