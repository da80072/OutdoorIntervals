import 'dart:math' as math;

import 'package:xml/xml.dart';

/// One GPX track point and the estimated power ranges for the next route section.
class RouteSegment {
  final double latitude;
  final double longitude;
  final double altitude;
  final double distance;
  final double gradePercent;
  final ({double min, double max}) possiblePowerRange;
  final ({double min, double max}) recommendedPowerRange;

  const RouteSegment({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.distance,
    required this.gradePercent,
    required this.possiblePowerRange,
    required this.recommendedPowerRange,
  });
}

/// Parses GPX track points and estimates climbing/rolling power at a fixed speed.
///
/// This is a simplified estimate, not a measured power prediction: it does not
/// account for wind, aerodynamic drag, drivetrain losses, or changing speed.
class GpxParsingService {
  static const double gravity = 9.81;
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
    if (!targetZone.min.isFinite ||
        !targetZone.max.isFinite ||
        targetZone.min < 0 ||
        targetZone.min > targetZone.max) {
      throw ArgumentError.value(targetZone, 'targetZone', 'Must be a non-negative finite range with min <= max.');
    }

    final document = XmlDocument.parse(xmlString);
    final trackPoints = document.findAllElements('trkpt');
    final segments = <RouteSegment>[];
    var accumulatedDistance = 0.0;

    for (final point in trackPoints) {
      final latitude = double.tryParse(point.getAttribute('lat') ?? '');
      final longitude = double.tryParse(point.getAttribute('lon') ?? '');
      final altitude = double.tryParse(point.findElements('ele').firstOrNull?.innerText ?? '0') ?? 0.0;
      if (latitude == null || longitude == null ||
          !latitude.isFinite || !longitude.isFinite ||
          latitude.abs() > 90 || longitude.abs() > 180 || !altitude.isFinite) {
        continue;
      }

      var gradePercent = 0.0;
      if (segments.isNotEmpty) {
        final previous = segments.last;
        final deltaDistance = calculateDistance(
          latitude,
          longitude,
          previous.latitude,
          previous.longitude,
        );
        accumulatedDistance += deltaDistance;
        if (deltaDistance > 0) {
          gradePercent = ((altitude - previous.altitude) / deltaDistance) * 100;
        }
      }

      final slopeAngle = math.atan(gradePercent / 100);
      final powerLimits = calculatePhysicalLimits(slopeAngle, systemWeightKg);
      segments.add(RouteSegment(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        distance: accumulatedDistance,
        gradePercent: gradePercent,
        possiblePowerRange: powerLimits,
        recommendedPowerRange: determineRecommendedRange(powerLimits, targetZone),
      ));
    }

    return segments;
  }

  /// Great-circle distance between coordinates, in metres.
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
    return (min: minPower, max: math.max(maximumHumanPower, minPower));
  }

  ({double min, double max}) determineRecommendedRange(
    ({double min, double max}) possibleLimits,
    ({double min, double max}) targetZone,
  ) {
    final effectiveMin = math.max(possibleLimits.min, targetZone.min);
    final effectiveMax = math.min(possibleLimits.max, targetZone.max);
    if (effectiveMin > effectiveMax) return possibleLimits;
    return (min: effectiveMin, max: effectiveMax);
  }
}
