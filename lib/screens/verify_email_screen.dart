import 'package:flutter/material.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../strings.dart';

/// شاشة إدخال رمز التحقق OTP بعد التسجيل (أو عند دخول حساب غير مؤكد).
/// عند النجاح تُحفظ الجلسة وتُغلق الشاشة.
class VerifyEmailScreen extends StatefulWidget {
  final AuthState auth;
  final String email;
  const VerifyEmailScreen({super.key, required this.auth, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = S.t('أدخل الرمز المكوّن من 6 أرقام.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final result =
        await widget.auth.verifyEmail(widget.email, _code.text.trim());
    if (!mounted) return;
    if (result.error == null) {
      Navigator.pop(context, true); // نجاح — الجلسة حُفظت
    } else {
      setState(() {
        _busy = false;
        _error = result.error;
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.auth.api.resendCode(widget.email);
      if (!mounted) return;
      setState(() =>
          _info = S.t('أُرسل رمز جديد إلى بريدك (إن كان الحساب غير مؤكد).'));
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
      appBar: AppBar(title: Text(S.t('تأكيد البريد الإلكتروني'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.mark_email_read_outlined,
                size: 64, color: Color(0xFFD9A441)),
            const SizedBox(height: 12),
            Text(
              '${S.t('أرسلنا رمز تحقق مكوّناً من 6 أرقام إلى')} ${widget.email}',
              textAlign: TextAlign.center,
            ),
            Text(
              S.t('صالح لمدة 10 دقائق ويُستخدم مرة واحدة.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: InputDecoration(
                labelText: S.t('رمز التحقق'),
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child:
                    Text(_info!, style: const TextStyle(color: Colors.green)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _verify,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child:
                    Text(_busy ? S.t('يرجى الانتظار…') : S.t('تأكيد والدخول')),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _resend,
              child: Text(S.t('إعادة إرسال الرمز')),
            ),
          ],
        ),
      ),
    );
  }
}
