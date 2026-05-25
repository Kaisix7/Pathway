import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Analytics {
  static const String _posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');
  static const String _posthogHost = String.fromEnvironment('POSTHOG_HOST', defaultValue: 'https://app.posthog.com');

  static String get _baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000/api';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000/api';
      default:
        return 'http://127.0.0.1:8000/api';
    }
  }

  static Future<void> track(
    String eventName, {
    String userEmail = '',
    Map<String, dynamic>? properties,
  }) async {
    print('EVENT: $eventName');

    try {
      await http.post(
        Uri.parse('$_baseUrl/events/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event_name': eventName,
          'user_email': userEmail,
          'properties': properties ?? {},
        }),
      );

      if (_posthogApiKey.isNotEmpty) {
        await http.post(
          Uri.parse('$_posthogHost/capture/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'api_key': _posthogApiKey,
            'event': eventName,
            'distinct_id': userEmail.isEmpty ? 'anonymous' : userEmail,
            'properties': properties ?? {},
          }),
        );
      }
    } catch (e) {
      print('analytics track error: $e');
    }
  }

  static Future<void> captureError(Object error, StackTrace stackTrace) async {
    await track(
      'app_error',
      properties: {
        'error': error.toString(),
        'stack': stackTrace.toString(),
      },
    );
  }
}
