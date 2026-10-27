import 'package:flutter/material.dart';

import '../airport_picker.dart';
import '../auth_state.dart';
import '../main.dart';
import '../models.dart';
import '../money.dart';
import '../recent_searches.dart';
import '../strings.dart';
import '../voice_assistant.dart';
import 'flight_results_screen.dart';
import 'multi_city_screen.dart';

/// ساق في محرر الرحلات متعددة المدن
class _LegEdit {
  Airport? from;
  Airport? to;
  DateTime date;
  _LegEdit(this.date);
}

/// صفحة حجز الطيران — بحث كامل (ذهاب/عودة/متعددة) + آخر بحث + مساعد صوتي
class FlightsScreen extends StatefulWidget {
  final AuthState auth;
  /// أمر صوتي جاهز من المساعد الذكي (الصفحة الرئيسية) — يُطبَّق فور تحميل المطارات
  final VoiceQuery? initialVoiceQuery;
  const FlightsScreen({super.key, required this.auth, this.initialVoiceQuery});

  @override
  State<FlightsScreen> createState() => _FlightsScreenState();
}

class _FlightsScreenState extends State<FlightsScreen> {
  // 0 = ذهاب فقط، 1 = ذهاب وعودة، 2 = متعددة
  int _trip = 0;
  Airport? _fromAirport;
  Airport? _toAirport;
  DateTime _depart = DateTime.now().add(const Duration(days: 7));
  DateTime _return = DateTime.now().add(const Duration(days: 14));
  int _adults = 1, _children = 0, _infants = 0;

  final List<_LegEdit> _legs = [];

  List<Airport>? _airports;
  bool _airportsFailed = false;

  List<RecentSearch> _recent = [];

  // ---------- شريط أرخص الأيام (يُحمَّل في الخلفية ولا يبطئ الشاشة) ----------
  List<Map<String, dynamic>>? _calDays;
  String _calRoute = '';

  @override
  void initState() {
    super.initState();
    _loadAirports();
    _loadRecent();
    final now = DateTime.now();
    _legs
      ..add(_LegEdit(now.add(const Duration(days: 7))))
      ..add(_LegEdit(now.add(const Duration(days: 11))));
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadAirports() async {
    try {
      final list = await widget.auth.api.airports();
      if (!mounted) return;
      setState(() {
        _airports = list
            .map((e) => Airport.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _airportsFailed = false;
      });
      // أمر صوتي جاهز من المساعد الذكي — طبّقه بعد توفر قائمة المطارات
      final vq = widget.initialVoiceQuery;
      if (vq != null && vq.type == VoiceServiceType.flight) _applyVoiceQuery(vq);
    } catch (_) {
      if (!mounted) return;
      setState(() => _airportsFailed = true);
    }
  }

  Future<void> _loadRecent() async {
    final items = await RecentSearchesStore.load();
    if (!mounted) return;
    setState(() => _recent = items);
  }

  Future<void> _pickAirport(bool isFrom) async {
    final airports = _airports;
    if (airports == null) return;
    final selected = await Navigator.push<Airport>(
      context,
      MaterialPageRoute(
        builder: (_) => AirportPickerScreen(
          airports: airports,
          selectedCode: isFrom ? _fromAirport?.code : _toAirport?.code,
        ),
      ),
    );
    if (selected != null) {
      setState(() => isFrom ? _fromAirport = selected : _toAirport = selected);
      _loadFareCalendar();
      // تسهيل البحث: بعد اختيار مطار الذهاب تُفتح مطارات الوصول تلقائياً،
      // وبعد اختيار الوصول يُفتح تاريخ السفر تلقائياً
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;
      if (isFrom) {
        await _pickAirport(false);
      } else {
        await _pickDates();
      }
    }
  }

  Future<void> _pickLegAirport(int index, bool isFrom) async {
    final airports = _airports;
    if (airports == null) return;
    final leg = _legs[index];
    final selected = await Navigator.push<Airport>(
      context,
      MaterialPageRoute(
        builder: (_) => AirportPickerScreen(
          airports: airports,
          selectedCode: isFrom ? leg.from?.code : leg.to?.code,
        ),
      ),
    );
    if (selected != null) {
      setState(() => isFrom ? leg.from = selected : leg.to = selected);
    }
  }

  Future<void> _pickLegDate(int index) async {
    final leg = _legs[index];
    final min = index == 0 ? DateTime.now() : _legs[index - 1].date;
    final picked = await showDatePicker(
      context: context,
      initialDate: leg.date.isBefore(min) ? min : leg.date,
      firstDate: min,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => leg.date = picked);
  }

  Future<void> _pickDates() async {
    if (_trip == 1) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: DateTimeRange(start: _depart, end: _return),
      );
      if (range != null) {
        setState(() {
          _depart = range.start;
          _return = range.end;
        });
      }
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: _depart,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null) setState(() => _depart = picked);
    }
  }

  void _swap() {
    setState(() {
      final tmp = _fromAirport;
      _fromAirport = _toAirport;
      _toAirport = tmp;
    });
    _loadFareCalendar();
  }

  /// تحميل أرخص أسعار الأيام للمسار الحالي — في الخلفية، والفشل لا يؤثر على البحث
  Future<void> _loadFareCalendar() async {
    final from = _fromAirport?.code, to = _toAirport?.code;
    if (_trip == 2 || from == null || to == null || from == to) {
      if (_calDays != null) setState(() { _calDays = null; _calRoute = ''; });
      return;
    }
    final route = '$from-$to';
    if (route == _calRoute) return; // نفس المسار — لا إعادة تحميل
    try {
      final list = await widget.auth.api.fareCalendar(from, to);
      if (!mounted) return;
      setState(() {
        _calRoute = route;
        _calDays = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((d) => ((d['amount'] as num?) ?? 0) > 0)
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _calRoute = route; _calDays = null; });
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _saveRecent() async {
    if (_trip == 2) return; // المتعددة لا تُحفظ في آخر بحث
    await RecentSearchesStore.add(RecentSearch(
      from: _fromAirport!.code,
      to: _toAirport!.code,
      fromLabel: _fromAirport!.displayName(S.isAr),
      toLabel: _toAirport!.displayName(S.isAr),
      departDate: _fmt(_depart),
      returnDate: _trip == 1 ? _fmt(_return) : null,
      roundTrip: _trip == 1,
      pax: _adults + _children + _infants,
    ));
  }

  void _search() async {
    if (_trip == 2) return _searchMulti();
    final from = _fromAirport?.code;
    final to = _toAirport?.code;
    if (from == null || to == null || from == to) {
      _snack(S.t('اختر مطار المغادرة والوصول من القائمة'));
      return;
    }
    await _saveRecent();
    _loadRecent();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FlightResultsScreen(
          auth: widget.auth,
          from: from,
          to: to,
          departDate: _fmt(_depart),
          returnDate: _trip == 1 ? _fmt(_return) : null,
          roundTrip: _trip == 1,
          adults: _adults,
          children: _children,
          infants: _infants,
        ),
      ),
    );
  }

  void _searchMulti() {
    for (final leg in _legs) {
      if (leg.from == null || leg.to == null || leg.from!.code == leg.to!.code) {
        _snack(S.t('أكمل اختيار مطاري كل رحلة'));
        return;
      }
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiCityScreen(
          auth: widget.auth,
          legs: [
            for (final l in _legs)
              MultiCityLeg(
                from: l.from!.code,
                to: l.to!.code,
                fromLabel: l.from!.displayName(S.isAr),
                toLabel: l.to!.displayName(S.isAr),
                date: _fmt(l.date),
              ),
          ],
          adults: _adults,
          children: _children,
          infants: _infants,
        ),
      ),
    );
  }

  void _applyRecent(RecentSearch r) {
    final airports = _airports;
    if (airports == null) return;
    Airport? find(String code) {
      for (final a in airports) {
        if (a.code == code) return a;
      }
      return null;
    }

    final from = find(r.from);
    final to = find(r.to);
    if (from == null || to == null) {
      _snack(S.t('تعذر تطبيق هذا البحث'));
      return;
    }
    setState(() {
      _trip = r.roundTrip ? 1 : 0;
      _fromAirport = from;
      _toAirport = to;
      final d = DateTime.tryParse(r.departDate);
      if (d != null) _depart = d;
      final ret = r.returnDate != null ? DateTime.tryParse(r.returnDate!) : null;
      if (ret != null) _return = ret;
    });
    _loadFareCalendar();
  }

  // ---------------- المساعد الصوتي ----------------

  Future<void> _openVoiceAssistant() async {
    final q = await showModalBottomSheet<VoiceQuery>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => AssistantVoiceSheet(api: widget.auth.api),
    );
    if (q != null && q.type == VoiceServiceType.flight) _applyVoiceQuery(q);
  }

  void _applyVoiceQuery(VoiceQuery q) {
    final airports = _airports;
    if (airports == null) return;
    Airport? find(String? code) {
      if (code == null) return null;
      for (final a in airports) {
        if (a.code == code) return a;
      }
      return null;
    }

    setState(() {
      _trip = q.roundTrip ? 1 : 0;
      final f = find(q.fromCode);
      final t = find(q.toCode);
      if (f != null) _fromAirport = f;
      if (t != null) _toAirport = t;
      if (q.departDate != null) {
        _depart = q.departDate!;
        if (q.roundTrip) _return = q.departDate!.add(const Duration(days: 7));
      }
    });
    _loadFareCalendar();

    if (q.flightComplete) {
      _search(); // بحث تلقائي مباشرة
    } else {
      _snack(S.t('فهمت جزءاً من طلبك — أكمل الحقول الناقصة ثم ابحث'));
    }
  }

  // ---------------- واجهات ----------------

  /// شريط «أرخص الأيام» — لمسة واحدة تعيّن تاريخ المغادرة على أرخص يوم
  Widget _cheapDaysStrip() {
    final days = _calDays;
    if (days == null || days.isEmpty) return const SizedBox.shrink();
    // أرخص سعر لكل يوم
    final byDay = <String, Map<String, dynamic>>{};
    for (final d in days) {
      final dt = DateTime.tryParse(d['date']?.toString() ?? '');
      if (dt == null) continue;
      final amt = (d['amount'] as num?) ?? 0;
      if (amt <= 0) continue;
      final key = _fmt(dt);
      final cur = byDay[key];
      if (cur == null || amt < (cur['amount'] as num)) {
        byDay[key] = {'date': dt, 'amount': amt, 'currency': d['currency']};
      }
    }
    if (byDay.isEmpty) return const SizedBox.shrink();
    final minAmt =
        byDay.values.map((e) => e['amount'] as num).reduce((a, b) => a < b ? a : b);
    final entries = byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 8),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final e = entries[i].value;
          final dt = e['date'] as DateTime;
          final amt = e['amount'] as num;
          final isCheapest = amt == minAmt;
          final isSelected = _fmt(_depart) == _fmt(dt);
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              _depart = dt;
              if (_trip == 1 && _return.isBefore(dt)) {
                _return = dt.add(const Duration(days: 7));
              }
            }),
            child: Container(
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? RtTheme.primaryMid.withOpacity(0.12)
                    : isCheapest
                        ? const Color(0xFFE8F7EE)
                        : const Color(0xFFF6F7F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? RtTheme.primaryMid
                      : isCheapest
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFE3E6EB),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${dt.day}/${dt.month}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  Text(
                    Money.fmt0(amt, e['currency']?.toString()),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isCheapest
                          ? const Color(0xFF16A34A)
                          : RtTheme.primaryMid,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _airportField({
    required String label,
    required IconData icon,
    required Airport? airport,
    required VoidCallback onTap,
  }) {
    final isAr = S.isAr;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: RtTheme.background,
          border: Border.all(color: RtTheme.cardBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: RtTheme.primaryMid),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Text(
                    airport != null
                        ? airport.displayName(isAr)
                        : S.t('اكتب اسم أو كود المطار...'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          airport != null ? FontWeight.w700 : FontWeight.normal,
                      color: airport != null
                          ? RtTheme.primary
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _counter(
      String label, int value, int min, int max, ValueChanged<int> onChanged) {
    const btnStyle = ButtonStyle(
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
      minimumSize: WidgetStatePropertyAll(Size(30, 30)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                style: btnStyle,
                iconSize: 21,
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: value > min ? () => onChanged(value - 1) : null,
              ),
              Text('$value',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                style: btnStyle,
                iconSize: 21,
                icon: const Icon(Icons.add_circle_outline),
                onPressed: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tripTab(int value, IconData icon, String label) {
    final selected = _trip == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _trip = value);
          if (value == 2) {
            setState(() { _calDays = null; _calRoute = ''; });
          } else {
            _loadFareCalendar();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? RtTheme.primaryMid : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 17, color: selected ? Colors.white : Colors.grey),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _multiLegEditor(int i) {
    final leg = _legs[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: RtTheme.cardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: RtTheme.primaryMid,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${S.t('رحلة')} ${i + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (_legs.length > 2)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.redAccent),
                  onPressed: () => setState(() => _legs.removeAt(i)),
                ),
            ],
          ),
          _airportField(
            label: S.t('من'),
            icon: Icons.flight_takeoff,
            airport: leg.from,
            onTap: () => _pickLegAirport(i, true),
          ),
          const SizedBox(height: 6),
          _airportField(
            label: S.t('إلى'),
            icon: Icons.flight_land,
            airport: leg.to,
            onTap: () => _pickLegAirport(i, false),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              alignment: AlignmentDirectional.centerStart,
            ),
            icon: const Icon(Icons.date_range, size: 20),
            label: Text(_fmt(leg.date)),
            onPressed: () => _pickLegDate(i),
          ),
        ],
      ),
    );
  }

  Widget _recentCard(RecentSearch r) {
    return InkWell(
      onTap: () => _applyRecent(r),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: RtTheme.cardBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Flexible(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _cityChip(r.from, r.fromLabel),
                      Icon(
                        r.roundTrip ? Icons.swap_horiz : Icons.arrow_forward,
                        color: RtTheme.primaryMid,
                        size: 20,
                      ),
                      _cityChip(r.to, r.toLabel),
                    ],
                  ),
                ),
                Icon(Icons.person, size: 15, color: Colors.grey.shade600),
                Text(' ${r.pax}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.event, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r.roundTrip && r.returnDate != null
                        ? '${S.t('الذهاب')}: ${r.departDate}   ${S.t('العودة')}: ${r.returnDate}'
                        : '${S.t('الذهاب')}: ${r.departDate}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cityChip(String code, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: RtTheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(code,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13)),
        ),
        const SizedBox(height: 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 84),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('حجز الطيران')),
        actions: [
          IconButton(
            tooltip: S.t('المساعد الصوتي'),
            icon: const Icon(Icons.mic_rounded),
            onPressed: _openVoiceAssistant,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 3,
            shadowColor: Colors.black26,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.t('✈ إلى أين تسافر؟'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),

                  // تبويبات نوع الرحلة
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: RtTheme.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        _tripTab(0, Icons.arrow_forward, S.t('ذهاب فقط')),
                        _tripTab(1, Icons.swap_horiz, S.t('ذهاب وعودة')),
                        _tripTab(2, Icons.alt_route, S.t('متعددة')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_airports == null && !_airportsFailed)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_airportsFailed)
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _airportsFailed = false;
                            _airports = null;
                          });
                          _loadAirports();
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(S.t(
                            'تعذر تحميل قائمة المطارات — إعادة المحاولة')),
                      ),
                    )
                  else if (_trip == 2) ...[
                    // محرر الرحلات المتعددة
                    for (var i = 0; i < _legs.length; i++) _multiLegEditor(i),
                    if (_legs.length < 4)
                      TextButton.icon(
                        onPressed: () => setState(() => _legs.add(_LegEdit(
                            _legs.last.date.add(const Duration(days: 3))))),
                        icon: const Icon(Icons.add_circle_outline),
                        label: Text(S.t('أضف مدينة أخرى')),
                      ),
                  ] else ...[
                    _airportField(
                      label: S.t('من'),
                      icon: Icons.flight_takeoff,
                      airport: _fromAirport,
                      onTap: () => _pickAirport(true),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: IconButton(
                        icon: const Icon(Icons.swap_vert,
                            color: RtTheme.primaryMid),
                        tooltip: S.t('تبديل الاتجاه'),
                        onPressed: _swap,
                      ),
                    ),
                    _airportField(
                      label: S.t('إلى'),
                      icon: Icons.flight_land,
                      airport: _toAirport,
                      onTap: () => _pickAirport(false),
                    ),
                  ],
                  const SizedBox(height: 12),

                  if (_trip != 2)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        alignment: AlignmentDirectional.centerStart,
                      ),
                      icon: const Icon(Icons.date_range),
                      label: Text(_trip == 1
                          ? '${_fmt(_depart)}  ←  ${_fmt(_return)}'
                          : _fmt(_depart)),
                      onPressed: _pickDates,
                    ),
                  if (_trip != 2) _cheapDaysStrip(),
                  if (_trip != 2) const SizedBox(height: 8),

                  Row(
                    children: [
                      _counter(S.t('بالغ'), _adults, 1, 6,
                          (v) => setState(() => _adults = v)),
                      _counter(S.t('طفل'), _children, 0, 4,
                          (v) => setState(() => _children = v)),
                      _counter(S.t('رضيع'), _infants, 0, 2,
                          (v) => setState(() => _infants = v)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.search),
                      label: Text(_trip == 2
                          ? S.t('ابحث عن الرحلات المتعددة')
                          : S.t('ابحث عن رحلات')),
                      onPressed: _airports == null ? null : _search,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // زر المساعد الصوتي
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: RtTheme.primaryMid),
                      ),
                      icon: const Icon(Icons.mic_rounded,
                          color: RtTheme.primaryMid),
                      label: Text(S.t('المساعد — ابحث بصوتك'),
                          style:
                              const TextStyle(color: RtTheme.primaryMid)),
                      onPressed: _openVoiceAssistant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---------- آخر بحث ----------
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(S.t('آخر بحث'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await RecentSearchesStore.clear();
                    _loadRecent();
                  },
                  child: Text(S.t('مسح'),
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
            for (final r in _recent) _recentCard(r),
          ],
        ],
      ),
    );
  }
}
