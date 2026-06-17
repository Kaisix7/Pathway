import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
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
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6366F1), // Indigo
              secondary: Color(0xFF00BFA6), // Teal
              surface: Color(0xFF1E293B), // Slate 800
              onPrimary: Colors.white,
              onSecondary: Colors.black,
            ),
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
              headlineMedium: GoogleFonts.outfit(
                textStyle: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
              ),
              titleLarge: GoogleFonts.outfit(
                textStyle: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0F172A),
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            cardTheme: CardTheme(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 4,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              ),
              labelStyle: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600),
            ),
          ),
          home: app.authed ? Shell(app: app) : AuthView(app: app),
        );
      },
    );
  }
}
