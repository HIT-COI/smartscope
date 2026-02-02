import 'package:flutter/material.dart';
import 'Pages/homePage.dart';
import 'package:flutter/services.dart';
import 'Pages/FocusPage.dart';
import 'PurePages/pureCenterAlignment.dart';

class DevicePPIManager {
  static final DevicePPIManager _instance = DevicePPIManager._internal();
  factory DevicePPIManager() => _instance;
  DevicePPIManager._internal();
  
  static const double physicalPPI = 441.0;
  // mate 70     441 ppi
  // find x9 pro 450 ppi
  // vivo X100 Ultra 518 ppi

  double getDevicePPI(BuildContext context) {
    return physicalPPI / MediaQuery.of(context).devicePixelRatio;
  }

  // mm to pixels
  double mmToPixels(double mm, BuildContext context) {
    return mm * (getDevicePPI(context) / 25.4);
  }

  // Conversion method without context dependency (requires direct ppi value)
  double mmToPixelsWithPPI(double mm, double ppi) {
    // 1 inch = 25.4 millimeters
    return mm * (ppi / 25.4);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // immersiveSticky mode
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  // Expose device PPI manager instance
  static final ppiManager = DevicePPIManager();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setSystemUIMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setSystemUIMode();
    }
  }

  void _setSystemUIMode() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData().copyWith(
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: Color.fromARGB(255, 111, 111, 111),
        ),
        scaffoldBackgroundColor: const Color.fromARGB(255, 0, 0, 0),
        // Use simpler page transition animation
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => MyHomePage(),
        '/focus': (context) => const FocusPage(),
        '/pure_center': (context) => const PureCenterAlignment(),
      },
    );
  }
}
