import Foundation

struct RouteProgressProjection {
  let distanceAlongRouteMeters: Double
  let remainingRouteMeters: Double
  let lateralDistanceMeters: Double
  let segmentBearingDegrees: Double
  let segmentIndex: Int
}

struct RoutePolylineIntersection {
  let point: GeoPoint
  let distanceAlongRouteMeters: Double
  let routeSegmentIndex: Int
  let otherSegmentIndex: Int
  /// Kąt między geometriami w zakresie od 0 do 90 stopni.
  let crossingAngleDegrees: Double
}

/// Wybiera stabilny odcinek trasy zamiast przypadkowego odcinka przy skrzyżowaniu.
enum RouteProjectionCore {
  private static let projectionBoundaryToleranceMeters = 0.05

  static func project(
    pathPoints: [GeoPoint],
    point: GeoPoint,
    minimumDistanceAlongRouteMeters: Double = 0,
    maximumDistanceAlongRouteMeters: Double = .greatestFiniteMagnitude,
    preferredCourseDegrees: Double? = nil,
    speedMetersPerSecond: Double? = nil,
    accuracyMeters: Double? = nil,
    monotonicFloorMeters: Double? = nil,
    preferredSegmentIndex: Int? = nil
  ) -> RouteProgressProjection? {
    guard pathPoints.count >= 2 else { return nil }
    guard minimumDistanceAlongRouteMeters.isFinite,
          (maximumDistanceAlongRouteMeters.isFinite ||
            maximumDistanceAlongRouteMeters == .infinity ||
            maximumDistanceAlongRouteMeters == .greatestFiniteMagnitude),
          minimumDistanceAlongRouteMeters <= maximumDistanceAlongRouteMeters,
          monotonicFloorMeters.map({ $0 <= maximumDistanceAlongRouteMeters }) ?? true else {
      return nil
    }

    let segments = pathPoints.dropLast().indices.map { index in
      projectOntoSegment(point: point, start: pathPoints[index], end: pathPoints[index + 1])
    }
    let routeLength = segments.reduce(0) { $0 + $1.lengthMeters }
    guard routeLength > 0 else { return nil }
    let upperBound = min(maximumDistanceAlongRouteMeters, routeLength)
    guard minimumDistanceAlongRouteMeters <= upperBound else { return nil }

    let preferredCourse = preferredCourseDegrees.flatMap { $0.isFinite ? $0 : nil }
    let useCourse = preferredCourse != nil &&
      speedMetersPerSecond?.isFinite == true &&
      speedMetersPerSecond! >= SharedProductRules.Navigation.routeProjectionCourseUseMinimumSpeedMetersPerSecond &&
      accuracyMeters?.isFinite == true &&
      accuracyMeters! <= SharedProductRules.Navigation.routeProjectionCourseMaximumAccuracyMeters

    var distanceBeforeSegment = 0.0
    var best: Candidate?
    let validPreferredSegmentIndex = preferredSegmentIndex.flatMap { segments.indices.contains($0) ? $0 : nil }
    for (segmentIndex, segment) in segments.enumerated() {
      let distanceAlongRoute = distanceBeforeSegment + segment.lengthMeters * segment.ratio
      if distanceAlongRoute < minimumDistanceAlongRouteMeters - projectionBoundaryToleranceMeters ||
        distanceAlongRoute > upperBound + projectionBoundaryToleranceMeters {
        distanceBeforeSegment += segment.lengthMeters
        continue
      }
      let boundedDistanceAlongRoute = min(
        max(distanceAlongRoute, minimumDistanceAlongRouteMeters),
        upperBound
      )

      let coursePenalty: Double
      if useCourse {
        let difference = directedBearingDifference(
          preferredCourse!,
          segment.bearingDegrees
        )
        coursePenalty = difference / 180.0 * SharedProductRules.Navigation.routeProjectionCourseMismatchPenaltyMeters
      } else {
        coursePenalty = 0
      }
      let segmentContinuityPenalty: Double
      if let validPreferredSegmentIndex {
        if segmentIndex == validPreferredSegmentIndex {
          segmentContinuityPenalty = 0
        } else {
          segmentContinuityPenalty = Double(min(abs(segmentIndex - validPreferredSegmentIndex), 4)) *
            SharedProductRules.Navigation.routeProjectionSegmentContinuityPenaltyMeters +
            SharedProductRules.Navigation.routeProjectionSegmentHysteresisMeters
        }
      } else {
        segmentContinuityPenalty = 0
      }
      let candidate = Candidate(
        distanceAlongRouteMeters: boundedDistanceAlongRoute,
        lateralDistanceMeters: segment.lateralDistanceMeters,
        segmentBearingDegrees: segment.bearingDegrees,
        segmentIndex: segmentIndex,
        score: segment.lateralDistanceMeters + coursePenalty + segmentContinuityPenalty
      )
      let scoreDifference = best.map { candidate.score - $0.score }
      if best == nil ||
        (scoreDifference ?? 0) < -0.01 ||
        (abs(scoreDifference ?? 0) <= 0.01 &&
          candidate.distanceAlongRouteMeters > (best?.distanceAlongRouteMeters ?? 0)) {
        best = candidate
      }
      distanceBeforeSegment += segment.lengthMeters
    }

    guard let selected = best else { return nil }
    let monotonicDistance = min(
      max(selected.distanceAlongRouteMeters, monotonicFloorMeters ?? selected.distanceAlongRouteMeters),
      routeLength
    )
    return RouteProgressProjection(
      distanceAlongRouteMeters: monotonicDistance,
      remainingRouteMeters: max(routeLength - monotonicDistance, 0),
      lateralDistanceMeters: selected.lateralDistanceMeters,
      segmentBearingDegrees: selected.segmentBearingDegrees,
      segmentIndex: selected.segmentIndex
    )
  }

  /// Zwraca miejsca, w których dwie polilinie rzeczywiście się przecinają.
  /// Odcinki równoległe lub nakładające się nie są uznawane za skrzyżowanie.
  static func polylineIntersections(
    routePoints: [GeoPoint],
    otherPoints: [GeoPoint],
    endpointToleranceMeters: Double = 2
  ) -> [RoutePolylineIntersection] {
    guard routePoints.count >= 2,
          otherPoints.count >= 2,
          endpointToleranceMeters.isFinite,
          endpointToleranceMeters >= 0 else {
      return []
    }

    let allPoints = routePoints + otherPoints
    let referenceLatitude = allPoints.map(\.latitude).reduce(0, +) / Double(allPoints.count) * .pi / 180
    let referenceLongitude = allPoints.map(\.longitude).reduce(0, +) / Double(allPoints.count) * .pi / 180
    let earthRadius = 6_371_000.0
    let routePlanar = routePoints.map {
      planarPoint($0, referenceLatitude: referenceLatitude, referenceLongitude: referenceLongitude, earthRadius: earthRadius)
    }
    let otherPlanar = otherPoints.map {
      planarPoint($0, referenceLatitude: referenceLatitude, referenceLongitude: referenceLongitude, earthRadius: earthRadius)
    }
    let routeSegmentLengths = zip(routePoints, routePoints.dropFirst()).map { $0.0.distance(to: $0.1) }
    var routeDistances = [0.0]
    for length in routeSegmentLengths {
      routeDistances.append((routeDistances.last ?? 0) + length)
    }

    var intersections: [RoutePolylineIntersection] = []
    for routeIndex in 0..<(routePlanar.count - 1) {
      let routeStart = routePlanar[routeIndex]
      let routeEnd = routePlanar[routeIndex + 1]
      let routeVector = routeEnd - routeStart
      let routeLengthSquared = routeVector.lengthSquared
      guard routeLengthSquared > 0 else { continue }

      for otherIndex in 0..<(otherPlanar.count - 1) {
        let otherStart = otherPlanar[otherIndex]
        let otherEnd = otherPlanar[otherIndex + 1]
        let otherVector = otherEnd - otherStart
        let otherLengthSquared = otherVector.lengthSquared
        guard otherLengthSquared > 0 else { continue }

        let denominator = cross(routeVector, otherVector)
        guard abs(denominator) > 1e-9 else { continue }
        let relativeStart = otherStart - routeStart
        let routeRatio = cross(relativeStart, otherVector) / denominator
        let otherRatio = cross(relativeStart, routeVector) / denominator
        let routeTolerance = endpointToleranceMeters / sqrt(routeLengthSquared)
        let otherTolerance = endpointToleranceMeters / sqrt(otherLengthSquared)
        guard routeRatio >= -routeTolerance,
              routeRatio <= 1 + routeTolerance,
              otherRatio >= -otherTolerance,
              otherRatio <= 1 + otherTolerance else {
          continue
        }

        let boundedRouteRatio = min(max(routeRatio, 0), 1)
        let boundedOtherRatio = min(max(otherRatio, 0), 1)
        let routePoint = routeStart + routeVector * boundedRouteRatio
        let otherPoint = otherStart + otherVector * boundedOtherRatio
        guard (routePoint - otherPoint).length <= endpointToleranceMeters else { continue }

        let routeDistance = routeDistances[routeIndex] +
          routeSegmentLengths[routeIndex] * boundedRouteRatio
        intersections.append(
          RoutePolylineIntersection(
            point: geoPoint(
              routePoint,
              referenceLatitude: referenceLatitude,
              referenceLongitude: referenceLongitude,
              earthRadius: earthRadius
            ),
            distanceAlongRouteMeters: routeDistance,
            routeSegmentIndex: routeIndex,
            otherSegmentIndex: otherIndex,
            crossingAngleDegrees: undirectedAngleDegrees(routeVector, otherVector)
          )
        )
      }
    }

    var deduplicated: [RoutePolylineIntersection] = []
    for candidate in intersections.sorted(by: { $0.distanceAlongRouteMeters < $1.distanceAlongRouteMeters }) {
      if !deduplicated.contains(where: {
        abs($0.distanceAlongRouteMeters - candidate.distanceAlongRouteMeters) <= endpointToleranceMeters
      }) {
        deduplicated.append(candidate)
      }
    }
    return deduplicated
  }

  static func routeLengthMeters(_ pathPoints: [GeoPoint]) -> Double {
    guard pathPoints.count >= 2 else { return 0 }
    return zip(pathPoints, pathPoints.dropFirst()).reduce(0) { total, pair in
      total + pair.0.distance(to: pair.1)
    }
  }

  /// Zwraca pozycję początku każdego kroku na geometrii trasy.
  ///
  /// Punkt manewru z routera jest źródłem pierwszego wyboru. Jeżeli go brakuje,
  /// pozycja jest rekonstruowana z długości poprzednich kroków między znanymi
  /// punktami, zamiast przenosić krok na koniec trasy.
  static func stepDistancesAlongRoute(
    steps: [RouteStep],
    pathPoints: [GeoPoint]
  ) -> [Double] {
    guard !steps.isEmpty else { return [] }
    let routeLength = routeLengthMeters(pathPoints)
    guard routeLength.isFinite, routeLength > 0 else {
      return Array(repeating: 0, count: steps.count)
    }

    var positions = Array<Double?>(repeating: nil, count: steps.count)
    positions[0] = 0
    var lastKnownPosition = 0.0

    // Pierwszy krok zawsze zaczyna się na początku przekazanej geometrii.
    for index in 1..<steps.count {
      let projected = steps[index].maneuverPoint
        .flatMap { point in
          project(
            pathPoints: pathPoints,
            point: point,
            minimumDistanceAlongRouteMeters: lastKnownPosition,
            maximumDistanceAlongRouteMeters: routeLength
          )?.distanceAlongRouteMeters
        }
        .flatMap { value in
          value.isFinite && value >= lastKnownPosition ? value : nil
        }
        .map { min(max($0, lastKnownPosition), routeLength) }
      if let projected {
        positions[index] = projected
        lastKnownPosition = projected
      }
    }

    var knownIndex = 0
    while knownIndex < positions.count - 1 {
      let nextKnownIndex = ((knownIndex + 1)..<positions.count).first { positions[$0] != nil }
      let upperPosition = nextKnownIndex.flatMap { positions[$0] } ?? routeLength
      let endExclusive = nextKnownIndex ?? positions.count
      let span = endExclusive - knownIndex
      let weights = (knownIndex..<endExclusive).map { stepTimelineWeight(steps[$0]) }
      let totalWeight = weights.reduce(0, +)
      let lowerPosition = positions[knownIndex] ?? 0

      for index in (knownIndex + 1)..<endExclusive {
        let weightBefore = weights.prefix(index - knownIndex).reduce(0, +)
        let ratio: Double
        if totalWeight > 0 {
          ratio = weightBefore / totalWeight
        } else {
          ratio = Double(index - knownIndex) / Double(span)
        }
        positions[index] = min(
          max(lowerPosition + (upperPosition - lowerPosition) * ratio, lowerPosition),
          upperPosition
        )
      }

      guard let nextKnownIndex else { break }
      knownIndex = nextKnownIndex
    }

    return positions.map { min(max($0 ?? 0, 0), routeLength) }
  }

  static func initialBearingDegrees(
    pathPoints: [GeoPoint],
    minimumSegmentMeters: Double = 3
  ) -> Double? {
    guard pathPoints.count >= 2 else { return nil }
    for pair in zip(pathPoints, pathPoints.dropFirst()) {
      guard pair.0.distance(to: pair.1) >= minimumSegmentMeters else { continue }
      return bearingDegrees(from: pair.0, to: pair.1)
    }
    return nil
  }

  static func bearingDegrees(from: GeoPoint, to: GeoPoint) -> Double? {
    guard from != to else { return nil }
    let latitude1 = from.latitude * .pi / 180
    let latitude2 = to.latitude * .pi / 180
    let longitudeDifference = (to.longitude - from.longitude) * .pi / 180
    let y = sin(longitudeDifference) * cos(latitude2)
    let x = cos(latitude1) * sin(latitude2) -
      sin(latitude1) * cos(latitude2) * cos(longitudeDifference)
    return normalizedBearingDegrees(atan2(y, x))
  }

  private struct Candidate {
    let distanceAlongRouteMeters: Double
    let lateralDistanceMeters: Double
    let segmentBearingDegrees: Double
    let segmentIndex: Int
    let score: Double
  }

  private struct PlanarPoint {
    let x: Double
    let y: Double

    static func +(lhs: PlanarPoint, rhs: PlanarPoint) -> PlanarPoint {
      PlanarPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func -(lhs: PlanarPoint, rhs: PlanarPoint) -> PlanarPoint {
      PlanarPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func *(lhs: PlanarPoint, rhs: Double) -> PlanarPoint {
      PlanarPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    var lengthSquared: Double { x * x + y * y }
    var length: Double { sqrt(lengthSquared) }
  }

  private struct SegmentProjection {
    let ratio: Double
    let lengthMeters: Double
    let lateralDistanceMeters: Double
    let bearingDegrees: Double
  }

  private static func projectOntoSegment(point: GeoPoint, start: GeoPoint, end: GeoPoint) -> SegmentProjection {
    let latitudeReference = (point.latitude + start.latitude + end.latitude) / 3.0 * .pi / 180.0
    let earthRadius = 6_371_000.0

    func project(_ geoPoint: GeoPoint) -> (x: Double, y: Double) {
      (
        geoPoint.longitude * .pi / 180.0 * earthRadius * cos(latitudeReference),
        geoPoint.latitude * .pi / 180.0 * earthRadius
      )
    }

    let pointProjection = project(point)
    let startProjection = project(start)
    let endProjection = project(end)
    let dx = endProjection.x - startProjection.x
    let dy = endProjection.y - startProjection.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else {
      return SegmentProjection(
        ratio: 0,
        lengthMeters: 0,
        lateralDistanceMeters: hypot(pointProjection.x - startProjection.x, pointProjection.y - startProjection.y),
        bearingDegrees: 0
      )
    }

    let ratio = min(
      max(((pointProjection.x - startProjection.x) * dx +
        (pointProjection.y - startProjection.y) * dy) / lengthSquared, 0),
      1
    )
    let nearestX = startProjection.x + ratio * dx
    let nearestY = startProjection.y + ratio * dy
    return SegmentProjection(
      ratio: ratio,
      // Proporcja wynika z lokalnej projekcji, ale postęp trasy musi używać
      // tej samej geograficznej długości co routeLengthMeters().
      lengthMeters: start.distance(to: end),
      lateralDistanceMeters: hypot(pointProjection.x - nearestX, pointProjection.y - nearestY),
      bearingDegrees: normalizedBearingDegrees(atan2(dx, dy))
    )
  }

  private static func directedBearingDifference(_ left: Double, _ right: Double) -> Double {
    abs(((left - right + 540) .truncatingRemainder(dividingBy: 360)) - 180)
  }

  private static func planarPoint(
    _ point: GeoPoint,
    referenceLatitude: Double,
    referenceLongitude: Double,
    earthRadius: Double
  ) -> PlanarPoint {
    PlanarPoint(
      x: (point.longitude * .pi / 180 - referenceLongitude) * earthRadius * cos(referenceLatitude),
      y: (point.latitude * .pi / 180 - referenceLatitude) * earthRadius
    )
  }

  private static func geoPoint(
    _ point: PlanarPoint,
    referenceLatitude: Double,
    referenceLongitude: Double,
    earthRadius: Double
  ) -> GeoPoint {
    GeoPoint(
      latitude: (referenceLatitude + point.y / earthRadius) * 180 / .pi,
      longitude: (referenceLongitude + point.x / (earthRadius * cos(referenceLatitude))) * 180 / .pi
    )
  }

  private static func cross(_ left: PlanarPoint, _ right: PlanarPoint) -> Double {
    left.x * right.y - left.y * right.x
  }

  private static func undirectedAngleDegrees(_ left: PlanarPoint, _ right: PlanarPoint) -> Double {
    let leftBearing = atan2(left.x, left.y) * 180 / .pi
    let rightBearing = atan2(right.x, right.y) * 180 / .pi
    let directed = abs(((leftBearing - rightBearing + 540).truncatingRemainder(dividingBy: 360)) - 180)
    return min(directed, 180 - directed)
  }

  private static func stepTimelineWeight(_ step: RouteStep) -> Double {
    if step.maneuverType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "approach" {
      return 0
    }
    return Double(max(step.distanceMeters, 0))
  }

  private static func normalizedBearingDegrees(_ radians: Double) -> Double {
    (radians * 180.0 / .pi + 360).truncatingRemainder(dividingBy: 360)
  }
}
