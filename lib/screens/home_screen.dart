import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../assistant_bubble.dart';
import '../auth_state.dart';
import '../main.dart';
import '../models.dart';
import '../money.dart';
import 'flight_results_screen.dart';
import 'flights_screen.dart';
import 'hotels_screen.dart';
import 'umrah_screen.dart';
import 'esim_screen.dart';
import 'extra_services_screen.dart';
import 'car_rental_screen.dart';
import 'airport_transfer_screen.dart';
import 'wallet_screen.dart';
import 'price_alerts_screen.dart';
import 'my_bookings_screen.dart';
import 'contact_screen.dart';
import 'login_screen.dart';
import '../strings.dart';
import '../lang_toggle.dart';

class HomeScreen extends StatefulWidget {
  final AuthState auth;
  const HomeScreen({super.key, required this.auth});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<TrendingDestination> _trending = [];
  String _heroTitle = '';
  String _heroSubtitle = '';
  num? _walletBalance;
  /// أرصدة المحافظ الثلاث — العرض يتبع العملة الحالية فقط
  final Map<String, num> _walletBals = {};
  Key _bannerKey = UniqueKey();

  /// أزرار الخدمات المفعّلة من الأدمن — الافتراضي: الكل ظاهر
  Map<String, bool> _svc = {};
  bool _svcOn(String key) => _svc[key] ?? true;

  @override
  void initState() {
    super.initState();
    _loadTrending();
    _loadHero();
    _loadWallet();
    _loadServiceButtons();
    // الأذونات تُطلب في شاشة البداية (أول شاشة في التطبيق)
  }

  Future<void> _loadServiceButtons() async {
    try {
      final raw = await widget.auth.api.serviceButtons();
      if (!mounted) return;
      setState(() {
        _svc = {
          for (final b in raw.whereType<Map>())
            (b['key'] ?? '').toString(): b['enabled'] == true
        };
      });
    } catch (_) {/* تبقى الافتراضية: الكل ظاهر */}
  }

  /// رصيد المحفظة الحالي — يظهر كشارة بجانب التحية عند تسجيل الدخول
  Future<void> _loadWallet() async {
    if (!widget.auth.isAuthenticated) return;
    try {
      final w = await widget.auth.api.wallet();
      if (!mounted) return;
      // نخزّن أرصدة كل المحافظ، والشارة تعرض رصيد العملة الحالية المختارة فقط
      _walletBals['LYD'] = w['balance'] as num? ?? 0;
      _walletBals['USD'] = w['balanceUsd'] as num? ?? 0;
      _walletBals['EUR'] = w['balanceEur'] as num? ?? 0;
      _walletBalance = _walletBals[Money.active] ?? 0;
      setState(() {});
    } catch (_) {/* لا نزعج المستخدم */}
  }

  /// كل الخدمات تتطلب تسجيل الدخول — غير المسجّل يُوجَّه لصفحة الدخول
  void _openService(Widget screen) {
    if (!widget.auth.isAuthenticated) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen(auth: widget.auth)),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  /// نصوص الواجهة من لوحة التحكم (الإعدادات) — مع نص افتراضي عند غيابها
  Future<void> _loadHero() async {
    try {
      final h = await widget.auth.api.homeSettings();
      if (!mounted) return;
      setState(() {
        _heroTitle = (h['heroTitle'] ?? '').toString();
        _heroSubtitle = (h['heroSubtitle'] ?? '').toString();
      });
    } catch (_) {/* النص الافتراضي يبقى */}
  }

  /// وجهات رائجة من آخر الحجوزات الحقيقية — تُخفى إن لم توجد بيانات
  Future<void> _loadTrending() async {
    try {
      final list = await widget.auth.api.trendingDestinations();
      if (!mounted) return;
      setState(() {
        _trending = list
            .map((e) =>
                TrendingDestination.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
    } catch (_) {
      // فشل التحميل لا يؤثر على الصفحة — القسم يبقى مخفياً
    }
  }

  /// فتح نتائج الطيران مباشرة: مصراتة (MJI) ← الوجهة بعد أسبوعين
  void _openTrending(TrendingDestination d) {
    if (!widget.auth.isAuthenticated) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen(auth: widget.auth)),
      );
      return;
    }
    final depart = DateTime.now().add(const Duration(days: 14));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FlightResultsScreen(
          auth: widget.auth,
          from: 'MJI',
          to: d.code,
          departDate: _fmt(depart),
          returnDate: null,
          roundTrip: false,
          adults: 1,
          children: 0,
          infants: 0,
        ),
      ),
    );
  }





  /// منتقي تاريخ واحد: مدى (ذهاب-عودة) أو يوم واحد حسب نوع الرحلة.




  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      body: Stack(
        children: [
        RefreshIndicator(
        onRefresh: _refresh,
        color: RtTheme.primaryMid,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---------- بانرات إعلانية (من لوحة الأدمن) ----------
                  BannerCarousel(key: _bannerKey, auth: widget.auth),

                  // ---------- الخدمات الرئيسية + زر المساعد الذكي ----------
                  Row(
                    children: [
                      Text(S.t('خدماتنا'),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 10),
                      AssistantMicButton(auth: widget.auth),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.32,
                    children: [
                      if (_svcOn('flights'))
                        _mainServiceCard(
                          icon: Icons.flight_takeoff,
                          title: S.t('طيران'),
                          subtitle: S.t('إصدار فوري للتذاكر'),
                          colors: const [Color(0xFF0E5A8A), Color(0xFF1487C8)],
                          onTap: () =>
                              _openService(FlightsScreen(auth: widget.auth)),
                        ),
                      if (_svcOn('hotels'))
                        _mainServiceCard(
                          icon: Icons.hotel_rounded,
                          title: S.t('فنادق'),
                          subtitle: S.t('حول العالم بأفضل سعر'),
                          colors: const [Color(0xFF0F6B4A), Color(0xFF19A974)],
                          onTap: () =>
                              _openService(HotelsScreen(auth: widget.auth)),
                        ),
                      if (_svcOn('umrah'))
                        _mainServiceCard(
                          icon: Icons.mosque_rounded,
                          title: S.t('عمرة'),
                          subtitle: S.t('برامج موثوقة ومريحة'),
                          colors: const [Color(0xFF8A6A12), Color(0xFFD9A441)],
                          onTap: () =>
                              _openService(UmrahScreen(auth: widget.auth)),
                        ),
                      if (_svcOn('esim'))
                        _mainServiceCard(
                          icon: Icons.sim_card_rounded,
                          title: 'eSIM',
                          subtitle: S.t('إنترنت فوري أثناء السفر'),
                          colors: const [Color(0xFF5B2D8E), Color(0xFF8B5CF6)],
                          onTap: () =>
                              _openService(EsimScreen(auth: widget.auth)),
                        ),
                      // خدمات السفر بنفس حجم بطاقات الخدمات الرئيسية
                      if (_svcOn('carrental'))
                        _mainServiceCard(
                          icon: Icons.directions_car_filled_rounded,
                          title: S.t('كراء سيارات'),
                          subtitle: S.t('باليوم وبأسعار الفترات'),
                          colors: const [Color(0xFF9C3D54), Color(0xFFD96C85)],
                          onTap: () =>
                              _openService(CarRentalScreen(auth: widget.auth)),
                        ),
                      if (_svcOn('transfer'))
                        _mainServiceCard(
                          icon: Icons.airport_shuttle_rounded,
                          title: S.t('نقل المطار'),
                          subtitle: S.t('استقبال وتوديع خاص'),
                          colors: const [Color(0xFF146C94), Color(0xFF1F9CCF)],
                          onTap: () => _openService(
                              AirportTransferScreen(auth: widget.auth)),
                        ),
                      if (_svcOn('activity'))
                        _mainServiceCard(
                          icon: Icons.map_rounded,
                          title: S.t('جولات وأنشطة'),
                          subtitle: S.t('تجارب محلية مميزة'),
                          colors: const [Color(0xFF0F6B4A), Color(0xFF27AE7B)],
                          onTap: () => _openService(ExtraServicesScreen(
                              auth: widget.auth, initialCategory: 'Activity')),
                        ),
                      if (_svcOn('insurance'))
                        _mainServiceCard(
                          icon: Icons.verified_user_rounded,
                          title: S.t('تأمين السفر'),
                          subtitle: S.t('تغطية شاملة لرحلتك'),
                          colors: const [Color(0xFF8A6A12), Color(0xFFD9A441)],
                          onTap: () => _openService(ExtraServicesScreen(
                              auth: widget.auth, initialCategory: 'Insurance')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ---------- خدمات سريعة ----------
                  Row(
                    children: [
                      _miniServiceTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: S.t('محفظتي'),
                        color: RtTheme.accent,
                        onTap: () => _openService(WalletScreen(auth: widget.auth)),
                      ),
                      const SizedBox(width: 10),
                      _miniServiceTile(
                        icon: Icons.confirmation_number_outlined,
                        label: S.t('حجوزاتي'),
                        color: RtTheme.primaryMid,
                        onTap: () =>
                            _openService(MyBookingsScreen(auth: widget.auth)),
                      ),
                      const SizedBox(width: 10),
                      _miniServiceTile(
                        icon: Icons.notifications_active_outlined,
                        label: S.t('التنبيهات'),
                        color: const Color(0xFFDD7A1F),
                        onTap: () =>
                            _openService(PriceAlertsScreen(auth: widget.auth)),
                      ),
                      const SizedBox(width: 10),
                      _miniServiceTile(
                        icon: Icons.headset_mic_outlined,
                        label: S.t('تواصل معنا'),
                        color: const Color(0xFF0E8A8A),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ContactScreen(auth: widget.auth)),
                        ),
                      ),
                    ],
                  ),

                  // ---------- وجهات رائجة (من الحجوزات الحقيقية) ----------
                  if (_trending.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(S.t('وجهات رائجة'),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        Text(S.t('من حجوزات عملائنا'),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 130,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _trending.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (ctx, i) {
                          final d = _trending[i];
                          return InkWell(
                            onTap: () => _openTrending(d),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 140,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: AlignmentDirectional.topStart,
                                  end: AlignmentDirectional.bottomEnd,
                                  colors: [
                                    Color(0xFF0E3A5D),
                                    Color(0xFF155E8A)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 8,
                                      offset: Offset(0, 3)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.flight_land,
                                      color: RtTheme.accent, size: 24),
                                  const Spacer(),
                                  Text(d.city,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(
                                      '${S.t('آخر سعر')} ${Money.fmt0(d.price)}',
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  // ---------- لماذا رحاب ----------
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(S.t('لماذا رحاب المسافرين؟'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(height: 10),
                          _featureRow(Icons.bolt,
                              S.t('⚡ إصدار فوري للتذاكر')),
                          _featureRow(Icons.account_balance_wallet,
                              S.t('💳 محفظة إلكترونية بالدينار الليبي')),
                          _featureRow(Icons.sim_card,
                              S.t('📱 شرائح eSIM بمسح QR فوري')),
                          _featureRow(Icons.card_giftcard,
                              S.t('🎁 نقاط ولاء مع كل حجز')),
                          _featureRow(Icons.notifications_active,
                              S.t('🔔 تنبيهات انخفاض الأسعار')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
        ],
      ),
    );
  }

  /// سحب الشاشة للأسفل = تحديث كل بيانات الصفحة (الرصيد، النصوص، الرائج، البانرات)
  Future<void> _refresh() async {
    setState(() => _bannerKey = UniqueKey());
    await Future.wait([_loadWallet(), _loadHero(), _loadTrending()]);
  }

  /// الترويسة المتدرجة: الشعار + التحية + رصيد المحفظة + نصوص الواجهة
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RtTheme.heroGradient,
        borderRadius: BorderRadiusDirectional.only(
          bottomStart: Radius.circular(30),
          bottomEnd: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: widget.auth,
                builder: (context, _) {
                  // حدّث الرصيد عند تغير حالة الدخول
                  if (widget.auth.isAuthenticated && _walletBalance == null) {
                    _loadWallet();
                  }
                  if (!widget.auth.isAuthenticated && _walletBalance != null) {
                    _walletBalance = null;
                    _walletBals.clear();
                  }
                  return Row(
                    children: [
                      // شعار الشركة من لوحة التحكم
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        clipBehavior: Clip.antiAlias,
                        // شعار الشركة من حزمة التطبيق مباشرة — لا يعتمد على الشبكة
                        child: Image.asset(
                          'assets/brand_logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.flight_takeoff,
                              color: RtTheme.primaryMid,
                              size: 26),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.auth.isAuthenticated
                                  ? S.t('مرحباً بعودتك 👋')
                                  : S.t('أهلاً بك في'),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11.5),
                            ),
                            Text(
                              widget.auth.isAuthenticated
                                  ? (widget.auth.fullName ?? '')
                                  : S.t('رحاب المسافرين'),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      // شارة رصيد المحفظة — الضغط يفتح المحفظة
                      if (widget.auth.isAuthenticated && _walletBalance != null)
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () =>
                              _openService(WalletScreen(auth: widget.auth)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: RtTheme.accent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.account_balance_wallet,
                                    size: 15, color: RtTheme.primary),
                                const SizedBox(width: 5),
                                ValueListenableBuilder<String>(
                                  valueListenable: Money.changes,
                                  builder: (context, cur, _) => Text(
                                    Money.fmt0(_walletBals[cur] ?? 0, cur),
                                    style: const TextStyle(
                                        color: RtTheme.primary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const LangToggleButton(),
                      if (widget.auth.isAuthenticated)
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white70),
                          tooltip: S.t('خروج'),
                          onPressed: () => widget.auth.logout(),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              Text(
                _heroTitle.isNotEmpty
                    ? _heroTitle
                    : S.t('سافر براحة بال… مع رحاب المسافرين'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                _heroSubtitle.isNotEmpty
                    ? _heroSubtitle
                    : S.t('تذاكر طيران بإصدار فوري، فنادق حول العالم، وبرامج عمرة موثوقة.'),
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// بطاقة خدمة رئيسية بتدرج لوني — شبكة 2×2
  Widget _mainServiceCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const Spacer(),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  /// بلاطة خدمة سريعة صغيرة — صف أسفل الخدمات الرئيسية
  Widget _miniServiceTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: RtTheme.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

}


/// كاروسيل البانرات الإعلانية — يُحمّل من api/banners ويختفي تماماً إن لم توجد بانرات.
class BannerCarousel extends StatefulWidget {
  final AuthState auth;
  const BannerCarousel({super.key, required this.auth});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  List<BannerItem> _banners = [];
  final PageController _controller = PageController();
  Timer? _timer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.auth.api.banners();
      if (!mounted) return;
      setState(() {
        _banners = list
            .map((e) => BannerItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
      if (_banners.length > 1) _startAutoScroll();
    } catch (_) {
      // فشل التحميل لا يؤثر — القسم يبقى مخفياً
    }
  }

  void _startAutoScroll() {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients || _banners.isEmpty) return;
      final next = (_current + 1) % _banners.length;
      _controller.animateToPage(next,
          duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(BannerItem b) async {
    final link = b.linkUrl;
    if (link == null) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* تجاهل */}
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _controller,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (ctx, i) {
              final b = _banners[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _open(b),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          b.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: RtTheme.primaryMid,
                            child: const Icon(Icons.image_outlined,
                                color: Colors.white54, size: 40),
                          ),
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : Container(
                                      color: RtTheme.primaryMid
                                          .withValues(alpha: 0.15),
                                      child: const Center(
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2)),
                                    ),
                        ),
                        if (b.title.isNotEmpty)
                          PositionedDirectional(
                            bottom: 0,
                            start: 0,
                            end: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Colors.black87, Colors.transparent],
                                ),
                              ),
                              child: Text(
                                b.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _banners.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _current == i ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _current == i
                          ? RtTheme.primaryMid
                          : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
