import CoreLocation
import Foundation

struct GeoPoint: Codable, Hashable, Sendable {
  var latitude: Double
  var longitude: Double

  var clCoordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  func distance(to other: GeoPoint) -> CLLocationDistance {
    CLLocation(latitude: latitude, longitude: longitude)
      .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
  }

  static func from(_ coordinate: CLLocationCoordinate2D) -> GeoPoint {
    GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
  }
}

struct Place: Identifiable, Codable, Hashable, Sendable {
  var id: String
  var name: String
  var address: String
  var walkDistanceMeters: Int
  var walkEtaMinutes: Int
  var point: GeoPoint?
  var phone: String?
  var website: String?

  var hasContactDetails: Bool {
    phone?.isEmpty == false || website?.isEmpty == false
  }
}

struct RouteStep: Identifiable, Codable, Hashable, Sendable {
  var id: UUID = UUID()
  var instruction: String
  var distanceMeters: Int
  var maneuverPoint: GeoPoint?
}

struct RouteSummary: Codable, Hashable, Sendable {
  var distanceMeters: Int
  var etaMinutes: Int
  var modeLabel: String
  var currentInstruction: String
  var nextInstruction: String
  var steps: [RouteStep]
  var pathPoints: [GeoPoint]
}

struct HeadingState: Codable, Hashable, Sendable {
  var instruction: String = ""
  var isAligned: Bool = false
  var arrowRotationDegrees: Double = 0
}

struct ActiveNavigationState: Codable, Hashable, Sendable {
  var currentInstruction: String = ""
  var nextInstruction: String = ""
  var distanceToNextMeters: Int = 0
  var remainingDistanceMeters: Int = 0
  var progressLabel: String = ""
  var isPaused: Bool = false
  var isOffRoute: Bool = false
  var isRecalculating: Bool = false
  var offRouteDistanceMeters: Int?
}

struct LocationFix: Codable, Hashable, Sendable {
  var point: GeoPoint
  var accuracyMeters: Double
  var timestamp: Date
  var courseDegrees: Double?
}

enum GuidanceSpeechMode: String, CaseIterable, Codable, Sendable {
  case automatic
  case voiceOver
  case speechSynthesizer
}

struct AppSettings: Codable, Hashable, Sendable {
  var showTutorialOnLaunch: Bool = true
  var vibrationEnabled: Bool = true
  var autoRecalculate: Bool = true
  var junctionAlerts: Bool = true
  var turnByTurnAnnouncements: Bool = true
  var speechMode: GuidanceSpeechMode = .automatic
  var speechRate: Double = 1.0
  var speechVolume: Double = 1.0
}

struct PersistedSnapshot: Codable, Sendable {
  var favorites: [Place] = []
  var lastRoutePlaceID: String?
  var settings: AppSettings = .init()
  var hasCompletedOnboarding: Bool = false
}

enum AppRoute: Hashable {
  case onboarding
  case permissions
  case search
  case placeDetails(placeID: String)
  case routeSummary(placeID: String)
  case headingAlign(placeID: String)
  case activeNavigation(placeID: String)
  case arrival(placeID: String)
  case currentPosition
  case favorites
  case settings
  case helpPrivacy
}
