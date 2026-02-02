import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';

/// AIKK Illumination Component
///
/// This component uses absolute positioning logic, directly controlling the component's position on the screen
/// through [offsetX] and [offsetY] parameters.
/// The component is not affected by parent layout and can be displayed at fixed coordinates on any page.
///
class AIKK_illumination extends StatefulWidget {
  final double radius; // Radius of small dots
  final double spacing; // Distance from dots to center
  final Color dotColor;
  final Duration animationDuration;
  final Function(bool isComplete)? onAnimationComplete;
  final bool continuousMode;
  final bool isPreview;
  final double offsetX; // X coordinate of component center point (pixels)
  final double offsetY; // Y coordinate of component center point (pixels)
  final Color? backgroundColor; // Background color parameter
  final bool showCenterPoint; // Whether to show only center point, used for debugging positioning
  final double centerRadius; // Radius of center point, used when showCenterPoint is true

  const AIKK_illumination({
    Key? key,
    required this.radius,
    required this.spacing,
    required this.dotColor,
    this.animationDuration = const Duration(milliseconds: 500),
    this.onAnimationComplete,
    this.continuousMode = true,
    this.isPreview = false,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.backgroundColor, // Optional background color
    this.showCenterPoint = false, // Default not showing center point
    this.centerRadius = 6, // Default center point radius
  }) : super(key: key);

  @override
  AIKK_illuminationState createState() => AIKK_illuminationState();
}

class AIKK_illuminationState extends State<AIKK_illumination> {
  late List<bool> dotStates;
  Timer? timer; // Changed to nullable type, not using late
  int currentDot = 0;
  bool _isPaused = false; // Add pause state flag

  @override
  void initState() {
    super.initState();
    _initializeDotStates();
    // Add a small delay before starting the animation to prevent the initial delay
    Future.delayed(const Duration(milliseconds: 50), () {
      _startAnimation();
    });
  }

  // Set specific dot as active
  void setActiveDot(int dotIndex) {
    if (timer != null && timer!.isActive) {
      timer!.cancel();
    }

    setState(() {
      dotStates = List.generate(4, (i) => false);
      dotStates[dotIndex % 4] = true;
      currentDot = dotIndex % 4;
      _isPaused = true;
    });
  }

  void _initializeDotStates() {
    dotStates = List.generate(4, (i) => false);
  }

  // Pause animation
  void pauseAnimation() {
    if (!_isPaused && timer != null && timer!.isActive) {
      timer!.cancel();
      _isPaused = true;
    }
  }

  // Resume animation
  void resumeAnimation() {
    if (_isPaused) {
      _startAnimation();
      _isPaused = false;
    }
  }

  void _startAnimation() {
    // Cancel existing timer
    if (timer != null && timer!.isActive) {
      timer!.cancel();
    }
    
    // Immediately show the first dot
    setState(() {
      if (widget.showCenterPoint) {
        // When showing only center point, there's only one state
        dotStates = List.generate(1, (i) => true);
      } else {
        // Otherwise light up the first dot according to original logic
        dotStates = List.generate(4, (i) => false);
        dotStates[currentDot] = true;
      }
    });
    
    // Start Timer immediately to ensure consistent intervals between dots
    timer = Timer.periodic(widget.animationDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        if (widget.showCenterPoint) {
          // When showing only center point, there's only one state
          dotStates = List.generate(1, (i) => true);
        } else {
          // Otherwise cycle through lighting up 4 dots according to original logic
          dotStates = List.generate(4, (i) => false);
          currentDot = (currentDot + 1) % 4;  // First update current dot index
          dotStates[currentDot] = true;  // Then light up new current dot
        }

        if (currentDot == 0 && !widget.showCenterPoint) {
          if (!widget.continuousMode) {
            timer.cancel();
            widget.onAnimationComplete?.call(true);
          } else {
            widget.onAnimationComplete?.call(false);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    if (timer != null) {
      timer!.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double totalSize;
    if (widget.showCenterPoint) {
      totalSize = widget.centerRadius * 2;
    } else {
      totalSize = widget.spacing * 2 + widget.radius * 2;
    }

    // Debug print for positioning verification
    print(
        'AIKK: totalSize=${totalSize}, centerRadius=${widget.centerRadius}, radius=${widget.radius}, spacing=${widget.spacing}');

    // Use absolute positioning
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.loose,
      children: [
        // Positioned container
        Positioned(
          // Calculate position to center the component at offsetX, offsetY
          left: widget.offsetX - totalSize / 2,
          top: widget.offsetY - totalSize / 2,
          child: SizedBox(
            width: totalSize,
            height: totalSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: _buildIlluminationPoints(totalSize),
            ),
          ),
        ),
      ],
    );
  }

  // Build illumination points
  List<Widget> _buildIlluminationPoints(double totalSize) {
    if (widget.showCenterPoint) {
      // When showCenterPoint is true, only show center point
      return [
        Positioned(
          left: totalSize / 2 - widget.centerRadius,
          top: totalSize / 2 - widget.centerRadius,
          child: Container(
            width: widget.centerRadius * 2,
            height: widget.centerRadius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.dotColor,
            ),
          ),
        ),
      ];
    } else {
      // Otherwise show four surrounding dots
      return [
        // Top dot (0, -spacing)
        Positioned(
          left: totalSize / 2 - widget.radius,
          top: totalSize / 2 - widget.spacing - widget.radius,
          child: _buildDot(0),
        ),
        // Right dot (spacing, 0)
        Positioned(
          left: totalSize / 2 + widget.spacing - widget.radius,
          top: totalSize / 2 - widget.radius,
          child: _buildDot(1),
        ),
        // Bottom dot (0, spacing)
        Positioned(
          left: totalSize / 2 - widget.radius,
          top: totalSize / 2 + widget.spacing - widget.radius,
          child: _buildDot(2),
        ),
        // Left dot (-spacing, 0)
        Positioned(
          left: totalSize / 2 - widget.spacing - widget.radius,
          top: totalSize / 2 - widget.radius,
          child: _buildDot(3),
        ),
      ];
    }
  }

  // Build single dot
  Widget _buildDot(int index) {
    return Container(
      width: widget.radius * 2,
      height: widget.radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dotStates[index]
            ? widget.dotColor
            : (widget.isPreview ? Colors.grey : Colors.transparent),
      ),
    );
  }
}
