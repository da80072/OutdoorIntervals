# OutdoorIntervals

Flutter app for outdoor workout intervals, GPX route analysis, interval timing, and optional live GPS distance/speed tracking.

## Run the app

This repository contains the Flutter app source. Install Flutter, then run:

```sh
flutter pub get
flutter run
```

## Features

- Import a `.gpx` file or paste GPX XML.
- View an elevation profile, route distance, grade, and estimated power ranges.
- Configure and run a work/recovery interval timer.
- Optionally track live GPS distance and speed while the app is open.

The power model is a simplified estimate based on grade, system weight, rolling resistance, and a fixed assumed speed. It is not a measured power reading.

## Location permissions for live tracking

Live GPS tracking requires platform permissions. Add these to the Flutter-generated platform projects before using the GPS feature:

- **Android**: in `android/app/src/main/AndroidManifest.xml`, add `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />` and `<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />` directly under the `<manifest>` element.
- **iOS**: in `ios/Runner/Info.plist`, add an `NSLocationWhenInUseUsageDescription` key with a user-facing explanation, for example: `OutdoorIntervals uses your location to track workout distance and speed.`

The app only requests location while tracking is started; it does not request background location.
