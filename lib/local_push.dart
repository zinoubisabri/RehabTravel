import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_state.dart';
import 'models.dart';

/// إشعارات النظام المحلية مع الصوت والصورة:
/// يستطلع إشعارات الحساب كل 20 ثانية (وفحص فوري عند فتح التطبيق أو العودة إليه
/// أو تسجيل الدخول)، وأي إشعار جديد يظهر فوراً كإشعار نظام بصوت وصورة.
class LocalPush {
  LocalPush._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'rt_alerts';
  static const _lastSeenKey = 'rt_last_notif_id';
  static Timer? _timer;
  static bool _initialized = false;
  static bool _checking = false;

  /// تهيئة القناة (بصوت + اهتزاز + أهمية قصوى) — تُستدعى مرة عند الإقلاع.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(const InitializationSettings(
          android: androidInit, iOS: darwinInit));

      const channel = AndroidNotificationChannel(
        _channelId,
        'إشعارات رحاب المسافرين',
        description: 'تنبيهات الحجوزات والعروض ورسائل الإدارة',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // أندرويد 13+: طلب إذن الإشعارات من نظام التشغيل مباشرة
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {/* فشل التهيئة لا يوقف التطبيق */}
  }

  /// يحمّل صورة الإشعار (إن وُجدت) إلى ملف مؤقت ويعيد مسارها.
  static Future<String?> _downloadImage(String url) async {
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
      final ext = url.toLowerCase().contains('.png')
          ? 'png'
          : url.toLowerCase().contains('.webp')
              ? 'webp'
              : 'jpg';
      final file = File(
          '${Directory.systemTemp.path}/rt_notif_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _show(AppNotification n) =>
      _showRaw(n.id, n.title, n.body, n.imageUrl);

  /// عرض إشعار نظام فوري — يُستدعى أيضاً من FCM عند وصول رسالة والتطبيق في المقدمة
  /// (رسائل الخلفية/الإغلاق يعرضها نظام التشغيل تلقائياً).
  static Future<void> showRemote(String title, String body, [String? imageUrl]) =>
      _showRaw(0, title, body, imageUrl);

  static Future<void> _showRaw(int id, String title, String body, String? imageUrl) async {
    try {
      String? imagePath;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        imagePath = await _downloadImage(imageUrl);
      }

      final AndroidNotificationDetails androidDetails;
      if (imagePath != null) {
        androidDetails = AndroidNotificationDetails(
          _channelId,
          'إشعارات رحاب المسافرين',
          channelDescription: 'تنبيهات الحجوزات والعروض ورسائل الإدارة',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          largeIcon: FilePathAndroidBitmap(imagePath),
          styleInformation: BigPictureStyleInformation(
            FilePathAndroidBitmap(imagePath),
            contentTitle: title.isEmpty ? 'رحاب المسافرين' : title,
            summaryText: body,
          ),
        );
      } else {
        androidDetails = const AndroidNotificationDetails(
          _channelId,
          'إشعارات رحاب المسافرين',
          channelDescription: 'تنبيهات الحجوزات والعروض ورسائل الإدارة',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        );
      }

      await _plugin.show(
        id > 0 ? (id % 2147483647) : DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title.isEmpty ? 'رحاب المسافرين' : title,
        body,
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(
              presentAlert: true, presentBadge: true, presentSound: true),
        ),
      );
    } catch (_) {}
  }

  /// بدء الاستطلاع الدوري — آمن للاستدعاء المتكرر (مرة واحدة فعلياً).
  static void startPolling(AuthState auth) {
    if (_timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 20), (_) => _tick(auth));
    }
    // فحص فوري بعد الإقلاع مباشرة
    Timer(const Duration(seconds: 2), () => _tick(auth));
    // فحص فوري لحظة تسجيل الدخول
    auth.addListener(() {
      if (auth.isAuthenticated) _tick(auth);
    });
  }

  /// فحص فوري — يُستدعى عند العودة للتطبيق من الخلفية.
  static void checkNow(AuthState auth) => _tick(auth);

  static Future<void> _tick(AuthState auth) async {
    if (_checking) return;
    _checking = true;
    try {
      if (!auth.isAuthenticated) return;
      final raw = await auth.api.notifications();
      final list = raw
          .whereType<Map>()
          .map((j) => AppNotification.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      if (list.isEmpty) return;

      final maxId = list.map((n) => n.id).fold(0, (a, b) => a > b ? a : b);
      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getInt(_lastSeenKey);

      if (lastSeen == null) {
        // أول تشغيل فقط: نسجّل الحد الحالي دون إزعاج المستخدم بالقديم
        await prefs.setInt(_lastSeenKey, maxId);
        return;
      }

      final fresh = list.where((n) => n.id > lastSeen).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      // نعرض حتى 3 إشعارات جديدة دفعة واحدة كحد أقصى
      for (final n in fresh.take(3)) {
        await _show(n);
      }
      if (fresh.isNotEmpty) await prefs.setInt(_lastSeenKey, maxId);
    } catch (_) {/* الشبكة/الخادم — نحاول في الدورة القادمة */}
    finally {
      _checking = false;
    }
  }
}
