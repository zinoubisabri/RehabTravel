import 'package:flutter/material.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../strings.dart';

/// استعادة كلمة السر: طلب الرمز ثم تعيين كلمة سر جديدة — في شاشة واحدة بخطوتين.
class ForgotPasswordScreen extends StatefulWidget {
  final AuthState auth;
  const ForgotPasswordScreen({super.key, required this.auth});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _sent = false;
  bool _done = false;
  String? _error;
  String? _info;

  Future<void> _send() async {
    if (!_email.text.contains('@')) {
      setState(() => _error = S.t('أدخل بريداً إلكترونياً صحيحاً.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.api.forgotPassword(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _sent = true;
        _info = S.t(
            'إن كان البريد مسجلاً لدينا فقد أُرسل رمز الاستعادة إليه — تفقّد بريدك.');
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = S.t('أدخل رمز الاستعادة.'));
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = S.t('كلمة المرور يجب أن تكون 6 أحرف على الأقل.'));
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = S.t('كلمتا المرور غير متطابقتين.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.api
          .resetPassword(_code.text.trim().toUpperCase(), _password.text);
      if (!mounted) return;
      setState(() => _done = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('استعادة كلمة السر'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _done
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green),
                  const SizedBox(height: 12),
                  Text(
                    S.t('تم تحديث كلمة السر بنجاح — يمكنك الدخول الآن.'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(S.t('العودة لتسجيل الدخول')),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_sent) ...[
                    Text(S.t(
                        'أدخل بريدك الإلكتروني وسنرسل لك رمز استعادة يُستخدم مرة واحدة.')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: S.t('البريد الإلكتروني'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _send,
                      child: Text(_busy
                          ? S.t('يرجى الانتظار…')
                          : S.t('إرسال رمز الاستعادة')),
                    ),
                  ] else ...[
                    if (_info != null)
                      Card(
                        color: const Color(0xFFE8F5E9),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_info!),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      textAlign: TextAlign.center,
                      style: const TextStyle(letterSpacing: 4),
                      decoration: InputDecoration(
                        labelText: S.t('رمز الاستعادة'),
                        hintText: S.t('الرمز الذي وصلك بالبريد'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: S.t('كلمة السر الجديدة'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: S.t('تأكيد كلمة السر'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _reset,
                      child: Text(
                          _busy ? S.t('يرجى الانتظار…') : S.t('تحديث كلمة السر')),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _send,
                      child: Text(S.t('إعادة إرسال الرمز')),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
      ),
    );
  }
}
