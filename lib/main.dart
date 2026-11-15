import 'package:flutter/material.dart';

import 'screens/gpx_analysis_screen.dart';

void main() => runApp(const OutdoorIntervalsApp());

class OutdoorIntervalsApp extends StatelessWidget {
  const OutdoorIntervalsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OutdoorIntervals',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const GpxAnalysisScreen(),
      );
}
