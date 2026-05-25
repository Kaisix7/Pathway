import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:ui';
import 'l10n/app_localizations.dart';


import 'analytics.dart';
import 'firebase_options.dart';
import 'state.dart';
import 'views.dart';
import 'services_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Analytics.captureError(details.exception, details.stack ?? StackTrace.current);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    Analytics.captureError(error, stack);
    return true;
  };

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const PathwayApp());
}

class PathwayApp extends StatefulWidget {
  const PathwayApp({super.key});

  @override
  State<PathwayApp> createState() => _PathwayAppState();
}

class _PathwayAppState extends State<PathwayApp> {
  final app = AppState();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'PATHWAY',

          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: app.locale,

          home: app.authed ? Shell(app: app) : AuthView(app: app),
        );
      },
    );
  }
}
