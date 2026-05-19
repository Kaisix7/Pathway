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

  static Future<bool> createAirportOrder({
    required String name,
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
        return false;
      }

      return true;
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
    String tariff = '',
    int price = 0,
    String status = 'Confirmed',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/orders/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
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

  static Future<List<AppOrder>> fetchOrders() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/orders/'));

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
