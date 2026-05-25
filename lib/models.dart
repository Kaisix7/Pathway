import 'package:flutter/material.dart';

enum UserRole { foreigner, worker }

enum Plan { free, standard, premium }

String planLabel(Plan p) {
  switch (p) {
    case Plan.free:
      return "Free";
    case Plan.standard:
      return "Standard";
    case Plan.premium:
      return "Premium";
  }
}

Color planColor(Plan p) {
  switch (p) {
    case Plan.free:
      return Colors.grey;
    case Plan.standard:
      return Colors.blue;
    case Plan.premium:
      return Colors.orange;
  }
}

class PaymentRecord {
  final String id;
  final String title;
  final double amount;
  final DateTime date;

  PaymentRecord({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
  });
}

class ChatMsg {
  final bool fromUser;
  final String text;
  final DateTime ts;

  ChatMsg({
    required this.fromUser,
    required this.text,
    required this.ts,
  });
}

/// Переименовали чтобы не конфликтовал с Firebase
class AppOrder {
  final String id;
  final String title;
  final String details;
  final String status;
  final DateTime createdAt;

  AppOrder({
    required this.id,
    required this.title,
    required this.details,
    required this.status,
    required this.createdAt,
  });
}

class IinCenter {
  final String id;
  final String name;
  final String address;
  final String district;
  final double lat;
  final double lng;

  const IinCenter({
    required this.id,
    required this.name,
    required this.address,
    required this.district,
    required this.lat,
    required this.lng,
  });
}

enum HousingType { hotel, dorm, apartment }

String housingTypeLabel(HousingType t) {
  switch (t) {
    case HousingType.hotel:
      return "Hotel";
    case HousingType.dorm:
      return "Dorm";
    case HousingType.apartment:
      return "Apartment";
  }
}

class HousingItem {
  final String id;
  final String title;
  final String address;
  final String district;
  final HousingType type;
  final int priceKztMonthly;

  /// новые поля которые требует UI
  final bool verified;
  final double rating;

  HousingItem({
    required this.id,
    required this.title,
    required this.address,
    required this.district,
    required this.type,
    required this.priceKztMonthly,
    this.verified = false,
    this.rating = 4.5,
  });
}

class TaskItem {
  final String title;
  bool done;

  TaskItem({
    required this.title,
    this.done = false,
  });
}