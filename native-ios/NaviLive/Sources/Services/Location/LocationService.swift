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
    manager.startUpdatingLocation()
    if CLLocationManager.headingAvailable() {
      manager.startUpdatingHeading()
    }
  }

  func stopUpdates() {
    manager.stopUpdatingLocation()
    manager.stopUpdatingHeading()
    isUpdating = false
  }
}

extension LocationService: CLLocationManagerDelegate {
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      authorizationStatus = manager.authorizationStatus
      if hasPermission && isUpdating {
        startUpdates()
      }
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    Task { @MainActor in
      latestFix = LocationFix(
        point: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
        accuracyMeters: max(0, location.horizontalAccuracy),
        timestamp: location.timestamp,
        courseDegrees: location.course >= 0 ? location.course : nil
      )
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    Task { @MainActor in
      headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }
  }
}
