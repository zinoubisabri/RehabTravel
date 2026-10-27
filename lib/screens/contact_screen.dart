import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_state.dart';
import '../models.dart';
import '../strings.dart';

/// صفحة "اتصل بنا" — كل بياناتها من قاعدة البيانات (تُدار من لوحة التحكم).
class ContactScreen extends StatefulWidget {
  final AuthState auth;
  const ContactScreen({super.key, required this.auth});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  ContactSettings? _settings;
  bool _failed = false;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

  static const Color _primary = Color(0xFF0E3A5D);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.auth.api.contactSettings();
      if (!mounted) return;
      setState(() {
        _settings = ContactSettings.fromJson(Map<String, dynamic>.from(j));
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _send() async {
    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _message.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(S.t('الاسم والبريد الإلكتروني والرسالة حقول مطلوبة'))));
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.auth.api.sendContactMessage(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        subject: _subject.text.trim(),
        message: _message.text.trim(),
      );
      if (!mounted) return;
      _name.clear();
      _email.clear();
      _phone.clear();
      _subject.clear();
      _message.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(S.t('تم استلام رسالتك بنجاح، سنتواصل معك قريباً'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = S.isAr;
    final s = _settings;

    return Scaffold(
      appBar: AppBar(title: Text(S.t('اتصل بنا'))),
      body: s == null
          ? Center(
              child: _failed
                  ? TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _failed = false;
                          _settings = null;
                        });
                        _load();
                      },
                      icon: const Icon(Icons.refresh),
                      label: Text(S.t('إعادة المحاولة')),
                    )
                  : const CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    S.t('فريق رحاب المسافرين جاهز لخدمتك في أي وقت'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),

                  // ---------- بطاقات التواصل ----------
                  Row(
                    children: [
                      Expanded(
                        child: _contactCard(
                          icon: Icons.phone,
                          label: S.t('اتصل بنا'),
                          value: s.phone,
                          onTap: s.phone.isEmpty
                              ? null
                              : () => _open('tel:${s.phone.replaceAll(' ', '')}'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _contactCard(
                          icon: Icons.chat,
                          label: S.t('واتساب'),
                          value: S.t('رد سريع خلال دقائق'),
                          color: const Color(0xFF1E7A45),
                          onTap: s.whatsapp.isEmpty
                              ? null
                              : () => _open('https://wa.me/${s.whatsapp}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _contactCard(
                          icon: Icons.email_outlined,
                          label: S.t('البريد الإلكتروني'),
                          value: s.email,
                          onTap: s.email.isEmpty
                              ? null
                              : () => _open('mailto:${s.email}'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _contactCard(
                          icon: Icons.location_on_outlined,
                          label: S.t('العنوان'),
                          value: isAr ? s.address : s.addressEn,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.access_time, color: _primary),
                      title: Text(S.t('ساعات العمل')),
                      subtitle:
                          Text(isAr ? s.workingHours : s.workingHoursEn),
                    ),
                  ),

                  // ---------- السوشيال ----------
                  if (s.facebook.isNotEmpty ||
                      s.instagram.isNotEmpty ||
                      s.twitter.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(S.t('تابعنا على'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (s.facebook.isNotEmpty)
                          ActionChip(
                              label: const Text('Facebook'),
                              onPressed: () => _open(s.facebook)),
                        if (s.instagram.isNotEmpty)
                          ActionChip(
                              label: const Text('Instagram'),
                              onPressed: () => _open(s.instagram)),
                        if (s.twitter.isNotEmpty)
                          ActionChip(
                              label: const Text('X'),
                              onPressed: () => _open(s.twitter)),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),
                  // ---------- نموذج الرسالة ----------
                  Text(S.t('أرسل لنا رسالة'),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _primary)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                        labelText: S.t('الاسم الكامل'),
                        border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                        labelText: S.t('البريد الإلكتروني'),
                        border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                        labelText: S.t('رقم الهاتف (اختياري)'),
                        border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _subject,
                    decoration: InputDecoration(
                        labelText: S.t('الموضوع'),
                        border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _message,
                    maxLines: 4,
                    decoration: InputDecoration(
                        labelText: S.t('رسالتك'),
                        border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.send),
                      label: Text(_sending
                          ? S.t('جارٍ الإرسال...')
                          : S.t('إرسال الرسالة')),
                      onPressed: _sending ? null : _send,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _contactCard({
    required IconData icon,
    required String label,
    required String value,
    Color color = _primary,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
