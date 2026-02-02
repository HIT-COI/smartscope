import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';

/// FPM Illumination Component
/// 
/// This component uses the same absolute positioning logic as AIKK, directly controlling 
/// the component's position on the screen through [offsetX] and [offsetY] parameters.
/// The component is not affected by parent layout and can be displayed at fixed coordinates on any page.
///
class FPM_illumination extends StatefulWidget {
  final int rows;
  final int columns;
  final double radius;
  final double spacing;
  final Color dotColor;
  final Duration animationDuration;
  final Function(bool isComplete)? onAnimationComplete;
  final bool continuousMode;
  final bool isPreview;
  final double offsetX;
  final double offsetY;
  final Color? backgroundColor;

  const FPM_illumination({
    Key? key,
    required this.rows,
    required this.columns,
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
  }) : super(key: key);

  @override
  FPM_illuminationState createState() => FPM_illuminationState();
}

class FPM_illuminationState extends State<FPM_illumination> {
  Timer? _timer;
  int _currentDot = 0;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _enterFullScreen();
    // Add a small delay before starting the animation to prevent the initial delay
    Future.delayed(const Duration(milliseconds: 50), () {
      _startTimer();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _exitFullScreen();
    super.dispose();
  }

  void pauseAnimation() {
    if (!_isPaused && _timer != null && _timer!.isActive) {
      _timer!.cancel();
      _isPaused = true;
    }
  }

  void resumeAnimation() {
    if (_isPaused) {
      _startTimer();
      _isPaused = false;
    }
  }

  void setActiveDot(int dotIndex) {
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
    }
    
    setState(() {
      _currentDot = dotIndex % (widget.rows * widget.columns);
      _isPaused = true;
    });
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  void _startTimer() {
    int totalDots = widget.rows * widget.columns;

    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
    }
    
    // Immediately show the first dot
    setState(() {
      _currentDot = _currentDot % totalDots;
    });

    _timer = Timer.periodic(widget.animationDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _currentDot = (_currentDot + 1) % totalDots;
        
        if (_currentDot == totalDots - 1) {
          if (!widget.continuousMode) {
            _timer?.cancel();
            widget.onAnimationComplete?.call(true);
            Future.delayed(widget.animationDuration, () {
              Navigator.pop(context);
            });
          } else {
            widget.onAnimationComplete?.call(false);
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Calculate total size of the dot matrix
    final double dotMatrixWidth = (widget.columns - 1) * widget.spacing + widget.radius * 2;
    final double dotMatrixHeight = (widget.rows - 1) * widget.spacing + widget.radius * 2;
    final double totalSize = max(dotMatrixWidth, dotMatrixHeight);
    
    // Use the same absolute positioning logic as AIKK
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.loose,
      children: [
        Positioned(
          left: widget.offsetX - totalSize / 2,
          top: widget.offsetY - totalSize / 2,
          child: Container(
            width: totalSize,
            height: totalSize,
            color: widget.backgroundColor ?? Colors.transparent,
            child: CustomPaint(
              painter: DotsPainter(
                currentDot: _currentDot,
                rows: widget.rows,
                columns: widget.columns,
                dotRadius: widget.radius,
                dotSpacing: widget.spacing,
                dotColor: widget.dotColor,
                isPreview: widget.isPreview,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DotsPainter extends CustomPainter {
  final int currentDot;
  final int rows;
  final int columns;
  final double dotRadius;
  final double dotSpacing;
  final Color dotColor;
  final bool isPreview;

  DotsPainter({
    required this.currentDot,
    required this.rows,
    required this.columns,
    required this.dotRadius,
    required this.dotSpacing,
    required this.dotColor,
    this.isPreview = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final dotMatrixWidth = (columns - 1) * dotSpacing + dotRadius * 2;
    final dotMatrixHeight = (rows - 1) * dotSpacing + dotRadius * 2;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    final startX = centerX - dotMatrixWidth / 2 + dotRadius;
    final startY = centerY - dotMatrixHeight / 2 + dotRadius;

    final centerRowIndex = (rows - 1) / 2;
    final centerColIndex = (columns - 1) / 2;

    int dotIndex = 0;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < columns; col++) {
        double x = startX + col * dotSpacing;
        double y = startY + row * dotSpacing;

        bool isCenterDot = _isApproximatelyCenterDot(row, col, centerRowIndex, centerColIndex);

        if (dotIndex == currentDot) {
          paint.color = dotColor;
        } else {
          paint.color = isPreview ? Colors.grey[800]! : Colors.transparent;
        }
        
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
        dotIndex++;
      }
    }
  }

  bool _isApproximatelyCenterDot(int row, int col, double centerRowIndex, double centerColIndex) {
    // For odd rows and columns, there's a single center dot
    if (rows % 2 == 1 && columns % 2 == 1) {
      return row == centerRowIndex.round() && col == centerColIndex.round();
    }

    // For even numbers, the center is between multiple dots
    return (row == centerRowIndex.floor() || row == centerRowIndex.ceil()) && 
           (col == centerColIndex.floor() || col == centerColIndex.ceil());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
