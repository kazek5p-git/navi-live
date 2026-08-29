import Foundation

struct RouteProgressProjection {
  let distanceAlongRouteMeters: Double
  let remainingRouteMeters: Double
  let lateralDistanceMeters: Double
  let segmentBearingDegrees: Double
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
    monotonicFloorMeters: Double? = nil
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
    for segment in segments {
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
      let candidate = Candidate(
        distanceAlongRouteMeters: boundedDistanceAlongRoute,
        lateralDistanceMeters: segment.lateralDistanceMeters,
        segmentBearingDegrees: segment.bearingDegrees,
        score: segment.lateralDistanceMeters + coursePenalty
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
      segmentBearingDegrees: selected.segmentBearingDegrees
    )
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
    let score: Double
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
