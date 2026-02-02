import 'FocusPage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'PreviewParameterPage.dart';
import 'centerAlignPage.dart';
import '../PurePages/pureCenterAlignment.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MainPageState();
}

class _MainPageState extends State<MyHomePage> {
  final double circleRadius = 55.0;
  final List<Color> circleColors = [
    const Color.fromARGB(255, 255, 0, 0), // Red
    const Color.fromARGB(255, 0, 255, 0), // Green
    const Color.fromARGB(255, 0, 0, 255), // Blue
  ];

  final List<Color> rainbowColors = [
    const Color(0xFFFF3B30), // Red
    const Color(0xFFFF9500), // Orange
    const Color(0xFFFFCC00), // Yellow
    const Color(0xFF4CD964), // Green
    const Color(0xFF5AC8FA), // Cyan
    const Color(0xFF5856D6), // Indigo
    const Color(0xFF007AFF), // Blue
  ];

  int _selectedColorIndex = -1;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _navigateToPage(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => page,
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required VoidCallback onPressed,
    required IconData icon,
    Color? color,
    Widget? trailingWidget,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: SizedBox(
        width: 320,
        height: 65,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                color: const Color(0xFFE8E8E8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                alignment: Alignment.center,
                child: Row(
                  children: [
                    const SizedBox(width: 20),
                    Icon(icon, size: 30, color: Colors.black),
                    const SizedBox(width: 25),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    if (trailingWidget != null) trailingWidget,
                    if (trailingWidget == null) const SizedBox(width: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Rainbow gradient bar
  Widget _buildRainbowDivider({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: rainbowColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }

  Widget _buildCircleIndicator(Color color, int index) {
    bool isSelected = _selectedColorIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedColorIndex = isSelected ? -1 : index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        width: circleRadius + (isSelected ? 10 : 0),
        height: circleRadius + (isSelected ? 10 : 0),
        margin: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: isSelected ? 15 : 8,
              spreadRadius: isSelected ? 2 : 0,
            ),
          ],
        ),
        child: isSelected
            ? Center(
                child: Icon(
                  Icons.check,
                  color: color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                  size: 28,
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
          backgroundColor: Colors.white,
          centerTitle: true,
          title: Text(
            'ComOpt LAB',
            style: GoogleFonts.ebGaramond(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: Colors.black,
            ),
          )),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 80),
              Column(
                children: [
                  const Text(
                    'KK-SmartScope',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildRainbowDivider(width: 240, height: 5),
                ],
              ),

              Container(
                margin: const EdgeInsets.symmetric(vertical: 35),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    circleColors.length,
                    (index) =>
                        _buildCircleIndicator(circleColors[index], index),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        _buildButton(
                          text: 'Sample Focus',
                          icon: Icons.center_focus_strong,
                          onPressed: () {
                            _navigateToPage(FocusPage());
                          },
                        ),
                        Container(
                          height: 10,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              SizedBox(
                                width: 244,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      _navigateToPage(CenterAlignPage());
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Ink(
                                      height: 65,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8E8E8),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Container(
                                        alignment: Alignment.center,
                                        child: Row(
                                          children: [
                                            const SizedBox(width: 20),
                                            const Icon(Icons.camera_alt,
                                                size: 30, color: Colors.black),
                                            const SizedBox(width: 25),
                                            const Text(
                                              'Center Align',
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                height: 65,
                                width: 60,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8E8E8),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.adjust,
                                      color: Colors.black),
                                  onPressed: () {
                                    _navigateToPage(
                                        const PureCenterAlignment());
                                  },
                                  iconSize: 30,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 10,
                        ),
                        _buildButton(
                          text: 'Image Acquisition',
                          icon: Icons.auto_awesome,
                          onPressed: () {
                            _navigateToPage(PreviewParameterPage());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Text(
                '© ComOpt Laboratory 2025',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                height: 10,
              )
            ],
          ),
        ],
      ),
    );
  }
}
