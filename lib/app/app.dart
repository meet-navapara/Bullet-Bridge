import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../ui/screens/main_menu_screen.dart';
import '../ui/screens/splash_screen.dart';
import '../ui/screens/welcome_screen.dart';
import '../ui/theme/palette.dart';
import 'app_services.dart';

class OrbitBlastApp extends StatefulWidget {
  const OrbitBlastApp({super.key, this.bootstrap});

  /// Overridable for tests.
  final Future<AppServices> Function()? bootstrap;

  @override
  State<OrbitBlastApp> createState() => _OrbitBlastAppState();
}

class _OrbitBlastAppState extends State<OrbitBlastApp> {
  AppServices? _services;
  late final _ScreenTracker _screens = _ScreenTracker(() => _services);

  static Future<AppServices> _defaultBootstrap() => AppServices.bootstrap(
    versionLoader: () async {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    },
  );

  void _showHome(AppServices services) {
    services.analytics.screen(
      services.needsWelcome ? _ScreenTracker.welcome : _ScreenTracker.menu,
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    return MaterialApp(
      title: AppConfig.title,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorObservers: [_screens],
      builder: (context, child) {
        // Keep text readable but stop huge system font scales from breaking
        // fixed game layouts.
        final media = MediaQuery.of(context);
        final scaled = media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.25),
        );
        final content = MediaQuery(data: scaled, child: child!);
        return services == null
            ? content
            : AppScope(services: services, child: content);
      },
      home: services == null
          ? SplashScreen(
              bootstrap: widget.bootstrap ?? _defaultBootstrap,
              onReady: (s) {
                setState(() => _services = s);
                _showHome(s);
              },
            )
          : services.needsWelcome
          ? WelcomeScreen(
              onDone: () {
                setState(() {});
                _showHome(services);
              },
            )
          : const MainMenuScreen(),
    );
  }
}

/// Reports each screen the player opens or returns to. Screens pushed with
/// [gameRoute] are named after their widget; the home route after what it
/// currently shows.
class _ScreenTracker extends NavigatorObserver {
  _ScreenTracker(this._services);

  static const welcome = 'WelcomeScreen';
  static const menu = 'MainMenuScreen';

  final AppServices? Function() _services;

  void _report(Route<dynamic>? route) {
    final services = _services();
    final name = route?.settings.name;
    if (services == null || name == null) return;
    services.analytics.screen(
      route!.isFirst ? (services.needsWelcome ? welcome : menu) : name,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _report(newRoute);
}
