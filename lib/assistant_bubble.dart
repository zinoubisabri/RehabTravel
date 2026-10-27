import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_state.dart';
import 'main.dart';
import 'strings.dart';
import 'voice_assistant.dart';
import 'screens/flights_screen.dart';
import 'screens/hotels_screen.dart';
import 'screens/umrah_screen.dart';
import 'screens/esim_screen.dart';
import 'screens/car_rental_screen.dart';
import 'screens/airport_transfer_screen.dart';
import 'screens/extra_services_screen.dart';

/// تفضيلات زر المساعد الذكي: الإخفاء + آخر موضع — محفوظة محلياً.
/// hidden هو ValueNotifier حي حتى تتحدث الرئيسية فور تبديله من صفحة «المزيد».
class AssistantPrefs {
  static const _hiddenKey = 'rt_assistant_hidden';
  static const _xKey = 'rt_assistant_x';
  static const _yKey = 'rt_assistant_y';

  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);
  static Offset? _savedPos;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    hidden.value = prefs.getBool(_hiddenKey) ?? false;
    final x = prefs.getDouble(_xKey);
    final y = prefs.getDouble(_yKey);
    if (x != null && y != null) _savedPos = Offset(x, y);
  }

  static Future<void> setHidden(bool v) async {
    hidden.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hiddenKey, v);
  }

  static Offset? get savedPos => _savedPos;

  static Future<void> savePos(Offset pos) async {
    _savedPos = pos;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_xKey, pos.dx);
    await prefs.setDouble(_yKey, pos.dy);
  }
}

/// يفتح ورقة الاستماع الصوتي ثم ينفذ الطلب المفهوم (رحلة/فندق/عمرة/شريحة).
/// مشترك بين الزر العائم وزر المايك المدمج بجانب «خدماتنا».
Future<void> openVoiceAssistant(BuildContext context, AuthState auth) async {
  // حماية إضافية: المساعد للمسجّلين فقط
  if (!auth.isAuthenticated) return;
  final q = await showModalBottomSheet<VoiceQuery>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => AssistantVoiceSheet(api: auth.api),
  );
  if (q == null || !context.mounted) return;

  switch (q.type) {
    case VoiceServiceType.flight:
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => FlightsScreen(auth: auth, initialVoiceQuery: q)),
      );
      break;
    case VoiceServiceType.hotel:
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HotelsScreen(
            auth: auth,
            initialCity: q.hotelCity,
            initialCheckIn: q.checkIn,
            initialCheckOut: q.checkOut,
            initialRooms: q.rooms,
            initialAdults: q.adults,
          ),
        ),
      );
      break;
    case VoiceServiceType.umrah:
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => UmrahScreen(auth: auth)));
      break;
    case VoiceServiceType.esim:
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => EsimScreen(auth: auth)));
      break;
    case VoiceServiceType.carRental:
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => CarRentalScreen(auth: auth)));
      break;
    case VoiceServiceType.transfer:
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => AirportTransferScreen(auth: auth)));
      break;
    case VoiceServiceType.activity:
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ExtraServicesScreen(auth: auth, initialCategory: 'Activity')));
      break;
    case VoiceServiceType.insurance:
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ExtraServicesScreen(
                  auth: auth, initialCategory: 'Insurance')));
      break;
  }
}

/// زر مايك صغير يوضع بجانب عنوان «خدماتنا» في الصفحة الرئيسية.
/// يحترم تفضيل الإخفاء نفسه (يُبدَّل من صفحة «المزيد»).
class AssistantMicButton extends StatelessWidget {
  final AuthState auth;
  const AssistantMicButton({super.key, required this.auth});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) => ValueListenableBuilder<bool>(
        valueListenable: AssistantPrefs.hidden,
        builder: (context, hidden, _) {
          // المساعد للمسجّلين فقط — يُخفى تماماً قبل تسجيل الدخول
          if (hidden || !auth.isAuthenticated) return const SizedBox.shrink();
          return Material(
          color: const Color(0xFF0E5A8A),
          borderRadius: BorderRadius.circular(22),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => openVoiceAssistant(context, auth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 19),
                  const SizedBox(width: 6),
                  Text(
                    S.t('مساعد ذكي'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        );
        },
      ),
    );
  }
}

/// زر المساعد الذكي العائم: متحرك بالسحب، لا يغطي المحتوى (يقف على الحافة)،
/// ويمكن إخفاؤه من صفحة «المزيد». بالضغط يفتح الاستماع الصوتي ثم ينفذ الطلب:
/// رحلة طيران → يملأ بحث الطيران ويبحث، فندق → يملأ بحث الفنادق ويبحث،
/// عمرة → يفتح صفحة العمرة، شريحة → يفتح صفحة eSIM.
class AssistantBubble extends StatefulWidget {
  final AuthState auth;
  const AssistantBubble({super.key, required this.auth});

  @override
  State<AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<AssistantBubble>
    with SingleTickerProviderStateMixin {
  static const double _size = 56;
  Offset? _pos; // null = الموضع الافتراضي (أسفل يسار الشاشة فوق شريط التنقل)
  bool _dragging = false;
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    // تحميل كسول للتفضيلات — لا نلمس مسار إقلاع التطبيق إطلاقاً:
    // إن تعذر التحميل يبقى الزر ظاهراً بموضعه الافتراضي (سلوك آمن)
    AssistantPrefs.load().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  Offset _clamp(Offset p, Size area) => Offset(
        p.dx.clamp(4.0, area.width - _size - 4),
        p.dy.clamp(4.0, area.height - _size - 4),
      );

  Future<void> _openAssistant() async {
    final q = await showModalBottomSheet<VoiceQuery>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => AssistantVoiceSheet(api: widget.auth.api),
    );
    if (q == null || !mounted) return;

    switch (q.type) {
      case VoiceServiceType.flight:
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  FlightsScreen(auth: widget.auth, initialVoiceQuery: q)),
        );
        break;
      case VoiceServiceType.hotel:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HotelsScreen(
              auth: widget.auth,
              initialCity: q.hotelCity,
              initialCheckIn: q.checkIn,
              initialCheckOut: q.checkOut,
              initialRooms: q.rooms,
              initialAdults: q.adults,
            ),
          ),
        );
        break;
      case VoiceServiceType.umrah:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => UmrahScreen(auth: widget.auth)));
        break;
      case VoiceServiceType.esim:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => EsimScreen(auth: widget.auth)));
        break;
      case VoiceServiceType.carRental:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => CarRentalScreen(auth: widget.auth)));
        break;
      case VoiceServiceType.transfer:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => AirportTransferScreen(auth: widget.auth)));
        break;
      case VoiceServiceType.activity:
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ExtraServicesScreen(
                    auth: widget.auth, initialCategory: 'Activity')));
        break;
      case VoiceServiceType.insurance:
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ExtraServicesScreen(
                    auth: widget.auth, initialCategory: 'Insurance')));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AssistantPrefs.hidden,
      builder: (context, hidden, _) {
        if (hidden) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final area = Size(constraints.maxWidth, constraints.maxHeight);
            final pos = _clamp(
              _pos ?? AssistantPrefs.savedPos ?? Offset(12, area.height - _size - 96),
              area,
            );
            return Positioned(
              left: pos.dx,
              top: pos.dy,
              child: GestureDetector(
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (d) =>
                    setState(() => _pos = _clamp(pos + d.delta, area)),
                onPanEnd: (_) {
                  setState(() => _dragging = false);
                  AssistantPrefs.savePos(_pos ?? pos);
                },
                onTap: _openAssistant,
                child: AnimatedBuilder(
                  animation: _glow,
                  builder: (_, __) => Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [RtTheme.primaryMid, RtTheme.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: RtTheme.accent
                              .withValues(alpha: _dragging ? 0.2 : 0.25 + 0.25 * _glow.value),
                          blurRadius: 14,
                          spreadRadius: 1 + 2 * _glow.value,
                        ),
                      ],
                      border: Border.all(color: RtTheme.accent, width: 2),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.white, size: 28),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// مفتاح إظهار/إخفاء زر المساعد — يوضع في صفحة «المزيد»
class AssistantVisibilityTile extends StatelessWidget {
  const AssistantVisibilityTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AssistantPrefs.hidden,
      builder: (context, hidden, _) => SwitchListTile(
        secondary: const Icon(Icons.mic_external_on_outlined,
            color: RtTheme.primaryMid),
        title: Text(S.t('زر المساعد الذكي العائم'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(S.t('يظهر في الصفحة الرئيسية ويتحرك بالسحب')),
        value: !hidden,
        onChanged: (v) => AssistantPrefs.setHidden(!v),
      ),
    );
  }
}
