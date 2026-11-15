import 'dart:math' as math;

import 'package:xml/xml.dart';

/// A point along a GPX track, with estimated power ranges for the route.
class RouteSegment {
  final double latitude;
  final double longitude;
  final double altitude;
  final double distance;
  final ({double min, double max}) possiblePowerRange;
  final ({double min, double max}) recommendedPowerRange;

  const RouteSegment({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.distance,
    required this.possiblePowerRange,
    required this.recommendedPowerRange,
  });
}

/// Parses GPX track points and estimates power ranges from route grade.
class GpxParsingService {
  static const double gravity = 9.81; // m/s²
  static const double rollingResistanceCoeff = 0.005;
  static const double assumedSpeed = 3.0; // m/s
  static const double maximumHumanPower = 400.0; // W

  List<RouteSegment> parseGpx(
    String xmlString,
    double systemWeightKg,
    ({double min, double max}) targetZone,
  ) {
    if (!systemWeightKg.isFinite || systemWeightKg <= 0) {
      throw ArgumentError.value(systemWeightKg, 'systemWeightKg', 'Must be positive and finite.');
    }
    if (!targetZone.min.isFinite || !targetZone.max.isFinite || targetZone.min > targetZone.max) {
      throw ArgumentError.value(targetZone, 'targetZone', 'Must be a finite range with min <= max.');
    }

    final document = XmlDocument.parse(xmlString);
    final trackPoints = document.findAllElements('trkpt');
    final segments = <RouteSegment>[];
    var accumulatedDistance = 0.0;

    for (final point in trackPoints) {
      final latitude = double.parse(point.getAttribute('lat')!);
      final longitude = double.parse(point.getAttribute('lon')!);
      final altitude = double.parse(point.findElements('ele').first.text);

      var slopeAngle = 0.0;
      if (segments.isNotEmpty) {
        final previous = segments.last;
        accumulatedDistance += calculateDistance(
          latitude,
          longitude,
          previous.latitude,
          previous.longitude,
        );
        final distanceDelta = accumulatedDistance - previous.distance;
        if (distanceDelta > 0) {
          slopeAngle = math.atan((altitude - previous.altitude) / distanceDelta);
        }
      }

      final powerLimits = calculatePhysicalLimits(slopeAngle, systemWeightKg);
      final recommendedRange = determineRecommendedRange(powerLimits, targetZone);

      segments.add(RouteSegment(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        distance: accumulatedDistance,
        possiblePowerRange: powerLimits,
        recommendedPowerRange: recommendedRange,
      ));
    }

    return segments;
  }

  /// Returns the great-circle distance between two coordinates, in metres.
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const radiansPerDegree = math.pi / 180;
    final latitudeDelta = (lat2 - lat1) * radiansPerDegree;
    final longitudeDelta = (lon2 - lon1) * radiansPerDegree;
    final haversine = math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(lat1 * radiansPerDegree) *
            math.cos(lat2 * radiansPerDegree) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    final boundedHaversine = haversine.clamp(0.0, 1.0).toDouble();
    return 6371000 * 2 * math.asin(math.sqrt(boundedHaversine));
  }

  ({double min, double max}) calculatePhysicalLimits(double angle, double weightKg) {
    final forceGravity = weightKg * gravity * math.sin(angle);
    final forceNormal = weightKg * gravity * math.cos(angle);
    final forceRolling = rollingResistanceCoeff * forceNormal;
    final minPower = math.max(0.0, (forceGravity + forceRolling) * assumedSpeed);
    final maxPower = math.max(maximumHumanPower, minPower);

    return (min: minPower, max: maxPower);
  }

  ({double min, double max}) determineRecommendedRange(
    ({double min, double max}) possibleLimits,
    ({double min, double max}) targetZone,
  ) {
    final effectiveMin = math.max(possibleLimits.min, targetZone.min);
    final effectiveMax = math.min(possibleLimits.max, targetZone.max);

    // If the target zone is not physically achievable, use the physical range.
    if (effectiveMin > effectiveMax) {
      return possibleLimits;
    }

    return (min: effectiveMin, max: effectiveMax);
  }
}
