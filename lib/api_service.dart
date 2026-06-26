import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;

import 'models.dart';

class ApiService {
  static const String _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    String url = _configuredBaseUrl;
    if (url.isEmpty) {
      if (kIsWeb) {
        final origin = html.window.location.origin;
        if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
          url = 'http://localhost:8000/api';
        } else {
          url = '$origin/api';
        }
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            url = 'http://10.0.2.2:8000/api';
            break;
          default:
            url = 'http://localhost:8000/api';
        }
      }
    }
    if (kIsWeb && url.contains('127.0.0.1')) {
      url = url.replaceAll('127.0.0.1', 'localhost');
    }
    return url;
  }

  /// Generate a unique idempotency key for payment requests
  static String _generateIdempotencyKey() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = now.hashCode.toRadixString(36);
    return 'idem_${now}_$rand';
  }

  static Future<String?> registerUser({
    required String name,
    required String email,
    String company = '',
    String utmSource = '',
    String utmMedium = '',
    String utmCampaign = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'company': company,
          'utm_source': utmSource,
          'utm_medium': utmMedium,
          'utm_campaign': utmCampaign,
        }),
      );

      debugPrint(response.statusCode.toString());

      if (response.statusCode != 200) {
        debugPrint(response.body);
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // Backend returns { "status": "ok", "token": "...", "user": {...} }
      return data['token'] as String?;
    } catch (e, stackTrace) {
      debugPrint('registerUser error: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  // ── Google OAuth ────────────────────────────────────────────────────

  /// Exchange Google OAuth code or fetch user info via the callback endpoint
  static Future<Map<String, dynamic>?> loginWithGoogle({
    String? code,
    String? email,
    String? name,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/oauth/google/callback/');
      final queryParams = <String, String>{};
      if (code != null) queryParams['code'] = code;
      if (email != null) queryParams['email'] = email;
      if (name != null) queryParams['name'] = name;

      final response = await http.get(uri.replace(queryParameters: queryParams));

      if (response.statusCode != 200) {
        debugPrint('loginWithGoogle error: ${response.body}');
        return null;
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('loginWithGoogle error: $e');
      return null;
    }
  }

  // ── Orders ──────────────────────────────────────────────────────────

  static Future<AppOrder?> createAirportOrder({
    required String name,
    required String userEmail,
    required String tariff,
    required int price,
    required String pickupLocation,
    required String flightNumber,
    required String arrivalDate,
    required String arrivalTime,
    required int passengers,
    required String destination,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/orders/'),
        headers: {
          'Content-Type': 'application/json',
          'X-Idempotency-Key': _generateIdempotencyKey(),
        },
        body: jsonEncode({
          'name': name,
          'user_email': userEmail,
          'tariff': tariff,
          'price': price,
          'service_type': 'airport',
          'pickup_location': pickupLocation,
          'flight_number': flightNumber,
          'arrival_date': arrivalDate,
          'arrival_time': arrivalTime,
          'passengers': passengers,
          'destination': destination,
        }),
      );

      debugPrint(response.statusCode.toString());

      if (response.statusCode != 200) {
        debugPrint(response.body);
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _mapOrder(data['order'] as Map<String, dynamic>);
    } catch (e, stackTrace) {
      debugPrint('createAirportOrder error: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  static Future<bool> createServiceOrder({
    required String name,
    required String serviceType,
    required String title,
    required String details,
    String userEmail = '',
    String tariff = '',
    int price = 0,
    String status = 'pending',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/orders/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'user_email': userEmail,
          'tariff': tariff,
          'price': price,
          'service_type': serviceType,
          'order_title': title,
          'details': details,
          'order_status': status,
        }),
      );

      debugPrint(response.statusCode.toString());

      if (response.statusCode != 200) {
        debugPrint(response.body);
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      debugPrint('createServiceOrder error: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  static Future<List<AppOrder>> fetchOrders({String userEmail = ''}) async {
    try {
      final uri = Uri.parse('$baseUrl/orders/').replace(
        queryParameters: userEmail.isEmpty ? null : {'user_email': userEmail},
      );
      final response = await http.get(uri);

      debugPrint(response.statusCode.toString());

      if (response.statusCode != 200) {
        debugPrint(response.body);
        throw Exception('Failed to load orders');
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => _mapOrder(item as Map<String, dynamic>)).toList();
    } catch (e, stackTrace) {
      debugPrint('fetchOrders error: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  static Future<AppOrder?> payOrder(String orderId) async {
    final numericId = orderId.replaceFirst('api_', '');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/orders/$numericId/pay/'),
        headers: {
          'Content-Type': 'application/json',
          'X-Idempotency-Key': _generateIdempotencyKey(),
        },
      );

      debugPrint(response.statusCode.toString());

      if (response.statusCode != 200) {
        debugPrint(response.body);
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _mapOrder(data['order'] as Map<String, dynamic>);
    } catch (e, stackTrace) {
      debugPrint('payOrder error: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  // ── Profile ─────────────────────────────────────────────────────────

  /// Fetch the current user's profile from the backend using their auth token.
  /// Returns the profile map (contains 'plan', 'name', 'email', etc.) or null on error.
  static Future<Map<String, dynamic>?> fetchUserProfile(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/profile/'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        debugPrint('fetchUserProfile error (${response.statusCode}): ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['user'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('fetchUserProfile error: $e');
      return null;
    }
  }

  /// Login via email+password and return the user data including plan.
  /// Returns the response data map or null on error.
  static Future<Map<String, dynamic>?> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode != 200) {
        debugPrint('loginWithEmail error (${response.statusCode}): ${response.body}');
        return null;
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('loginWithEmail error: $e');
      return null;
    }
  }

  // ── Payment Verification ────────────────────────────────────────────

  /// Verify a Stripe payment session status from the backend
  static Future<Map<String, dynamic>?> verifyPaymentSession(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/payment/status/').replace(
          queryParameters: {'session_id': sessionId},
        ),
      );

      if (response.statusCode != 200) {
        debugPrint('verifyPaymentSession error: ${response.body}');
        return null;
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('verifyPaymentSession error: $e');
      return null;
    }
  }

  /// Get payment/order status by order ID
  static Future<String?> getPaymentStatus(String orderId) async {
    final numericId = orderId.replaceFirst('api_', '');
    try {
      final orders = await fetchOrders();
      final order = orders.where((o) => o.id == 'api_$numericId').firstOrNull;
      return order?.status;
    } catch (e) {
      debugPrint('getPaymentStatus error: $e');
      return null;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  static AppOrder _mapOrder(Map<String, dynamic> item) {
    final orderTitle = (item['order_title'] ?? '').toString();
    final savedDetails = (item['details'] ?? '').toString();
    final serviceType = (item['service_type'] ?? 'airport').toString();
    final pickupLocation = (item['pickup_location'] ?? '').toString();
    final flightNumber = (item['flight_number'] ?? '').toString();
    final arrivalDate = (item['arrival_date'] ?? '').toString();
    final arrivalTime = (item['arrival_time'] ?? '').toString();
    final passengers = item['passengers'] ?? 1;
    final destination = (item['destination'] ?? '').toString();
    final tariff = (item['tariff'] ?? '').toString();

    final generatedTitle = orderTitle.isNotEmpty
        ? orderTitle
        : (serviceType == 'airport' ? 'Airport pickup ($tariff)' : serviceType.toUpperCase());
    final generatedDetails = savedDetails.isNotEmpty
        ? savedDetails
        : 'Pickup: $pickupLocation\nFlight: $flightNumber\n$arrivalDate at $arrivalTime\nPax: $passengers\nTo: $destination\nPrice: ${item['price']} KZT';

    return AppOrder(
      id: 'api_${item['id']}',
      title: generatedTitle,
      details: generatedDetails,
      status: (item['order_status'] ?? 'Saved in Django').toString(),
      createdAt: DateTime.tryParse((item['created_at'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}
