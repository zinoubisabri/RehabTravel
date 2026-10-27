import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_state.dart';
import 'money.dart';
import 'local_push.dart';
import 'push_fcm.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/more_screen.dart';
import 'screens/my_bookings_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/price_alerts_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/wallet_screen.dart';
import 'strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthState();
  // تحميل عملة الموقع وأسعار الصرف مبكراً — لا يوقف الإقلاع عند فشل الشبكة
  Money.load(auth.api);
  runApp(RehabTravelApp(auth: auth));
}

/// هوية رحاب المسافرين اللونية والخطية — مرجع واحد لكل الشاشات.
class RtTheme {
  static const Color primary = Color(0xFF0B2D4D);   // كحلي عميق
  static const Color primaryMid = Color(0xFF0E3A5D);
  static const Color accent = Color(0xFFD9A441);    // ذهبي
  static const Color accentSoft = Color(0xFFF6E8C8);
  static const Color background = Color(0xFFF4F7FA);
  static const Color cardBorder = Color(0xFFE3EAF1);
  static const Color success = Color(0xFF1E7A45);
  static const Color esim = Color(0xFFD97706);

  // ألوان الوضع الليلي
  static const Color darkBackground = Color(0xFF0B1520);
  static const Color darkSurface = Color(0xFF122233);
  static const Color darkCardBorder = Color(0xFF23394F);

  static const LinearGradient heroGradient = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [Color(0xFF082138), Color(0xFF0E3A5D), Color(0xFF155E8A)],
  );

  /// وضع السمة الحالي (فاتح/داكن) — يُحفظ في SharedPreferences ويُستعاد عند الإقلاع.
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  static Future<void> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    mode.value = prefs.getString('rt_theme') == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  static Future<void> setMode(ThemeMode m) async {
    mode.value = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rt_theme', m == ThemeMode.dark ? 'dark' : 'light');
  }

  static ThemeData build() {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: accent,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: background,
      fontFamily: 'Cairo',
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryMid, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryMid,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
              fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryMid,
          textStyle: const TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          side: const BorderSide(color: cardBorder),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: accentSoft,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(
            fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  static ThemeData buildDark() {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      primary: const Color(0xFF7FB3E8),
      secondary: accent,
      surface: darkSurface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: darkBackground,
      fontFamily: 'Cairo',
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D1E30),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: darkSurface,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkCardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF16293D),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkCardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkCardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF7FB3E8), width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2C6DA3),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
              fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF7FB3E8),
          textStyle: const TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          side: const BorderSide(color: darkCardBorder),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0D1E30),
        indicatorColor: const Color(0xFF2C4A66),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(
            fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class RehabTravelApp extends StatelessWidget {
  final AuthState auth;
  const RehabTravelApp({super.key, required this.auth});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: S.lang,
      builder: (context, lang, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: RtTheme.mode,
        builder: (context, mode, _) => MaterialApp(
          title: S.t('رحاب المسافرين'),
          debugShowCheckedModeBanner: false,
          locale: Locale(lang),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: RtTheme.build(),
          darkTheme: RtTheme.buildDark(),
          themeMode: mode,
          home: SplashGate(auth: auth),
        ),
      ),
    );
  }
}

/// البوابة الأولى: سباش بشعار الشركة أثناء التحميل، ثم Onboarding في أول تشغيل،
/// ثم الواجهة الرئيسية.
class SplashGate extends StatefulWidget {
  final AuthState auth;
  const SplashGate({super.key, required this.auth});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _ready = false;
  bool _needsOnboarding = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final results = await Future.wait([
      widget.auth.load(),
      RtTheme.loadMode(),
      SharedPreferences.getInstance(),
      Money.loadUserCurrency(), // عملة العميل المحفوظة على الجهاز
      // إبقاء السبلاش ظاهراً لحظة كافية ليتعرف المستخدم على الشعار
      Future.delayed(const Duration(milliseconds: 1600)),
    ]);
    final prefs = results[2] as SharedPreferences;
    S.setLang(prefs.getString('rt_lang') ?? 'ar');
    _needsOnboarding = prefs.getBool('rt_onboarded') != true;
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _finishOnboarding(String lang, ThemeMode mode, String currency) async {
    final prefs = await SharedPreferences.getInstance();
    S.setLang(lang);
    await RtTheme.setMode(mode);
    await Money.setUserCurrency(currency); // عملة العميل من شاشة الترحيب
    // حفظها في حسابه إن كان مسجلاً — تتزامن مع الموقع
    if (widget.auth.isAuthenticated) {
      widget.auth.api.setMyCurrency(currency).catchError((_) => <String, dynamic>{});
    }
    await prefs.setString('rt_lang', lang);
    await prefs.setBool('rt_onboarded', true);
    if (mounted) setState(() => _needsOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return SplashScreen(auth: widget.auth);
    if (_needsOnboarding) {
      return OnboardingScreen(auth: widget.auth, onDone: _finishOnboarding);
    }
    return MainShell(auth: widget.auth);
  }
}

class MainShell extends StatefulWidget {
  final AuthState auth;
  const MainShell({super.key, required this.auth});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // إشعارات النظام بالصوت: تهيئة القناة + استطلاع الإشعارات الجديدة
    LocalPush.init();
    LocalPush.startPolling(widget.auth);
    // إشعارات Firebase — تصل حتى والتطبيق مغلق أو في الخلفية
    PushFcm.init(widget.auth.api);
    // ربط توكن الجهاز بحساب العميل فور تسجيل الدخول (لمن دخل بعد الإقلاع)
    widget.auth.addListener(() {
      if (widget.auth.isAuthenticated) PushFcm.registerDevice(widget.auth.api);
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // فحص فوري للإشعارات لحظة العودة إلى التطبيق من الخلفية
    if (state == AppLifecycleState.resumed) {
      LocalPush.checkNow(widget.auth);
      Money.refreshNow(widget.auth.api);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;

    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        // تُبنى داخل المستمع حتى تتبدل التبويبات فوراً عند الدخول/الخروج
        final screens = [
          HomeScreen(auth: auth),
          auth.isAuthenticated
              ? MyBookingsScreen(auth: auth)
              : LoginScreen(auth: auth),
          auth.isAuthenticated
              ? WalletScreen(auth: auth)
              : LoginScreen(auth: auth),
          auth.isAuthenticated
              ? PriceAlertsScreen(auth: auth)
              : LoginScreen(auth: auth),
          MoreScreen(auth: auth),
        ];
        return Scaffold(
        body: IndexedStack(index: _index, children: screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: S.t('الرئيسية')),
            NavigationDestination(icon: Icon(Icons.confirmation_number_outlined), label: S.t('حجوزاتي')),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: S.t('محفظتي')),
            NavigationDestination(icon: Icon(Icons.notifications_active_outlined), label: S.t('التنبيهات')),
            NavigationDestination(icon: Icon(Icons.menu), label: S.t('المزيد')),
          ],
        ),
      );
      },
    );
  }
}
