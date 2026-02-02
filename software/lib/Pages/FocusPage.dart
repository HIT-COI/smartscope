import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../camera2_proxy.dart';
import 'dart:math' as math;
import '../Widgets/AIKK_illumination.dart';
import '../main.dart';

class FocusPage extends StatefulWidget {
  const FocusPage({Key? key}) : super(key: key);

  @override
  _FocusPageState createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  final Camera2Proxy _camera = Camera2Proxy(pageId: 'focus_page');
  
  bool _isTakingPicture = false;
  bool _isRearCamera = true;
  double _zoomLevel = 1.0;
  double _maxZoomLevel = 5.0;
  double _stretchFactor = 1.0;
  bool _isStretching = false;
  bool _isAutoExposure = true;
  bool _isHighResolutionMode = true;
  String _resolutionInfo = "";

  bool _showAIKK = true;
  bool _showFullGreen = false;
  final bool _showCenterPoint = true;
  final Color _aikkColor = Color.fromARGB(255, 0,  255, 0);

  final double _radiusMM = 0.5; // Small dot radius (millimeters)
  final double _spacingMM = 2.7; // Small dot to center distance (millimeters)
  final  double _offsetXMM = 34.45; // X-axis offset (millimeters)
  final double _offsetYMM = 6.65; // Y-axis offset (millimeters)
  final double _centerPointRadiusMM = 0.5; // Center point radius (millimeters)

  int _aikkScanInterval = 1000;

  final GlobalKey<AIKK_illuminationState> _illuminationKey = GlobalKey();
  
  @override
  void initState() {
    super.initState();
    _enterFullScreen();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    setState(() => _isAutoExposure = true);

    _requestPermissions();
  }
  
  Future<void> _requestPermissions() async {
    List<Permission> permissions = [Permission.camera];

    final androidVersion = int.parse(await _getPlatformVersion());
    
    if (Platform.isAndroid) {
      if (androidVersion >= 33) {
        // Android 13+ uses photos permission
        permissions.add(Permission.photos);
      } else {
        // Lower Android versions use storage permission
        permissions.add(Permission.storage);
      }
    }
    Map<Permission, PermissionStatus> statuses = await permissions.request();
    
    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        debugPrint('Permission not granted: $permission, status: $status');
        allGranted = false;
      }
    });
    
    if (allGranted) {
      _initCamera();
    } else {
      _showSnackBar('Camera and storage permissions required', Colors.red);
    }
  }
  
  Future<String> _getPlatformVersion() async {
    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        return androidInfo.version.sdkInt.toString();
      } catch (e) {
        debugPrint('Failed to get Android version: $e');
        return '0';
      }
    }
    return '0';
  }
  
  @override
  void dispose() {
    _exitFullScreen();
    _camera.dispose();
    super.dispose();
  }
  
  Future<void> _initCamera() async {
    try {
      final result = await _camera.initCamera(
        useRearCamera: _isRearCamera,
        highResolutionMode: _isHighResolutionMode,
      );
      
      if (result) {
        _getCameraInfo();
        await _camera.setAutoExposure(true);
        setState(() => _isAutoExposure = true);

        await _getMaxZoomLevel();
      }
    } catch (e) {
      _showSnackBar('Camera initialization failed: $e', Colors.red);
    }
  }
  
  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }
  
  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _toggleCamera() async {
    try {
      setState(() => _isRearCamera = !_isRearCamera);

      await _camera.dispose();
      await _camera.initCamera(useRearCamera: _isRearCamera);

      await _camera.setAutoExposure(true);
      setState(() => _isAutoExposure = true);
      
    } catch (e) {
      _showSnackBar('Failed to switch camera: $e', Colors.red);
    }
  }
  
  // Zoom in
  Future<void> _zoomIn() async {
    if (_zoomLevel < _maxZoomLevel) {
      double increment = 0.25;
      if (_zoomLevel > 3.0) {
        increment = 0.1;
      }
      _setZoomLevel(_zoomLevel + increment);
    }
  }
  
  // Zoom out
  Future<void> _zoomOut() async {
    if (_zoomLevel > 1.0) {
      double decrement = 0.25;
      if (_zoomLevel > 3.0) {
        decrement = 0.1;
      }
      _setZoomLevel(_zoomLevel - decrement);
    }
  }

  Future<void> _setZoomLevel(double value) async {
    try {
      // Clamp value
      value = value.clamp(1.0, _maxZoomLevel);
      
      // Calculate stretch factor
      double stretchFactor = value / _maxZoomLevel;
      if (stretchFactor > 1.0) {
        setState(() {
          _isStretching = true;
          _stretchFactor = stretchFactor;
        });
        _showSnackBar('Stretch zoom enabled', Colors.orange);
      } else {
        setState(() {
          _isStretching = false;
          _stretchFactor = 1.0;
        });
      }
      
      final bool result = await _camera.setZoomLevel(value);
      if (result && mounted) {
        setState(() => _zoomLevel = value);
      }
    } catch (e) {
      _showSnackBar('Failed to set zoom: $e', Colors.red);
    }
  }

  Future<void> _getMaxZoomLevel() async {
    try {
      final cameraInfo = await _camera.getCameraInfo();
      
      if (cameraInfo != null && cameraInfo.containsKey('maxZoom')) {
        double maxZoom = cameraInfo['maxZoom'] as double? ?? 8.0;
        maxZoom = maxZoom.clamp(1.0, 8.0);
        
        setState(() {
          _maxZoomLevel = maxZoom;
          debugPrint('Device max zoom level: $_maxZoomLevel');
        });
      }
    } catch (e) {
      debugPrint('Failed to get max zoom level: $e');
      setState(() {
        _maxZoomLevel = 8.0;
      });
    }
  }

  Future<void> _toggleAutoExposure() async {
    try {
      final bool result = await _camera.setAutoExposure(!_isAutoExposure);

      if (result && mounted) {
        setState(() => _isAutoExposure = !_isAutoExposure);
      }
    } catch (e) {
      _showSnackBar('Failed to toggle exposure mode: $e', Colors.red);
    }
  }

  Future<void> _takePicture() async {
    if (_isTakingPicture) return;
    
    try {
      setState(() => _isTakingPicture = true);

      final imagePath = await _camera.takePicture(
        highResolutionMode: _isHighResolutionMode,
      );
      
      if (imagePath != null && imagePath.isNotEmpty) {
        _showSnackBar('Image saved to: $imagePath', Colors.green);
      } else {
        _showSnackBar('Capture failed: No image path', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Capture failed: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isTakingPicture = false);
      }
    }
  }

  Future<void> _getCameraInfo() async {
    try {
      final cameraInfo = await _camera.getCameraInfo();
      
      if (cameraInfo != null && mounted) {
        final int width = cameraInfo['width'] as int? ?? 0;
        final int height = cameraInfo['height'] as int? ?? 0;
        final double megapixels = cameraInfo['megapixels'] as double? ?? 0.0;

        if (width <= 0 || height <= 0) {
          setState(() {
            _resolutionInfo = 'Unknown';
          });
          return;
        }
        
        setState(() {
          if (_isHighResolutionMode) {
            // Format as integer or one decimal place
            final String mpText = megapixels >= 10 
                ? '${megapixels.round()}' 
                : megapixels.toStringAsFixed(1);
            
            _resolutionInfo = '${width}x${height} (${mpText}MP)';
          } else {
            _resolutionInfo = '${width}x${height} (${megapixels.toStringAsFixed(1)}MP)';
          }
        });
      } else {
        // If failed to get info, show unknown
        setState(() {
          _resolutionInfo = 'Unknown';
        });
      }
    } catch (e) {
      debugPrint('Failed to get camera info: $e');
      if (mounted) {
        setState(() {
          _resolutionInfo = 'Unknown';
        });
      }
    }
  }

  Future<void> _toggleHighResMode() async {
    try {
      final bool result = await _camera.setHighResolutionMode(!_isHighResolutionMode);
      
      if (result && mounted) {
        setState(() => _isHighResolutionMode = !_isHighResolutionMode);
        _showSnackBar(
          _isHighResolutionMode ? 'High resolution mode enabled' : 'High resolution mode disabled',
          _isHighResolutionMode ? Colors.green : Colors.orange
        );

        _getCameraInfo();
      }
    } catch (e) {
      _showSnackBar('Failed to toggle resolution mode: $e', Colors.red);
    }
  }

  // Manual focus
  Future<void> _performManualFocus(double x, double y) async {
    try {
      _showSnackBar('Focusing...', Colors.blue);
    } catch (e) {
      debugPrint('Manual focus failed: $e');
    }
  }

  void _toggleIllumination() {
    setState(() {
      if (!_showAIKK && !_showFullGreen) {
        _showAIKK = true;
        _showFullGreen = false;
        _updateAIKKParameters();
      } else if (_showAIKK && !_showFullGreen) {
        _showAIKK = false;
        _showFullGreen = true;
      } else {
        _showAIKK = false;
        _showFullGreen = false;
      }
    });
  }

  IconData _getIlluminationIcon() {
    if (_showAIKK) {
      return Icons.blur_circular;
    } else if (_showFullGreen) {
      return Icons.format_color_fill;
    } else {
      return Icons.lightbulb_outline;
    }
  }

  Color _getIlluminationColor() {
    if (_showAIKK || _showFullGreen) {
      return Color.fromARGB(255, 0, 255, 0);
    } else {
      return Colors.black;
    }
  }

  void _updateAIKKParameters() {
    final double ppi = _getDevicePPI(context);
  }

  double _mmToPixels(double mm, BuildContext context) {
    return MyApp.ppiManager.mmToPixels(mm, context);
  }

  double _getDevicePPI(BuildContext context) {
    return MyApp.ppiManager.getDevicePPI(context);
  }

  Widget _buildAIKKIllumination(double screenWidth, double screenHeight) {
    final double ppi = _getDevicePPI(context);

    final double centerX = screenWidth / 2;
    final double centerY = screenHeight / 2;

    final double radiusPixels = _mmToPixels(_radiusMM, context);
    final double spacingPixels = _mmToPixels(_spacingMM, context);
    final double centerPointRadiusPixels = _mmToPixels(_centerPointRadiusMM, context);

    final double offsetXPixels = _mmToPixels(_offsetXMM, context);
    final double offsetYPixels = _mmToPixels(_offsetYMM, context);
    
    return IgnorePointer(
      child: AIKK_illumination(
        key: _illuminationKey,
        radius: radiusPixels,
        spacing: spacingPixels,
        dotColor: _aikkColor,
        animationDuration: Duration(milliseconds: _aikkScanInterval),
        continuousMode: true,
        isPreview: false,
        offsetX: offsetXPixels,
        offsetY: offsetYPixels,
        backgroundColor: Colors.transparent,
        showCenterPoint: _showCenterPoint,
        centerRadius: centerPointRadiusPixels,
      ),
    );
  }

  Widget _buildLiveIllumination() {
    return Stack(
      children: [
        if (_showAIKK)
          _buildAIKKIllumination(
            MediaQuery.of(context).size.width,
            MediaQuery.of(context).size.height
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    if (_showAIKK) {
      _updateAIKKParameters();
    }
    
    return Scaffold(
      appBar: AppBar(
          backgroundColor: _showFullGreen
              ? Color.fromARGB(255, 255, 255, 255)
              : Color.fromARGB(0, 0, 0, 0),
          automaticallyImplyLeading: false,
          elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: screenWidth,
            height: screenHeight / 2,
            color: _showFullGreen 
                ? Color.fromARGB(255, 255, 255, 255)
                : Colors.transparent,
            child: _showAIKK ? _buildAIKKIllumination(screenWidth, screenHeight / 2) : null,
          ),

          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: GestureDetector(
                    onTapDown: (TapDownDetails details) {
                      _performManualFocus(details.localPosition.dx, details.localPosition.dy);
                    },
                    child: Stack(
                      children: [
                        Transform.scale(
                          scale: _isStretching ? _stretchFactor : 1.0,
                          child: Camera2Preview(
                            useRearCamera: _isRearCamera,
                            highResolutionMode: _isHighResolutionMode,
                            pageId: 'focus_page',
                          ),
                        ),

                        CustomPaint(
                          size: Size.infinite,
                          painter: GridLinePainter(),
                        ),
                      ],
                    ),
                  ),
                ),

                Positioned(
                  bottom: 80,
                  right: 20,
                  child: _showAIKK || _showFullGreen ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _showAIKK ? 'AIKK' : 'Full Green',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ) : SizedBox.shrink(),
                ),

                Positioned(
                  top: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_zoomLevel.toStringAsFixed(1)}x',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),

                Positioned(
                  top: 70,
                  right: 20,
                  child: GestureDetector(
                    onTap: _toggleHighResMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isHighResolutionMode 
                            ? Colors.green.withOpacity(0.7) 
                            : Colors.grey.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isHighResolutionMode 
                                    ? Icons.hd 
                                    : Icons.sd,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isHighResolutionMode ? 'HD' : 'SD',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                          if (_resolutionInfo.isNotEmpty)
                            Text(
                              _resolutionInfo,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FloatingActionButton(
                        heroTag: 'toggleCamera',
                        onPressed: _toggleCamera,
                        mini: true,
                        backgroundColor: Colors.white.withOpacity(0.7),
                        child: Icon(
                          _isRearCamera ? Icons.camera_front : Icons.camera_rear,
                          color: Colors.black,
                        ),
                      ),

                      FloatingActionButton(
                        heroTag: 'zoomOut',
                        onPressed: _zoomOut,
                        mini: true,
                        backgroundColor: Colors.white.withOpacity(0.7),
                        child: const Icon(Icons.zoom_out, color: Colors.black),
                      ),

                      FloatingActionButton(
                        heroTag: 'takePicture',
                        onPressed: _isTakingPicture ? null : _takePicture,
                        backgroundColor: _isTakingPicture 
                            ? Colors.grey 
                            : Colors.white,
                        child: _isTakingPicture
                            ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black))
                            : const Icon(Icons.camera, color: Colors.black),
                      ),

                      FloatingActionButton(
                        heroTag: 'zoomIn',
                        onPressed: _zoomIn,
                        mini: true,
                        backgroundColor: Colors.white.withOpacity(0.7),
                        child: const Icon(Icons.zoom_in, color: Colors.black),
                      ),

                      FloatingActionButton(
                        heroTag: 'toggleIllumination',
                        onPressed: _toggleIllumination,
                        mini: true,
                        backgroundColor: Colors.white.withOpacity(0.7),
                        child: Icon(
                          _getIlluminationIcon(),
                          color: _getIlluminationColor(),
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
}

class GridLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.7)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
