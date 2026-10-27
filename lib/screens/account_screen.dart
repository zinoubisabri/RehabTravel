import 'package:flutter/material.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../strings.dart';

/// شاشة «حسابي» — البيانات الشخصية، كلمة المرور، البريد، الهاتف، حذف الحساب.
class AccountScreen extends StatefulWidget {
  final AuthState auth;
  const AccountScreen({super.key, required this.auth});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, dynamic>? _status;
  String? _loadError;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.auth.api.profileStatus();
      if (mounted) {
        setState(() {
          _status = s;
          _loadError = null;
          _name.text = (s['fullName'] ?? '').toString();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _run(Future<dynamic> Function() action, String okMsg,
      {bool reload = false}) async {
    try {
      await action();
      _toast(okMsg);
      if (reload) _load();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('حسابي'))),
      body: _status == null
          ? (_loadError != null
              ? Center(child: Text(_loadError!))
              : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _personalCard(),
                _passwordCard(),
                _emailCard(),
                _phoneCard(),
                _deleteCard(),
              ],
            ),
    );
  }

  Widget _card({required String title, required IconData icon, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF0E3A5D)),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _personalCard() {
    return _card(
      title: S.t('تعديل البيانات الشخصية'),
      icon: Icons.person_outline,
      children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(
              labelText: S.t('الاسم الكامل'), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => _run(
                () => widget.auth.api.updateProfile(_name.text.trim()),
                S.t('تم حفظ البيانات بنجاح')),
            child: Text(S.t('حفظ البيانات')),
          ),
        ),
      ],
    );
  }

  Widget _passwordCard() {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    return _card(
      title: S.t('تغيير كلمة المرور'),
      icon: Icons.lock_outline,
      children: [
        TextField(
          controller: current,
          obscureText: true,
          decoration: InputDecoration(
              labelText: S.t('كلمة المرور الحالية'), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: next,
          obscureText: true,
          decoration: InputDecoration(
              labelText: S.t('كلمة المرور الجديدة'), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: confirm,
          obscureText: true,
          decoration: InputDecoration(
              labelText: S.t('تأكيد كلمة المرور'), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => _run(
                () => widget.auth.api
                    .changePassword(current.text, next.text, confirm.text),
                S.t('تم تغيير كلمة المرور بنجاح')),
            child: Text(S.t('تغيير كلمة المرور')),
          ),
        ),
      ],
    );
  }

  Widget _emailCard() {
    final s = _status!;
    final confirmed = s['emailConfirmed'] == true;
    final pending = (s['pendingEmail'] ?? '').toString();
    final newEmail = TextEditingController();
    final code = TextEditingController();
    final code2 = TextEditingController();
    return _card(
      title: S.t('تغيير أو تأكيد البريد الإلكتروني'),
      icon: Icons.mail_outline,
      children: [
        Row(
          children: [
            Expanded(child: Text((s['email'] ?? '').toString())),
            Icon(
              confirmed ? Icons.verified : Icons.error_outline,
              color: confirmed ? Colors.green : Colors.orange,
            ),
            Text(confirmed ? S.t('مؤكد') : S.t('غير مؤكد')),
          ],
        ),
        const SizedBox(height: 10),
        if (!confirmed) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: code,
                  decoration: InputDecoration(
                      labelText: S.t('رمز تأكيد البريد'),
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => _run(
                    () => widget.auth.api.confirmEmail(code.text.trim()),
                    S.t('تم تأكيد بريدك الإلكتروني'),
                    reload: true),
                child: Text(S.t('تأكيد')),
              ),
              TextButton(
                onPressed: () => _run(
                    () => widget.auth.api.resendEmailVerification(),
                    S.t('أُرسل الرمز')),
                child: Text(S.t('إعادة الإرسال')),
              ),
            ],
          ),
          const Divider(height: 24),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: newEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                    labelText: S.t('البريد الجديد'),
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _run(
                  () => widget.auth.api
                      .requestEmailChange(newEmail.text.trim()),
                  S.t('أُرسل رمز التحقق للبريد الجديد'),
                  reload: true),
              child: Text(S.t('إرسال')),
            ),
          ],
        ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: code2,
                  decoration: InputDecoration(
                      labelText: '${S.t('رمز التحقق لـ')} $pending',
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _run(
                    () => widget.auth.api.confirmEmailChange(code2.text.trim()),
                    S.t('تم تغيير بريدك الإلكتروني'),
                    reload: true),
                child: Text(S.t('تأكيد التغيير')),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _phoneCard() {
    final s = _status!;
    final confirmed = s['phoneConfirmed'] == true;
    final pending = (s['pendingPhone'] ?? '').toString();
    final newPhone = TextEditingController();
    final code = TextEditingController();
    return _card(
      title: S.t('تغيير أو تأكيد رقم الهاتف'),
      icon: Icons.phone_android,
      children: [
        Row(
          children: [
            Expanded(child: Text((s['phoneNumber'] ?? '—').toString())),
            Icon(
              confirmed ? Icons.verified : Icons.error_outline,
              color: confirmed ? Colors.green : Colors.orange,
            ),
            Text(confirmed ? S.t('مؤكد') : S.t('غير مؤكد')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: newPhone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                    labelText: S.t('الرقم الجديد'),
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _run(
                  () => widget.auth.api
                      .requestPhoneChange(newPhone.text.trim()),
                  S.t('أُنشئ رمز التحقق — تجده في إشعاراتك'),
                  reload: true),
              child: Text(S.t('إرسال الرمز')),
            ),
          ],
        ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: S.t('رمز التحقق (من الإشعارات)'),
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _run(
                    () => widget.auth.api.confirmPhoneChange(code.text.trim()),
                    S.t('تم تغيير رقم هاتفك'),
                    reload: true),
                child: Text(S.t('تأكيد التغيير')),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _deleteCard() {
    final requested = _status!['deletionRequested'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.redAccent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.delete_forever_outlined, color: Colors.red),
                const SizedBox(width: 8),
                Text(S.t('طلب حذف الحساب'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.red)),
              ],
            ),
            const SizedBox(height: 8),
            if (requested)
              Text(S.t('طلبك قيد المراجعة — سيتواصل معك فريقنا قريباً.'))
            else ...[
              Text(S.t('عند حذف الحساب تفقد حجوزاتك ومحفظتك — يُراجع الطلب من الإدارة قبل التنفيذ.')),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(S.t('تأكيد طلب حذف الحساب')),
                        content: Text(S.t('هل أنت متأكد؟ لا يمكن التراجع بعد تنفيذ الحذف.')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(S.t('تراجع'))),
                          FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(S.t('نعم، احذف حسابي'))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      _run(() => widget.auth.api.requestAccountDeletion(),
                          S.t('تم إرسال طلب حذف الحساب'),
                          reload: true);
                    }
                  },
                  child: Text(S.t('طلب حذف الحساب')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
