import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../ui/screens/main_menu_screen.dart';
import '../ui/screens/splash_screen.dart';
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

  static Future<AppServices> _defaultBootstrap() => AppServices.bootstrap(
    versionLoader: () async {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    },
  );

  @override
  Widget build(BuildContext context) {
    final services = _services;
    return MaterialApp(
      title: AppConfig.title,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
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
              onReady: (s) => setState(() => _services = s),
            )
          : const MainMenuScreen(),
    );
  }
}
