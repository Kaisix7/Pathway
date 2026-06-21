import 'dart:convert';
import 'dart:js' as js;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Analytics {
  static const String _posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');
  static const String _posthogHost = String.fromEnvironment('POSTHOG_HOST', defaultValue: 'https://app.posthog.com');
  static const String _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String userCompany = '';
  static String utmSource = '';
  static String utmMedium = '';
  static String utmCampaign = '';

  static String get _baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:8000/api';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000/api';
      default:
        return 'http://localhost:8000/api';
    }
  }

  // ── Generic tracker ──────────────────────────────────────────────────

  static Future<void> track(
    String eventName, {
    String userEmail = '',
    Map<String, dynamic>? properties,
  }) async {
    debugPrint('EVENT: $eventName');

    final Map<String, dynamic> eventProperties = Map<String, dynamic>.from(properties ?? {});
    if (userCompany.isNotEmpty) {
      eventProperties[r'$groups'] = {'company': userCompany};
    }
    if (utmSource.isNotEmpty) {
      eventProperties[r'$utm_source'] = utmSource;
      eventProperties['utm_source'] = utmSource;
    }
    if (utmMedium.isNotEmpty) {
      eventProperties[r'$utm_medium'] = utmMedium;
      eventProperties['utm_medium'] = utmMedium;
    }
    if (utmCampaign.isNotEmpty) {
      eventProperties[r'$utm_campaign'] = utmCampaign;
      eventProperties['utm_campaign'] = utmCampaign;
    }

    try {
      await http.post(
        Uri.parse('$_baseUrl/events/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event_name': eventName,
          'user_email': userEmail,
          'properties': eventProperties,
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
            'properties': eventProperties,
          }),
        );
      }

      // GA4 Web Integration via JS Interop
      if (kIsWeb) {
        try {
          final ga4Event = eventProperties['ga4_event'] as String?;
          if (ga4Event != null) {
            final cleanProps = Map<String, dynamic>.from(eventProperties)..remove('ga4_event');
            js.context.callMethod('trackGA4Event', [ga4Event, js.JsObject.jsify(cleanProps)]);
          }
        } catch (e) {
          debugPrint('GA4 track error: $e');
        }
      }
    } catch (e) {
      debugPrint('analytics track error: $e');
    }
  }

  // ── PostHog Identify ─────────────────────────────────────────────────

  static Future<void> identify(String email, {Map<String, dynamic>? properties}) async {
    if (_posthogApiKey.isEmpty || email.isEmpty) return;

    final Map<String, dynamic> setProps = Map<String, dynamic>.from(properties ?? {});
    if (userCompany.isNotEmpty) {
      setProps['company'] = userCompany;
    }
    if (utmSource.isNotEmpty) {
      setProps['utm_source'] = utmSource;
      setProps[r'$utm_source'] = utmSource;
    }
    if (utmMedium.isNotEmpty) {
      setProps['utm_medium'] = utmMedium;
      setProps[r'$utm_medium'] = utmMedium;
    }
    if (utmCampaign.isNotEmpty) {
      setProps['utm_campaign'] = utmCampaign;
      setProps[r'$utm_campaign'] = utmCampaign;
    }

    try {
      await http.post(
        Uri.parse('$_posthogHost/capture/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': _posthogApiKey,
          'event': r'$identify',
          'distinct_id': email,
          r'$set': setProps,
        }),
      );

      if (userCompany.isNotEmpty) {
        await groupIdentify(email, userCompany);
      }
    } catch (e) {
      debugPrint('analytics identify error: $e');
    }
  }

  static Future<void> groupIdentify(String email, String companyName) async {
    if (_posthogApiKey.isEmpty || email.isEmpty || companyName.isEmpty) return;
    try {
      await http.post(
        Uri.parse('$_posthogHost/capture/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': _posthogApiKey,
          'event': r'$groupidentify',
          'distinct_id': email,
          'properties': {
            r'$group_type': 'company',
            r'$group_key': companyName,
            r'$group_set': {
              'name': companyName,
            },
          },
        }),
      );
    } catch (e) {
      debugPrint('analytics groupIdentify error: $e');
    }
  }

  // ── Typed Event Methods (PostHog + GA4 mapping) ─────────────────────

  /// PostHog: "user signed up"  |  GA4: sign_up
  static Future<void> trackSignUp(String email, {String? name, String? nationality}) async {
    await identify(email, properties: {
      'name': name ?? '',
      'nationality': nationality ?? '',
    });
    await track(
      'user signed up',
      userEmail: email,
      properties: {
        'ga4_event': 'sign_up',
        'name': name ?? '',
        'nationality': nationality ?? '',
      },
    );
  }

  /// PostHog: "user logged in"
  static Future<void> trackLogin(String email, {String source = 'email'}) async {
    await identify(email);
    await track(
      'user logged in',
      userEmail: email,
      properties: {
        'source': source,
      },
    );
  }

  /// PostHog: "checkout started"  |  GA4: begin_checkout
  static Future<void> trackCheckoutStarted(String email, {double? amount, String? plan}) async {
    await track(
      'checkout started',
      userEmail: email,
      properties: {
        'ga4_event': 'begin_checkout',
        'amount': amount ?? 0,
        'plan': plan ?? 'premium',
      },
    );
  }

  /// PostHog: "payment completed"  |  GA4: purchase
  static Future<void> trackPaymentCompleted(String email, {double? amount, String? plan}) async {
    await track(
      'payment completed',
      userEmail: email,
      properties: {
        'ga4_event': 'purchase',
        'amount': amount ?? 0,
        'plan': plan ?? 'premium',
        'currency': 'USD',
        'value': amount ?? 0,
      },
    );
  }

  /// PostHog: "payment failed"
  static Future<void> trackPaymentFailed(String email, {String? error}) async {
    await track(
      'payment failed',
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

  // ── Feature Flags ──────────────────────────────────────────────────
  
  static bool isFeatureEnabled(String flagName) {
    if (!kIsWeb) return false;
    try {
      final res = js.context.callMethod('isPostHogFeatureEnabled', [flagName]);
      return res == true;
    } catch (e) {
      debugPrint('Error checking feature flag: $e');
      return false;
    }
  }

  // ── UTM parameters retrieval ────────────────────────────────────────

  static Map<String, String> getStoredUtms() {
    if (!kIsWeb) return {};
    try {
      final jsonStr = js.context.callMethod('getStoredUtmParameters');
      if (jsonStr != null) {
        return Map<String, String>.from(json.decode(jsonStr as String));
      }
    } catch (e) {
      debugPrint('Error getting UTM parameters: $e');
    }
    return {};
  }
}
