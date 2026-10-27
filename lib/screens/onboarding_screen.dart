import 'package:flutter/material.dart';

import '../auth_state.dart';
import '../main.dart';

/// شاشة الترحيب عند أول تشغيل: اختيار اللغة (عربي/إنجليزي) والسمة (فاتح/داكن)
/// والعملة المفضلة (دينار/دولار/يورو) — كلها قابلة للتغيير لاحقاً من «المزيد».
class OnboardingScreen extends StatefulWidget {
  final AuthState auth;
  final Future<void> Function(String lang, ThemeMode mode, String currency) onDone;
  const OnboardingScreen({super.key, required this.auth, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String _lang = 'ar';
  ThemeMode _mode = ThemeMode.light;
  String _currency = 'LYD';
  bool _saving = false;

  bool get _isAr => _lang == 'ar';

  String _tr(String ar, String en) => _isAr ? ar : en;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: RtTheme.heroGradient),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // الشعار
                      Center(
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
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
                              size: 56,
                              color: RtTheme.primaryMid,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        _tr('أهلاً بك في رحاب المسافرين',
                            'Welcome to Rehab Travel'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _tr('خصّص تجربتك قبل البدء',
                            'Personalize your experience before you start'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // اختيار اللغة
                      Text(
                        _tr('لغة التطبيق', 'App language'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _OptionCard(
                              selected: _lang == 'ar',
                              icon: Icons.language,
                              title: 'العربية',
                              subtitle: 'واجهة عربية بالكامل',
                              onTap: () => setState(() => _lang = 'ar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _OptionCard(
                              selected: _lang == 'en',
                              icon: Icons.language,
                              title: 'English',
                              subtitle: 'Full English interface',
                              onTap: () => setState(() => _lang = 'en'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // اختيار السمة
                      Text(
                        _tr('مظهر التطبيق', 'App appearance'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _OptionCard(
                              selected: _mode == ThemeMode.light,
                              icon: Icons.wb_sunny_outlined,
                              title: _tr('فاتح', 'Light'),
                              subtitle: _tr('ألوان مشرقة', 'Bright colors'),
                              onTap: () =>
                                  setState(() => _mode = ThemeMode.light),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _OptionCard(
                              selected: _mode == ThemeMode.dark,
                              icon: Icons.nightlight_round,
                              title: _tr('داكن', 'Dark'),
                              subtitle: _tr('مريح للعين', 'Easy on the eyes'),
                              onTap: () =>
                                  setState(() => _mode = ThemeMode.dark),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // اختيار العملة — كل عميل يعرض الأسعار ويدفع بعملته
                      Text(
                        _tr('عملتك المفضلة', 'Your currency'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _OptionCard(
                              selected: _currency == 'LYD',
                              icon: Icons.payments_outlined,
                              title: _tr('دينار', 'Dinar'),
                              subtitle: 'LYD — د.ل',
                              onTap: () =>
                                  setState(() => _currency = 'LYD'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _OptionCard(
                              selected: _currency == 'USD',
                              icon: Icons.attach_money,
                              title: _tr('دولار', 'Dollar'),
                              subtitle: 'USD — \$',
                              onTap: () =>
                                  setState(() => _currency = 'USD'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _OptionCard(
                              selected: _currency == 'EUR',
                              icon: Icons.euro_symbol,
                              title: _tr('يورو', 'Euro'),
                              subtitle: 'EUR — €',
                              onTap: () =>
                                  setState(() => _currency = 'EUR'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 34),

                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: RtTheme.accent,
                          foregroundColor: RtTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _saving
                            ? null
                            : () async {
                                setState(() => _saving = true);
                                await widget.onDone(_lang, _mode, _currency);
                              },
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: RtTheme.primary),
                              )
                            : Text(
                                _tr('ابدأ الآن', 'Get started'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _tr('يمكنك تغيير هذه الخيارات لاحقاً من «المزيد»',
                            'You can change these later from the More tab'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? RtTheme.accent : Colors.white.withValues(alpha: 0.3),
            width: selected ? 2.2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 30,
                color: selected ? RtTheme.primaryMid : Colors.white),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: selected ? RtTheme.primary : Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: selected
                    ? RtTheme.primaryMid
                    : Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
