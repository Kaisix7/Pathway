import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class ApiService {
  static String get baseUrl {
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

  static Future<bool> registerUser({
    required String name,
    required String email,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
        }),
      );

      print(response.statusCode);

      if (response.statusCode != 200) {
        print(response.body);
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      print('registerUser error: $e');
      print(stackTrace);
      rethrow;
    }
  }

<<<<<<< HEAD
  static Future<bool> createAirportOrder({
    required String name,
=======
  static Future<AppOrder?> createAirportOrder({
    required String name,
    required String userEmail,
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
<<<<<<< HEAD
=======
          'user_email': userEmail,
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
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

      print(response.statusCode);

      if (response.statusCode != 200) {
        print(response.body);
<<<<<<< HEAD
        return false;
      }

      return true;
=======
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _mapOrder(data['order'] as Map<String, dynamic>);
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
    } catch (e, stackTrace) {
      print('createAirportOrder error: $e');
      print(stackTrace);
      rethrow;
    }
  }

  static Future<bool> createServiceOrder({
    required String name,
    required String serviceType,
    required String title,
    required String details,
<<<<<<< HEAD
    String tariff = '',
    int price = 0,
    String status = 'Confirmed',
=======
    String userEmail = '',
    String tariff = '',
    int price = 0,
    String status = 'pending',
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/orders/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
<<<<<<< HEAD
=======
          'user_email': userEmail,
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
          'tariff': tariff,
          'price': price,
          'service_type': serviceType,
          'order_title': title,
          'details': details,
          'order_status': status,
        }),
      );

      print(response.statusCode);

      if (response.statusCode != 200) {
        print(response.body);
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      print('createServiceOrder error: $e');
      print(stackTrace);
      rethrow;
    }
  }

<<<<<<< HEAD
  static Future<List<AppOrder>> fetchOrders() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/orders/'));
=======
  static Future<List<AppOrder>> fetchOrders({String userEmail = ''}) async {
    try {
      final uri = Uri.parse('$baseUrl/orders/').replace(
        queryParameters: userEmail.isEmpty ? null : {'user_email': userEmail},
      );
      final response = await http.get(uri);
>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950

      print(response.statusCode);

      if (response.statusCode != 200) {
        print(response.body);
        throw Exception('Failed to load orders');
      }

      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => _mapOrder(item as Map<String, dynamic>)).toList();
    } catch (e, stackTrace) {
      print('fetchOrders error: $e');
      print(stackTrace);
      rethrow;
    }
  }

<<<<<<< HEAD
=======
  static Future<AppOrder?> payOrder(String orderId) async {
    final numericId = orderId.replaceFirst('api_', '');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/orders/$numericId/pay/'),
        headers: {'Content-Type': 'application/json'},
      );

      print(response.statusCode);

      if (response.statusCode != 200) {
        print(response.body);
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _mapOrder(data['order'] as Map<String, dynamic>);
    } catch (e, stackTrace) {
      print('payOrder error: $e');
      print(stackTrace);
      rethrow;
    }
  }

>>>>>>> ada3666a7ae7021d50248364e83e0eda6abf2950
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
