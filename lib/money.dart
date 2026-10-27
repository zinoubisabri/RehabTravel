import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// مساعد العملة العام — يجلب عملة الموقع وأسعار الصرف ويُحدّثها دورياً.
/// كل أسعار الخدمات الداخلية بالدينار (LYD) وتُحوَّل عند العرض.
/// كل عميل يختار عملته الخاصة (تُحفظ في حسابه وعلى الجهاز) — الزائر يرى الافتراضية.
class Money {
  static const Duration refreshInterval = Duration(seconds: 15);
  static const String _userKey = 'rt_currency';

  static String site = 'LYD'; // الافتراضية (للزوار) — يضبطها الأدمن
  static String? userCurrency; // اختيار العميل — يتغلب على الافتراضية

  /// العملة الفعلية للعرض والتحويل
  static String get active =>
      _valid(userCurrency) ? userCurrency! : site;

  static String get symbol => switch (active) {
        'USD' => '\$',
        'EUR' => '€',
        _ => 'د.ل',
      };

  /// يُخطر الشاشات عند تغيير العميل عملته حتى تُعيد رسم الأسعار فوراً
  static final ValueNotifier<String> changes = ValueNotifier('LYD');

  static bool _valid(String? c) => c == 'LYD' || c == 'USD' || c == 'EUR';

  /// قراءة اختيار العميل المحفوظ على الجهاز — تُستدعى عند الإقلاع
  static Future<void> loadUserCurrency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final c = prefs.getString(_userKey);
      userCurrency = _valid(c) ? c : null;
      changes.value = active;
    } catch (_) {}
  }

  /// حفظ اختيار العميل على الجهاز + إخطار الشاشات المفتوحة
  static Future<void> setUserCurrency(String? currency) async {
    userCurrency = _valid(currency) ? currency : null;
    changes.value = active;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (userCurrency == null) {
        await prefs.remove(_userKey);
      } else {
        await prefs.setString(_userKey, userCurrency!);
      }
    } catch (_) {}
  }

  static final Map<String, double> _rates = {}; // 'USD>LYD' → rate
  static bool _loaded = false;
  static bool _loading = false;
  static DateTime? _loadedAt;
  static ApiClient? _api;
  static Timer? _timer;

  static Future<void> load(ApiClient api, {bool force = false}) async {
    _api = api;
    _startAutoRefresh();

    final freshEnough = _loaded &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < refreshInterval;
    if (freshEnough && !force) return;
    if (_loading) return;

    _loading = true;
    try {
      final info = await api.currencyInfo();
      site = (info['siteCurrency'] ?? 'LYD').toString().toUpperCase();
      _rates.clear();
      for (final r in (info['rates'] as List? ?? const [])) {
        final k = '${r['fromCurrency']}>${r['toCurrency']}'.toUpperCase();
        final v = (r['rate'] as num?)?.toDouble() ?? 0;
        if (v > 0) _rates[k] = v;
      }
      _loaded = true;
      _loadedAt = DateTime.now();
    } catch (_) {
      // يبقى آخر سعر معروف — لا نكسر العرض أبداً بسبب الشبكة
    } finally {
      _loading = false;
    }
  }

  static void _startAutoRefresh() {
    if (_timer != null) return;
    _timer = Timer.periodic(refreshInterval, (_) {
      final api = _api;
      if (api != null) load(api, force: true);
    });
  }

  /// يُستدعى عند العودة من الخلفية حتى لا ينتظر المستخدم دورة التحديث التالية.
  static Future<void> refreshNow(ApiClient api) => load(api, force: true);

  /// تحويل مبلغ من عملته المصدرية (LYD افتراضياً) إلى عملة العميل الفعلية
  static double convert(num amount, [String? from]) {
    final f = (from ?? 'LYD').toUpperCase();
    if (f == active) return amount.toDouble();
    final r = _rates['$f>$active'];
    if (r == null || r <= 0) return amount.toDouble();
    return (amount * r * 100).roundToDouble() / 100;
  }

  /// تنسيق: «1,234.00 د.ل» أو «$ 45.50» حسب عملة العميل
  static String fmt(num amount, [String? from, int decimals = 2]) {
    final v = convert(amount, from);
    final fixed = v.toStringAsFixed(decimals);
    final dot = fixed.indexOf('.');
    final intPart = dot < 0 ? fixed : fixed.substring(0, dot);
    final fracPart = dot < 0 ? '' : fixed.substring(dot);
    final grouped = intPart.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    final s = '$grouped$fracPart';
    return active == 'LYD' ? '$s $symbol' : '$symbol $s';
  }

  static String fmt0(num amount, [String? from]) => fmt(amount, from, 0);

  /// رمز أي عملة محددة — بغض النظر عن عملة العرض الحالية
  static String symbolOf(String? currency) => switch (currency) {
        'USD' => '\$',
        'EUR' => '€',
        _ => 'د.ل',
      };

  /// تنسيق معاملة مكتملة بعملتها الأصلية كما بيعت — بلا أي تحويل،
  /// حتى لا تتغير عملة المعاملة عندما يبدّل العميل عملة العرض.
  static String fmtOrig(num amount, String? currency, [int decimals = 2]) {
    final fixed = amount.toStringAsFixed(decimals);
    final dot = fixed.indexOf('.');
    final intPart = dot < 0 ? fixed : fixed.substring(0, dot);
    final fracPart = dot < 0 ? '' : fixed.substring(dot);
    final grouped = intPart.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    final s = '$grouped$fracPart';
    final sym = symbolOf(currency);
    return (currency ?? 'LYD') == 'LYD' ? '$s $sym' : '$sym $s';
  }
}
