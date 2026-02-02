import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import '../Widgets/AIKK_illumination.dart';
import '../Widgets/FPM_illumination.dart';
import '../Widgets/sAIKK_illumination.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../main.dart';
import '../pages/FormalCapture.dart'
    show IlluminationType;

class PureIllumiantionPage extends StatefulWidget {
  final IlluminationType illuminationType;
  final Map<String, dynamic> illuminationParams;

  const PureIllumiantionPage({
    Key? key,
    required this.illuminationType,
    required this.illuminationParams,
  }) : super(key: key);

  @override
  PureIllumiantionPageState createState() => PureIllumiantionPageState();
}

class PureIllumiantionPageState extends State<PureIllumiantionPage>
    with WidgetsBindingObserver {

  static const MethodChannel _channel = MethodChannel('smart_scope/camera2');

  static const MethodChannel _memoryChannel =
      MethodChannel('smart_scope/memory');

  bool _illuminationPaused = false;

  final GlobalKey<dynamic> _illuminationKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterFullScreen();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  Widget _buildIllumination() {
    final Duration animationDuration =
        Duration(milliseconds: widget.illuminationParams['interval'] ?? 1500);

    // Get offset in millimeters
    final double offsetXMM = widget.illuminationParams['offsetX_mm'] ?? 0.0;
    final double offsetYMM = widget.illuminationParams['offsetY_mm'] ?? 0.0;

    // Get device PPI
    final double ppi = widget.illuminationParams['ppi'] ?? 441.0;

    // Convert millimeters to pixels
    final double offsetXPixels =
        MyApp.ppiManager.mmToPixelsWithPPI(offsetXMM, ppi);
    final double offsetYPixels =
        MyApp.ppiManager.mmToPixelsWithPPI(offsetYMM, ppi);

    switch (widget.illuminationType) {
      case IlluminationType.AIKK:
        return AIKK_illumination(
          key: _illuminationKey,
          radius: widget.illuminationParams['radius'] ?? 10.0,
          spacing: widget.illuminationParams['spacing'] ?? 20.0,
          dotColor: widget.illuminationParams['dotColor'] ?? Colors.white,
          animationDuration: animationDuration,
          continuousMode: !_illuminationPaused, // Control continuous mode based on pause state
          isPreview: false, // Set to non-preview mode, this is the formal capture page
          offsetX: offsetXPixels, // Pass offset value directly to AIKK component
          offsetY: offsetYPixels, // Pass offset value directly to AIKK component
          backgroundColor: Colors.transparent,
          showCenterPoint: widget.illuminationParams['showCenterPoint'] ??
              false,
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
          innerRingCount: widget.illuminationParams['innerRingCount'] ?? 2,
          outerRingCount: widget.illuminationParams['outerRingCount'] ?? 2,
          outerRingOverlapRatios: widget.illuminationParams['outerRingOverlapRatios'] ?? [0.5, 0.4],
        );
      default:
        return Container();
    }
  }

  @override
  void dispose() {
    debugPrint("PureIllumiantionPageState.dispose starting resource cleanup");
    try {
      // Exit fullscreen
      _exitFullScreen();

      // Remove lifecycle observer
      WidgetsBinding.instance.removeObserver(this);
    } catch (e) {
      debugPrint("PureIllumiantionPageState.dispose error: $e");
    } finally {
      // Call parent dispose
      debugPrint("PureIllumiantionPageState.dispose calling super.dispose()");
      super.dispose();
    }
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
          // Illumination component
          _buildIllumination(),
        ],
      ),
    );
  }
}
