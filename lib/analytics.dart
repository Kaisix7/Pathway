import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Analytics {
  static const String _posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');
  static const String _posthogHost = String.fromEnvironment('POSTHOG_HOST', defaultValue: 'https://app.posthog.com');
  static const String _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get _baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }

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

  // ── Generic tracker (existing) ──────────────────────────────────────

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

  // ── PostHog Identify ─────────────────────────────────────────────────

  static Future<void> identify(String email, {Map<String, dynamic>? properties}) async {
    if (_posthogApiKey.isEmpty || email.isEmpty) return;

    try {
      await http.post(
        Uri.parse('$_posthogHost/capture/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': _posthogApiKey,
          'event': '\$identify',
          'distinct_id': email,
          '\$set': properties ?? {},
        }),
      );
    } catch (e) {
      print('analytics identify error: $e');
    }
  }

  // ── Typed Event Methods (PostHog + GA4 mapping) ─────────────────────

  /// PostHog: user_signed_up  |  GA4: sign_up
  static Future<void> trackSignUp(String email, {String? name, String? nationality}) async {
    await identify(email, properties: {
      'name': name ?? '',
      'nationality': nationality ?? '',
    });
    await track(
      'user_signed_up',
      userEmail: email,
      properties: {
        'ga4_event': 'sign_up',
        'name': name ?? '',
        'nationality': nationality ?? '',
      },
    );
  }

  /// PostHog: user_logged_in
  static Future<void> trackLogin(String email, {String source = 'email'}) async {
    await identify(email);
    await track(
      'user_logged_in',
      userEmail: email,
      properties: {
        'source': source,
      },
    );
  }

  /// PostHog: checkout_started  |  GA4: begin_checkout
  static Future<void> trackCheckoutStarted(String email, {double? amount, String? plan}) async {
    await track(
      'checkout_started',
      userEmail: email,
      properties: {
        'ga4_event': 'begin_checkout',
        'amount': amount ?? 0,
        'plan': plan ?? 'premium',
      },
    );
  }

  /// PostHog: payment_completed  |  GA4: purchase
  static Future<void> trackPaymentCompleted(String email, {double? amount, String? plan}) async {
    await track(
      'payment_completed',
      userEmail: email,
      properties: {
        'ga4_event': 'purchase',
        'amount': amount ?? 0,
        'plan': plan ?? 'premium',
        'currency': 'USD',
      },
    );
  }

  /// PostHog: payment_failed
  static Future<void> trackPaymentFailed(String email, {String? error}) async {
    await track(
      'payment_failed',
      userEmail: email,
      properties: {
        'error': error ?? 'unknown',
      },
    );
  }

  // ── Error capture ───────────────────────────────────────────────────

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
