import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Camera2 API proxy class, handles communication with native Android Camera2 API
class Camera2Proxy {
  static const MethodChannel _channel = MethodChannel('smart_scope/camera2');
  
  // Page ID and instance mapping, allows different pages to have independent camera proxies
  static final Map<String, Camera2Proxy> _instances = {};

  // Get or create camera proxy instance for specific page
  factory Camera2Proxy({String pageId = 'default'}) {
    if (!_instances.containsKey(pageId)) {
      _instances[pageId] = Camera2Proxy._internal(pageId);
    }
    return _instances[pageId]!;
  }

  final String pageId;

  Camera2Proxy._internal(this.pageId);

  // Camera state
  bool _isInitialized = false;
  bool _isHighResolutionEnabled = true;
  bool _isHDREnabled = false;
  double _zoomLevel = 1.0;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isHighResolutionEnabled => _isHighResolutionEnabled;
  bool get isHDREnabled => _isHDREnabled;
  double get zoomLevel => _zoomLevel;

  /// Initialize camera
  /// [useRearCamera] - Whether to use rear camera
  Future<bool> initializeCamera({
    bool useRearCamera = true,
    bool highResolutionMode = true,
    bool hdrMode = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('initCamera', {
        'useRearCamera': useRearCamera,
        'highResolutionMode': highResolutionMode,
        'hdrMode': hdrMode,
        'pageId': pageId,
      });
      
      _isInitialized = result ?? false;
      _isHighResolutionEnabled = highResolutionMode;
      _isHDREnabled = hdrMode;
      
      return _isInitialized;
    } catch (e) {
      debugPrint('Camera2 initialization failed: $e');
      return false;
    }
  }

  /// Release camera resources
  Future<void> disposeCamera() async {
    if (!_isInitialized) return;
    
    try {
      await _channel.invokeMethod('disposeCamera', {
        'pageId': pageId,
      });
      _isInitialized = false;

      _instances.remove(pageId);
    } catch (e) {
      debugPrint('Camera2 disposal failed: $e');
    }
  }

  /// Pause camera without fully releasing resources (suitable for temporarily inactive pages)
  Future<void> pauseCamera() async {
    if (!_isInitialized) return;
    
    try {
      await stopLightIntensityMonitoring();

      debugPrint('Camera2 paused (pageId: $pageId)');
    } catch (e) {
      debugPrint('Camera2 pause failed: $e');
    }
  }

  Future<void> dispose() => disposeCamera();

  Future<bool> initCamera({
    bool useRearCamera = true,
    bool highResolutionMode = true,
    bool hdrMode = false,
  }) => initializeCamera(
    useRearCamera: useRearCamera,
    highResolutionMode: highResolutionMode,
    hdrMode: hdrMode,
  );

  /// Set camera zoom level
  Future<bool> setZoomLevel(double zoomLevel) async {
    if (!_isInitialized) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('setZoomLevel', {
        'zoomLevel': zoomLevel,
        'pageId': pageId,
      });
      
      if (result == true) {
        _zoomLevel = zoomLevel;
      }
      
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to set zoom level: $e');
      return false;
    }
  }

  /// Toggle HDR mode
  Future<bool> setHDRMode(bool enabled) async {
    if (!_isInitialized) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('setHDRMode', {
        'enabled': enabled,
        'pageId': pageId,
      });
      
      if (result == true) {
        _isHDREnabled = enabled;
      }
      
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to set HDR mode: $e');
      return false;
    }
  }

  /// Toggle high resolution mode
  Future<bool> setHighResolutionMode(bool enabled) async {
    if (!_isInitialized) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('setHighResolutionMode', {
        'enabled': enabled,
        'pageId': pageId,
      });
      
      if (result == true) {
        _isHighResolutionEnabled = enabled;
      }
      
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to set high resolution mode: $e');
      return false;
    }
  }

  /// Take picture
  Future<String?> takePicture({
    bool hdrMode = false,
    bool highResolutionMode = true,
  }) async {
    if (!_isInitialized) return null;
    
    try {
      final result = await _channel.invokeMethod<String>('takePicture', {
        'hdrMode': hdrMode,
        'highResolutionMode': highResolutionMode,
        'pageId': pageId,
      });
      
      return result;
    } catch (e) {
      debugPrint('Failed to take picture: $e');
      return null;
    }
  }

  /// Get list of supported camera resolutions
  Future<List<Map<String, dynamic>>?> getSupportedResolutions() async {
    if (!_isInitialized) return null;
    
    try {
      final resolutions = await _channel.invokeListMethod<Map<String, dynamic>>(
        'getSupportedResolutions',
        {'pageId': pageId}
      );
      return resolutions;
    } catch (e) {
      debugPrint('Failed to get supported resolutions: $e');
      return null;
    }
  }

  /// Set auto exposure
  Future<bool> setAutoExposure(bool enabled) async {
    if (!_isInitialized) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('setAutoExposure', {
        'enabled': enabled,
        'pageId': pageId,
      });
      
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to set auto exposure: $e');
      return false;
    }
  }

  /// Set exposure time (nanoseconds)
  Future<bool> setExposureTime(int exposureTime) async {
    if (!_isInitialized) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('setExposureTime', {
        'exposureTime': exposureTime,
        'pageId': pageId,
      });
      
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to set exposure time: $e');
      return false;
    }
  }

  /// Start image stream
  StreamSubscription<Uint8List>? startImageStream(Function(Uint8List) onImageAvailable) {
    if (!_isInitialized) return null;
    
    try {
      // Set method call handler
      _channel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'onImageAvailable') {
          // Extract image data
          final Map<dynamic, dynamic>? args = call.arguments;
          if (args != null && args['pageId'] == pageId) {
            final Uint8List? imageBytes = args['imageData'];
            if (imageBytes != null) {
              onImageAvailable(imageBytes);
            }
          }
        }
      });
      
      // Start image stream
      _channel.invokeMethod('startImageStream', {'pageId': pageId});
      
      // Return mock subscription
      return _MockStreamSubscription(() {
        stopImageStream();
      });
    } catch (e) {
      debugPrint('Failed to start image stream: $e');
      return null;
    }
  }

  /// Stop image stream
  Future<void> stopImageStream() async {
    if (!_isInitialized) return;
    
    try {
      await _channel.invokeMethod('stopImageStream', {'pageId': pageId});
    } catch (e) {
      debugPrint('Failed to stop image stream: $e');
    }
  }
  
  /// Get current light intensity value
  Future<double> getCurrentLightIntensity() async {
    if (!_isInitialized) {
      debugPrint('Camera not initialized, cannot get light intensity');
      return 0.0;
    }
    
    // Check if page ID is center_align_page
    if (pageId != 'center_align_page') {
      debugPrint('Light intensity measurement only available on center_align_page.');
      return 0.0;
    }
    
    try {
      // Call native method to get light intensity value
      final result = await _channel.invokeMethod<double>('getCurrentLightIntensity');
      return result ?? 0.0;
    } catch (e) {
      debugPrint('Failed to get light intensity value: $e');
      return 0.0;
    }
  }

  /// Start light intensity monitoring
  Stream<double>? startLightIntensityMonitoring() {
    if (!_isInitialized) return null;
    
    // Check if page ID is center_align_page
    if (pageId != 'center_align_page') {
      debugPrint('Light intensity monitoring only available on center_align_page.');
      return null;
    }
    
    try {
      final controller = StreamController<double>.broadcast();

      _channel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'onIntensityUpdate') {
          final Map<dynamic, dynamic>? args = call.arguments;
          if (args != null && args['event'] == 'intensityUpdate') {
            final double intensity = args['intensity'] ?? 0.0;
            controller.add(intensity);
          }
        }
        return null;
      });
      
      // Start intensity monitoring
      _channel.invokeMethod('startIntensityMonitoring');
      
      // Set cancel callback
      controller.onCancel = () {
        stopLightIntensityMonitoring();
      };
      
      return controller.stream;
    } catch (e) {
      debugPrint('Failed to start light intensity monitoring: $e');
      return null;
    }
  }
  
  /// Stop light intensity monitoring
  Future<bool> stopLightIntensityMonitoring() async {
    if (!_isInitialized) return false;
    
    // Check if page ID is center_align_page
    if (pageId != 'center_align_page') {
      debugPrint('Light intensity monitoring only available on center_align_page.');
      return true; // Return true as it's not applicable
    }
    
    try {
      final result = await _channel.invokeMethod<bool>('stopIntensityMonitoring');
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to stop light intensity monitoring: $e');
      return false;
    }
  }

  /// Get camera information
  Future<Map<String, dynamic>?> getCameraInfo() async {
    if (!_isInitialized) {
      debugPrint('Camera not initialized, cannot get camera info');
      return null;
    }
    
    try {
      final Map<String, dynamic>? result = await _channel.invokeMapMethod<String, dynamic>(
        'getCameraInfo',
        {'pageId': pageId}
      );
      
      if (result != null) {
        // Get camera max zoom capability from native code
        if (!result.containsKey('maxZoom')) {
          // If native code doesn't provide maxZoom, add a default value
          result['maxZoom'] = 5.0;
        }

        debugPrint('Camera info retrieved: ${result.toString()}');
      }
      
      return result;
    } catch (e) {
      debugPrint('Failed to get camera info: $e');
      return null;
    }
  }

  /// Get best resolution information
  Future<Map<String, dynamic>?> getBestResolution(bool highResolution) async {
    if (!_isInitialized) return null;
    
    try {
      // Get all supported resolutions
      final resolutions = await getSupportedResolutions();
      if (resolutions == null || resolutions.isEmpty) {
        return null;
      }

      if (highResolution) {
        resolutions.sort((a, b) {
          final aPixels = (a['width'] as int) * (a['height'] as int);
          final bPixels = (b['width'] as int) * (b['height'] as int);
          return bPixels.compareTo(aPixels); // Sort in descending order
        });
        
        // Return highest resolution
        final bestRes = resolutions.first;
        final width = bestRes['width'] as int;
        final height = bestRes['height'] as int;
        return {
          'width': width,
          'height': height,
          'megapixels': (width * height) / 1000000,
          'ratio': width / height,
        };
      } else {
        // Find suitable medium resolution
        final targetRes = resolutions.firstWhere(
          (res) => (res['height'] as int) >= 1080 && (res['height'] as int) <= 1440,
          orElse: () {
            // If not found, use closest to 1080p
            resolutions.sort((a, b) {
              final aDiff = ((a['height'] as int) - 1080).abs();
              final bDiff = ((b['height'] as int) - 1080).abs();
              return aDiff.compareTo(bDiff);
            });
            return resolutions.first;
          }
        );
        
        final width = targetRes['width'] as int;
        final height = targetRes['height'] as int;
        return {
          'width': width,
          'height': height,
          'megapixels': (width * height) / 1000000,
          'ratio': width / height,
        };
      }
    } catch (e) {
      debugPrint('Failed to get best resolution: $e');
      return null;
    }
  }
}

class _MockStreamSubscription implements StreamSubscription<Uint8List> {
  final Function _onCancel;
  
  _MockStreamSubscription(this._onCancel);
  
  @override
  Future<void> cancel() async {
    _onCancel();
    return Future.value();
  }
  
  @override
  Future<E> asFuture<E>([E? futureValue]) {
    return Future.value(futureValue as E);
  }
  
  @override
  bool get isPaused => false;
  
  @override
  void onData(void Function(Uint8List data)? handleData) {}
  
  @override
  void onDone(void Function()? handleDone) {}
  
  @override
  void onError(Function? handleError) {}
  
  @override
  void pause([Future<void>? resumeSignal]) {}
  
  @override
  void resume() {}
}

/// Widget for displaying Camera2 preview
class Camera2Preview extends StatefulWidget {
  final bool useRearCamera;
  final bool highResolutionMode;
  final bool hdrMode;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String pageId;

  const Camera2Preview({
    Key? key,
    this.useRearCamera = true,
    this.highResolutionMode = true,
    this.hdrMode = false,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.pageId = 'default',
  }) : super(key: key);

  @override
  State<Camera2Preview> createState() => _Camera2PreviewState();
}

class _Camera2PreviewState extends State<Camera2Preview> {
  @override
  Widget build(BuildContext context) {
    // Using Android platform view
    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: AndroidView(
        viewType: 'smart_scope/camera2_preview',
        creationParams: {
          'useRearCamera': widget.useRearCamera,
          'highResolutionMode': widget.highResolutionMode,
          'hdrMode': widget.hdrMode,
          'pageId': widget.pageId,
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}