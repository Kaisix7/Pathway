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
              primary: Color(0xFFE8D44D),      // Bold yellow accent
              secondary: Color(0xFFE8D44D),
              surface: Color(0xFF111111),       // Near-black surface
              onPrimary: Color(0xFF0A0A0A),     // Black text on yellow
              onSecondary: Color(0xFF0A0A0A),
              onSurface: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFF0A0A0A),
            textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
              headlineLarge: GoogleFonts.inter(
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.5,
                ),
              ),
              headlineMedium: GoogleFonts.inter(
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.0,
                ),
              ),
              titleLarge: GoogleFonts.inter(
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0A0A0A),
              elevation: 0,
              centerTitle: false,
              surfaceTintColor: Colors.transparent,
              titleTextStyle: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: const Color(0xFF111111),
              indicatorColor: const Color(0xFFE8D44D),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const IconThemeData(color: Color(0xFF0A0A0A), size: 22);
                }
                return const IconThemeData(color: Colors.white38, size: 22);
              }),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    color: Color(0xFFE8D44D),
                    letterSpacing: 0.8,
                  );
                }
                return const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  color: Colors.white38,
                  letterSpacing: 0.8,
                );
              }),
            ),
            cardTheme: CardThemeData(
              color: const Color(0xFF141414),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF242424), width: 1),
              ),
              elevation: 0,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE8D44D), width: 1.5),
              ),
              labelStyle: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w600),
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIconColor: Colors.white38,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8D44D),
                foregroundColor: const Color(0xFF0A0A0A),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            dividerTheme: const DividerThemeData(color: Color(0xFF1E1E1E), thickness: 1),
          ),
          home: app.authed ? Shell(app: app) : AuthView(app: app),
        );
      },
    );
  }
}
