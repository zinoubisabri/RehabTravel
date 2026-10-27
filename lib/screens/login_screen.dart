import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../auth_state.dart';
import '../main.dart';
import '../strings.dart';
import '../lang_toggle.dart';
import 'forgot_password_screen.dart';
import 'terms_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthState auth;
  const LoginScreen({super.key, required this.auth});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  bool _acceptTerms = false;
  String? _error;

  Future<void> _submit() async {
    if (_registerMode && !_acceptTerms) {
      setState(() => _error =
          S.t('يجب الموافقة على شروط وأحكام رحاب المسافرين قبل إنشاء الحساب'));
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final result = _registerMode
        ? await widget.auth.register(
            _name.text.trim(), _email.text.trim(), _phone.text.trim(), _password.text)
        : await widget.auth.login(_email.text.trim(), _password.text);
    if (!mounted) return;

    if (result.requiresVerification) {
      // الحساب ينتظر رمز OTP من البريد — انتقل لشاشة التأكيد
      setState(() => _busy = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              VerifyEmailScreen(auth: widget.auth, email: _email.text.trim()),
        ),
      );
      return;
    }

    if (result.error == null) {
      // ✅ نجح الدخول/التسجيل — إن كانت الشاشة مفتوحة فوق صفحة أخرى فأغلقها فوراً
      // حتى تظهر الشاشة الأصلية بحالة الدخول الجديدة دون الحاجة لتحديث يدوي.
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        setState(() => _busy = false);
      }
      return;
    }

    setState(() {
      _busy = false;
      _error = result.error;
    });
  }

  /// دخول Google — الخادم يتحقق من idToken لدى Google قبل إصدار الجلسة
  Future<void> _googleSignIn() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final google = GoogleSignIn(scopes: ['email', 'profile']);
      final account = await google.signIn();
      if (account == null) {
        setState(() => _busy = false); // ألغى المستخدم
        return;
      }
      final auth = await account.authentication;
      final result = await widget.auth.socialLogin(
        provider: 'Google',
        providerKey: account.id,
        email: account.email,
        fullName: account.displayName,
        idToken: auth.idToken,
      );
      if (!mounted) return;
      if (result.error == null) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          setState(() => _busy = false);
        }
      } else {
        setState(() {
          _busy = false;
          _error = result.error;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = S.t('تعذر الدخول عبر Google — تحقق من إعداد التطبيق');
        });
      }
    }
  }

  /// دخول Apple (iOS) — sign_in_with_apple يتحقق من خوادم آبل مباشرة
  Future<void> _appleSignIn() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final name = [
        credential.givenName ?? '',
        credential.familyName ?? '',
      ].where((p) => p.isNotEmpty).join(' ');
      final result = await widget.auth.socialLogin(
        provider: 'Apple',
        providerKey: credential.userIdentifier ?? '',
        email: credential.email,
        fullName: name.isEmpty ? null : name,
      );
      if (!mounted) return;
      if (result.error == null) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          setState(() => _busy = false);
        }
      } else {
        setState(() {
          _busy = false;
          _error = result.error;
        });
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      if (mounted && e.code != AuthorizationErrorCode.canceled) {
        setState(() {
          _busy = false;
          _error = S.t('تعذر الدخول عبر Apple');
        });
      } else if (mounted) {
        setState(() => _busy = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = S.t('تعذر الدخول عبر Apple');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ---------- رأس متدرج ----------
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: RtTheme.heroGradient),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 26),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _registerMode
                              ? S.t('إنشاء حساب جديد')
                              : S.t('تسجيل الدخول'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800),
                        ),
                        const LangToggleButton(),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      // شعار الشركة من حزمة التطبيق مباشرة — لا يعتمد على الشبكة
                      child: Image.asset(
                        'assets/brand_logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.flight_takeoff,
                            size: 46,
                            color: RtTheme.accent),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(S.t('رحاب المسافرين'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    Text(S.t('رحلتك تبدأ من هنا'),
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),

          // ---------- النموذج ----------
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (_registerMode)
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                          labelText: S.t('الاسم الكامل'),
                          prefixIcon: const Icon(Icons.person_outline)),
                    ),
                  if (_registerMode) const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                        labelText: S.t('البريد الإلكتروني'),
                        prefixIcon: const Icon(Icons.mail_outline)),
                  ),
                  const SizedBox(height: 12),
                  if (_registerMode)
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                          labelText: S.t('رقم الهاتف'),
                          hintText: '09XXXXXXXX',
                          prefixIcon: const Icon(Icons.phone_outlined)),
                    ),
                  if (_registerMode) const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: S.t('كلمة المرور'),
                        prefixIcon: const Icon(Icons.lock_outline)),
                  ),
                  if (!_registerMode)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ForgotPasswordScreen(auth: widget.auth)),
                        ),
                        child: Text(S.t('نسيت كلمة السر؟')),
                      ),
                    ),
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDECEA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(color: Color(0xFFB3261E))),
                    ),
                  if (_registerMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: CheckboxListTile(
                        value: _acceptTerms,
                        onChanged: (v) =>
                            setState(() => _acceptTerms = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Wrap(
                          children: [
                            Text('${S.t('أوافق على')} '),
                            GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const TermsScreen()),
                              ),
                              child: Text(
                                S.t('شروط وأحكام رحاب المسافرين'),
                                style: const TextStyle(
                                  color: RtTheme.primary,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_busy
                          ? S.t('يرجى الانتظار…')
                          : (_registerMode
                              ? S.t('إنشاء الحساب')
                              : S.t('دخول'))),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(S.t('أو سجّل عبر'),
                          style: const TextStyle(color: Colors.grey)),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 12),
                  // Google: أندرويد والويب — Apple: iOS فقط (سياسة آبل)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _googleSignIn,
                      icon: const Text('G',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF4285F4))),
                      label: Text(S.t('المتابعة عبر Google')),
                    ),
                  ),
                  if (!kIsWeb && Platform.isIOS) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black),
                        onPressed: _busy ? null : _appleSignIn,
                        icon: const Icon(Icons.apple, size: 22),
                        label: Text(S.t('المتابعة عبر Apple')),
                      ),
                    ),
                  ],
                  TextButton(
                    onPressed: () => setState(() {
                      _registerMode = !_registerMode;
                      _error = null;
                    }),
                    child: Text(_registerMode
                        ? S.t('لديك حساب؟ سجّل الدخول')
                        : S.t('ليس لديك حساب؟ أنشئ حساباً')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
