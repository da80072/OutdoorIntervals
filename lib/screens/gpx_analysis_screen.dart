import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/gpx_parsing_service.dart';

class GpxAnalysisScreen extends StatefulWidget {
  const GpxAnalysisScreen({super.key});

  @override
  State<GpxAnalysisScreen> createState() => _GpxAnalysisScreenState();
}

class _GpxAnalysisScreenState extends State<GpxAnalysisScreen> {
  final _gpxController = TextEditingController();
  final _service = GpxParsingService();
  final _weightController = TextEditingController(text: '72');
  final _targetMinController = TextEditingController(text: '180');
  final _targetMaxController = TextEditingController(text: '260');
  final _workMinutesController = TextEditingController(text: '3');
  final _restMinutesController = TextEditingController(text: '1');
  final _repeatsController = TextEditingController(text: '5');

  List<RouteSegment> _segments = [];
  bool _isLoading = false;
  bool _isWorkPhase = true;
  bool _isPaused = true;
  int _remainingSeconds = 180;
  int _completedIntervals = 0;
  Timer? _timer;
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  final List<Position> _recordedPositions = [];
  double _liveDistanceMeters = 0;
  String? _locationMessage;

  static const _sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="OutdoorIntervals" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Sample Route</name><trkseg>
    <trkpt lat="47.3769" lon="8.5417"><ele>440</ele></trkpt>
    <trkpt lat="47.3771" lon="8.5422"><ele>445</ele></trkpt>
    <trkpt lat="47.3773" lon="8.5428"><ele>451</ele></trkpt>
    <trkpt lat="47.3776" lon="8.5434"><ele>462</ele></trkpt>
    <trkpt lat="47.3778" lon="8.5441"><ele>470</ele></trkpt>
    <trkpt lat="47.3780" lon="8.5448"><ele>478</ele></trkpt>
    <trkpt lat="47.3782" lon="8.5455"><ele>488</ele></trkpt>
  </trkseg></trk>
</gpx>''';

  @override
  void initState() {
    super.initState();
    _gpxController.text = _sampleGpx;
    _parseGpx();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    _gpxController.dispose();
    _weightController.dispose();
    _targetMinController.dispose();
    _targetMaxController.dispose();
    _workMinutesController.dispose();
    _restMinutesController.dispose();
    _repeatsController.dispose();
    super.dispose();
  }

  Future<void> _pickGpxFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gpx'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return;
      final xml = String.fromCharCodes(result.files.single.bytes!);
      _gpxController.text = xml;
      _parseGpx();
    } catch (error) {
      _showMessage('Could not open GPX file: $error');
    }
  }

  void _parseGpx() {
    final weight = double.tryParse(_weightController.text);
    final minPower = double.tryParse(_targetMinController.text);
    final maxPower = double.tryParse(_targetMaxController.text);
    if (weight == null || minPower == null || maxPower == null) {
      _showMessage('Enter valid weight and power target values.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final parsed = _service.parseGpx(
        _gpxController.text.trim(),
        weight,
        (min: minPower, max: maxPower),
      );
      setState(() {
        _segments = parsed;
        _isLoading = false;
      });
      if (parsed.isEmpty) _showMessage('No valid GPX track points found.');
    } catch (error) {
      setState(() => _isLoading = false);
      _showMessage('Could not parse GPX: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  int _durationSeconds(TextEditingController controller) {
    final minutes = int.tryParse(controller.text) ?? 0;
    return math.max(1, minutes) * 60;
  }

  int get _totalIntervals => math.max(1, int.tryParse(_repeatsController.text) ?? 1);

  void _startTimer() {
    if (_completedIntervals >= _totalIntervals) {
      _completedIntervals = 0;
      _isWorkPhase = true;
      _remainingSeconds = _durationSeconds(_workMinutesController);
    }
    _timer?.cancel();
    setState(() => _isPaused = false);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 1) {
          _remainingSeconds--;
          return;
        }
        if (_isWorkPhase) {
          _isWorkPhase = false;
          _remainingSeconds = _durationSeconds(_restMinutesController);
        } else {
          _completedIntervals++;
          if (_completedIntervals >= _totalIntervals) {
            _timer?.cancel();
            _isPaused = true;
            _remainingSeconds = 0;
            _showMessage('Workout complete. Great work!');
          } else {
            _isWorkPhase = true;
            _remainingSeconds = _durationSeconds(_workMinutesController);
          }
        }
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _isPaused = true);
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isPaused = true;
      _isWorkPhase = true;
      _completedIntervals = 0;
      _remainingSeconds = _durationSeconds(_workMinutesController);
    });
  }

  String _formatTime(int seconds) {
    final safeSeconds = math.max(0, seconds);
    return '${(safeSeconds ~/ 60).toString().padLeft(2, '0')}:${(safeSeconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _toggleLocationTracking() async {
    if (_positionSubscription != null) {
      await _positionSubscription?.cancel();
      setState(() {
        _positionSubscription = null;
        _locationMessage = 'Location tracking stopped';
      });
      return;
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _locationMessage = 'Enable location services to track outdoors.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _locationMessage = 'Location permission is not available.');
        return;
      }

      setState(() {
        _recordedPositions.clear();
        _liveDistanceMeters = 0;
        _locationMessage = null;
      });
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((position) {
        if (!mounted) return;
        setState(() {
          if (_recordedPositions.isNotEmpty) {
            final previous = _recordedPositions.last;
            _liveDistanceMeters += _service.calculateDistance(
              position.latitude,
              position.longitude,
              previous.latitude,
              previous.longitude,
            );
          }
          _recordedPositions.add(position);
          _currentPosition = position;
        });
      }, onError: (Object error) {
        if (mounted) setState(() => _locationMessage = 'Location error: $error');
      });
    } catch (error) {
      setState(() => _locationMessage = 'Could not start location tracking: $error');
    }
  }

  String _distanceLabel(double meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(2)} km'
      : '${meters.toStringAsFixed(0)} m';

  String _powerLabel(({double min, double max}) range) =>
      '${range.min.round()}–${range.max.round()} W';

  @override
  Widget build(BuildContext context) {
    final totalRouteDistance = _segments.isEmpty ? 0.0 : _segments.last.distance;
    final maxGrade = _segments.isEmpty
        ? 0.0
        : _segments.map((point) => point.gradePercent.abs()).reduce(math.max);
    final targetRange = _segments.isEmpty
        ? (min: 0.0, max: 0.0)
        : _segments.first.recommendedPowerRange;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OutdoorIntervals'),
        actions: [
          IconButton(
            tooltip: 'Load GPX file',
            onPressed: _pickGpxFile,
            icon: const Icon(Icons.folder_open),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Your ride, planned better.', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Load a route, review the effort, and take your intervals outside.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            _sectionTitle(context, 'Route analysis', Icons.route),
            const SizedBox(height: 10),
            TextField(
              controller: _gpxController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'GPX route data',
                hintText: 'Paste GPX XML or choose a .gpx file',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _pickGpxFile, icon: const Icon(Icons.upload_file), label: const Text('Choose GPX'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: _isLoading ? null : _parseGpx, icon: const Icon(Icons.analytics_outlined), label: Text(_isLoading ? 'Analysing…' : 'Analyse route'))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _numberField(_weightController, 'System weight (kg)', '72')),
              const SizedBox(width: 8),
              Expanded(child: _numberField(_targetMinController, 'Target min (W)', '180')),
              const SizedBox(width: 8),
              Expanded(child: _numberField(_targetMaxController, 'Target max (W)', '260')),
            ]),
            if (_segments.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(height: 170, child: _RoutePlot(segments: _segments)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _metricCard(context, 'Route distance', _distanceLabel(totalRouteDistance), Icons.straighten)),
                const SizedBox(width: 10),
                Expanded(child: _metricCard(context, 'Steepest grade', '${maxGrade.toStringAsFixed(1)}%', Icons.trending_up)),
                const SizedBox(width: 10),
                Expanded(child: _metricCard(context, 'Power target', _powerLabel(targetRange), Icons.bolt)),
              ]),
              const SizedBox(height: 8),
              ..._segments.asMap().entries.map((entry) => Card(
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 16, child: Text('${entry.key + 1}', style: const TextStyle(fontSize: 12))),
                  title: Text('${_distanceLabel(entry.value.distance)}  ·  ${entry.value.gradePercent >= 0 ? '+' : ''}${entry.value.gradePercent.toStringAsFixed(1)}% grade'),
                  subtitle: Text('Suggested ${_powerLabel(entry.value.recommendedPowerRange)}  ·  ${entry.value.altitude.toStringAsFixed(0)} m elevation'),
                ),
              )),
            ],
            const SizedBox(height: 24),
            _sectionTitle(context, 'Interval timer', Icons.timer_outlined),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(_isWorkPhase ? 'WORK' : 'RECOVERY', style: TextStyle(color: _isWorkPhase ? Theme.of(context).colorScheme.primary : Colors.teal, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Text(_formatTime(_remainingSeconds), style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                  Text('Interval ${math.min(_completedIntervals + 1, _totalIntervals)} of $_totalIntervals'),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _numberField(_workMinutesController, 'Work min', '3')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(_restMinutesController, 'Rest min', '1')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(_repeatsController, 'Repeats', '5')),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: FilledButton.icon(onPressed: _isPaused ? _startTimer : _pauseTimer, icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause), label: Text(_isPaused ? 'Start' : 'Pause')),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: _resetTimer, icon: const Icon(Icons.replay), label: const Text('Reset')),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Live outdoor tracking', Icons.my_location),
            const SizedBox(height: 10),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(_positionSubscription == null ? 'GPS tracking is off' : 'GPS tracking active', style: const TextStyle(fontWeight: FontWeight.w600))),
                  FilledButton.tonalIcon(onPressed: _toggleLocationTracking, icon: Icon(_positionSubscription == null ? Icons.play_arrow : Icons.stop), label: Text(_positionSubscription == null ? 'Start tracking' : 'Stop')),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _metricCard(context, 'Distance', _distanceLabel(_liveDistanceMeters), Icons.straighten)),
                  const SizedBox(width: 10),
                  Expanded(child: _metricCard(context, 'Speed', '${((_currentPosition?.speed ?? 0) * 3.6).toStringAsFixed(1)} km/h', Icons.speed)),
                  const SizedBox(width: 10),
                  Expanded(child: _metricCard(context, 'Points', '${_recordedPositions.length}', Icons.location_on_outlined)),
                ]),
                if (_locationMessage != null) ...[const SizedBox(height: 8), Text(_locationMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
                const SizedBox(height: 8),
                Text('GPS distance is an estimate and may vary with device accuracy.', style: Theme.of(context).textTheme.bodySmall),
              ]),
            )),
            const SizedBox(height: 20),
            Text('Power values are simplified estimates based on grade, weight, and a fixed 3 m/s speed—not a substitute for a power meter.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon) => Row(children: [
    Icon(icon, color: Theme.of(context).colorScheme.primary),
    const SizedBox(width: 8),
    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
  ]);

  Widget _numberField(TextEditingController controller, String label, String hint) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
  );

  Widget _metricCard(BuildContext context, String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [Icon(icon, size: 18), const SizedBox(height: 5), Text(value, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall)],
  );
}

class _RoutePlot extends StatelessWidget {
  final List<RouteSegment> segments;
  const _RoutePlot({required this.segments});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
    child: CustomPaint(painter: _RoutePainter(segments, Theme.of(context).colorScheme.primary), size: Size.infinite),
  );
}

class _RoutePainter extends CustomPainter {
  final List<RouteSegment> segments;
  final Color color;
  _RoutePainter(this.segments, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;
    const inset = 12.0;
    final plot = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    final minAltitude = segments.map((point) => point.altitude).reduce(math.min);
    final maxAltitude = segments.map((point) => point.altitude).reduce(math.max);
    final altitudeRange = math.max(1.0, maxAltitude - minAltitude);
    final path = Path();
    for (var i = 0; i < segments.length; i++) {
      final x = segments.length == 1 ? plot.left : plot.left + plot.width * i / (segments.length - 1);
      final y = plot.bottom - ((segments[i].altitude - minAltitude) / altitudeRange) * plot.height;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    final fillPath = Path.from(path)..lineTo(plot.right, plot.bottom)..lineTo(plot.left, plot.bottom)..close();
    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.12)..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    final label = TextPainter(text: TextSpan(text: 'Elevation profile  ·  ${minAltitude.toStringAsFixed(0)}–${maxAltitude.toStringAsFixed(0)} m', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr)..layout();
    label.paint(canvas, Offset(plot.left, 0));
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) => oldDelegate.segments != segments || oldDelegate.color != color;
}
