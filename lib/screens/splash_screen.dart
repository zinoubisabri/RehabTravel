import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../auth_state.dart';
import '../strings.dart';

/// شاشة البداية — شعار رحاب المسافرين مع حركات دخول احترافية:
/// توهج دائري نابض، دخول الشعار بقفزة مرنة، طائرة تطير خلفه،
/// اسم الشركة ينزلق للأعلى، وشريط تقدّم متلألئ.
class SplashScreen extends StatefulWidget {
  final AuthState auth;
  const SplashScreen({super.key, required this.auth});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // دخول الشعار (قفزة مرنة + ظهور)
  late final AnimationController _logoCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..forward();
  // النصوص بعد الشعار
  late final AnimationController _textCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  // توهج نابض مستمر خلف الشعار
  late final AnimationController _glowCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat(reverse: true);
  // طائرة صغيرة تعبر الشاشة
  late final AnimationController _planeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    // النصوص تظهر بعد بدء دخول الشعار
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _textCtrl.forward();
    });
    // الطائرة تعبر بعد اكتمال دخول الشعار
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _planeCtrl.forward();
    });
  }

  /// أذونات التطبيق عند الإقلاع: مايكروفون (المساعد الصوتي)، الموقع، الإشعارات.
  /// ملاحظة: تظهر النوافذ فقط إذا صُرّح بها في AndroidManifest.xml / Info.plist.
  Future<void> _requestPermissions() async {
    try {
      await Future.delayed(const Duration(milliseconds: 1200));
      await [
        Permission.microphone,
        Permission.locationWhenInUse,
        Permission.notification,
      ].request();
    } catch (_) {/* النظام يتولى الرفض/القبول */}
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _glowCtrl.dispose();
    _planeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final logoScale = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.0, 0.75, curve: Curves.elasticOut),
    );
    final logoFade = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
    );
    final textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut);
    final textSlide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic));

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF063C68), // أزرق الشعار الأصلي
              Color(0xFF0B2D4D),
              Color(0xFF082138),
            ],
          ),
        ),
        child: Stack(
          children: [
            // زخرفة دوائر خافتة في الزوايا
            Positioned(
              top: -70,
              left: -70,
              child: _decoCircle(190, 0.05),
            ),
            Positioned(
              bottom: -90,
              right: -60,
              child: _decoCircle(230, 0.04),
            ),

            // الطائرة العابرة مع ذيل خطي
            AnimatedBuilder(
              animation: _planeCtrl,
              builder: (_, __) {
                final t = _planeCtrl.value;
                if (t == 0 || t == 1) return const SizedBox.shrink();
                final dx = -60 + (size.width + 160) * t;
                final dy = size.height * 0.24 -
                    math.sin(t * math.pi) * 60; // قوس خفيف للأعلى
                final opacity =
                    (t < 0.15 ? t / 0.15 : (1 - t) / 0.25).clamp(0.0, 1.0);
                return Positioned(
                  left: dx,
                  top: dy,
                  child: Opacity(
                    opacity: opacity,
                    child: Row(
                      children: [
                        Container(
                          width: 90,
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: 0.7),
                            ]),
                          ),
                        ),
                        const Icon(Icons.flight_rounded,
                            color: Colors.white, size: 26),
                      ],
                    ),
                  ),
                );
              },
            ),

            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // الشعار مع توهج نابض
                  AnimatedBuilder(
                    animation: _glowCtrl,
                    builder: (_, __) {
                      final glow = _glowCtrl.value;
                      return ScaleTransition(
                        scale: Tween(begin: 0.2, end: 1.0).animate(logoScale),
                        child: FadeTransition(
                          opacity: logoFade,
                          child: Container(
                            width: 250,
                            height: 250,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF073159),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4FA3E3).withValues(
                                      alpha: 0.35 + glow * 0.3),
                                  blurRadius: 45 + glow * 25,
                                  spreadRadius: 4 + glow * 6,
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Padding(
                              padding: const EdgeInsets.all(38),
                              child: Image.asset(
                                'assets/splash_logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.flight_takeoff,
                                  size: 110,
                                  color: Color(0xFF4FA3E3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 34),

                  // اسم الشركة والوصف — انزلاق للأعلى مع ظهور
                  SlideTransition(
                    position: textSlide,
                    child: FadeTransition(
                      opacity: textFade,
                      child: Column(
                        children: [
                          Text(
                            S.t('رحاب المسافرين'),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'REHAB TRAVEL',
                            style: TextStyle(
                              fontSize: 13,
                              letterSpacing: 6,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            S.t('طيران • فنادق • عمرة • شرائح إلكترونية'),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 46),

                  // شريط تقدّم متلألئ
                  FadeTransition(
                    opacity: textFade,
                    child: SizedBox(
                      width: 150,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: AnimatedBuilder(
                          animation: _glowCtrl,
                          builder: (_, __) => LinearProgressIndicator(
                            minHeight: 5,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation(
                              Color.lerp(const Color(0xFFD9A441),
                                  const Color(0xFFF6E8C8), _glowCtrl.value),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decoCircle(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: Colors.white.withValues(alpha: alpha), width: 1.4),
        ),
      );
}
