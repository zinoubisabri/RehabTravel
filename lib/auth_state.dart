import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'money.dart';
import 'strings.dart';

/// نتيجة محاولة دخول/تسجيل: error=null تعني نجاحاً،
/// وrequiresVerification=true تعني أن الحساب ينتظر رمز OTP من البريد.
class AuthResult {
  final String? error;
  final bool requiresVerification;
  const AuthResult.ok()
      : error = null,
        requiresVerification = false;
  const AuthResult.fail(this.error) : requiresVerification = false;
  const AuthResult.verify(this.error) : requiresVerification = true;
}

/// حالة المصادقة: تحفظ رمز JWT محلياً وتوفره لكل الشاشات.
class AuthState extends ChangeNotifier {
  static const _tokenKey = 'rt_token';
  static const _nameKey = 'rt_name';

  final ApiClient api = ApiClient();

  String? fullName;
  bool get isAuthenticated => api.token != null;
  bool isLoaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    api.token = prefs.getString(_tokenKey);
    fullName = prefs.getString(_nameKey);
    isLoaded = true;
    notifyListeners();
    if (isAuthenticated) _syncCurrency(); // مزامنة عملة العميل من حسابه
  }

  /// جلب عملة العميل من حسابه على الخادم (اختارها من الموقع أو جهاز آخر) وتطبيقها محلياً
  void _syncCurrency() {
    api.profileStatus().then((p) {
      final cur = p['preferredCurrency']?.toString();
      if (cur != null && cur.isNotEmpty) Money.setUserCurrency(cur);
    }).catchError((_) {});
  }

  Future<AuthResult> login(String email, String password) async {
    try {
      final result = await api.login(email, password);
      if (result['success'] == true && result['token'] != null) {
        await _persist(result['token'], result['fullName']);
        return const AuthResult.ok();
      }
      return AuthResult.fail(
          result['message']?.toString() ?? S.t('بيانات الدخول غير صحيحة'));
    } on ApiException catch (e) {
      // الـ API يرجع requiresVerification=true في جسم الخطأ عندما يكون البريد غير مؤكد
      if (api.lastErrorBody?['requiresVerification'] == true) {
        return AuthResult.verify(e.message);
      }
      return AuthResult.fail(e.message);
    }
  }

  Future<AuthResult> register(
      String fullName, String email, String phone, String password) async {
    try {
      final result = await api.register(fullName, email, phone, password);
      if (result['success'] == true && result['token'] != null) {
        await _persist(result['token'], result['fullName']);
        return const AuthResult.ok();
      }
      if (result['success'] == true && result['requiresVerification'] == true) {
        return AuthResult.verify(result['message']?.toString() ??
            S.t('أرسلنا رمز التحقق إلى بريدك الإلكتروني'));
      }
      return AuthResult.fail(
          result['message']?.toString() ?? S.t('تعذر إنشاء الحساب'));
    } on ApiException catch (e) {
      return AuthResult.fail(e.message);
    }
  }

  /// دخول اجتماعي (Google/Apple) — عند النجاح تُحفظ الجلسة مباشرة.
  Future<AuthResult> socialLogin({
    required String provider,
    required String providerKey,
    String? email,
    String? fullName,
    String? idToken,
  }) async {
    try {
      final result = await api.socialAppLogin(
          provider: provider,
          providerKey: providerKey,
          email: email,
          fullName: fullName,
          idToken: idToken);
      if (result['success'] == true && result['token'] != null) {
        await _persist(result['token'], result['fullName']);
        return const AuthResult.ok();
      }
      return AuthResult.fail(
          result['message']?.toString() ?? S.t('تعذر الدخول'));
    } on ApiException catch (e) {
      return AuthResult.fail(e.message);
    }
  }

  /// تأكيد البريد برمز OTP — عند النجاح تُحفظ الجلسة مباشرة.
  Future<AuthResult> verifyEmail(String email, String code) async {
    try {
      final result = await api.verifyEmail(email, code);
      if (result['success'] == true && result['token'] != null) {
        await _persist(result['token'], result['fullName']);
        return const AuthResult.ok();
      }
      return AuthResult.fail(
          result['message']?.toString() ?? S.t('الرمز غير صحيح'));
    } on ApiException catch (e) {
      return AuthResult.fail(e.message);
    }
  }

  Future<void> logout() async {
    api.token = null;
    fullName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_nameKey);
    notifyListeners();
  }

  Future<void> _persist(String token, String? name) async {
    api.token = token;
    fullName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (name != null) await prefs.setString(_nameKey, name);
    notifyListeners();
    _syncCurrency(); // مزامنة عملة العميل من حسابه فور الدخول
  }
}
