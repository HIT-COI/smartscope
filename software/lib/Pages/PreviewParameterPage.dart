import 'package:flutter/material.dart';
import '../Widgets/FPM_illumination.dart';
import '../Widgets/AIKK_illumination.dart';
import '../Widgets/sAIKK_illumination.dart';
import 'package:flutter/services.dart';
import '../pages/FormalCapture.dart' show FormalCapture, IlluminationType;
import '../main.dart'; // Import main.dart to use PPI manager
import '../PurePages/PureIllumiantionPage.dart';

class PreviewParameterPage extends StatefulWidget {
  final String? imagePath;

  const PreviewParameterPage({
    super.key,
    this.imagePath,
  });

  @override
  PreviewParameterPageState createState() => PreviewParameterPageState();
}

class PreviewParameterPageState extends State<PreviewParameterPage>
    with SingleTickerProviderStateMixin {
  // Use late final to reduce unnecessary rebuilds
  late final ValueNotifier<int> _rowsNotifier = ValueNotifier(1);
  late final ValueNotifier<int> _columnsNotifier = ValueNotifier(1);
  late final ValueNotifier<int> _intervalNotifier = ValueNotifier(2000);
  late final ValueNotifier<double> _radiusNotifier = ValueNotifier(1.0); // Unit: millimeters
  late final ValueNotifier<double> _spacingNotifier =
      ValueNotifier(5.7); // Unit: millimeters

  // Offset values - modify default values here
  late final ValueNotifier<double> _offsetXNotifier =
      ValueNotifier(38.1+0); // Center point X coordinate (millimeters)
  late final ValueNotifier<double> _offsetYNotifier =
      ValueNotifier(65.4); // Center point Y coordinate (millimeters)

  // Ring count control variables
  late final ValueNotifier<int> _innerRingCountNotifier = ValueNotifier(2); // Inner dense ring count
  late final ValueNotifier<int> _outerRingCountNotifier = ValueNotifier(2); // Outer sparse ring count

  // FP overlap ratio control variables
  late final ValueNotifier<double> _firstRingOverlapNotifier = ValueNotifier(0.5); // First ring overlap ratio
  late final ValueNotifier<double> _secondRingOverlapNotifier = ValueNotifier(0.4); // Second ring overlap ratio

  late final ValueNotifier<Color> _dotColorNotifier =
      ValueNotifier(const Color.fromARGB(255, 0, 255, 0));
  late final ValueNotifier<String> _selectedModeNotifier = ValueNotifier('FPM');

  // Add a ValueNotifier to control whether to show center point
  late final ValueNotifier<bool> _showCenterPointNotifier =
      ValueNotifier(false);

  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;

  static const List<String> _modes = ['FPM', 'AIKK', 'sAIKK'];
  static const List<Color> _presetColors = [
    Color.fromARGB(255, 255, 0, 0), // Red
    Color.fromARGB(255, 0, 255, 0), // Green
    Color.fromARGB(255, 0, 0, 255), // Blue
    Color.fromARGB(255, 255, 255, 255), // White
  ];
  static const Map<String, String> _modeDescriptions = {
    'FPM': '',
    'AIKK': ' ',
    'sAIKK': ' '
  };

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeInOut));

    _animController.forward();
    _selectedModeNotifier.addListener(_onModeChanged);
  }

  void _onModeChanged() {
    _animController.reset();
    _animController.forward();
  }

  @override
  void dispose() {
    // Release resources
    _rowsNotifier.dispose();
    _columnsNotifier.dispose();
    _intervalNotifier.dispose();
    _radiusNotifier.dispose();
    _spacingNotifier.dispose();
    _offsetXNotifier.dispose();
    _offsetYNotifier.dispose();
    _dotColorNotifier.dispose();
    _selectedModeNotifier.dispose();
    _showCenterPointNotifier.dispose();
    _innerRingCountNotifier.dispose();
    _outerRingCountNotifier.dispose();
    _firstRingOverlapNotifier.dispose();
    _secondRingOverlapNotifier.dispose();
    _animController.dispose();
    super.dispose();
  }

  double _getDevicePPI(BuildContext context) {
    return MyApp.ppiManager.getDevicePPI(context);
  }

  double _mmToPixels(double mm, BuildContext context) {
    return MyApp.ppiManager.mmToPixels(mm, context);
  }

  PageRouteBuilder<void> _createAnimationRoute(Widget screen) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => screen,
      transitionDuration: const Duration(milliseconds: 400),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 0.2);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;
        final tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        final offsetAnimation = animation.drive(tween);

        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  void _startIllumination() {
    IlluminationType illuminationType;
    switch (_selectedModeNotifier.value) {
      case 'AIKK':
        illuminationType = IlluminationType.AIKK;
        break;
      case 'sAIKK':
        illuminationType = IlluminationType.sAIKK;
        break;
      case 'FPM':
      default:
        illuminationType = IlluminationType.FPM;
        break;
    }

    final double ppi = _getDevicePPI(context);

    final double spacingInPixels = _mmToPixels(_spacingNotifier.value, context);
    final double radiusInPixels = _mmToPixels(_radiusNotifier.value, context);

    final double offsetXInMM = _offsetXNotifier.value;
    final double offsetYInMM = _offsetYNotifier.value;

    Map<String, dynamic> illuminationParams = {
      'radius': radiusInPixels,
      'spacing': spacingInPixels,
      'dotColor': _dotColorNotifier.value,
      'rows': _rowsNotifier.value,
      'columns': _columnsNotifier.value,
      'interval': _intervalNotifier.value,
      'offsetX_mm': offsetXInMM,
      'offsetY_mm': offsetYInMM,
      'ppi': ppi,
      'showCenterPoint': _showCenterPointNotifier.value,
      'innerRingCount': _innerRingCountNotifier.value,
      'outerRingCount': _outerRingCountNotifier.value,
      'overlapRatios': [_firstRingOverlapNotifier.value, _secondRingOverlapNotifier.value],
    };

    Navigator.push(
      context,
      _createAnimationRoute(
        FormalCapture(
          illuminationType: illuminationType,
          illuminationParams: illuminationParams,
          imagePath: widget.imagePath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  _buildModeSelector(),
                  _buildColorSelector(),
                  _buildParametersSection(),
                  _buildStartButton(),
                  _buildPureIlluminationButton(),
                ],
              ),
            ),
          ),
          _buildLiveIllumination(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      title: Text(
        'Lighting Control',
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.auto_awesome,
          title: 'Mode',
        ),
        ValueListenableBuilder(
          valueListenable: _selectedModeNotifier,
          builder: (context, selectedMode, _) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _modes.map((mode) {
                  final bool isSelected = selectedMode == mode;
                  return Expanded(
                    child: _ModeButton(
                      mode: mode,
                      isSelected: isSelected,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _selectedModeNotifier.value = mode;
                      },
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
        ValueListenableBuilder(
          valueListenable: _selectedModeNotifier,
          builder: (context, selectedMode, _) {
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: 0.8,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  _modeDescriptions[selectedMode] ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildColorSelector() {
    return Column(
      children: [
        const _SectionHeader(
          icon: Icons.color_lens_outlined,
          title: 'Color',
        ),
        SizedBox(
          height: 60,
          child: _ColorSelectorList(
            colors: _presetColors,
            selectedColorNotifier: _dotColorNotifier,
          ),
        ),
      ],
    );
  }

  Widget _buildParametersSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.tune,
            title: 'Animation Parameters',
          ),
          const SizedBox(height: 12),

          // Dynamically display row and column parameters for FPM mode
          ValueListenableBuilder(
            valueListenable: _selectedModeNotifier,
            builder: (context, mode, _) {
              if (mode == 'FPM') {
                return _buildParameterRow([
                  Expanded(
                    child: _CompactParameterInput(
                      label: 'Rows',
                      notifier: _rowsNotifier,
                      keyboardType: TextInputType.number,
                      valueToString: (value) => value.toString(),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          final intValue = int.tryParse(value);
                          if (intValue != null && intValue > 0) {
                            _rowsNotifier.value = intValue;
                          }
                        }
                      },
                      icon: Icons.grid_on,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CompactParameterInput(
                      label: 'Cols',
                      notifier: _columnsNotifier,
                      keyboardType: TextInputType.number,
                      valueToString: (value) => value.toString(),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          final intValue = int.tryParse(value);
                          if (intValue != null && intValue > 0) {
                            _columnsNotifier.value = intValue;
                          }
                        }
                      },
                      icon: Icons.view_column,
                    ),
                  ),
                ]);
              }
              // Dynamically display ring count parameters for sAIKK mode
              else if (mode == 'sAIKK') {
                return Column(
                  children: [
                    _buildParameterRow([
                      Expanded(
                        child: _CompactParameterInput(
                          label: 'Inner',
                          notifier: _innerRingCountNotifier,
                          keyboardType: TextInputType.number,
                          valueToString: (value) => value.toString(),
                          onChanged: (value) {
                            if (value.isNotEmpty) {
                              final intValue = int.tryParse(value);
                              if (intValue != null && intValue >= 0) {
                                _innerRingCountNotifier.value = intValue;
                              }
                            }
                          },
                          icon: Icons.circle_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CompactParameterInput(
                          label: 'Outer',
                          notifier: _outerRingCountNotifier,
                          keyboardType: TextInputType.number,
                          valueToString: (value) => value.toString(),
                          onChanged: (value) {
                            if (value.isNotEmpty) {
                              final intValue = int.tryParse(value);
                              if (intValue != null && intValue >= 0) {
                                _outerRingCountNotifier.value = intValue;
                              }
                            }
                          },
                          icon: Icons.panorama_fish_eye,
                        ),
                      ),
                    ]),
                    _buildParameterRow([
                      Expanded(
                        child: _CompactParameterInput(
                          label: 'Ring1 FP',
                          notifier: _firstRingOverlapNotifier,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          valueToString: (value) => value.toStringAsFixed(2),
                          onChanged: (value) {
                            if (value.isNotEmpty) {
                              final doubleValue = double.tryParse(value);
                              if (doubleValue != null && doubleValue >= 0 && doubleValue <= 1) {
                                _firstRingOverlapNotifier.value = doubleValue;
                              }
                            }
                          },
                          icon: Icons.blur_circular,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CompactParameterInput(
                          label: 'Ring2 FP',
                          notifier: _secondRingOverlapNotifier,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          valueToString: (value) => value.toStringAsFixed(2),
                          onChanged: (value) {
                            if (value.isNotEmpty) {
                              final doubleValue = double.tryParse(value);
                              if (doubleValue != null && doubleValue >= 0 && doubleValue <= 1) {
                                _secondRingOverlapNotifier.value = doubleValue;
                              }
                            }
                          },
                          icon: Icons.blur_on,
                        ),
                      ),
                    ]),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),

          _buildParameterRow([
            Expanded(
              child: _CompactParameterInput(
                label: 'Interval',
                notifier: _intervalNotifier,
                keyboardType: TextInputType.number,
                valueToString: (value) => value.toString(),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    final intValue = int.tryParse(value);
                    if (intValue != null && intValue > 0) {
                      _intervalNotifier.value = intValue;
                    }
                  }
                },
                suffix: 'ms',
                icon: Icons.timer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactParameterInput(
                label: 'Radius',
                notifier: _radiusNotifier,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                valueToString: (value) => value.toString(),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    final doubleValue = double.tryParse(value);
                    if (doubleValue != null && doubleValue > 0) {
                      _radiusNotifier.value = doubleValue;
                    }
                  }
                },
                suffix: 'mm',
                icon: Icons.radio_button_checked,
              ),
            ),
          ]),

          _buildParameterRow([
            Expanded(
              child: _CompactParameterInput(
                label: 'Spacing',
                notifier: _spacingNotifier,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                valueToString: (value) => value.toString(),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    final doubleValue = double.tryParse(value);
                    if (doubleValue != null && doubleValue > 0) {
                      _spacingNotifier.value = doubleValue;
                    }
                  }
                },
                suffix: 'mm',
                icon: Icons.space_bar,
              ),
            ),
          ]),

          _buildParameterRow([
            Expanded(
              child: _CompactParameterInput(
                label: 'Center X',
                notifier: _offsetXNotifier,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                valueToString: (value) => value.toString(),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    final doubleValue = double.tryParse(value);
                    if (doubleValue != null) {
                      _offsetXNotifier.value = doubleValue;
                    }
                  }
                },
                suffix: 'mm',
                icon: Icons.swap_horiz,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactParameterInput(
                label: 'Center Y',
                notifier: _offsetYNotifier,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                valueToString: (value) => value.toString(),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    final doubleValue = double.tryParse(value);
                    if (doubleValue != null) {
                      _offsetYNotifier.value = doubleValue;
                    }
                  }
                },
                suffix: 'mm',
                icon: Icons.swap_vert,
              ),
            ),
          ]),

          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Row(
              children: [
                Icon(Icons.center_focus_strong, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Center Point Only',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                ValueListenableBuilder(
                  valueListenable: _showCenterPointNotifier,
                  builder: (context, showCenter, _) {
                    return Switch(
                      value: showCenter,
                      onChanged: (value) {
                        HapticFeedback.selectionClick();
                        _showCenterPointNotifier.value = value;
                      },
                      activeColor: const Color(0xFF007AFF),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterRow(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildStartButton() {
    return ElevatedButton(
      onPressed: _startIllumination,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF007AFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        elevation: 5,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.not_started, size: 24, color: Colors.white),
          SizedBox(width: 12),
          Text(
            'Start Animation',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white,
              letterSpacing: 0.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPureIlluminationButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: ElevatedButton(
        onPressed: () {
          // Get current illumination type
          IlluminationType illuminationType;
          switch (_selectedModeNotifier.value) {
            case 'AIKK':
              illuminationType = IlluminationType.AIKK;
              break;
            case 'sAIKK':
              illuminationType = IlluminationType.sAIKK;
              break;
            case 'FPM':
            default:
              illuminationType = IlluminationType.FPM;
              break;
          }

          final double ppi = _getDevicePPI(context);
          final double spacingInPixels =
              _mmToPixels(_spacingNotifier.value, context);
          final double radiusInPixels =
              _mmToPixels(_radiusNotifier.value, context);
          final double offsetXInMM = _offsetXNotifier.value;
          final double offsetYInMM = _offsetYNotifier.value;

          Map<String, dynamic> illuminationParams = {
            'radius': radiusInPixels,
            'spacing': spacingInPixels,
            'dotColor': _dotColorNotifier.value,
            'rows': _rowsNotifier.value,
            'columns': _columnsNotifier.value,
            'interval': _intervalNotifier.value,
            'offsetX_mm': offsetXInMM,
            'offsetY_mm': offsetYInMM,
            'ppi': ppi,
            'showCenterPoint': _showCenterPointNotifier.value,
            'innerRingCount': _innerRingCountNotifier.value, // Inner ring count
            'outerRingCount': _outerRingCountNotifier.value, // Outer ring count
            'overlapRatios': [_firstRingOverlapNotifier.value, _secondRingOverlapNotifier.value], // FP overlap ratios
          };

          Navigator.push(
            context,
            _createAnimationRoute(
              PureIllumiantionPage(
                illuminationType: illuminationType,
                illuminationParams: illuminationParams,
              ),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00C853),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 5,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lightbulb_outline, size: 24, color: Colors.white),
            SizedBox(width: 12),
            Text(
              'Pure Illumination',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                letterSpacing: 0.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
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
        child: ValueListenableBuilder(
          valueListenable: _selectedModeNotifier,
          builder: (context, mode, _) {
            return ValueListenableBuilder(
              valueListenable: _dotColorNotifier,
              builder: (context, color, _) {
                return ValueListenableBuilder(
                  valueListenable: _intervalNotifier,
                  builder: (context, interval, _) {
                    final animationDuration = Duration(milliseconds: interval);

                    return ValueListenableBuilder(
                      valueListenable: _radiusNotifier,
                      builder: (context, radiusMM, _) {
                        //
                        final double radiusPixels =
                            _mmToPixels(radiusMM, context);
                        return ValueListenableBuilder(
                          valueListenable: _spacingNotifier,
                          builder: (context, spacingMM, _) {
                            //
                            final double spacingPixels =
                                _mmToPixels(spacingMM, context);

                            return ValueListenableBuilder(
                              valueListenable: _offsetXNotifier,
                              builder: (context, offsetX, _) {
                                return ValueListenableBuilder(
                                  valueListenable: _offsetYNotifier,
                                  builder: (context, offsetY, _) {
                                        //
                                        final double offsetXPixels =
                                            _mmToPixels(offsetX, context);
                                        final double offsetYPixels =
                                            _mmToPixels(offsetY, context);

                                        //
                                        final finalX = offsetXPixels;
                                        final finalY = offsetYPixels;

                                    return ValueListenableBuilder(
                                      valueListenable:
                                          _showCenterPointNotifier,
                                      builder:
                                          (context, showCenterPoint, _) {
                                        Widget illumination;
                                        switch (mode) {
                                          case 'FPM':
                                            illumination = FPM_illumination(
                                              rows: _rowsNotifier.value,
                                              columns:
                                                  _columnsNotifier.value,
                                              radius: radiusPixels,
                                              spacing: spacingPixels,
                                              dotColor: color,
                                              animationDuration:
                                                  animationDuration,
                                              continuousMode: true,
                                              isPreview: true,
                                              offsetX: finalX,
                                              offsetY: finalY,
                                              backgroundColor:
                                                  Colors.transparent,
                                            );
                                            break;
                                          case 'AIKK':
                                            illumination =
                                                AIKK_illumination(
                                              radius: radiusPixels,
                                              spacing: spacingPixels,
                                              dotColor: color,
                                              animationDuration:
                                                  animationDuration,
                                              continuousMode: true,
                                              isPreview: true,
                                              offsetX: finalX,
                                              offsetY: finalY,
                                              backgroundColor:
                                                  Colors.transparent,
                                              showCenterPoint:
                                                  showCenterPoint, //
                                            );
                                            break;
                                          case 'sAIKK':
                                            illumination = ValueListenableBuilder(
                                              valueListenable: _innerRingCountNotifier,
                                              builder: (context, innerRingCount, _) {
                                                return ValueListenableBuilder(
                                                  valueListenable: _outerRingCountNotifier,
                                                  builder: (context, outerRingCount, _) {
                                                    return ValueListenableBuilder(
                                                      valueListenable: _firstRingOverlapNotifier,
                                                      builder: (context, firstOverlap, _) {
                                                        return ValueListenableBuilder(
                                                          valueListenable: _secondRingOverlapNotifier,
                                                          builder: (context, secondOverlap, _) {
                                                            return sAIKK_illumination(
                                                              radius: radiusPixels,
                                                              spacing: spacingPixels,
                                                              dotColor: color,
                                                              animationDuration: animationDuration,
                                                              continuousMode: true,
                                                              isPreview: true,
                                                              offsetX: finalX,
                                                              offsetY: finalY,
                                                              backgroundColor: Colors.transparent,
                                                              innerRingCount: innerRingCount, //
                                                              outerRingCount: outerRingCount, //
                                                              outerRingOverlapRatios: [firstOverlap, secondOverlap], //
                                                            );
                                                          },
                                                        );
                                                      },
                                                    );
                                                  },
                                                );
                                              },
                                            );
                                            break;
                                          default:
                                            illumination = Container();
                                        }

                                        return illumination;
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String mode;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 4), //
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF007AFF) : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF007AFF),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown, //
          child: Text(
            mode,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[800],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis, //
          ),
        ),
      ),
    );
  }
}

class _CompactParameterInput extends StatefulWidget {
  final String label;
  final ValueNotifier<dynamic> notifier;
  final TextInputType keyboardType;
  final String Function(dynamic) valueToString;
  final Function(String) onChanged;
  final String? suffix;
  final IconData icon;

  const _CompactParameterInput({
    required this.label,
    required this.notifier,
    required this.keyboardType,
    required this.valueToString,
    required this.onChanged,
    this.suffix,
    required this.icon,
  });

  @override
  State<_CompactParameterInput> createState() => _CompactParameterInputState();
}

class _CompactParameterInputState extends State<_CompactParameterInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.valueToString(widget.notifier.value));
    _focusNode = FocusNode();
    
    //
    _focusNode.addListener(_onFocusChange);

    widget.notifier.addListener(_onNotifierChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _isEditing = true;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _isEditing = false;
      _controller.text = widget.valueToString(widget.notifier.value);
    }
  }

  void _onNotifierChange() {
    if (!_isEditing) {
      setState(() {
        _controller.text = widget.valueToString(widget.notifier.value);
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    widget.notifier.removeListener(_onNotifierChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDDDDD)),
      ),
      child: Row(
        children: [
          //
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 16, color: Colors.grey[700]),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          //
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: widget.suffix != null ? 30 : 40,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    keyboardType: widget.keyboardType,
                    onChanged: widget.onChanged,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black, fontSize: 14),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
                if (widget.suffix != null)
                  Flexible(
                    child: Text(
                      widget.suffix!,
                      style: TextStyle(color: Colors.grey[700], fontSize: 11),
                      overflow: TextOverflow.ellipsis,
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

class _ColorSelectorList extends StatelessWidget {
  final List<Color> colors;
  final ValueNotifier<Color> selectedColorNotifier;

  const _ColorSelectorList({
    required this.colors,
    required this.selectedColorNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: colors.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        return ValueListenableBuilder(
          valueListenable: selectedColorNotifier,
          builder: (context, currentColor, _) {
            final bool isSelected = currentColor == colors[index];
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                selectedColorNotifier.value = colors[index];
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: colors[index],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors[index],
                      blurRadius: isSelected ? 12 : 8,
                      spreadRadius: isSelected ? 2 : 1,
                    ),
                  ],
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 24)
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}
