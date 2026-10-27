import 'package:flutter/material.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import 'flight_booking_screen.dart';
import '../strings.dart';

class FlightResultsScreen extends StatefulWidget {
  final AuthState auth;
  final String from, to, departDate;
  final String? returnDate;
  final bool roundTrip;
  final int adults, children, infants;

  const FlightResultsScreen({
    super.key,
    required this.auth,
    required this.from,
    required this.to,
    required this.departDate,
    this.returnDate,
    required this.roundTrip,
    required this.adults,
    required this.children,
    required this.infants,
  });

  @override
  State<FlightResultsScreen> createState() => _FlightResultsScreenState();
}

/// ساق واحدة من رحلة (ذهاب أو عودة) مع السعر المعروض
typedef _Leg = ({int providerId, FlightOption flight, FareOption fare});

/// بطاقة مجمّعة: ذهاب + عودة بسعر إجمالي واحد
typedef _Combo = ({_Leg outbound, _Leg returning, num total});

class _FlightResultsScreenState extends State<FlightResultsScreen> {
  bool _loading = true;
  String? _error;
  List<ProviderResult> _providers = [];

  // الفلاتر والترتيب
  String _sort = 'price'; // price / duration / departure
  int? _maxStops; // null = الكل
  String? _airline; // null = الكل
  String? _classBand; // null = الكل (أرخص درجة)

  /// إجمالي سعر الساق الواحدة لكل المسافرين — نفس معادلة الموقع تماماً:
  /// بالغ = السعر الكامل، طفل = الأساس × (1 - خصم الطفل) + الضريبة،
  /// رضيع = الأساس × (1 - خصم الرضيع) + الضريبة.
  num _partyTotal(int providerId, FareOption fare) {
    ProviderResult? provider;
    for (final p in _providers) {
      if (p.providerId == providerId) {
        provider = p;
        break;
      }
    }
    final childMult = 1 - ((provider?.childDiscountPercent ?? 25) / 100);
    final infantMult = 1 - ((provider?.infantDiscountPercent ?? 90) / 100);
    return widget.adults * fare.totalPrice +
        widget.children * (fare.price * childMult + fare.tax) +
        widget.infants * (fare.price * infantMult + fare.tax);
  }

  num _legTotal(_Leg leg) => _partyTotal(leg.providerId, leg.fare);

  /// سطر الوزن/الأمتعة من نصوص فئة الأجرة — أول سطر يذكر الأمتعة أو الكيلو
  String? _baggageOf(FareOption f) {
    for (final r in f.fareRules) {
      final l = r.toLowerCase();
      if (l.contains('kg') || l.contains('luggage') || l.contains('bag')) {
        return r;
      }
    }
    return null;
  }

  /// عرض شروط التذكرة كاملة في لوحة سفلية — ساق واحدة أو ساقين (ذهاب/عودة)
  void _showFareRules(BuildContext context, FareOption f, [FareOption? ret]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '📜 ${S.t('شروط التذكرة')}${ret == null ? ' — ${f.classBandName}' : ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 10),
              if (ret != null)
                Text('${S.t('الذهاب')} — ${f.classBandName}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700)),
              for (final r in f.fareRules)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $r',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade800)),
                ),
              if (ret != null &&
                  ret.fareRules.isNotEmpty &&
                  ret.classBandName != f.classBandName) ...[
                const SizedBox(height: 10),
                Text('${S.t('العودة')} — ${ret.classBandName}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700)),
                for (final r in ret.fareRules)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $r',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade800)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// وصف عدد المسافرين أسفل السعر الإجمالي
  String get _partyLabel {
    final parts = <String>['${widget.adults} ${S.t('بالغ')}'];
    if (widget.children > 0) parts.add('${widget.children} ${S.t('طفل')}');
    if (widget.infants > 0) parts.add('${widget.infants} ${S.t('رضيع')}');
    return parts.join(' + ');
  }

  /// السعر المعروض للرحلة: الأرخص ضمن الدرجة المختارة (أو الأرخص إجمالاً)
  FareOption? _displayFare(FlightOption f) {
    final avail = f.fares.where((x) => x.isAvailable && x.totalPrice > 0).toList()
      ..sort((a, b) => a.totalPrice.compareTo(b.totalPrice));
    if (avail.isEmpty) return null;
    if (_classBand != null) {
      for (final fa in avail) {
        if (fa.classBandName == _classBand) return fa;
      }
      return null; // هذه الرحلة لا توفّر الدرجة المطلوبة
    }
    return avail.first;
  }

  bool _passesFilters(FlightOption f) {
    if (_maxStops != null && f.stops > _maxStops!) return false;
    if (_airline != null && f.airlineCode != _airline) return false;
    return true;
  }

  List<_Leg> _legsOf(List<FlightOption> Function(ProviderResult) pick) {
    final legs = <_Leg>[
      for (final p in _providers)
        for (final f in pick(p))
          if (_passesFilters(f) && _displayFare(f) != null)
            (providerId: p.providerId, flight: f, fare: _displayFare(f)!),
    ];
    // الترتيب الافتراضي بالسعر الإجمالي لكل المسافرين — وليس سعر الشخص الواحد
    legs.sort((a, b) => _legTotal(a).compareTo(_legTotal(b)));
    return legs;
  }

  /// نتائج الذهاب فقط
  List<_Leg> get _outboundOnly {
    final list = _legsOf((p) => p.outboundFlights);
    switch (_sort) {
      case 'duration':
        list.sort((a, b) =>
            a.flight.durationMinutes.compareTo(b.flight.durationMinutes));
        break;
      case 'departure':
        list.sort(
            (a, b) => a.flight.departTime.compareTo(b.flight.departTime));
        break;
      case 'arrival':
        list.sort(
            (a, b) => a.flight.arriveTime.compareTo(b.flight.arriveTime));
        break;
      default:
        break; // مرتبة بالسعر مسبقاً
    }
    return list;
  }

  /// نتائج ذهاب وعودة: نركّب أرخص التوليفات في بطاقة واحدة بسعر إجمالي
  List<_Combo> get _combos {
    // نأخذ أفضل 12 ساقاً من كل اتجاه (بعد الفلاتر) لتفادي انفجار التوليفات
    final outs = _legsOf((p) => p.outboundFlights).take(12).toList();
    final rets = _legsOf((p) => p.returnFlights).take(12).toList();
    final combos = <_Combo>[
      for (final o in outs)
        for (final r in rets)
          if (o.providerId == r.providerId) // نفس المزود لضمان حجز واحد
            (
              outbound: o,
              returning: r,
              // إجمالي الذهاب والعودة لكل المسافرين (بالغ/طفل/رضيع)
              total: _legTotal(o) + _legTotal(r),
            ),
    ];
    switch (_sort) {
      case 'duration':
        combos.sort((a, b) =>
            (a.outbound.flight.durationMinutes +
                    a.returning.flight.durationMinutes)
                .compareTo(b.outbound.flight.durationMinutes +
                    b.returning.flight.durationMinutes));
        break;
      case 'departure':
        combos.sort((a, b) => a.outbound.flight.departTime
            .compareTo(b.outbound.flight.departTime));
        break;
      case 'arrival':
        combos.sort((a, b) => a.outbound.flight.arriveTime
            .compareTo(b.outbound.flight.arriveTime));
        break;
      default:
        combos.sort((a, b) => a.total.compareTo(b.total));
    }
    // نكتفي بأفضل 60 بطاقة
    return combos.take(60).toList();
  }

  /// نافذة الفلاتر والترتيب — تظهر عند الضغط على الزر (مخفية افتراضياً)
  void _openFilters(Map<String, String> airlines, List<String> bands) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(S.t('الترتيب حسب'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 6),
                for (final opt in [
                  ('price', S.t('السعر')),
                  ('duration', S.t('الأسرع')),
                  ('departure', S.t('وقت المغادرة')),
                  ('arrival', S.t('وقت الوصول')),
                ])
                  RadioListTile<String>(
                    dense: true,
                    value: opt.$1,
                    groupValue: _sort,
                    title: Text(opt.$2),
                    secondary: const Icon(Icons.arrow_downward, size: 16),
                    onChanged: (v) {
                      setSheet(() => _sort = v!);
                      setState(() {});
                    },
                  ),
                const Divider(),
                CheckboxListTile(
                  dense: true,
                  value: _maxStops == 0,
                  title: Text(S.t('رحلة مباشرة (بدون توقف)')),
                  onChanged: (v) {
                    setSheet(() => _maxStops = v == true ? 0 : null);
                    setState(() {});
                  },
                ),
                CheckboxListTile(
                  dense: true,
                  value: _maxStops == 1,
                  title: Text(S.t('توقف واحد كحد أقصى')),
                  onChanged: (v) {
                    setSheet(() => _maxStops = v == true ? 1 : null);
                    setState(() {});
                  },
                ),
                if (airlines.length > 1) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonFormField<String?>(
                      value: _airline,
                      decoration:
                          InputDecoration(labelText: S.t('✈ فلتر خطوط الطيران')),
                      items: [
                        DropdownMenuItem(
                            value: null, child: Text(S.t('كل الشركات'))),
                        for (final e in airlines.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) {
                        setSheet(() => _airline = v);
                        setState(() {});
                      },
                    ),
                  ),
                ],
                if (bands.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(S.t('درجة السفر:'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        ChoiceChip(
                          label: Text(S.t('الكل')),
                          selected: _classBand == null,
                          onSelected: (_) {
                            setSheet(() => _classBand = null);
                            setState(() {});
                          },
                        ),
                        for (final b in bands)
                          ChoiceChip(
                            label: Text(b),
                            selected: _classBand == b,
                            onSelected: (_) {
                              setSheet(() => _classBand = b);
                              setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _sort = 'price';
                            _maxStops = null;
                            _airline = null;
                            _classBand = null;
                          });
                          Navigator.pop(ctx);
                        },
                        child: Text(S.t('إعادة الضبط')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0E5A8A)),
                        child: Text(S.t('عرض النتائج')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    try {
      final result = await widget.auth.api.searchFlights(
        from: widget.from,
        to: widget.to,
        departDate: widget.departDate,
        returnDate: widget.returnDate,
        roundTrip: widget.roundTrip,
        adults: widget.adults,
        children: widget.children,
        infants: widget.infants,
      );
      if (!mounted) return;
      setState(() {
        _providers = ((result['providerResults'] ?? []) as List)
            .map((p) => ProviderResult.fromJson(Map<String, dynamic>.from(p)))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = S.t('حدث خطأ أثناء تحميل النتائج — حاول مجدداً');
        _loading = false;
      });
    }
  }

  Future<void> _createPriceAlert() async {
    if (!widget.auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('سجّل الدخول أولاً لإنشاء تنبيه سعر'))),
      );
      return;
    }

    final controller = TextEditingController();
    final target = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('🔔 تنبيه انخفاض السعر')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.from} ← ${widget.to} — ${widget.departDate}'),
            const SizedBox(height: 8),
            Text(S.t('نفحص السعر كل 15 دقيقة ونرسل إشعاراً عند بلوغ هدفك.')),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: '${S.t('السعر المستهدف')} (${Money.symbol})',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(S.t('إلغاء'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, num.tryParse(controller.text)),
              child: Text(S.t('إنشاء'))),
        ],
      ),
    );

    if (target == null || target <= 0) return;
    try {
      await widget.auth.api.createPriceAlert(
        from: widget.from,
        to: widget.to,
        departDate: widget.departDate,
        targetPrice: target,
        currency: Money.active,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(S.t('تم إنشاء التنبيه — سنخبرك فور انخفاض السعر'))),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roundTrip
            ? '${widget.from} ⇄ ${widget.to} — ${widget.departDate}'
            : '${widget.from} ← ${widget.to} — ${widget.departDate}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notification_add_outlined),
            tooltip: S.t('تنبيه انخفاض السعر'),
            onPressed: _createPriceAlert,
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(S.t('نبحث لدى جميع المزودين…')),
                ],
              ),
            )
          : _error != null
              ? Center(child: Text(_error!))
              : _providers.every((p) => p.outboundFlights.isEmpty)
                  ? Center(child: Text(S.t('لا توجد رحلات متاحة لهذا التاريخ')))
                  : Builder(builder: (context) {
                      final airlines = {
                        for (final p in _providers)
                          for (final f in p.outboundFlights)
                            f.airlineCode: f.airlineName
                      };
                      final bands = {
                        for (final p in _providers)
                          for (final f in p.outboundFlights)
                            for (final fa in f.fares)
                              if (fa.isAvailable && fa.classBandName.isNotEmpty)
                                fa.classBandName
                      }.toList()
                        ..sort();

                      final oneway = widget.roundTrip ? <_Leg>[] : _outboundOnly;
                      final combos = widget.roundTrip ? _combos : <_Combo>[];
                      final cheapest = widget.roundTrip
                          ? (combos.isEmpty
                              ? 0
                              : combos
                                  .map((c) => c.total)
                                  .reduce((a, b) => a < b ? a : b))
                          : (oneway.isEmpty
                              ? 0
                              : oneway
                                  .map(_legTotal)
                                  .reduce((a, b) => a < b ? a : b));

                      final resultsCount = widget.roundTrip
                          ? combos.length
                          : oneway.length;
                      final hasActiveFilters = _sort != 'price' ||
                          _maxStops != null ||
                          _airline != null ||
                          _classBand != null;

                      return ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          // شريط الملخص: عدد الرحلات + زر الفلاتر (تظهر عند الضغط)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: const [
                                BoxShadow(
                                    color: Color(0x14000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 2))
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.format_list_numbered_rounded,
                                    size: 19, color: Color(0xFF0E5A8A)),
                                const SizedBox(width: 6),
                                Text('${S.t("عدد الرحلات")} ($resultsCount)',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () =>
                                      _openFilters(airlines, bands),
                                  icon: Icon(Icons.tune_rounded,
                                      size: 18,
                                      color: hasActiveFilters
                                          ? const Color(0xFFD9A441)
                                          : const Color(0xFF0E5A8A)),
                                  label: Text(
                                    hasActiveFilters
                                        ? S.t('الفلاتر • مفعّلة')
                                        : S.t('الفلاتر والترتيب'),
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: hasActiveFilters
                                            ? const Color(0xFFD9A441)
                                            : const Color(0xFF0E5A8A)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          if (widget.roundTrip && combos.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Text(S.t(
                                    'لا توجد توليفات ذهاب وعودة مطابقة — خفف الفلاتر أو جرّب تاريخاً آخر.')),
                              ),
                            ),
                          if (!widget.roundTrip && oneway.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Text(S.t(
                                    'لا توجد نتائج مطابقة للفلاتر — خفف الشروط.')),
                              ),
                            ),

                          for (final c in combos)
                            _comboCard(c, isCheapest: c.total == cheapest),
                          for (final e in oneway)
                            _oneWayCard(e,
                                isCheapest: _legTotal(e) == cheapest),
                        ],
                      );
                    }),
    );
  }

  // ---------- بطاقة ذهاب وعودة مجمّعة ----------
  Widget _comboCard(_Combo c, {bool isCheapest = false}) {
    final out = c.outbound;
    final ret = c.returning;
    final currency = out.fare.currency;

    return Card(
      elevation: isCheapest ? 4 : 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isCheapest
            ? const BorderSide(color: Color(0xFF1E7A45), width: 1.6)
            : BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // الترويسة
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF0E3A5D),
                  child: Text(
                    out.flight.airlineCode.length >= 2
                        ? out.flight.airlineCode.substring(0, 2)
                        : out.flight.airlineCode,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(out.flight.airlineName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (isCheapest)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E7A45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('🏷 ${S.t('أقل سعر')}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // ساق الذهاب
            _legRow(
              label: '${S.t('الذهاب')} • ${widget.departDate}',
              icon: Icons.flight_takeoff,
              flight: out.flight,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Divider(color: Colors.grey.shade300, height: 1),
            ),
            // ساق العودة
            _legRow(
              label: '${S.t('العودة')} • ${widget.returnDate ?? ''}',
              icon: Icons.flight_land,
              flight: ret.flight,
            ),
            const Divider(height: 22),
            // السعر الإجمالي + زر الحجز
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Money.fmt0(c.total, currency),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0E3A5D)),
                      ),
                      Text(
                        '${S.t('إجمالي الذهاب والعودة لـ')} $_partyLabel • ${S.t('تقديري — يُؤكد قبل الدفع')}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700),
                      ),
                      Text(
                        out.fare.classBandName.isNotEmpty
                            ? out.fare.classBandName
                            : out.fare.classCode,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      // الوزن المسموح لكل ساق — ظاهر مباشرة
                      if (_baggageOf(out.fare) != null)
                        Text('🧳 ${S.t('الذهاب')}: ${_baggageOf(out.fare)}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E7A45))),
                      if (_baggageOf(ret.fare) != null)
                        Text('🧳 ${S.t('العودة')}: ${_baggageOf(ret.fare)}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E7A45))),
                      // شروط التذكرة للساقين
                      if (out.fare.fareRules.isNotEmpty ||
                          ret.fare.fareRules.isNotEmpty)
                        GestureDetector(
                          onTap: () => _showFareRules(context, out.fare, ret.fare),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '📜 ${S.t('شروط التذكرة')}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0E3A5D),
                                  decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FlightBookingScreen(
                        auth: widget.auth,
                        providerId: out.providerId,
                        flightId: out.flight.flightId,
                        classCode: out.fare.classCode,
                        returnFlightId: ret.flight.flightId,
                        returnClassCode: ret.fare.classCode,
                        from: widget.from,
                        to: widget.to,
                        departDate: widget.departDate,
                        returnDate: widget.returnDate,
                        roundTrip: true,
                        adults: widget.adults,
                        children: widget.children,
                        infants: widget.infants,
                        price: c.total,
                        currency: currency,
                        outFlight: out.flight,
                        outFare: out.fare,
                        retFlight: ret.flight,
                        retFare: ret.fare,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.airplane_ticket_outlined, size: 18),
                  label: Text(S.t('احجز')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// سطر ساق رحلة داخل البطاقة المجمّعة
  Widget _legRow({
    required String label,
    required IconData icon,
    required FlightOption flight,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF0E3A5D)),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0E3A5D))),
            const Spacer(),
            Text('${flight.airlineCode}${flight.flightNumber}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _time(flight.departTime, flight.departAirport),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${flight.durationMinutes ~/ 60}${S.t('س')} ${flight.durationMinutes % 60}${S.t('د')}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                          child: Divider(
                              color: Colors.grey.shade400, thickness: 1)),
                      Icon(Icons.flight, size: 14, color: Colors.grey.shade500),
                      Expanded(
                          child: Divider(
                              color: Colors.grey.shade400, thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    flight.stops == 0
                        ? S.t('مباشرة')
                        : '${flight.stops} ${S.t('توقف')}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: flight.stops == 0
                          ? const Color(0xFF1E7A45)
                          : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
            _time(flight.arriveTime, flight.arriveAirport),
          ],
        ),
      ],
    );
  }

  // ---------- بطاقة ذهاب فقط ----------
  Widget _oneWayCard(_Leg e, {bool isCheapest = false}) {
    final flight = e.flight;
    final best = e.fare;
    final partyTotal = _legTotal(e); // السعر الإجمالي لكل المسافرين
    final bandName = best.classBandName.isNotEmpty
        ? best.classBandName
        : (best.classCode.isNotEmpty ? best.classCode : S.t('اقتصادية'));

    return Card(
      elevation: isCheapest ? 4 : 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isCheapest
            ? const BorderSide(color: Color(0xFF1E7A45), width: 1.6)
            : BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF0E3A5D),
                  child: Text(
                    flight.airlineCode.length >= 2
                        ? flight.airlineCode.substring(0, 2)
                        : flight.airlineCode,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(flight.airlineName,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${flight.airlineCode}${flight.flightNumber}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                if (isCheapest)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E7A45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('🏷 ${S.t('أقل سعر')}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _time(flight.departTime, flight.departAirport),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${flight.durationMinutes ~/ 60}${S.t('س')} ${flight.durationMinutes % 60}${S.t('د')}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                              child: Divider(
                                  color: Colors.grey.shade400, thickness: 1)),
                          Icon(Icons.flight_takeoff,
                              size: 16, color: Colors.grey.shade500),
                          Expanded(
                              child: Divider(
                                  color: Colors.grey.shade400, thickness: 1)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        flight.stops == 0
                            ? S.t('مباشرة')
                            : '${flight.stops} ${S.t('توقف')}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: flight.stops == 0
                              ? const Color(0xFF1E7A45)
                              : Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                _time(flight.arriveTime, flight.arriveAirport),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Money.fmt0(partyTotal, best.currency),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0E3A5D)),
                      ),
                      Text(
                        '${S.t('الإجمالي لـ')} $_partyLabel • ${S.t('تقديري — يُؤكد قبل الدفع')}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700),
                      ),
                      Text(
                        '$bandName • ${S.t('المقاعد:')} ${best.availableSeats}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      // الوزن المسموح ظاهر مباشرة على البطاقة
                      if (_baggageOf(best) != null)
                        Text(
                          '🧳 ${_baggageOf(best)}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E7A45)),
                        ),
                      // شروط التذكرة — تفتح لوحة بكل الشروط
                      if (best.fareRules.isNotEmpty)
                        GestureDetector(
                          onTap: () => _showFareRules(context, best),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '📜 ${S.t('شروط التذكرة')}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0E3A5D),
                                  decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FlightBookingScreen(
                        auth: widget.auth,
                        providerId: e.providerId,
                        flightId: flight.flightId,
                        classCode: best.classCode,
                        from: widget.from,
                        to: widget.to,
                        departDate: widget.departDate,
                        returnDate: widget.returnDate,
                        roundTrip: false,
                        adults: widget.adults,
                        children: widget.children,
                        infants: widget.infants,
                        price: partyTotal,
                        currency: best.currency,
                        outFlight: flight,
                        outFare: best,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.airplane_ticket_outlined, size: 18),
                  label: Text(S.t('احجز')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _time(String time, String airport) {
    final short = time.length >= 5 ? time.substring(0, 5) : time;
    return Column(
      children: [
        Text(short,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(airport, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
