import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'PreviewParameterPage.dart';
import '../Widgets/AIKK_illumination.dart';
import '../camera2_proxy.dart';
import '../main.dart';

class CenterAlignPage extends StatefulWidget {
  final Color? backgroundColor;

  const CenterAlignPage({
    super.key,
    this.backgroundColor,
  });

  @override
  _CenterAlignPageState createState() => _CenterAlignPageState();
}

class _CenterAlignPageState extends State<CenterAlignPage>
    with SingleTickerProviderStateMixin {
  final Camera2Proxy _camera = Camera2Proxy(pageId: 'center_align_page');
  bool _isCameraInitialized = false;

  bool _isCapturing = false;
  
  double _zoomLevel = 1.0;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 10.0;

  bool _isInitialized = false;
  bool _isScanning = false;
  String? _initializationError;

  // Add fixed parameters - get parameters from PreviewParameterPage
  double? _cachedPPI;
  final String _selectedMode = 'AIKK'; // Fixed to AIKK mode
  final Color _dotColor = Colors.white; // Fixed to white
  final bool _showCenterPoint = true; // Show center point only
  final double _radius = 4.0; // Unit: millimeters
  final double _spacing = 3.0; // Millimeters
  final int _interval = 200; // Milliseconds

  final double _height = 20.0; // Millimeters

  double _offsetX = 30.6; // Center point X coordinate (millimeters)
  double _offsetY = 13.64; // Center point Y coordinate (millimeters)
  
  // Scan range and step size
  final double _minX = 25; // Minimum X coordinate (millimeters)
  final double _maxX = 60; // Maximum X coordinate (millimeters)
  final double _minY = 5; // Minimum Y coordinate (millimeters)
  final double _maxY = 10; // Maximum Y coordinate (millimeters)
  final double _stepSize = 1; // Step size (millimeters) - finer scanning

  Map<String, double> _intensityMap = {};
  double _currentIntensity = 0.0;

  double? _bestX;
  double? _bestY;
  double _bestIntensity = 0.0;

  double _scanProgress = 0.0;

  Timer? _scanTimer;
  Timer? _measureTimer;
  Timer? _realtimeUpdateTimer;

  DateTime _lastIntensityUpdateTime = DateTime.now();

  bool _isAutoExposure = false;
  double _exposureTime = 200.0; // Exposure time (milliseconds)
  static const double _minExposureTime = 10.0; // Minimum exposure time (milliseconds)
  static const double _maxExposureTime = 500.0; // Maximum exposure time (milliseconds)
  static const double _exposureStep = 10.0; // Exposure time step (milliseconds)

  bool _intensityMonitoringActive = false;
  Stream<double>? _intensityStream;
  StreamSubscription<double>? _intensitySubscription;
  Timer? _intensityUpdateTimer;

  @override
  void initState() {
    super.initState();

    _initializeCamera();

    _startRealtimeIntensityUpdate();
  }

  @override
  void dispose() {
    _intensityUpdateTimer?.cancel();
    _scanTimer?.cancel();
    _measureTimer?.cancel();
    _camera.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    debugPrint('CenterAlignPage deactivate: Pausing camera resources');
    _stopIntensityMonitoring();
    _scanTimer?.cancel();
    _measureTimer?.cancel();
    _intensityUpdateTimer?.cancel();

    if (_isCameraInitialized) {
      _camera.pauseCamera();
    }
    
    super.deactivate();
  }

  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (status.isDenied) {
        setState(() {
          _isCameraInitialized = false;
          _initializationError = 'Camera permission required';
        });
        return;
      }

      await _camera.initCamera();
      setState(() {
        _isCameraInitialized = true;
        _isInitialized = true;
      });

      await _setExposureTime(_exposureTime);
      
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      setState(() {
        _isCameraInitialized = false;
        _initializationError = 'Camera initialization failed: $e';
      });
    }
  }
  
  Future<void> _setZoomLevel(double value) async {
    if (!_isCameraInitialized) return;

    try {
      value = value.clamp(_minZoom, _maxZoom);
      await _camera.setZoomLevel(value);
      if (mounted) setState(() => _zoomLevel = value);
    } catch (e) {
      debugPrint('Zoom adjustment error: $e');
    }
  }

  Future<void> _zoomIn() async {
    final newZoom = _zoomLevel + 0.5;
    if (newZoom <= _maxZoom) await _setZoomLevel(newZoom);
  }

  Future<void> _zoomOut() async {
    final newZoom = _zoomLevel - 0.5;
    if (newZoom >= _minZoom) await _setZoomLevel(newZoom);
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

    _realtimeUpdateTimer?.cancel();
    
    setState(() {
      _isScanning = true;
      _intensityMap.clear();
      _offsetX = _minX;
      _offsetY = _minY;
      _scanProgress = 0.0;

      _bestX = null;
      _bestY = null;
      _bestIntensity = 0.0;
      debugPrint('Scan started: Reset best position and intensity');
    });

    _scanTimer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      _moveToNextPosition();
      _measureScanningIntensity();
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

  Future<void> _measureCurrentIntensity() async {
    if (!_isCameraInitialized || !mounted || _isScanning) {
      return;
    }
    if (_isCapturing) {
      debugPrint('Measurement in progress, skipping');
      return;
    }

    _isCapturing = true;
    
    try {
      final double intensity = await _camera.getCurrentLightIntensity();

      _isCapturing = false;
      
      if (mounted) {
        setState(() {
          _currentIntensity = intensity;
          _lastIntensityUpdateTime = DateTime.now();

          if (_bestX == null || _bestY == null || intensity > _bestIntensity) {
            _bestIntensity = intensity;
            _bestX = _offsetX;
            _bestY = _offsetY;
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to measure current intensity: $e');
      _isCapturing = false;
    }
  }

  void _measureScanningIntensity() {
    if (!_isCameraInitialized || !_isScanning || !mounted) {
      return;
    }

    if (_isCapturing) {
      _measureTimer?.cancel();
      _measureTimer = Timer(Duration(milliseconds: 500), () {
        if (mounted && _isScanning) {
          _measureScanningIntensity();
        }
      });
      return;
    }

    final double currentX = _offsetX;
    final double currentY = _offsetY;

    String positionKey = '${currentX.toStringAsFixed(2)},${currentY.toStringAsFixed(2)}';
    if (_intensityMap.containsKey(positionKey)) {
      debugPrint('Position: (${currentX.toStringAsFixed(2)}, ${currentY.toStringAsFixed(2)}) already measured, skipping');
      return;
    }
    
    _measureTimer?.cancel();
    _measureTimer = Timer(Duration(milliseconds: 300), () async {
      if (_isCapturing) {
        if (mounted && _isScanning) {
          _measureScanningIntensity();
        }
        return;
      }

      if (_intensityMap.containsKey(positionKey)) {
        debugPrint('Position: (${currentX.toStringAsFixed(2)}, ${currentY.toStringAsFixed(2)}) measured during delay, skipping');
        return;
      }

      _isCapturing = true;
      
      try {
        final double intensity = await _camera.getCurrentLightIntensity();

        _isCapturing = false;
        
        if (mounted && _isScanning) {
          _intensityMap[positionKey] = intensity;
          
          setState(() {
            _currentIntensity = intensity;

            if (intensity > 0.01) {
              if (_bestX == null || _bestY == null || intensity > _bestIntensity) {
                _bestIntensity = intensity;
                _bestX = currentX;
                _bestY = currentY;
              }

              debugPrint('Position: (${currentX.toStringAsFixed(2)}, ${currentY.toStringAsFixed(2)}), Intensity: ${intensity.toStringAsFixed(2)}, Best: ${_bestIntensity.toStringAsFixed(2)} at (${_bestX!.toStringAsFixed(2)}, ${_bestY!.toStringAsFixed(2)})');
            } else {
              debugPrint('Position: (${currentX.toStringAsFixed(2)}, ${currentY.toStringAsFixed(2)}) intensity too low: $intensity, not updating best position');
            }
          });
        }
      } catch (e) {
        debugPrint('Scan measurement error: $e');
        _isCapturing = false;
        _intensityMap[positionKey] = -1.0;
        if (mounted && _isScanning) {
          setState(() {});
        }
      }
    });
  }

  void _stopScanning() {
    if (!_isScanning) return;
    
    setState(() {
      _isScanning = false;
      _scanProgress = 0.0;
    });

    _scanTimer?.cancel();
    _measureTimer?.cancel();

    _startRealtimeIntensityUpdate();
  }

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
        totalPoints = ((_maxX - _minX) / _stepSize).ceil() * ((_maxY - _minY) / _stepSize).ceil();
        completedPoints = ((_offsetY - _minY) / _stepSize).ceil() * ((_maxX - _minX) / _stepSize).ceil() + 
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

  void _startRealtimeIntensityUpdate() {
    _intensityUpdateTimer?.cancel();
    int consecutiveZeroIntensity = 0;
    _intensityUpdateTimer = Timer.periodic(Duration(milliseconds: 500), (timer) async {
      if (!mounted || !_isCameraInitialized) {
        timer.cancel();
        return;
      }
      if (_isScanning) return;
      
      try {
        final double intensity = await _camera.getCurrentLightIntensity();

        if (intensity <= 0.01) {
          consecutiveZeroIntensity++;

          if (consecutiveZeroIntensity >= 5) {
            consecutiveZeroIntensity = 0;
          }
        } else {
          consecutiveZeroIntensity = 0;
        }
        
        if (mounted) {
          setState(() {
            _currentIntensity = intensity;
            _lastIntensityUpdateTime = DateTime.now();

            if (intensity > 0.01 && (_bestX == null || _bestY == null || intensity > _bestIntensity)) {
              _bestIntensity = intensity;
              _bestX = _offsetX;
              _bestY = _offsetY;
            }
          });
        }
      } catch (e) {
        debugPrint('Failed to get intensity: $e');
      }
    });
  }

  void _stopIntensityMonitoring() {
    _intensityUpdateTimer?.cancel();
    _intensityUpdateTimer = null;
    _intensityMonitoringActive = false;
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
        clipBehavior: Clip.none,
        children: [
          _buildLiveIllumination(),
          Column(
            children: [
              Expanded(
                flex: 1,
                child: Container(),
              ),

              Container(
                height: MediaQuery.of(context).size.height * 0.45, //
                margin: const EdgeInsets.only(bottom: 16), //
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20), 
                    topRight: Radius.circular(20)
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildScanningInfoPanel(),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildCameraPreviewArea(),
                          ),
                          SizedBox(
                            width: 150,
                            child: Column(
                              children: [
                                Expanded(child: _buildControlPanel()),
                                Container(
                                  width: double.infinity,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: _isScanning ? _stopScanning : _startScanning,
                                        icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow, size: 18),
                                        label: Text(_isScanning ? 'Stop Scan' : 'Start Scan', style: TextStyle(fontSize: 14)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _isScanning ? Colors.red : Colors.blue,
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(vertical: 10),
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
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanningInfoPanel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: EdgeInsets.only(top: 8, left: 12, right: 12, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURR: (${_offsetX.toStringAsFixed(2)}, ${_offsetY.toStringAsFixed(2)})',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'CURR: ${_currentIntensity.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'CURR: (${_bestX?.toStringAsFixed(2) ?? _offsetX.toStringAsFixed(2)}, ${_bestY?.toStringAsFixed(2) ?? _offsetY.toStringAsFixed(2)})',
                      style: TextStyle(
                        color: _bestX != null ? Colors.greenAccent : Colors.white70, 
                        fontSize: 14, 
                        fontWeight: _bestX != null ? FontWeight.bold : FontWeight.normal
                      ),
                    ),
                    Text(
                      'CURR: ${_bestX != null ? _bestIntensity.toStringAsFixed(2) : _currentIntensity.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: _bestX != null ? Colors.greenAccent : Colors.white70, 
                        fontSize: 14
                      ),
                    ),
                  ],
                ),
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
              'Pro: ${(_scanProgress * 100).toStringAsFixed(1)}%',
              style: TextStyle(color: Colors.white70, fontSize: 12),
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
        child: Builder(
          builder: (context) {
            final double radiusPixels = MyApp.ppiManager.mmToPixels(_radius, context);
            final double spacingPixels = MyApp.ppiManager.mmToPixels(_spacing, context);

            final double offsetXPixels = MyApp.ppiManager.mmToPixels(_offsetX, context);
            final double offsetYPixels = MyApp.ppiManager.mmToPixels(_offsetY, context);

            final finalX = offsetXPixels;
            final finalY = offsetYPixels;

            return Stack(
              children: [
                if (_isScanning)
                  CustomPaint(
                    size: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
                    painter: ScanAreaPainter(
                      minX: _minX,
                      maxX: _maxX,
                      minY: _minY,
                      maxY: _maxY,
                      currentX: _offsetX,
                      currentY: _offsetY,
                      mmToPixels: (double mm) => MyApp.ppiManager.mmToPixels(mm, context),
                    ),
                  ),

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
                ),
              ],
            );
          }
        ),
      ),
    );
  }

  double _getDevicePPI(BuildContext context) {
    return MyApp.ppiManager.getDevicePPI(context);
  }

  double _mmToPixels(double mm, BuildContext context) {
    return MyApp.ppiManager.mmToPixels(mm, context);
  }

  Widget _buildCameraPreviewArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _isCameraInitialized 
                ? AspectRatio(
                    aspectRatio: 1 / 1.0,
                    child: AndroidView(
                      viewType: 'smart_scope/camera2_preview',
                      creationParams: {
                        'useRearCamera': true,
                        'highResolutionMode': true,
                        'pageId': 'center_align_page',
                      },
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: (int id) {
                        debugPrint('Android camera view created: $id');
                      },
                    ),
                  )
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
            ),
          ),
        ),

        const Padding(
          padding: EdgeInsets.all(16.0),
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              child: CustomPaint(
                size: Size.infinite,
                painter: GridPainter(),
              ),
            ),
          ),
        ),

        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _buildNextButton(),
          ),
        ),
      ],
    );
  }

  Widget _buildNextButton() {
    return GestureDetector(
      onTap: _navigateToNextPage,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: Color(0xFF1565C0),
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

  Widget _buildControlPanel() {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildZoomControl(),
            SizedBox(height: 16),
            _buildExposureControl(),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomControl() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0x1AFFFFFF),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zoom: ${_zoomLevel.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 12,
            ),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildZoomButton(Icons.remove, _zoomOut, Color(0xFF0D47A1)),
              const SizedBox(width: 12),
              _buildZoomButton(Icons.add, _zoomIn, Color(0xFF1565C0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.all(Radius.circular(18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildExposureControl() {
    return Container(
      padding: const EdgeInsets.all(0),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0x1AFFFFFF),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Exp: ${_exposureTime.toStringAsFixed(0)}ms',
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 12,
            ),
          ),
          if (!_isAutoExposure) ...[
            Slider(
              value: _exposureTime,
              min: _minExposureTime,
              max: _maxExposureTime,
              divisions: ((_maxExposureTime - _minExposureTime) / _exposureStep).round(),
              label: '${_exposureTime.toStringAsFixed(0)}ms',
              onChanged: (value) {
                _setExposureTime(value);
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setExposureTime(double value) async {
    try {
      value = value.clamp(_minExposureTime, _maxExposureTime);

      final int exposureTime = (value * 1000000).round();

      final result = await _camera.setExposureTime(exposureTime);
      
      if (result && mounted) {
        setState(() {
          _exposureTime = value;
          _isAutoExposure = false;
        });
      }
    } catch (e) {
    }
  }

  Future<void> _toggleAutoExposure() async {
    try {
      final result = await _camera.setAutoExposure(!_isAutoExposure);
      
      if (result && mounted) {
        setState(() {
          _isAutoExposure = !_isAutoExposure;
          if (_isAutoExposure) {
          } else {
          }
        });
      }
    } catch (e) {
    }
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

class GridPainter extends CustomPainter {
  const GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 0.5;

    for (int i = 1; i < 3; i++) {
      double y = size.height / 3 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    for (int i = 1; i < 3; i++) {
      double x = size.width / 3 * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final centerPaint = Paint()
      ..color = const Color(0x80FFFFFF)
      ..strokeWidth = 1.5;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const centerSize = 10.0;

    canvas.drawLine(
        Offset(centerX - centerSize, centerY),
        Offset(centerX + centerSize, centerY),
        centerPaint
    );
    canvas.drawLine(
        Offset(centerX, centerY - centerSize),
        Offset(centerX, centerY + centerSize),
        centerPaint
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    return oldDelegate.currentX != currentX || 
           oldDelegate.currentY != currentY;
  }
}