import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// عملية بحث واحدة عن طيران — تُحفظ محلياً وتظهر في قسم «آخر بحث».
class RecentSearch {
  final String from; // كود المطار
  final String to;
  final String fromLabel; // اسم المدينة للعرض
  final String toLabel;
  final String departDate; // yyyy-MM-dd
  final String? returnDate;
  final bool roundTrip;
  final int pax; // إجمالي المسافرين

  const RecentSearch({
    required this.from,
    required this.to,
    required this.fromLabel,
    required this.toLabel,
    required this.departDate,
    this.returnDate,
    required this.roundTrip,
    required this.pax,
  });

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'fromLabel': fromLabel,
        'toLabel': toLabel,
        'departDate': departDate,
        'returnDate': returnDate,
        'roundTrip': roundTrip,
        'pax': pax,
      };

  factory RecentSearch.fromJson(Map<String, dynamic> j) => RecentSearch(
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        fromLabel: j['fromLabel'] ?? j['from'] ?? '',
        toLabel: j['toLabel'] ?? j['to'] ?? '',
        departDate: j['departDate'] ?? '',
        returnDate: j['returnDate'],
        roundTrip: j['roundTrip'] == true,
        pax: j['pax'] ?? 1,
      );
}

/// يحتفظ بآخر 3 عمليات بحث في SharedPreferences (مفتاح rt_recent_searches).
class RecentSearchesStore {
  static const _key = 'rt_recent_searches';
  static const maxItems = 3;

  static Future<List<RecentSearch>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => RecentSearch.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(RecentSearch item) async {
    final items = await load();
    // لا تكرار: نفس الوجهة والتاريخ يحل محل القديم
    items.removeWhere((x) =>
        x.from == item.from &&
        x.to == item.to &&
        x.departDate == item.departDate &&
        x.returnDate == item.returnDate);
    items.insert(0, item);
    if (items.length > maxItems) items.removeRange(maxItems, items.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// عملية بحث واحدة عن فنادق — تُحفظ محلياً وتظهر في قسم «آخر بحث».
class HotelRecentSearch {
  final String destination;      // كود الوجهة أو النص
  final String destinationLabel; // الاسم للعرض
  final String checkIn;          // yyyy-MM-dd
  final String checkOut;
  final int rooms;
  final int adults;
  final int children;

  const HotelRecentSearch({
    required this.destination,
    required this.destinationLabel,
    required this.checkIn,
    required this.checkOut,
    required this.rooms,
    required this.adults,
    required this.children,
  });

  Map<String, dynamic> toJson() => {
        'destination': destination,
        'destinationLabel': destinationLabel,
        'checkIn': checkIn,
        'checkOut': checkOut,
        'rooms': rooms,
        'adults': adults,
        'children': children,
      };

  factory HotelRecentSearch.fromJson(Map<String, dynamic> j) =>
      HotelRecentSearch(
        destination: j['destination'] ?? '',
        destinationLabel: j['destinationLabel'] ?? j['destination'] ?? '',
        checkIn: j['checkIn'] ?? '',
        checkOut: j['checkOut'] ?? '',
        rooms: j['rooms'] ?? 1,
        adults: j['adults'] ?? 2,
        children: j['children'] ?? 0,
      );
}

/// يحتفظ بآخر 3 عمليات بحث عن فنادق (مفتاح rt_recent_hotel_searches).
class HotelRecentStore {
  static const _key = 'rt_recent_hotel_searches';
  static const maxItems = 3;

  static Future<List<HotelRecentSearch>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => HotelRecentSearch.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(HotelRecentSearch item) async {
    try {
      final items = await load();
      items.removeWhere((x) =>
          x.destination == item.destination &&
          x.checkIn == item.checkIn &&
          x.checkOut == item.checkOut);
      items.insert(0, item);
      if (items.length > maxItems) items.removeRange(maxItems, items.length);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
