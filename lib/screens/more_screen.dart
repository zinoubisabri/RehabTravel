import 'package:flutter/material.dart';

import '../assistant_bubble.dart';
import '../auth_state.dart';
import '../lang_toggle.dart';
import '../main.dart';
import '../money.dart';
import '../strings.dart';
import 'contact_screen.dart';
import 'account_screen.dart';
import 'travelers_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'static_page_screen.dart';

/// صفحة "المزيد" — الحساب والروابط الثانوية في مكان واحد.
class MoreScreen extends StatelessWidget {
  final AuthState auth;
  const MoreScreen({super.key, required this.auth});

  @override
  Widget build(BuildContext context) {
    final isAr = S.isAr;

    return Scaffold(
      appBar: AppBar(title: Text(S.t('المزيد'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------- بطاقة الحساب ----------
          Card(
            color: const Color(0xFF0E3A5D),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.isAuthenticated
                              ? (auth.fullName ?? '')
                              : S.t('زائر'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          auth.isAuthenticated
                              ? S.t('حساب مفعّل')
                              : S.t('سجّل الدخول لإدارة حجوزاتك ومحفظتك'),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  if (!auth.isAuthenticated)
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD9A441)),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => LoginScreen(auth: auth)),
                      ),
                      child: Text(S.t('دخول')),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          _item(
            context,
            icon: Icons.notifications_outlined,
            label: S.t('الإشعارات'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => auth.isAuthenticated
                      ? NotificationsScreen(auth: auth)
                      : LoginScreen(auth: auth)),
            ),
          ),
          if (auth.isAuthenticated)
            _item(
              context,
              icon: Icons.manage_accounts_outlined,
              label: S.t('حسابي'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AccountScreen(auth: auth)),
              ),
            ),
          if (auth.isAuthenticated)
            _item(
              context,
              icon: Icons.groups_outlined,
              label: S.t('المسافرون'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TravelersScreen(auth: auth)),
              ),
            ),
          _item(
            context,
            icon: Icons.headset_mic_outlined,
            label: S.t('اتصل بنا'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ContactScreen(auth: auth)),
            ),
          ),
          _item(
            context,
            icon: Icons.info_outline,
            label: S.t('من نحن'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const StaticPageScreen(type: StaticPageType.about)),
            ),
          ),
          _item(
            context,
            icon: Icons.help_outline,
            label: S.t('الأسئلة الشائعة'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const StaticPageScreen(type: StaticPageType.faq)),
            ),
          ),
          _item(
            context,
            icon: Icons.description_outlined,
            label: S.t('الشروط والأحكام'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const StaticPageScreen(type: StaticPageType.terms)),
            ),
          ),
          _item(
            context,
            icon: Icons.privacy_tip_outlined,
            label: S.t('سياسة الخصوصية'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      const StaticPageScreen(type: StaticPageType.privacy)),
            ),
          ),

          const Divider(height: 24),
          // ---------- عملة العميل المفضلة ----------
          ValueListenableBuilder<String>(
            valueListenable: Money.changes,
            builder: (context, active, _) => ListTile(
              leading: const Icon(Icons.payments_outlined, color: Color(0xFF0E3A5D)),
              title: Text(S.t('عملتي')),
              subtitle: Text(
                active == 'USD'
                    ? S.t('دولار أمريكي (USD)')
                    : active == 'EUR'
                        ? S.t('يورو (EUR)')
                        : S.t('دينار ليبي (LYD)'),
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _pickCurrency(context),
            ),
          ),
          // ---------- اللغة ----------
          ListTile(
            leading: const Icon(Icons.language, color: Color(0xFF0E3A5D)),
            title: Text(S.t('اللغة')),
            trailing: const LangToggleButton(),
          ),
          // ---------- المظهر: فاتح / داكن ----------
          ValueListenableBuilder<ThemeMode>(
            valueListenable: RtTheme.mode,
            builder: (context, mode, _) => SwitchListTile(
              secondary: Icon(
                mode == ThemeMode.dark
                    ? Icons.nightlight_round
                    : Icons.wb_sunny_outlined,
                color: const Color(0xFF0E3A5D),
              ),
              title: Text(S.t('الوضع الليلي')),
              value: mode == ThemeMode.dark,
              onChanged: (dark) =>
                  RtTheme.setMode(dark ? ThemeMode.dark : ThemeMode.light),
            ),
          ),
          // ---------- زر المساعد الذكي العائم ----------
          const AssistantVisibilityTile(),
          if (auth.isAuthenticated)
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(S.t('تسجيل الخروج'),
                  style: const TextStyle(color: Colors.red)),
              onTap: () => auth.logout(),
            ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              isAr ? 'رحاب المسافرين — الإصدار 1.0' : 'Rehab Travel — v1.0',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// اختيار عملة العميل — تُطبق فوراً على كل الأسعار وتُحفظ في حسابه إن كان مسجلاً
  void _pickCurrency(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(S.t('اختر عملتك — كل الأسعار تُعرض بها'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final c in const [
              ('LYD', 'دينار ليبي', 'د.ل'),
              ('USD', 'دولار أمريكي', '\$'),
              ('EUR', 'يورو', '€'),
            ])
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Money.active == c.$1
                      ? const Color(0xFF0E3A5D)
                      : Colors.grey.shade200,
                  child: Text(c.$3,
                      style: TextStyle(
                          fontSize: 13,
                          color: Money.active == c.$1
                              ? Colors.white
                              : Colors.black87)),
                ),
                title: Text(S.t(c.$2)),
                trailing: Money.active == c.$1
                    ? const Icon(Icons.check_circle, color: Color(0xFF1E7A45))
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await Money.setUserCurrency(c.$1);
                  if (auth.isAuthenticated) {
                    try {
                      await auth.api.setMyCurrency(c.$1);
                    } catch (_) {}
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0E3A5D)),
        title: Text(label),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
