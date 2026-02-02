import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';

/// sAIKK Illumination Component
///
/// This component uses the same absolute positioning logic as AIKK, directly controlling 
/// the component's position on the screen through [offsetX] and [offsetY] parameters.
/// The component is not affected by parent layout and can be displayed at fixed coordinates on any page.
///
class sAIKK_illumination extends StatefulWidget {
  final double radius;
  final double spacing;
  final Color dotColor;
  final Duration animationDuration;
  final Function(bool isComplete)? onAnimationComplete;
  final bool continuousMode;
  final bool isPreview; // Add preview mode flag
  final double offsetX; // X coordinate of component center point (pixels)
  final double offsetY; // Y coordinate of component center point (pixels)
  final Color? backgroundColor; // New background color parameter
  final double firstRingRadiusRatio; // First ring dot radius ratio
  final double secondRingRadiusRatio; // Second ring dot radius ratio
  final double thirdRingRadiusRatio; // Third ring dot radius ratio
  final int innerRingCount; // Number of inner dense rings
  final int outerRingCount; // Number of outer sparse rings
  final List<double> outerRingOverlapRatios; // Overlap ratio list for each outer ring
  final bool enablePointFiltering; // Whether to enable point filtering (only show specified points)

  const sAIKK_illumination({
    Key? key,
    required this.radius,
    required this.spacing,
    required this.dotColor,
    this.animationDuration = const Duration(milliseconds: 500),
    this.onAnimationComplete,
    this.continuousMode = true,
    this.isPreview = false, // Default to non-preview mode
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.backgroundColor, // Optional background color
    this.firstRingRadiusRatio = 1.2, // Default first ring dot radius ratio
    this.secondRingRadiusRatio =1.4, // Default second ring dot radius ratio
    this.thirdRingRadiusRatio = 1.5, // Default third ring dot radius ratio
    this.innerRingCount = 2, // Default 2 inner dense rings
    this.outerRingCount = 2, // Default 2 outer sparse rings
    this.outerRingOverlapRatios = const [0.5, 0.4], // Default overlap ratios: first ring 0.5, second ring 0.4
    this.enablePointFiltering = false, // Default enable point filtering
  }) : super(key: key);

  @override
  sAIKK_illuminationState createState() => sAIKK_illuminationState();
}

class sAIKK_illuminationState extends State<sAIKK_illumination> {
  late List<bool> dotStates;
  Timer? timer;
  int currentDot = 1;
  late List<Offset> allPoints;
  bool _isPaused = false;
  late List<int> animationSequence;

  late List<int> ringStartIndices;

  @override
  void initState() {
    super.initState();
    _initializePoints();
    _initializeDotStates();
    _initializeAnimationSequence();
    Future.delayed(const Duration(milliseconds: 35), () {
      _startAnimation();
    });
  }

  // Create animation sequence
  void _initializeAnimationSequence() {
    animationSequence = [];
    
    // Iterate through all generated points
    for (int i = 0; i < dotStates.length; i++) {
      // If filtering is enabled, apply hardcoded filtering logic
      if (widget.enablePointFiltering && i < 25) {
        // Only light up points 22, 18, 14, 10, 1
        int oneBasedIndex = i + 1;
        if (oneBasedIndex == 1 ||
          oneBasedIndex == 10 ||
            oneBasedIndex == 14 ||
            oneBasedIndex == 18 ||
            oneBasedIndex == 22) {
          animationSequence.add(i);
        }
      } else {
        // Filtering disabled or points after 25, add normally
        animationSequence.add(i);
      }
    }
  }

  void pauseAnimation() {
    if (!_isPaused && timer != null && timer!.isActive) {
      timer!.cancel();
      _isPaused = true;
    }
  }

  void resumeAnimation() {
    if (_isPaused) {
      _startAnimation();
      _isPaused = false;
    }
  }

  // Add method to set currently active dot, used for auto-capture feature
  void setActiveDot(int dotIndex) {
    if (timer != null && timer!.isActive) {
      timer!.cancel();
    }

    if (allPoints.isEmpty) {
      print('Warning: Point list is empty, cannot set active dot');
      return;
    }

    setState(() {
      dotStates = List.generate(dotStates.length, (i) => false);

      int validIndex = (dotIndex % animationSequence.length);
      if (validIndex < 0) validIndex = 0;

      currentDot = validIndex + 1;

      dotStates[animationSequence[validIndex]] = true;
      _isPaused = true;
    });
  }

  void _initializePoints() {
    allPoints = [];
    ringStartIndices = [];
    // Add center point
    ringStartIndices.add(allPoints.length);
    allPoints.add(Offset.zero);

    // ====== Inner dense rings (using dynamic ring count) ======
    double ringSpacing = widget.spacing / 2;
    for (int ring = 1; ring <= widget.innerRingCount; ring++) {
      ringStartIndices.add(allPoints.length);
      double r = ring * ringSpacing;
      int pointsOnRing = max(6, (2 * pi * r / ringSpacing).round());
      pointsOnRing = (pointsOnRing / 4).ceil() * 4;

      for (int i = 0; i < pointsOnRing; i++) {
        double angle = (i * 2 * pi) / pointsOnRing;
        double x = r * cos(angle);
        double y = r * sin(angle);
        allPoints.add(Offset(x, y));
      }
    }

    // ====== Outer sparse rings (using FP overlap ratio theory) ======
    for (int ring = 0; ring < widget.outerRingCount; ring++) {
      ringStartIndices.add(allPoints.length);

      double currentOverlapRatio = ring < widget.outerRingOverlapRatios.length
          ? widget.outerRingOverlapRatios[ring]
          : widget.outerRingOverlapRatios.last;

      // Calculate theta angle based on overlap ratio
      // overlap = (2*theta - sin(2*theta)) / pi
      double theta = _calculateThetaFromOverlap(currentOverlapRatio);

      double currentR = 2*widget.spacing * cos(theta);

      // Calculate physical distance of current ring from center point
      // First ring: R1 + widget.spacing
      // Second ring: widget.spacing + R1 + R2
      double ringRadius;
      if (ring == 0) {
        ringRadius = currentR + widget.spacing;
      } else if (ring == 1) {
        // Need to get R value of first ring
        double firstRingOverlapRatio = widget.outerRingOverlapRatios[0];
        double firstTheta = _calculateThetaFromOverlap(firstRingOverlapRatio);
        double firstR = 2*widget.spacing * cos(firstTheta);
        ringRadius = widget.spacing + firstR + currentR;
      } else {
        // For third ring and above, need to accumulate R values of all previous rings
        double totalR = widget.spacing;
        for (int prevRing = 0; prevRing <= ring; prevRing++) {
          double prevOverlapRatio = prevRing < widget.outerRingOverlapRatios.length
              ? widget.outerRingOverlapRatios[prevRing]
              : widget.outerRingOverlapRatios.last;
          double prevTheta = _calculateThetaFromOverlap(prevOverlapRatio);
          double prevR = 2*widget.spacing * cos(prevTheta);
          totalR += prevR;
        }
        ringRadius = totalR;
      }

      // Number of points = 2*pi*ring radius / currentR
      int ringPoints = (2 * pi * ringRadius / currentR).floor();

      // Ensure XY-axis symmetry: point count must be even
      // Even points ensure symmetry about both X and Y axes
      if (ringPoints % 2 != 0) ringPoints++;

      if (ringPoints < 6) ringPoints = 6;

      for (int i = 0; i < ringPoints; i++) {
        double angle = (i * 2 * pi) / ringPoints;
        double x = ringRadius * cos(angle);
        double y = ringRadius * sin(angle);
        allPoints.add(Offset(x, y));
      }
    }

    ringStartIndices.add(allPoints.length);
  }

  // Calculate theta from overlap ratio
  double _calculateThetaFromOverlap(double overlap) {
    // Use bisection method for numerical solution: overlap = (2*theta - sin(2*theta)) / pi
    double low = 0.0;
    double high = pi / 2; // Theoretical maximum value of theta
    double epsilon = 1e-6;

    while (high - low > epsilon) {
      double mid = (low + high) / 2;
      double calculatedOverlap = (2 * mid - sin(2 * mid)) / pi;

      if (calculatedOverlap < overlap) {
        low = mid;
      } else {
        high = mid;
      }
    }

    return (low + high) / 2;
  }

  void _initializeDotStates() {
    dotStates = List.generate(allPoints.length, (i) => false);
  }

  void _startAnimation() {
    if (allPoints.length <= 1) {
      print('Warning: Not enough points for animation');
      return;
    }

    if (timer != null && timer!.isActive) {
      timer!.cancel();
    }

    currentDot = 0;

    setState(() {
      dotStates = List.generate(dotStates.length, (i) => false);

      currentDot++;

      if (currentDot <= animationSequence.length) {
        dotStates[animationSequence[currentDot - 1]] = true;
      }
    });

    timer = Timer.periodic(widget.animationDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        dotStates = List.generate(dotStates.length, (i) => false);

        currentDot++;

        if (currentDot > animationSequence.length) {
          currentDot = 1;

          if (!widget.continuousMode) {
            timer.cancel();
            widget.onAnimationComplete?.call(true);
          } else {
            widget.onAnimationComplete?.call(false);
          }
        }

        dotStates[animationSequence[currentDot - 1]] = true;
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
    double maxDistance = 0;
    for (var point in allPoints) {
      double distance = sqrt(point.dx * point.dx + point.dy * point.dy);
      if (distance > maxDistance) {
        maxDistance = distance;
      }
    }

    final totalSize = maxDistance * 2 + widget.radius * 2;

    // Use the same absolute positioning logic as AIKK
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.loose,
      children: [
        // Place sAIKK view at specified position
        Positioned(
          left: widget.offsetX - totalSize / 2,
          top: widget.offsetY - totalSize / 2,
          child: Container(
            width: totalSize,
            height: totalSize,
            color: widget.backgroundColor ?? Colors.transparent,
            child: CustomPaint(
              painter: SAIKKDotsPainter(
                dotStates: dotStates,
                points: allPoints,
                dotRadius: widget.radius,
                dotColor: widget.dotColor,
                isPreview: widget.isPreview,
                firstRingRadiusRatio: widget.firstRingRadiusRatio,
                secondRingRadiusRatio: widget.secondRingRadiusRatio,
                thirdRingRadiusRatio: widget.thirdRingRadiusRatio,
                ringStartIndices: ringStartIndices,
                enablePointFiltering: widget.enablePointFiltering,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SAIKKDotsPainter extends CustomPainter {
  final List<bool> dotStates;
  final List<Offset> points;
  final double dotRadius;
  final Color dotColor;
  final bool isPreview;
  final double firstRingRadiusRatio;
  final double secondRingRadiusRatio;
  final double thirdRingRadiusRatio;
  final List<int> ringStartIndices;
  final bool enablePointFiltering;

  SAIKKDotsPainter({
    required this.dotStates,
    required this.points,
    required this.dotRadius,
    required this.dotColor,
    this.isPreview = false,
    this.firstRingRadiusRatio = 1.0,
    this.secondRingRadiusRatio = 1.0,
    this.thirdRingRadiusRatio = 1.0,
    required this.ringStartIndices,
    this.enablePointFiltering = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    canvas.translate(size.width / 2, size.height / 2);

    // Helper function
    double getPointRadius(int i) {
      double pointRadius = dotRadius;

      // Dynamically calculate point radius ratio
      // ringStartIndices structure: [center, inner1, inner2, ..., outer1, outer2, ..., end]
      int outerRingStartIndex = ringStartIndices.length - 3;

      // Ensure ringStartIndices has enough elements
      if (ringStartIndices.length > 3) {
        if (i == 0) {
          // Center point
          pointRadius = dotRadius;
        } else if (i < ringStartIndices[outerRingStartIndex]) {
          // Inner dense rings
          pointRadius = dotRadius;
        } else {
          // Outer sparse rings, apply different radius ratios based on ring number
          int outerRingIndex = 0;
          for (int j = outerRingStartIndex; j < ringStartIndices.length - 1; j++) {
            if (i >= ringStartIndices[j] && i < ringStartIndices[j + 1]) {
              outerRingIndex = j - outerRingStartIndex;
              break;
            }
          }

          // Apply radius ratio based on outer ring index
          switch (outerRingIndex) {
            case 0:
              pointRadius = dotRadius * firstRingRadiusRatio;
              break;
            case 1:
              pointRadius = dotRadius * secondRingRadiusRatio;
              break;
            case 2:
            default:
              pointRadius = dotRadius * thirdRingRadiusRatio;
              break;
          }
        }
      }
      return pointRadius;
    }

    // Helper function: determine if point should be displayed
    bool shouldShowPoint(int i) {
      if (!enablePointFiltering) {
        return true;
      }
      
      if (i < 25) {
        int oneBasedIndex = i + 1;
        return (oneBasedIndex == 1 ||
                oneBasedIndex == 10 || 
                oneBasedIndex == 14 || 
                oneBasedIndex == 18 || 
                oneBasedIndex == 22);
      }
      return true;
    }

    // Draw inactive dots
    for (int i = 0; i < points.length && i < dotStates.length; i++) {
      if (!shouldShowPoint(i)) continue;

      if (!dotStates[i]) {
        paint.color = isPreview ? Colors.grey[800]! : Colors.black;
        canvas.drawCircle(points[i], getPointRadius(i), paint);
      }
    }

    // Draw active dots
    for (int i = 0; i < points.length && i < dotStates.length; i++) {
      if (!shouldShowPoint(i)) continue;

      if (dotStates[i]) {
        paint.color = dotColor;
        canvas.drawCircle(points[i], getPointRadius(i), paint);
      }
    }

    // Draw ring outlines in preview mode
    if (isPreview) {
      final outlinePaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.grey[600]!
        ..strokeWidth = 0.5;

      Set<double> uniqueRadii = {};
      for (int i = 0; i < points.length; i++) {
        if (!shouldShowPoint(i)) continue;
        
        double radius =
            sqrt(points[i].dx * points[i].dx + points[i].dy * points[i].dy);
        double roundedRadius = (radius * 10).floor() / 10;
        uniqueRadii.add(roundedRadius);
      }

      for (double radius in uniqueRadii) {
        canvas.drawCircle(Offset.zero, radius, outlinePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
