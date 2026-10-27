import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_client.dart';
import 'local_push.dart';

/// إشعارات Firebase — تصل للعميل حتى والتطبيق مغلق أو في الخلفية.
///
/// التهيئة تتم بقيم صريحة عبر --dart-define (لا حاجة لملف google-services.json):
///   flutter build apk \
///     --dart-define=RT_FCM_API_KEY=... \
///     --dart-define=RT_FCM_APP_ID=... \
///     --dart-define=RT_FCM_SENDER_ID=... \
///     --dart-define=RT_FCM_PROJECT_ID=...
/// كلها من Firebase Console ← Project settings ← General ← Your apps.
/// بدونها يتخطى التطبيق FCM بهدوء ويبقى الاستطلاع الداخلي يعمل.
class PushFcm {
  PushFcm._();

  static const _apiKey = String.fromEnvironment('RT_FCM_API_KEY');
  static const _appId = String.fromEnvironment('RT_FCM_APP_ID');
  static const _senderId = String.fromEnvironment('RT_FCM_SENDER_ID');
  static const _projectId = String.fromEnvironment('RT_FCM_PROJECT_ID');

  static bool get available =>
      _apiKey.isNotEmpty && _appId.isNotEmpty && _projectId.isNotEmpty;

  static bool _initialized = false;

  /// تسجيل توكن الجهاز في حساب العميل الحالي — تُستدعى بعد الدخول أيضاً
  /// (المستخدم الذي يسجل دخوله بعد الإقلاع يحتاج ربط جهازه بحسابه).
  static Future<void> registerDevice(ApiClient api) async {
    if (!available || api.token == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await api.registerDevice(token, Platform.isIOS ? 'ios' : 'android');
    } catch (_) {}
  }

  /// تهيئة Firebase + تسجيل توكن الجهاز في حساب العميل + الاستماع للرسائل.
  /// آمنة تماماً: أي فشل يُبتلع ولا يؤثر على إقلاع التطبيق.
  static Future<void> init(ApiClient api) async {
    if (_initialized || !available) return;
    _initialized = true;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );

      final messaging = FirebaseMessaging.instance;

      // إذن الإشعارات (iOS + Android 13)
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // تسجيل توكن الجهاز — الخادم يستخدمه لإرسال الإشعارات في الخلفية
      await registerDevice(api);
      messaging.onTokenRefresh.listen((token) async {
        if (api.token == null) return;
        try {
          await api.registerDevice(token, Platform.isIOS ? 'ios' : 'android');
        } catch (_) {}
      });

      // التطبيق في المقدمة: نعرض الإشعار بأنفسنا (النظام لا يعرضه هنا)
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        final title = n?.title ?? message.data['title']?.toString() ?? '';
        final body = n?.body ?? message.data['body']?.toString() ?? '';
        final image = n?.android?.imageUrl ??
            n?.apple?.imageUrl ??
            message.data['imageUrl']?.toString();
        if (title.isEmpty && body.isEmpty) return;
        LocalPush.showRemote(title, body, image);
      });

      // رسائل الخلفية/الإغلاق يعرضها نظام التشغيل تلقائياً (حمولة notification) —
      // لا يلزم معالج إضافي هنا.
    } catch (_) {
      // فشل FCM لا يكسر التطبيق — يبقى الاستطلاع الداخلي يعمل
    }
  }
}
