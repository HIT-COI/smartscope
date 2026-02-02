import 'dart:async';
import 'package:flutter/material.dart';
import '../Pages/PreviewParameterPage.dart';
import '../Widgets/AIKK_illumination.dart';
import '../main.dart';

class PureCenterAlignment extends StatefulWidget {
  final Color? backgroundColor;
  const PureCenterAlignment({
    super.key,
    this.backgroundColor,
  });

  @override
  _PureCenterAlignmentState createState() => _PureCenterAlignmentState();
}

class _PureCenterAlignmentState extends State<PureCenterAlignment>
    with SingleTickerProviderStateMixin {
  bool _isInitialized = false;
  bool _isScanning = false; // Control scanning state

  // Add fixed parameters - get parameters from PreviewParameterPage
  double? _cachedPPI;

  final String _selectedMode = 'AIKK'; // Fixed to AIKK mode
  final Color _dotColor = Colors.white; // Fixed to white
  final bool _showCenterPoint = true; // Show center point only
  final double _radius = 2.0; // Unit: millimeters
  // This variable controls the size of the illumination point
  final double _centerPointRadius = 2; // Add center point size control variable (unit: millimeters)
  final double _spacing = 3.0; // Millimeters
  final int _interval = 3000;

  // Replace with variable coordinate values
  double _offsetX = 38; // Center point X coordinate (millimeters)
  double _offsetY = 70; // Center point Y coordinate (millimeters)

  // Scan range and step size
  final double _minX = 35; // Minimum X coordinate (millimeters)
  final double _maxX = 35; // Maximum X coordinate (millimeters)
  final double _minY = 50; // Minimum Y coordinate (millimeters)
  final double _maxY = 80; // Maximum Y coordinate (millimeters)
  final double _stepSize = 2; // Step size (millimeters) - finer scanning

  // Scan progress
  double _scanProgress = 0.0;

  // Timers for scanning
  Timer? _scanTimer;
  Timer? _realtimeUpdateTimer;

  @override
  void initState() {
    super.initState();

    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  @override
  void deactivate() {
    // Stop all timers
    _scanTimer?.cancel(); // Stop scanning
    super.deactivate();
  }

  void _navigateToNextPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PreviewParameterPage(),
      ),
    );
  }

  void _startScanning() {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _offsetX = _minX;
      _offsetY = _minY;
      _scanProgress = 0.0;
      debugPrint('Start scanning: Position reset');
    });

    // Increase scan interval to 1000 milliseconds
    _scanTimer = Timer.periodic(Duration(milliseconds: 2000), (timer) {
      _moveToNextPosition();
    });

    String scanModeText = '';
    if (_minX == _maxX && _minY == _maxY) {
      scanModeText = 'Single Point Scan';
    } else if (_minX == _maxX) {
      scanModeText = 'Vertical Scan';
    } else if (_minY == _maxY) {
      scanModeText = 'Horizontal Scan';
    } else {
      scanModeText = 'Area Scan';
    }

    _showSnackBar('Starting $scanModeText...', Colors.blue);
  }

  // Stop scanning process
  void _stopScanning() {
    if (!_isScanning) return;

    setState(() {
      _isScanning = false;
      _scanProgress = 0.0;
    });

    // Cancel timer
    _scanTimer?.cancel();
  }

  // Move to next measurement position
  void _moveToNextPosition() {
    if (!_isScanning) return;

    setState(() {
      _offsetX += _stepSize;

      if (_offsetX > _maxX) {
        _offsetX = _minX;

        if (_minY != _maxY) {
          _offsetY += _stepSize;

          if (_offsetY > _maxY) {
            _stopScanning();
            return;
          }
        } else {
          _stopScanning();
          return;
        }
      }

      int totalPoints;
      int completedPoints;

      if (_minX == _maxX && _minY != _maxY) {
        // Vertical scan
        totalPoints = ((_maxY - _minY) / _stepSize).ceil();
        completedPoints = ((_offsetY - _minY) / _stepSize).ceil();
      } else if (_minY == _maxY && _minX != _maxX) {
        // Horizontal scan
        totalPoints = ((_maxX - _minX) / _stepSize).ceil();
        completedPoints = ((_offsetX - _minX) / _stepSize).ceil();
      } else if (_minX != _maxX && _minY != _maxY) {
        // Area scan
        totalPoints = ((_maxX - _minX) / _stepSize).ceil() *
            ((_maxY - _minY) / _stepSize).ceil();
        completedPoints = ((_offsetY - _minY) / _stepSize).ceil() *
                ((_maxX - _minX) / _stepSize).ceil() +
            ((_offsetX - _minX) / _stepSize).ceil();
      } else {
        // Single point
        totalPoints = 1;
        completedPoints = 1;
      }

      if (totalPoints > 0) {
        _scanProgress = (completedPoints / totalPoints).clamp(0.0, 1.0);
      } else {
        _scanProgress = 0.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Color.fromARGB(0, 0, 0, 0),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: Stack(
        clipBehavior: Clip.none, // Important: allow child components to overflow
        children: [
          _buildLiveIllumination(),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildScanningInfoPanel(),

                Container(
                  padding: EdgeInsets.only(bottom: 0, left: 16, right: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildNextButton(),

                      ElevatedButton.icon(
                        onPressed:
                            _isScanning ? _stopScanning : _startScanning,
                        icon: Icon(
                            _isScanning ? Icons.stop : Icons.play_arrow,
                            size: 18),
                        label: Text(_isScanning ? 'Stop Scan' : 'Start Scan',
                            style: TextStyle(fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isScanning ? Colors.grey : Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningInfoPanel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      margin: EdgeInsets.only(bottom: 0, left: 12, right: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Current Position: (${_offsetX.toStringAsFixed(2)}, ${_offsetY.toStringAsFixed(2)})',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          if (_isScanning) ...[
            SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _scanProgress,
                backgroundColor: Colors.grey[800],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 8,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Process: ${(_scanProgress * 100).toStringAsFixed(1)}%',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveIllumination() {
    return Positioned(
      left: 0,
      top: 0,
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height,
      child: IgnorePointer(
        child: Builder(builder: (context) {
          // Convert parameters from millimeters to pixels using global PPI manager
          final double radiusPixels =
              MyApp.ppiManager.mmToPixels(_radius, context);
          final double centerRadiusPixels = MyApp.ppiManager
              .mmToPixels(_centerPointRadius, context);
          final double spacingPixels =
              MyApp.ppiManager.mmToPixels(_spacing, context);

          final double offsetXPixels =
              MyApp.ppiManager.mmToPixels(_offsetX, context);
          final double offsetYPixels =
              MyApp.ppiManager.mmToPixels(_offsetY, context);

          final finalX = offsetXPixels;
          final finalY = offsetYPixels;

          return Stack(
            children: [
              if (_isScanning)
                CustomPaint(
                  size: Size(MediaQuery.of(context).size.width,
                      MediaQuery.of(context).size.height),
                  painter: ScanAreaPainter(
                    minX: _minX,
                    maxX: _maxX,
                    minY: _minY,
                    maxY: _maxY,
                    currentX: _offsetX,
                    currentY: _offsetY,
                    mmToPixels: (double mm) =>
                        MyApp.ppiManager.mmToPixels(mm, context),
                  ),
                ),

              // Illumination point
              AIKK_illumination(
                radius: radiusPixels,
                spacing: spacingPixels,
                dotColor: _dotColor,
                animationDuration: Duration(milliseconds: _interval),
                continuousMode: true,
                isPreview: true,
                offsetX: finalX,
                offsetY: finalY,
                backgroundColor: Colors.transparent,
                showCenterPoint: _showCenterPoint,
                centerRadius: centerRadiusPixels,
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildNextButton() {
    return GestureDetector(
      onTap: _navigateToNextPage,
      child: Container(
        width: 48, // Make the button smaller
        height: 48,
        decoration: const BoxDecoration(
          color: Colors.grey,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.arrow_forward,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1000),
      ),
    );
  }
}

class ScanAreaPainter extends CustomPainter {
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double currentX;
  final double currentY;
  final double Function(double) mmToPixels;

  ScanAreaPainter({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.currentX,
    required this.currentY,
    required this.mmToPixels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Paint currentPosPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(mmToPixels(currentX), mmToPixels(currentY)),
      3.0,
      currentPosPaint,
    );
  }

  @override
  bool shouldRepaint(covariant ScanAreaPainter oldDelegate) {
    return oldDelegate.currentX != currentX || oldDelegate.currentY != currentY;
  }
}
