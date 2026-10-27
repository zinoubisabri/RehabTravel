import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'api_client.dart';
import 'main.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// نتيجة تحليل الأمر الصوتي: «رحلة من معيتيقة إلى اسطنبول بتاريخ 22-10»
class VoiceFlightQuery {
  final String? fromCode;
  final String? toCode;
  final DateTime? departDate;
  final bool roundTrip;
  final String rawText;

  const VoiceFlightQuery({
    this.fromCode,
    this.toCode,
    this.departDate,
    this.roundTrip = false,
    this.rawText = '',
  });

  bool get isComplete => fromCode != null && toCode != null && departDate != null;
}

/// تحليل نص عربي إلى وجهة وتاريخ — يعمل محلياً بدون خادم.
class VoiceFlightParser {
  /// أشهر المدن/المطارات الليبية والعربية → كود IATA (عامة: يستخدمها محلل المساعد العام)
  static const Map<String, String> cities = {

    'معيتيقة': 'MJI', 'معيتيقه': 'MJI',
    'طرابلس': 'TIP', // افتراضي: طرابلس = معيتيقة أدناه نصياً
    'بنينا': 'BEN', 'بنغازي': 'BEN', 'بن غازي': 'BEN',
    'مصراتة': 'MRA', 'مصراته': 'MRA',
    'سبها': 'SEB', 'صبها': 'SEB',
    'البيضاء': 'LAQ', 'لباق': 'LAQ',
    'الكفرة': 'AKF',
    'طبرق': 'TOB',
    'اسطنبول': 'IST', 'إسطنبول': 'IST', 'استانبول': 'IST',
    'انقرة': 'ESB', 'أنقرة': 'ESB',
    'تونس': 'TUN', 'قرطاج': 'TUN',
    'القاهرة': 'CAI', 'قاهرة': 'CAI',
    'الاسكندرية': 'HBE', 'الإسكندرية': 'HBE', 'اسكندرية': 'HBE',
    'جدة': 'JED', 'جده': 'JED',
    'الرياض': 'RUH',
    'المدينة': 'MED', 'المدينة المنورة': 'MED',
    'مكة': 'JED',
    'دبي': 'DXB',
    'ابوظبي': 'AUH', 'أبوظبي': 'AUH', 'ابو ظبي': 'AUH',
    'الدوحة': 'DOH', 'دوحة': 'DOH',
    'عمان': 'AMM', 'عمّان': 'AMM',
    'بيروت': 'BEY',
    'الدار البيضاء': 'CMN', 'كازابلانكا': 'CMN',
    'الجزائر': 'ALG',
    'الخرطوم': 'KRT',
    'لندن': 'LHR',
    'باريس': 'CDG',
    'روما': 'FCO',
    'مدريد': 'MAD',
    'برلين': 'BER',
    'فرانكفورت': 'FRA',
    'مالطا': 'MLA',
    'أثينا': 'ATH', 'اثينا': 'ATH',
    'المنامة': 'BAH',
    'الكويت': 'KWI',
    'مسقط': 'MCT',
    'شرم الشيخ': 'SSH',
    'الغردقة': 'HRG',
    'مرسى علم': 'RMF',
    'عنتاب': 'GZT', 'غازي عنتاب': 'GZT',
    'طرابزون': 'TZX',
  };

  /// تحليل النص. يعيد null إذا لم يُفهم شيء.
  static VoiceFlightQuery? parse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    text = text
        .replaceAll('إلى', ' الى ')
        .replaceAll('الي', ' الى ')
        .replaceAll('  ', ' ');

    String? fromCode;
    String? toCode;

    // نبحث عن «من <مدينة> الى <مدينة>»
    final m = RegExp(r'من\s+(.+?)\s+الى\s+(.+?)(?:\s+(?:بتاريخ|تاريخ|يوم|غدا|بعد|ذهاب|رجوع|الى)\b|$)')
        .firstMatch(text);
    String? fromName;
    String? toName;
    if (m != null) {
      fromName = m.group(1);
      toName = m.group(2);
    } else {
      // صيغة أقصر: «معيتيقة اسطنبول»
      final found = <MapEntry<String, String>>[];
      for (final e in cities.entries) {
        if (text.contains(e.key)) found.add(e);
      }
      if (found.length >= 2) {
        fromName = found[0].key;
        toName = found[1].key;
      }
    }

    if (fromName != null) fromCode = _resolveCity(fromName);
    if (toName != null) toCode = _resolveCity(toName);

    // التاريخ: 22-10 أو 22/10 أو «غداً» أو «بعد غد» أو «يوم 22»
    DateTime? date;
    final now = DateTime.now();
    if (text.contains('بعد غد')) {
      date = now.add(const Duration(days: 2));
    } else if (text.contains('غدا')) {
      date = now.add(const Duration(days: 1));
    } else {
      final dm = RegExp(r'(\d{1,2})\s*[-/\.]\s*(\d{1,2})').firstMatch(text);
      if (dm != null) {
        final d = int.tryParse(dm.group(1)!);
        final mo = int.tryParse(dm.group(2)!);
        if (d != null && mo != null && d >= 1 && d <= 31 && mo >= 1 && mo <= 12) {
          var year = now.year;
          var dt = DateTime(year, mo, d);
          if (dt.isBefore(DateTime(now.year, now.month, now.day))) {
            dt = DateTime(year + 1, mo, d); // التاريخ مضى هذه السنة → السنة القادمة
          }
          date = dt;
        }
      } else {
        final dayOnly = RegExp(r'يوم\s+(\d{1,2})').firstMatch(text);
        if (dayOnly != null) {
          final d = int.tryParse(dayOnly.group(1)!);
          if (d != null && d >= 1 && d <= 31) {
            var dt = DateTime(now.year, now.month, d);
            if (dt.isBefore(DateTime(now.year, now.month, now.day))) {
              dt = DateTime(now.year, now.month + 1, d);
            }
            date = dt;
          }
        }
      }
    }

    final roundTrip = text.contains('ذهاب وعودة') || text.contains('ذهاب و عودة');
    if (fromCode == null && toCode == null && date == null) return null;
    return VoiceFlightQuery(
      fromCode: fromCode,
      toCode: toCode,
      departDate: date,
      roundTrip: roundTrip,
      rawText: input,
    );
  }

  static String? _resolveCity(String name) {
    final n = name.trim();
    // الأطول أولاً حتى تتغلب «المدينة المنورة» على «المدينة»
    final entries = cities.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final e in entries) {
      if (n.contains(e.key)) return e.value;
    }
    return null;
  }
}

/// التقاط الصوت بالعربية عبر speech_to_text على الجهاز.
class VoiceCapture {
  final SpeechToText _speech = SpeechToText();
  bool _ready = false;

  bool get isListening => _speech.isListening;

  Future<bool> init() async {
    try {
      _ready = await _speech.initialize();
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// يبدأ الاستماع. onText يُستدعى مع كل نتيجة جزئية/نهائية.
  Future<void> start(void Function(String text, bool isFinal) onText) async {
    if (!_ready) return;
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) =>
          onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: 'ar-SA',
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> stop() async => _speech.stop();
}

// =====================================================================
// المساعد الذكي العام — يفهم كل الخدمات: الطيران والفنادق والعمرة والشرائح وكراء السيارات والنقل المطاري والجولات والتأمين
// =====================================================================

/// نوع الخدمة المطلوبة صوتياً
enum VoiceServiceType { flight, hotel, umrah, esim, carRental, transfer, activity, insurance }

/// نتيجة تحليل عامة لكل الخدمات
class VoiceQuery {
  final VoiceServiceType type;
  // طيران
  final String? fromCode;
  final String? toCode;
  final DateTime? departDate;
  final bool roundTrip;
  // فنادق
  final String? hotelCity;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int rooms;
  final int adults;

  final String rawText;

  const VoiceQuery({
    required this.type,
    this.fromCode,
    this.toCode,
    this.departDate,
    this.roundTrip = false,
    this.hotelCity,
    this.checkIn,
    this.checkOut,
    this.rooms = 1,
    this.adults = 2,
    this.rawText = '',
  });

  bool get flightComplete =>
      type == VoiceServiceType.flight &&
      fromCode != null && toCode != null && departDate != null;
  bool get hotelComplete =>
      type == VoiceServiceType.hotel && hotelCity != null && checkIn != null;
}

/// محلل موحّد: يحدد الخدمة من الكلمات ثم يستخرج التفاصيل — محلي بالكامل،
/// ويفهم أي لهجة عربية لأن التحويل الصوتي يتم على الجهاز (ar-SA يفهم اللهجات).
class VoiceAssistantParser {
  static List<DateTime> _dates(String text) {
    final out = <DateTime>[];
    final now = DateTime.now();
    for (final m in RegExp(r'(\d{1,2})\s*[-/\.]\s*(\d{1,2})').allMatches(text)) {
      final d = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      if (d == null || mo == null || d < 1 || d > 31 || mo < 1 || mo > 12) continue;
      var dt = DateTime(now.year, mo, d);
      if (dt.isBefore(DateTime(now.year, now.month, now.day))) {
        dt = DateTime(now.year + 1, mo, d);
      }
      out.add(dt);
    }
    return out;
  }

  static VoiceQuery? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    // ---- نوع الخدمة ----
    final isHotel = text.contains('فندق') || text.contains('فنادق') ||
        text.contains('إقامة') || text.contains('اقامة') ||
        text.contains('غرفة') || text.contains('غرفه');
    final isUmrah = text.contains('عمرة') || text.contains('عمره') ||
        text.contains('معتمر') || text.contains('الحرم');
    final isEsim = text.toLowerCase().contains('esim') ||
        text.contains('شريحة') || text.contains('شريحه') ||
        text.contains('انترنت') || text.contains('إنترنت') ||
        text.contains('شرائح');
    // كراء السيارات
    final isCar = text.contains('سيارة') || text.contains('سياره') ||
        text.contains('كراء') || text.contains('كرا') && text.contains('سيار') ||
        text.contains('استئجار') || text.contains('ايجار') || text.contains('إيجار');
    // النقل من/إلى المطار — قبل الطيران حتى لا تلتقطه كلمات «مطار»
    final isTransfer = text.contains('ترانسفير') ||
        text.contains('من المطار') || text.contains('الى المطار') ||
        text.contains('إلى المطار') || text.contains('للمطار') ||
        (text.contains('مطار') &&
            (text.contains('نقل') || text.contains('توصيل') ||
             text.contains('مشوار') || text.contains('وصلني') || text.contains('خذني')));
    // الجولات والأنشطة
    final isActivity = text.contains('جولة') || text.contains('جوله') ||
        text.contains('جولات') || text.contains('نشاط') || text.contains('انشطة') ||
        text.contains('أنشطة') || text.contains('معالم') || text.contains('رحلة يوم');
    // التأمين على السفر
    final isInsurance = text.contains('تأمين') || text.contains('تامين');

    if (isUmrah && !isHotel) {
      return VoiceQuery(type: VoiceServiceType.umrah, rawText: input);
    }
    if (isInsurance) {
      return VoiceQuery(type: VoiceServiceType.insurance, rawText: input);
    }
    if (isTransfer && !isCar) {
      return VoiceQuery(type: VoiceServiceType.transfer, rawText: input);
    }
    if (isCar) {
      return VoiceQuery(type: VoiceServiceType.carRental, rawText: input);
    }
    if (isActivity) {
      return VoiceQuery(type: VoiceServiceType.activity, rawText: input);
    }
    if (isEsim && !isHotel) {
      return VoiceQuery(type: VoiceServiceType.esim, rawText: input);
    }

    if (isHotel) {
      // المدينة: أول اسم مدينة يظهر في النص
      String? city;
      final entries = VoiceFlightParser.cities.entries.toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));
      for (final e in entries) {
        if (text.contains(e.key)) { city = e.key; break; }
      }

      // التواريخ: أول تاريخ = وصول، ثاني = مغادرة
      final dates = _dates(text);
      DateTime? checkIn = dates.isNotEmpty ? dates[0] : null;
      DateTime? checkOut = dates.length > 1 ? dates[1] : null;
      final now = DateTime.now();
      if (checkIn == null && text.contains('بعد غد')) {
        checkIn = now.add(const Duration(days: 2));
      } else if (checkIn == null && text.contains('غدا')) {
        checkIn = now.add(const Duration(days: 1));
      }
      if (checkIn != null && checkOut == null) {
        checkOut = checkIn.add(const Duration(days: 3));
      }

      // الغرف: «غرفة زوجية» = غرفة لشخصين، «مفردة» = شخص، «غرفتين» = 2
      var rooms = 1, adults = 2;
      if (text.contains('مفردة') || text.contains('مفرده') ||
          text.contains('لشخص واحد')) {
        adults = 1;
      }
      if (text.contains('غرفتين')) rooms = 2;
      if (text.contains('ثلاث غرف') || text.contains('3 غرف')) rooms = 3;

      if (city == null && checkIn == null) return null;
      return VoiceQuery(
        type: VoiceServiceType.hotel,
        hotelCity: city,
        checkIn: checkIn,
        checkOut: checkOut,
        rooms: rooms,
        adults: adults,
        rawText: input,
      );
    }

    // ---- طيران (المحلل الأصلي) ----
    final f = VoiceFlightParser.parse(text);
    if (f == null) return null;
    return VoiceQuery(
      type: VoiceServiceType.flight,
      fromCode: f.fromCode,
      toCode: f.toCode,
      departDate: f.departDate,
      roundTrip: f.roundTrip,
      rawText: input,
    );
  }
}

/// تحويل رد المساعد السحابي (AI API) إلى VoiceQuery — مع fallback محلي عند أي نقص.
class RemoteAssistantParser {
  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static VoiceQuery? parse(Map<String, dynamic> m, String rawText) {
    if (m['success'] == false) return null;
    VoiceServiceType? type;
    switch ((m['type'] ?? '').toString()) {
      case 'flight': type = VoiceServiceType.flight; break;
      case 'hotel': type = VoiceServiceType.hotel; break;
      case 'umrah': type = VoiceServiceType.umrah; break;
      case 'esim': type = VoiceServiceType.esim; break;
      case 'carRental': type = VoiceServiceType.carRental; break;
      case 'transfer': type = VoiceServiceType.transfer; break;
      case 'activity': type = VoiceServiceType.activity; break;
      case 'insurance': type = VoiceServiceType.insurance; break;
    }
    if (type == null) return null;

    final q = VoiceQuery(
      type: type,
      fromCode: (m['fromCode'] ?? '').toString().trim().isEmpty ? null : m['fromCode'].toString().toUpperCase(),
      toCode: (m['toCode'] ?? '').toString().trim().isEmpty ? null : m['toCode'].toString().toUpperCase(),
      departDate: _date(m['departDate']),
      roundTrip: m['roundTrip'] == true,
      hotelCity: (m['hotelCity'] ?? '').toString().trim().isEmpty ? null : m['hotelCity'].toString(),
      checkIn: _date(m['checkIn']),
      checkOut: _date(m['checkOut']),
      rooms: (m['rooms'] as num?)?.toInt() ?? 1,
      adults: (m['adults'] as num?)?.toInt() ?? 2,
      rawText: rawText,
    );

    // الطيران والفنادق تحتاج الحد الأدنى قبل الانتقال — غير ذلك نرجع للمحلل المحلي.
    if (type == VoiceServiceType.flight && !q.flightComplete) return null;
    if (type == VoiceServiceType.hotel && !q.hotelComplete) return null;
    return q;
  }
}

/// لوحة المساعد الذكي — واجهة محادثة احترافية (نص + صوت) متصلة بكل الخدمات.
/// تُغلق راجعةً VoiceQuery لينفذ الطلب فوراً (رحلة/فندق/عمرة/شريحة/سيارة/نقل/نشاط/تأمين).
class AssistantVoiceSheet extends StatefulWidget {
  final ApiClient api;
  const AssistantVoiceSheet({super.key, required this.api});

  @override
  State<AssistantVoiceSheet> createState() => _AssistantVoiceSheetState();
}

class _Msg {
  final String text;
  final bool isUser;
  const _Msg(this.text, {this.isUser = false});
}

class _AssistantVoiceSheetState extends State<AssistantVoiceSheet>
    with SingleTickerProviderStateMixin {
  final _capture = VoiceCapture();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [
    const _Msg(
        'أهلاً بك 👋 أنا مساعد رحاب الذكي — اطلب ما تريد بالكتابة أو بالصوت وسأنفذه فوراً ✨'),
  ];
  bool _micAvailable = false;
  bool _listening = false;
  bool _thinking = false;
  late final AnimationController _pulse;

  static const List<Color> _grad = [
    Color(0xFF14634B),
    Color(0xFF1B6FA8),
    Color(0xFF6A4FD8),
  ];

  static const _services = <(String, IconData, VoiceServiceType)>[
    ('طيران', Icons.flight_takeoff_rounded, VoiceServiceType.flight),
    ('فنادق', Icons.hotel_rounded, VoiceServiceType.hotel),
    ('عمرة', Icons.mosque_rounded, VoiceServiceType.umrah),
    ('شرائح إنترنت', Icons.sim_card_rounded, VoiceServiceType.esim),
    ('كراء سيارات', Icons.directions_car_rounded, VoiceServiceType.carRental),
    ('نقل من المطار', Icons.airport_shuttle_rounded, VoiceServiceType.transfer),
    ('أنشطة وجولات', Icons.local_activity_rounded, VoiceServiceType.activity),
    ('تأمين سفر', Icons.health_and_safety_rounded, VoiceServiceType.insurance),
  ];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    final ok = await _capture.init();
    if (mounted) setState(() => _micAvailable = ok);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  static String _replyFor(VoiceServiceType t) {
    switch (t) {
      case VoiceServiceType.flight:
        return 'تمام ✅ فهمت طلبك — أنقلك الآن إلى رحلات الطيران ✈️';
      case VoiceServiceType.hotel:
        return 'تمام ✅ فهمت طلبك — أنقلك الآن إلى الفنادق 🏨';
      case VoiceServiceType.umrah:
        return 'تمام ✅ — أنقلك الآن إلى باقات العمرة 🕋';
      case VoiceServiceType.esim:
        return 'تمام ✅ — أنقلك الآن إلى شرائح الإنترنت 📱';
      case VoiceServiceType.carRental:
        return 'تمام ✅ — أنقلك الآن إلى كراء السيارات 🚗';
      case VoiceServiceType.transfer:
        return 'تمام ✅ — أنقلك الآن إلى النقل من وإلى المطار 🚕';
      case VoiceServiceType.activity:
        return 'تمام ✅ — أنقلك الآن إلى الأنشطة والجولات 🎟️';
      case VoiceServiceType.insurance:
        return 'تمام ✅ — أنقلك الآن إلى تأمين السفر 🛡️';
    }
  }

  Future<void> _submit(String text) async {
    final input = text.trim();
    if (input.isEmpty || _thinking) return;
    setState(() {
      _input.clear();
      _messages.add(_Msg(input, isUser: true));
      _thinking = true;
    });
    _scrollToEnd();

    VoiceQuery? q;
    try {
      // المسار الأساسي: AI API المدفوع المضبوط من لوحة الإدارة.
      final remote = await widget.api.parseAssistant(input);
      q = RemoteAssistantParser.parse(remote, input);
    } catch (_) {
      // fallback آمن: التحليل المحلي يعمل دائماً عند عدم ضبط المفتاح أو انقطاع الخدمة.
    }
    q ??= VoiceAssistantParser.parse(input);
    if (!mounted) return;

    if (q == null) {
      setState(() {
        _thinking = false;
        _messages.add(const _Msg(
            'لم أفهم طلبك تماماً 🤔 — حدد الخدمة والوجهة والتاريخ، أو اختر الخدمة مباشرة من الأزرار بالأسفل.'));
      });
      _scrollToEnd();
      return;
    }
    await _complete(q);
  }

  Future<void> _complete(VoiceQuery q) async {
    setState(() => _messages.add(_Msg(_replyFor(q.type))));
    _scrollToEnd();
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.pop(context, q);
  }

  Future<void> _pickService(VoiceServiceType t) async {
    if (_thinking) return;
    setState(() {
      _messages.add(
          _Msg(_services.firstWhere((s) => s.$3 == t).$1, isUser: true));
      _thinking = true;
    });
    _scrollToEnd();
    await _complete(VoiceQuery(type: t));
  }

  Future<void> _toggleMic() async {
    if (!_micAvailable || _thinking) return;
    if (_listening) {
      await _capture.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      await _submit(_input.text);
      return;
    }
    setState(() {
      _input.clear();
      _listening = true;
    });
    await _capture.start((text, isFinal) {
      if (!mounted) return;
      setState(() => _input.text = text);
      if (isFinal) {
        unawaited(_capture.stop());
        setState(() => _listening = false);
        unawaited(_submit(text));
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _capture.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: _grad,
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.16),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('مساعد رحاب الذكي',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4ADE80)
                              .withValues(alpha: 0.6 + 0.4 * _pulse.value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('ذكاء اصطناعي • متصل بكل خدماتنا',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11.5)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final isUser = m.isUser;
    return Align(
      alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: _grad,
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                )
              : null,
          color: isUser ? null : const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          m.text,
          style: TextStyle(
              color: isUser ? Colors.white : Colors.black87,
              fontSize: 13.5,
              height: 1.45),
        ),
      ),
    );
  }

  Widget _typingBubble() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final a = (_pulse.value + i / 3) % 1.0;
              final wave = a < 0.5 ? a * 2 : (1 - a) * 2;
              return Container(
                width: 7,
                height: 7,
                margin: EdgeInsets.only(left: i == 2 ? 0 : 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: RtTheme.primaryMid
                      .withValues(alpha: 0.25 + 0.55 * wave),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildMessages() {
    final count = _messages.length + (_thinking ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      itemCount: count,
      itemBuilder: (_, i) {
        if (_thinking && i == count - 1) return _typingBubble();
        return _bubble(_messages[i]);
      },
    );
  }

  Widget _buildChips() {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _services.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = _services[i];
          return ActionChip(
            avatar: Icon(s.$2, size: 16, color: RtTheme.primaryMid),
            label: Text(s.$1,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            backgroundColor: RtTheme.primaryMid.withValues(alpha: 0.08),
            side: BorderSide(
                color: RtTheme.primaryMid.withValues(alpha: 0.25)),
            onPressed: _thinking ? null : () => _pickService(s.$3),
          );
        },
      ),
    );
  }

  Widget _buildInput() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          children: [
            if (_micAvailable) ...[
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => GestureDetector(
                  onTap: _toggleMic,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _listening
                          ? Colors.redAccent
                              .withValues(alpha: 0.85 + 0.15 * _pulse.value)
                          : RtTheme.primaryMid.withValues(alpha: 0.1),
                      boxShadow: _listening
                          ? [
                              BoxShadow(
                                color: Colors.redAccent.withValues(
                                    alpha: 0.35 * _pulse.value),
                                blurRadius: 18,
                                spreadRadius: 4 * _pulse.value,
                              )
                            ]
                          : null,
                    ),
                    child: Icon(
                      _listening ? Icons.stop_rounded : Icons.mic_rounded,
                      color: _listening ? Colors.white : RtTheme.primaryMid,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: _submit,
                readOnly: _listening,
                decoration: InputDecoration(
                  hintText: _listening ? 'أستمع إليك الآن…' : 'اكتب طلبك هنا…',
                  hintStyle:
                      TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  filled: true,
                  fillColor: const Color(0xFFF1F3F5),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _submit(_input.text),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _grad,
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h * 0.78,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMessages()),
            _buildChips(),
            _buildInput(),
          ],
        ),
      ),
    );
  }
}
