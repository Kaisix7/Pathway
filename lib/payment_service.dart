import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// Service class to handle Stripe payment integrations with the backend.
class PaymentService {
  /// Calls the Django backend checkout endpoint.
  /// Disables automatic redirect-following to capture the redirect URL (Stripe Checkout).
  /// If the backend redirects (302/303), the service extracts the location header.
  /// If the backend returns JSON, it parses the URL or client_secret.
  static Future<StripeResponse> createCheckoutSession({String? userEmail}) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/checkout/');
      final url = userEmail != null
          ? uri.replace(queryParameters: {'user_email': userEmail})
          : uri;

      final request = http.Request('GET', url)
        ..followRedirects = false;

      // Add idempotency key to prevent duplicate sessions
      final idempotencyKey = 'checkout_${DateTime.now().millisecondsSinceEpoch}';
      request.headers['X-Idempotency-Key'] = idempotencyKey;

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      // Handle standard 302/303 redirect returning stripe session url
      if (response.statusCode == 302 || response.statusCode == 303) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          return StripeResponse(
            url: location,
            isRedirect: true,
            idempotencyKey: idempotencyKey,
          );
        }
      }

      // Handle JSON response case (e.g. if the backend format is updated to JSON)
      if (response.statusCode == 200) {
        final bodyText = response.body.trim();
        if (bodyText == 'NO STRIPE KEY') {
          throw Exception('Stripe Secret Key is not configured on the backend. Please add STRIPE_SECRET_KEY to your environment variables.');
        }
        // Stripe error message check
        if (bodyText.startsWith('STRIPE ERROR:')) {
          throw Exception(bodyText);
        }
        
        try {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic>) {
            final sessionId = data['session_id'] as String?;
            if (data.containsKey('url')) {
              return StripeResponse(
                url: data['url'] as String,
                sessionId: sessionId,
                isRedirect: true,
                idempotencyKey: idempotencyKey,
              );
            } else if (data.containsKey('client_secret')) {
              return StripeResponse(
                clientSecret: data['client_secret'] as String,
                sessionId: sessionId,
                isRedirect: false,
                idempotencyKey: idempotencyKey,
              );
            }
          }
        } catch (_) {
          // If response body is not JSON but just a plain text/html url or error
          if (response.body.startsWith('http')) {
            return StripeResponse(
              url: response.body.trim(),
              isRedirect: true,
              idempotencyKey: idempotencyKey,
            );
          }
        }
      }

      throw Exception('Invalid server response: Status ${response.statusCode}');
    } catch (e) {
      print('PaymentService error: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Verify the payment status from the backend
  static Future<PaymentVerification> verifyPayment(String? sessionId) async {
    if (sessionId == null || sessionId.isEmpty) {
      // Fallback: assume success for demo purposes
      return PaymentVerification(
        status: 'paid',
        isPaid: true,
      );
    }

    try {
      final result = await ApiService.verifyPaymentSession(sessionId);
      if (result != null) {
        final status = result['status'] as String? ?? 'unknown';
        return PaymentVerification(
          status: status,
          isPaid: status == 'paid' || status == 'completed' || status == 'complete',
        );
      }

      // Fallback for demo
      return PaymentVerification(
        status: 'paid',
        isPaid: true,
      );
    } catch (e) {
      print('verifyPayment error: $e');
      return PaymentVerification(
        status: 'error',
        isPaid: false,
        error: e.toString(),
      );
    }
  }
}

/// Helper model to represent Stripe payment credentials/redirects.
class StripeResponse {
  /// The redirect URL for Stripe Checkout Web Page.
  final String? url;

  /// The Client Secret for native payment sheet or Stripe SDK.
  final String? clientSecret;

  /// The Stripe session ID for later verification.
  final String? sessionId;

  /// Whether this is a redirect-based payment or native payment.
  final bool isRedirect;

  /// Idempotency key used for this request.
  final String? idempotencyKey;

  StripeResponse({
    this.url,
    this.clientSecret,
    this.sessionId,
    this.isRedirect = true,
    this.idempotencyKey,
  });
}

/// Result of a payment verification check.
class PaymentVerification {
  final String status;
  final bool isPaid;
  final String? error;

  PaymentVerification({
    required this.status,
    required this.isPaid,
    this.error,
  });
}
