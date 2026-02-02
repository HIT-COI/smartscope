import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import '../Widgets/AIKK_illumination.dart';
import '../Widgets/FPM_illumination.dart';
import '../Widgets/sAIKK_illumination.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../main.dart';

class ImageSaver {
  static Future<Map<String, dynamic>> saveFile(String filePath) async {
    try {
      final Directory? directory = await getExternalStorageDirectory();
      final String newPath = directory!.path + '/Pictures/' + 
          'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      final Directory picDir = Directory(directory.path + '/Pictures/');
      if (!await picDir.exists()) {
        await picDir.create(recursive: true);
      }
      
      final File originalFile = File(filePath);
      if (await originalFile.exists()) {
        await originalFile.copy(newPath);
        return {'isSuccess': true, 'filePath': newPath};
      } else {
        return {'isSuccess': false, 'errorMessage': 'Source file does not exist'};
      }
    } catch (e) {
      return {'isSuccess': false, 'errorMessage': e.toString()};
    }
  }
}

enum IlluminationType {
  AIKK,
  FPM,
  sAIKK,
}

class FormalCapture extends StatefulWidget {
  final IlluminationType illuminationType;
  final Map<String, dynamic> illuminationParams;
  final String? imagePath;

  const FormalCapture({
    Key? key,
    required this.illuminationType,
    required this.illuminationParams,
    this.imagePath,
  }) : super(key: key);

  @override
  FormalCaptureState createState() => FormalCaptureState();
}

class FormalCaptureState extends State<FormalCapture> with WidgetsBindingObserver {
  // Define channels for native code interaction
  static const MethodChannel _channel = MethodChannel('smart_scope/camera2');
  static const MethodChannel _memoryChannel = MethodChannel('smart_scope/memory');
  
  bool _isTakingPicture = false;
  String? _imagePath;
  Uint8List? _imageBytes;  // Store image data
  bool _isCameraInitialized = false;
  
  // Camera parameters
  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 5.0;

  // Add HDR and high resolution mode parameters
  bool _isHDREnabled = false;
  bool _isHighResolutionEnabled = true;
  bool _useFixedCameraParams = true;
  
  // Add illumination control state variables
  bool _illuminationPaused = false;
  
  // Add auto capture related variables
  bool _isAutoCapturing = false;
  int _currentCapturePoint = 0;
  List<String> _capturedImagePaths = [];
  final GlobalKey<dynamic> _illuminationKey = GlobalKey();

  // Add camera ISO and exposure time parameters
  final int _fixedIsoValue = 500; // Corrected to reasonable ISO value
  final double _fixedExposureTime = 150; // Corrected to 150 milliseconds

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupMemoryChannel();
    _enterFullScreen();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    _useFixedCameraParams = true;

    if (widget.imagePath == null) {
      Future.delayed(Duration(milliseconds: 300), () {
        if (mounted) {
          _requestPermissions();
        }
      });
    } else {
      _imagePath = widget.imagePath;
    }
  }

  void _setupMemoryChannel() {
    _memoryChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLowMemory') {
        if (_isCameraInitialized) {
          await _disposeCamera();
          _isCameraInitialized = false;
        }

        if (_imageBytes != null) {
          setState(() {
            _imageBytes = null;
          });
        }

        if (mounted && widget.imagePath == null) {
          Future.delayed(Duration(seconds: 1), () {
            if (mounted && !_isCameraInitialized) {
              _initCamera();
            }
          });
        }
        
        return true;
      }
      return null;
    });
  }

  Future<void> _requestMemoryRelease() async {
    try {
      await _memoryChannel.invokeMethod('releaseMemory');
    } catch (e) {
      debugPrint('Memory release request failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        if (_isCameraInitialized) {
          _disposeCamera();
          _isCameraInitialized = false;
        }
        break;
      case AppLifecycleState.resumed:
        if (!_isCameraInitialized && widget.imagePath == null) {
          _initCamera();
        }
        break;
      default:
        break;
    }
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullScreen() {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      if (Platform.isAndroid && await Permission.storage.isGranted)
        Permission.storage,
      if (Platform.isAndroid && int.parse(await _getPlatformVersion()) >= 33)
        Permission.photos
    ].request();
    
    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
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
        return '0';
      }
    }
    return '0';
  }

  Future<void> _initCamera() async {
    try {
      if (_isCameraInitialized) {
        await _disposeCamera();
      }

      int isoValue = _fixedIsoValue;
      if (isoValue < 100) {
        debugPrint('Init: ISO too low, auto-adjusted to 100');
        isoValue = 100;
      }
      
      int exposureTime = _fixedExposureTime.toInt();
      if (exposureTime < 1) { // Minimum exposure time set to 1ms
        debugPrint('Init: Exposure time too short, auto-adjusted to 1ms');
        exposureTime = 1;
      }
      
      // Default: rear camera, high resolution mode, auto exposure and auto focus
      final result = await _channel.invokeMethod('initCamera', {
        'useRearCamera': true,
        'highResolutionMode': _isHighResolutionEnabled,
        'hdrMode': _isHDREnabled,
        'useFixedCameraParams': _useFixedCameraParams,
        'isoValue': isoValue,
        'exposureTimeMs': exposureTime,
      });
      
      if (result == true && mounted) {
        setState(() => _isCameraInitialized = true);
        debugPrint('Camera initialized successfully with params ISO: $isoValue, Exposure: ${exposureTime}ms');

        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted && _isCameraInitialized) {
            setFixedCameraParams();
          }
        });
      } else {
        _showSnackBar('Camera initialization failed', Colors.red);
      }
    } catch (e) {
      debugPrint('Camera initialization failed: $e');
      _showSnackBar('Camera initialization failed: $e', Colors.red);
    }
  }
  
  Future<void> _disposeCamera() async {
    if (!_isCameraInitialized) {
      debugPrint('Camera not initialized, no need to release');
      return;
    }
    
    debugPrint('Starting camera resource release');
    try {
      _isCameraInitialized = false;
      
      // Call native method to release camera resources
      final result = await _channel.invokeMethod('disposeCamera');
      debugPrint('Camera resources released successfully: $result');
      return result;
    } catch (e) {
      debugPrint('Camera release failed: $e');
      _isCameraInitialized = false;
      return;
    }
  }

  Future<void> _setZoomLevel(double value) async {
    try {
      value = value.clamp(_minZoom, _maxZoom);
      final bool result = await _channel.invokeMethod('setZoomLevel', {'zoomLevel': value});
      if (result && mounted) {
        setState(() => _zoomLevel = value);
      }
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

  Widget _buildIllumination() {
    final Duration animationDuration = Duration(
        milliseconds: widget.illuminationParams['interval'] ?? 1500
    );

    final double offsetXMM = widget.illuminationParams['offsetX_mm'] ?? 0.0;
    final double offsetYMM = widget.illuminationParams['offsetY_mm'] ?? 0.0;

    final double ppi = widget.illuminationParams['ppi'] ?? 470.0;

    final double offsetXPixels = MyApp.ppiManager.mmToPixelsWithPPI(offsetXMM, ppi);
    final double offsetYPixels = MyApp.ppiManager.mmToPixelsWithPPI(offsetYMM, ppi);

    switch (widget.illuminationType) {
      case IlluminationType.AIKK:
        return AIKK_illumination(
          key: _illuminationKey,
          radius: widget.illuminationParams['radius'] ?? 10.0,
          spacing: widget.illuminationParams['spacing'] ?? 20.0,
          dotColor: widget.illuminationParams['dotColor'] ?? Colors.white,
          animationDuration: animationDuration,
          continuousMode: !_illuminationPaused,
          isPreview: false,
          offsetX: offsetXPixels,
          offsetY: offsetYPixels,
          backgroundColor: Colors.transparent,
          showCenterPoint: widget.illuminationParams['showCenterPoint'] ?? false,
        );
      case IlluminationType.FPM:
        return FPM_illumination(
          key: _illuminationKey,
          rows: widget.illuminationParams['rows'] ?? 4,
          columns: widget.illuminationParams['columns'] ?? 4,
          radius: widget.illuminationParams['radius'] ?? 10.0,
          spacing: widget.illuminationParams['spacing'] ?? 20.0,
          dotColor: widget.illuminationParams['dotColor'] ?? Colors.white,
          animationDuration: animationDuration,
          continuousMode: !_illuminationPaused,
          isPreview: false,
          offsetX: offsetXPixels,
          offsetY: offsetYPixels,
          backgroundColor: Colors.transparent,
        );
      case IlluminationType.sAIKK:
        return sAIKK_illumination(
          key: _illuminationKey,
          radius: widget.illuminationParams['radius'] ?? 10.0,
          spacing: widget.illuminationParams['spacing'] ?? 20.0,
          dotColor: widget.illuminationParams['dotColor'] ?? Colors.white,
          animationDuration: animationDuration,
          continuousMode: !_illuminationPaused,
          isPreview: false,
          offsetX: offsetXPixels,
          offsetY: offsetYPixels,
          backgroundColor: Colors.transparent,
        );
      default:
        return Container();
    }
  }

  double _mmToPixels(double mm, double ppi) {
    return MyApp.ppiManager.mmToPixelsWithPPI(mm, ppi);
  }

  Future<void> _toggleHDRMode() async {
    try {
      final bool newHDRMode = !_isHDREnabled;
      final bool result = await _channel.invokeMethod('setHDRMode', {'enabled': newHDRMode});
      
      if (result && mounted) {
        setState(() => _isHDREnabled = newHDRMode);
        _showSnackBar('HDR Mode: ${newHDRMode ? "ON" : "OFF"}', Colors.green);
      }
    } catch (e) {
      debugPrint('HDR mode toggle error: $e');
      _showSnackBar('HDR mode toggle failed', Colors.red);
    }
  }

  Future<void> _toggleHighResolutionMode() async {
    try {
      final bool newHighResMode = !_isHighResolutionEnabled;
      final bool result = await _channel.invokeMethod('setHighResolutionMode', {'enabled': newHighResMode});
      
      if (result && mounted) {
        setState(() => _isHighResolutionEnabled = newHighResMode);
        _showSnackBar('High Resolution Mode: ${newHighResMode ? "ON" : "OFF"}', Colors.green);
      }
    } catch (e) {
      debugPrint('High resolution mode toggle error: $e');
      _showSnackBar('High resolution mode toggle failed', Colors.red);
    }
  }

  void _pauseIllumination() {
    if (!_illuminationPaused) {
      setState(() {
        _illuminationPaused = true;
      });

      if (_illuminationKey.currentState != null && 
          _illuminationKey.currentState.pauseAnimation != null) {
        _illuminationKey.currentState.pauseAnimation();
      }
    }
  }

  void _resumeIllumination() {
    if (_illuminationPaused) {
      setState(() {
        _illuminationPaused = false;
      });

      if (_illuminationKey.currentState != null && 
          _illuminationKey.currentState.resumeAnimation != null) {
        _illuminationKey.currentState.resumeAnimation();
      }
    }
  }

  Future<void> _startAutoCapture() async {
    if (_isAutoCapturing) return;
    
    setState(() {
      _isAutoCapturing = true;
      _currentCapturePoint = 0;
      _capturedImagePaths = [];
    });
    
    _showSnackBar('Starting auto capture', Colors.blue);

    int totalPoints;
    switch (widget.illuminationType) {
      case IlluminationType.AIKK:
        totalPoints = 4;
        break;
      case IlluminationType.FPM:
        int rows = widget.illuminationParams['rows'] ?? 4;
        int columns = widget.illuminationParams['columns'] ?? 4;
        totalPoints = rows * columns;
        break;
      case IlluminationType.sAIKK:
        totalPoints = widget.illuminationParams['circlePoints'] ?? 16;
        break;
      default:
        totalPoints = 4;
    }
    
    try {
      _pauseIllumination();
      _currentCapturePoint = 0;

      int isoValue = _fixedIsoValue;
      if (isoValue < 100) {
        debugPrint('Auto capture: ISO too low, auto-adjusted to 100');
        isoValue = 100;
      }
      
      int exposureTime = _fixedExposureTime.toInt();
      if (exposureTime < 1) { // Minimum exposure time set to 1ms
        debugPrint('Auto capture: Exposure time too short, auto-adjusted to 1ms');
        exposureTime = 1;
      }

      bool useFixedParams = true;

      while (_currentCapturePoint < totalPoints) {
        if (!_isAutoCapturing) break; // Exit if user cancelled auto capture
        
        setState(() {
        });
        
        if (_illuminationKey.currentState != null) {
          if (widget.illuminationType == IlluminationType.AIKK) {
            _illuminationKey.currentState.setActiveDot(_currentCapturePoint % 4);
          } else if (widget.illuminationType == IlluminationType.FPM) {
            _illuminationKey.currentState.setActiveDot(_currentCapturePoint);
          } else if (widget.illuminationType == IlluminationType.sAIKK) {
            _illuminationKey.currentState.setActiveDot(_currentCapturePoint);
          }
        }

        await Future.delayed(Duration(milliseconds: 300));

        try {
          String illuminationTypeName = widget.illuminationType.toString().split('.').last;
          int radiusValue = (widget.illuminationParams['radius']).round();
          int spacingValue = (widget.illuminationParams['spacing']).round();
          
          Map<String, dynamic> illuminationParams = {
            'radius': radiusValue,
            'spacing': spacingValue,
            'type': illuminationTypeName,
            'currentPoint': _currentCapturePoint, // Add current point index
          };

          if (widget.illuminationParams.containsKey('offsetX_mm')) {
            illuminationParams['offsetX_mm'] = widget.illuminationParams['offsetX_mm'];
          }
          
          if (widget.illuminationParams.containsKey('offsetY_mm')) {
            illuminationParams['offsetY_mm'] = widget.illuminationParams['offsetY_mm'];
          }
          
          if (widget.illuminationParams.containsKey('showCenterPoint')) {
            illuminationParams['showCenterPoint'] = widget.illuminationParams['showCenterPoint'];
          }

          debugPrint("Auto capture point ${_currentCapturePoint+1}/$totalPoints, ISO=$isoValue, Exposure=${exposureTime}ms");
          
          String imagePath;
          try {
            if (_useFixedCameraParams) {
              imagePath = await _channel.invokeMethod('takePicture', {
                'hdrMode': _isHDREnabled,
                'highResolutionMode': _isHighResolutionEnabled,
                'illuminationParams': illuminationParams,
                'pageId': 'default',
                'useFixedCameraParams': true, 
                'isoValue': _useFixedCameraParams ? isoValue : null,
                'exposureTimeMs': _useFixedCameraParams ? exposureTime : null,
              });
            } else {
              imagePath = await _channel.invokeMethod('takePicture', {
                'hdrMode': _isHDREnabled,
                'highResolutionMode': _isHighResolutionEnabled,
                'illuminationParams': illuminationParams,
                'pageId': 'default',
                'useFixedCameraParams': false,
              });
            }
          } catch (takePictureError) {
            if (_useFixedCameraParams) {
              debugPrint("Failed with fixed params, switching to auto: $takePictureError");

              imagePath = await _channel.invokeMethod('takePicture', {
                'hdrMode': _isHDREnabled,
                'highResolutionMode': _isHighResolutionEnabled,
                'illuminationParams': illuminationParams,
                'pageId': 'default',
                'useFixedCameraParams': false,
              });
            } else {
              throw takePictureError;
            }
          }

          _capturedImagePaths.add(imagePath);

          _showSnackBar('Captured ${_currentCapturePoint + 1}/$totalPoints', Colors.green);

          await Future.delayed(Duration(milliseconds: 500));
          
        } catch (e) {
          debugPrint("Auto capture error: $e");
          _showSnackBar('Capture failed: $e', Colors.red);
        }

        _currentCapturePoint++;
      }

      if (_isAutoCapturing) {
        _showSnackBar('Auto capture completed, ${_capturedImagePaths.length} images captured', Colors.blue);
      }
    } catch (e) {
      debugPrint("Auto capture process error: $e");
      _showSnackBar('Auto capture failed: $e', Colors.red);
    } finally {
      _resumeIllumination();
      setState(() {
        _isAutoCapturing = false;
      });
    }
  }

  void _cancelAutoCapture() {
    if (!_isAutoCapturing) return;
    
    setState(() {
      _isAutoCapturing = false;
    });
    
    _showSnackBar('Auto capture cancelled', Colors.orange);
    _resumeIllumination();
  }

  // Use native camera to take picture
  Future<void> _takePicture() async {
    if (_isTakingPicture) return;

    setState(() => _isTakingPicture = true);

    _pauseIllumination();
    
    try {
      HapticFeedback.mediumImpact();
      String illuminationTypeName = widget.illuminationType.toString().split('.').last;
      int radiusValue = (widget.illuminationParams['radius']).round();
      int spacingValue = (widget.illuminationParams['spacing']).round();

      Map<String, dynamic> illuminationParams = {
        'radius': radiusValue,
        'spacing': spacingValue,
        'type': illuminationTypeName,
      };

      if (widget.illuminationParams.containsKey('offsetX_mm')) {
        illuminationParams['offsetX_mm'] = widget.illuminationParams['offsetX_mm'];
      }
      
      if (widget.illuminationParams.containsKey('offsetY_mm')) {
        illuminationParams['offsetY_mm'] = widget.illuminationParams['offsetY_mm'];
      }
      
      if (widget.illuminationParams.containsKey('showCenterPoint')) {
        illuminationParams['showCenterPoint'] = widget.illuminationParams['showCenterPoint'];
      }

      int isoValue = _fixedIsoValue;
      if (isoValue < 100) {
        debugPrint('Capture: ISO too low, auto-adjusted to 100');
        isoValue = 100;
      }
      
      int exposureTime = _fixedExposureTime.toInt();
      if (exposureTime < 1) {
        debugPrint('Capture: Exposure time too short, auto-adjusted to 1ms');
        exposureTime = 1;
      }

      debugPrint("Illumination params: $illuminationParams");
      debugPrint("Camera params: ISO=$isoValue, Exposure=${exposureTime}ms");
      
      String imagePath;
      try {
        imagePath = await _channel.invokeMethod('takePicture', {
          'hdrMode': _isHDREnabled,
          'highResolutionMode': _isHighResolutionEnabled,
          'illuminationParams': illuminationParams,
          'pageId': 'default',
          'useFixedCameraParams': _useFixedCameraParams,
          'isoValue': _useFixedCameraParams ? isoValue : null,
          'exposureTimeMs': _useFixedCameraParams ? exposureTime : null,
        });
      } catch (takePictureError) {
        debugPrint("Failed with current params, trying auto: $takePictureError");

        imagePath = await _channel.invokeMethod('takePicture', {
          'hdrMode': _isHDREnabled,
          'highResolutionMode': _isHighResolutionEnabled,
          'illuminationParams': illuminationParams,
          'pageId': 'default',
          'useFixedCameraParams': false,
        });
      }
      
      debugPrint("Photo captured: $imagePath");

      if (mounted) {
        setState(() => _isTakingPicture = false);
        _showSnackBar('Photo saved to: $imagePath', Colors.green);

        _resumeIllumination();
      }
    } catch (e) {
      debugPrint("Capture error: $e");
      if (mounted) {
        _showSnackBar('Capture failed: $e', Colors.red);
        setState(() => _isTakingPicture = false);

        _resumeIllumination();
      }
    }
  }

  Future<Uint8List?> _loadContentUriBytes(String uri) async {
    try {
      final Uint8List? bytes = await _channel.invokeMethod('loadImageFromContentUri', {'uri': uri});
      return bytes;
    } catch (e) {
      debugPrint('Failed to load content URI image data: $e');
      return null;
    }
  }

  bool _isContentUri(String path) {
    return path.startsWith('content://');
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

  @override
  void dispose() {
    debugPrint("FormalCaptureState.dispose starting resource cleanup");
    try {
      _memoryChannel.setMethodCallHandler(null);

      _requestMemoryRelease();

      _exitFullScreen();

      SystemChrome.setPreferredOrientations([]);

      WidgetsBinding.instance.removeObserver(this);

      _disposeCamera();
    } catch (e) {
      debugPrint("FormalCaptureState.dispose error: $e");
    } finally {
      debugPrint("FormalCaptureState.dispose calling super.dispose()");
      super.dispose();
    }
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? Colors.white.withOpacity(0.2) : Colors.black,
          border: Border.all(
            color: isActive ? Colors.white : Colors.white38,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureButton() {
    final double outerSize = 60;
    final double innerSize = _isTakingPicture ? 50 : 50;

    return GestureDetector(
      onTap: _isTakingPicture ? null : _takePicture,
      child: Container(
        width: outerSize,
        height: outerSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(
            color: Colors.white,
            width: 2.5,
          ),
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              color: _isTakingPicture ? Colors.grey : Colors.white,
              shape: BoxShape.circle,
            ),
            child: _isTakingPicture
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color.fromARGB(0, 0, 0, 0),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      backgroundColor: Colors.black,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildIllumination(),

          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              height: 200,
              color: Colors.black,
              child: widget.imagePath != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _imageBytes != null
                      ? Image.memory(
                          _imageBytes!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint("内存图片加载错误: $error");
                            return const Center(
                              child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
                            );
                          },
                        )
                      : _isContentUri(widget.imagePath!)
                        ? FutureBuilder<Uint8List?>(
                            future: _loadContentUriBytes(widget.imagePath!),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              } else if (snapshot.hasData && snapshot.data != null) {
                                return Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    debugPrint("内容URI图片加载错误: $error");
                                    return const Center(
                                      child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
                                    );
                                  },
                                );
                              } else {
                                return const Center(
                                  child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
                                );
                              }
                            },
                          )
                        : Image.file(
                            File(widget.imagePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint("图片加载错误: $error");
                              return const Center(
                                child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
                              );
                            },
                          ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: _isCameraInitialized 
                      ? AndroidView(
                          viewType: 'smart_scope/camera2_preview',
                          layoutDirection: TextDirection.ltr,
                          creationParams: <String, dynamic>{
                            'useRearCamera': true,
                            'highResolutionMode': _isHighResolutionEnabled,
                            'hdrMode': _isHDREnabled,
                            'useFixedCameraParams': false,
                          },
                          creationParamsCodec: const StandardMessageCodec(),
                          onPlatformViewCreated: (int id) {
                            debugPrint('相机预览视图已创建: $id');
                          },
                        )
                      : Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        ),
                    ),
                  ),
            ),
          ),

          if (widget.imagePath == null)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildOptionButton(
                        label: 'HDR',
                        isActive: _isHDREnabled,
                        onTap: _toggleHDRMode,
                      ),
                      
                      const SizedBox(width: 16),
                      _buildOptionButton(
                        label: 'High Res',
                        isActive: _isHighResolutionEnabled,
                        onTap: _toggleHighResolutionMode,
                      ),
                      
                      const SizedBox(width: 16),

                      _buildOptionButton(
                        label: _useFixedCameraParams ? 'Fixed' : 'Auto',
                        isActive: _useFixedCameraParams,
                        onTap: _toggleFixedParamsMode,
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        icon: _isAutoCapturing ? Icons.stop : Icons.auto_awesome_motion,
                        onTap: _isAutoCapturing ? _cancelAutoCapture : _startAutoCapture,
                        isActive: _isAutoCapturing,
                      ),
                      
                      _buildCaptureButton(),

                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildControlButton(
                            icon: Icons.remove,
                            onTap: _zoomOut,
                            isActive: _zoomLevel > _minZoom,
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '${_zoomLevel.toStringAsFixed(1)}x',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _buildControlButton(
                            icon: Icons.add,
                            onTap: _zoomIn,
                            isActive: _zoomLevel < _maxZoom,
                          ),
                        ],
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

  Widget _buildOptionButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? Colors.white : Colors.white38,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> setFixedCameraParams() async {
    if (_isCameraInitialized) {
      try {
        debugPrint('Preparing to set camera params: ISO $_fixedIsoValue, Exposure ${_fixedExposureTime}ms');

        int isoValue = _fixedIsoValue;
        if (isoValue < 100) {
          debugPrint('ISO too low, auto-adjusted to 100');
          isoValue = 100;
        }
        
        int exposureTime = _fixedExposureTime.toInt();
        if (exposureTime < 1) { // Minimum exposure time set to 1ms
          debugPrint('Exposure time too short, auto-adjusted to 1ms');
          exposureTime = 1;
        }

        try {
          final bool result = await _channel.invokeMethod('setCameraParams', {
            'useFixedCameraParams': true, // Always use fixed params
            'isoValue': isoValue,
            'exposureTimeMs': exposureTime,
          });
          
          if (result) {
            debugPrint('Camera params set: ISO $isoValue, Exposure ${exposureTime}ms');
          }
        } catch (innerError) {
          debugPrint('Attempting to apply params by reinitializing camera: $innerError');

          await _disposeCamera();

          await Future.delayed(Duration(milliseconds: 200));

          final result = await _channel.invokeMethod('initCamera', {
            'useRearCamera': true,
            'highResolutionMode': _isHighResolutionEnabled,
            'hdrMode': _isHDREnabled,
            'useFixedCameraParams': true,
            'isoValue': isoValue,
            'exposureTimeMs': exposureTime,
          });
          
          if (result == true && mounted) {
            setState(() => _isCameraInitialized = true);
            debugPrint('Successfully applied params by reinitializing camera');
          }
        }
      } catch (e) {
        debugPrint('Set camera params error: $e');
      }
    }
  }

  Future<void> updateCameraParams() async {
    if (!_isCameraInitialized) return;
    
    try {
      debugPrint('Updating camera params: ISO $_fixedIsoValue, Exposure ${_fixedExposureTime}ms');

      int isoValue = _fixedIsoValue;

      int exposureTime = _fixedExposureTime.toInt();

      final bool result = await _channel.invokeMethod('setCameraParams', {
        'useFixedCameraParams': true,
        'isoValue': isoValue,
        'exposureTimeMs': exposureTime,
      });
      
      if (result) {
        debugPrint('Camera params updated: ISO $isoValue, Exposure ${exposureTime}ms');
        _showSnackBar('Camera params updated', Colors.green);
      }
    } catch (e) {
      debugPrint('Update camera params error: $e');
      _showSnackBar('Update camera params failed', Colors.red);
    }
  }

  Future<void> _toggleFixedParamsMode() async {
    try {
      final bool newMode = !_useFixedCameraParams;
      setState(() => _useFixedCameraParams = newMode);
      
      if (newMode) {
        await setFixedCameraParams();
        _showSnackBar('Switched to fixed params mode', Colors.green);
      } else {
        final bool result = await _channel.invokeMethod('setCameraParams', {
          'useFixedCameraParams': false,
        });
        if (result) {
          _showSnackBar('Switched to auto params mode', Colors.green);
        }
      }
    } catch (e) {
      debugPrint('Toggle params mode error: $e');
      _showSnackBar('Toggle params mode failed', Colors.red);
    }
  }
}
