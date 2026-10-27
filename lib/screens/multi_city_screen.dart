import 'package:flutter/material.dart';

import '../auth_state.dart';
import '../birth_rules.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';
import '../main.dart';

/// ساق واحدة في رحلة متعددة المدن
class MultiCityLeg {
  final String from, to, fromLabel, toLabel, date; // date: yyyy-MM-dd
  const MultiCityLeg({
    required this.from,
    required this.to,
    required this.fromLabel,
    required this.toLabel,
    required this.date,
  });
}

typedef _Offer = ({int providerId, FlightOption flight, FareOption fare});

class _PaxForm {
  String title = 'MR';
  int type;
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final passport = TextEditingController();
  final nationality = TextEditingController(text: 'LY');
  /// تاريخ الميلاد — إجباري للطفل والرضيع ويُطابَق مع العمر في أول وآخر ساق
  DateTime? dob;
  _PaxForm(this.type);
}

/// شاشة الرحلات متعددة المدن: نتائج كل ساق + اختيار رحلة لكل ساق + حجز متسلسل.
class MultiCityScreen extends StatefulWidget {
  final AuthState auth;
  final List<MultiCityLeg> legs;
  final int adults, children, infants;

  const MultiCityScreen({
    super.key,
    required this.auth,
    required this.legs,
    required this.adults,
    required this.children,
    required this.infants,
  });

  @override
  State<MultiCityScreen> createState() => _MultiCityScreenState();
}

class _MultiCityScreenState extends State<MultiCityScreen> {
  // 0 = اختيار الرحلات، 1 = بيانات المسافرين، 2 = النتيجة النهائية
  int _step = 0;

  final List<List<_Offer>> _offers = [];
  final List<String?> _errors = [];
  final List<bool> _loading = [];
  final List<int?> _selected = [];

  late final List<_PaxForm> _passengers;
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _issueTicket = true;
  bool _holdAllowed = true; // سياسة الإدارة للحجز المبدئي — تُجلب من الخادم
  bool _booking = false;
  final List<String> _bookingResults = [];

  @override
  void initState() {
    super.initState();
    _passengers = [
      for (var i = 0; i < widget.adults; i++) _PaxForm(0),
      for (var i = 0; i < widget.children; i++) _PaxForm(1),
      for (var i = 0; i < widget.infants; i++) _PaxForm(2),
    ];
    for (var i = 0; i < widget.legs.length; i++) {
      _offers.add([]);
      _errors.add(null);
      _loading.add(true);
      _selected.add(null);
      _searchLeg(i);
    }
    _loadHoldPermission();
  }

  /// خيار «حجز مبدئي» خاضع لسياسة الإدارة — يُخفى عند منعه ويُفرض الإصدار الفوري
  Future<void> _loadHoldPermission() async {
    final allowed = await widget.auth.api.holdPermission();
    if (!mounted) return;
    setState(() {
      _holdAllowed = allowed;
      if (!allowed) _issueTicket = true;
    });
  }

  Future<void> _searchLeg(int i) async {
    final leg = widget.legs[i];
    try {
      final res = await widget.auth.api.searchFlights(
        from: leg.from,
        to: leg.to,
        departDate: leg.date,
        roundTrip: false,
        adults: widget.adults,
        children: widget.children,
        infants: widget.infants,
      );
      final providers = ((res['providerResults'] ?? []) as List)
          .map((p) => ProviderResult.fromJson(Map<String, dynamic>.from(p)))
          .toList();
      final offers = <_Offer>[
        for (final p in providers)
          for (final f in p.outboundFlights)
            if (f.fares.any((x) => x.isAvailable && x.totalPrice > 0))
              (
                providerId: p.providerId,
                flight: f,
                fare: (f.fares.where((x) => x.isAvailable && x.totalPrice > 0)
                        .toList()
                      ..sort((a, b) => a.totalPrice.compareTo(b.totalPrice)))
                    .first,
              ),
      ]..sort((a, b) => a.fare.totalPrice.compareTo(b.fare.totalPrice));
      if (!mounted) return;
      setState(() {
        _offers[i] = offers;
        _loading[i] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[i] = e.toString();
        _loading[i] = false;
      });
    }
  }

  num get _total {
    num t = 0;
    for (var i = 0; i < _selected.length; i++) {
      final s = _selected[i];
      if (s != null && s < _offers[i].length) t += _offers[i][s].fare.totalPrice;
    }
    return t;
  }

  String get _currency {
    for (var i = 0; i < _selected.length; i++) {
      final s = _selected[i];
      if (s != null && s < _offers[i].length) return _offers[i][s].fare.currency;
    }
    return 'LYD';
  }

  bool get _allSelected =>
      _selected.every((s) => s != null) && !_loading.any((l) => l);

  Future<void> _book() async {
    // تحقق من اكتمال البيانات
    for (final p in _passengers) {
      if (p.firstName.text.trim().isEmpty || p.lastName.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('أدخل أسماء جميع المسافرين كما في الجواز.'))),
        );
        return;
      }
    }
    // تاريخ الميلاد إجباري للرضيع/الطفل ويُطابَق مع الفئة العمرية
    // في تاريخ أول ساق وتاريخ آخر ساق من المسار
    final legDates = widget.legs
        .map((l) => DateTime.tryParse(l.date))
        .whereType<DateTime>()
        .toList()
      ..sort();
    final firstLeg = legDates.isNotEmpty ? legDates.first : DateTime.now();
    final lastLeg = legDates.length > 1 ? legDates.last : null;
    for (final p in _passengers) {
      final dobError = BirthRules.validate(p.type, p.dob, firstLeg, lastLeg);
      if (dobError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t(dobError))),
        );
        return;
      }
    }
    if (_email.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('أدخل البريد الإلكتروني ورقم الهاتف.'))),
      );
      return;
    }

    setState(() {
      _booking = true;
      _bookingResults.clear();
    });

    final paxPayload = [
      for (final p in _passengers)
        {
          'title': p.title,
          'firstName': p.firstName.text.trim().toUpperCase(),
          'lastName': p.lastName.text.trim().toUpperCase(),
          'type': p.type,
          'dateOfBirth': p.dob?.toIso8601String(),
          'passportNumber': p.passport.text.trim(),
          'nationality': p.nationality.text.trim().isEmpty
              ? 'LY'
              : p.nationality.text.trim().toUpperCase(),
          'gender': 'M',
        }
    ];

    for (var i = 0; i < widget.legs.length; i++) {
      final leg = widget.legs[i];
      final offer = _offers[i][_selected[i]!];
      try {
        final result = await widget.auth.api.createBooking({
          'apiProviderId': offer.providerId,
          'outboundFlightId': offer.flight.flightId,
          'outboundClassCode': offer.fare.classCode,
          'tripType': 0,
          'fromAirport': leg.from,
          'toAirport': leg.to,
          'departDate': leg.date,
          'paymentMethod': 0,
          'issueTicket': _issueTicket,
          'contactEmail': _email.text.trim(),
          'contactPhone': _phone.text.trim(),
          'passengers': paxPayload,
        });
        final ok = result['success'] == true;
        final ref = result['bookingReference'] ?? result['pnr'] ?? '';
        _bookingResults.add(ok
            ? '✅ ${leg.fromLabel} ← ${leg.toLabel}: ${S.t('تم الحجز')} ${ref ?? ''}'
            : '❌ ${leg.fromLabel} ← ${leg.toLabel}: ${result['message'] ?? S.t('فشل الحجز')}');
      } catch (e) {
        _bookingResults.add('❌ ${leg.fromLabel} ← ${leg.toLabel}: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _booking = false;
      _step = 2;
    });
  }

  String _fmtDur(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    return '${h}س ${m}د';
  }

  String _hhmm(String timeSpan) =>
      timeSpan.length >= 5 ? timeSpan.substring(0, 5) : timeSpan;

  Widget _offerCard(int legIndex, int offerIndex) {
    final o = _offers[legIndex][offerIndex];
    final selected = _selected[legIndex] == offerIndex;
    return InkWell(
      onTap: () => setState(() => _selected[legIndex] = offerIndex),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? RtTheme.primaryMid.withValues(alpha: 0.08)
              : Colors.white,
          border: Border.all(
            color: selected ? RtTheme.primaryMid : RtTheme.cardBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected ? RtTheme.primaryMid : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${o.flight.airlineName} · ${o.flight.flightNumber}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_hhmm(o.flight.departTime)} ${o.flight.departAirport} → '
                    '${_hhmm(o.flight.arriveTime)} ${o.flight.arriveAirport} · '
                    '${_fmtDur(o.flight.durationMinutes)} · '
                    '${o.flight.stops == 0 ? S.t('مباشرة') : '${o.flight.stops} ${S.t('توقف')}'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Money.fmt0(o.fare.totalPrice, o.fare.currency),
              style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: RtTheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        for (var i = 0; i < widget.legs.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: RtTheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${S.t('رحلة')} ${i + 1}: ${widget.legs[i].fromLabel} ← ${widget.legs[i].toLabel} · ${widget.legs[i].date}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(height: 6),
          if (_loading[i])
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errors[i] != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('${S.t('تعذر البحث')}: ${_errors[i]}'),
            )
          else if (_offers[i].isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(S.t('لا توجد رحلات متاحة في هذا التاريخ')),
            )
          else
            for (var j = 0; j < _offers[i].length && j < 15; j++)
              _offerCard(i, j),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _paxCard(_PaxForm p, int index) {
    final typeName = p.type == 0
        ? S.t('بالغ')
        : p.type == 1
            ? S.t('طفل')
            : S.t('رضيع');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$typeName ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: p.firstName,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                        labelText: S.t('الاسم الأول'),
                        isDense: true,
                        border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: p.lastName,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                        labelText: S.t('اسم العائلة'),
                        isDense: true,
                        border: const OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: p.passport,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                        labelText: S.t('رقم الجواز'),
                        isDense: true,
                        border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: p.nationality,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                        labelText: S.t('الجنسية'),
                        isDense: true,
                        border: const OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // تاريخ الميلاد — إجباري للطفل والرضيع (يُطابَق مع العمر في أول وآخر رحلة)
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: p.dob ??
                      DateTime(now.year -
                          (p.type == 2 ? 1 : (p.type == 1 ? 6 : 25))),
                  firstDate: DateTime(now.year - 100),
                  lastDate: now,
                );
                if (picked != null) setState(() => p.dob = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  labelText: p.type == 0
                      ? S.t('تاريخ الميلاد (اختياري)')
                      : '${S.t('تاريخ الميلاد')} *',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_month),
                ),
                child: Text(
                  p.dob == null
                      ? S.t('اضغط لاختيار التاريخ')
                      : '${p.dob!.year}-${p.dob!.month.toString().padLeft(2, '0')}-${p.dob!.day.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      color: p.dob == null ? Colors.grey.shade500 : null),
                ),
              ),
            ),
            if (p.type != 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  S.t('إلزامي — ويُطابَق مع العمر يومَي الذهاب والعودة'),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaxStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                      labelText: S.t('البريد الإلكتروني'),
                      isDense: true,
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: S.t('رقم الهاتف'),
                      isDense: true,
                      border: const OutlineInputBorder()),
                ),
                if (_holdAllowed)
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(S.t('إصدار التذاكر فوراً'),
                        style: const TextStyle(fontSize: 14)),
                    value: _issueTicket,
                    onChanged: (v) => setState(() => _issueTicket = v),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < _passengers.length; i++) _paxCard(_passengers[i], i),
      ],
    );
  }

  Widget _buildResultStep() {
    final allOk = _bookingResults.every((r) => r.startsWith('✅'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(allOk ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 64, color: allOk ? Colors.green : Colors.orange),
        const SizedBox(height: 10),
        Text(
          allOk ? S.t('تم حجز جميع الرحلات بنجاح') : S.t('اكتملت العملية — راجع التفاصيل'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        for (final r in _bookingResults)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(r, style: const TextStyle(fontSize: 13.5)),
            ),
          ),
        const SizedBox(height: 10),
        FilledButton.icon(
          icon: const Icon(Icons.home),
          label: Text(S.t('العودة للرئيسية')),
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0
            ? S.t('رحلات متعددة — اختر رحلة لكل ساق')
            : _step == 1
                ? S.t('بيانات المسافرين')
                : S.t('نتيجة الحجز')),
      ),
      body: _step == 0
          ? _buildSelectStep()
          : _step == 1
              ? _buildPaxStep()
              : _buildResultStep(),
      bottomSheet: _step == 2
          ? null
          : Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: SafeArea(
                top: false,
                child: _step == 0
                    ? SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(_allSelected
                              ? '${S.t('متابعة')} · ${Money.fmt0(_total, _currency)}'
                              : S.t('اختر رحلة لكل ساق')),
                          onPressed:
                              _allSelected ? () => setState(() => _step = 1) : null,
                        ),
                      )
                    : SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          icon: _booking
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_circle),
                          label: Text(_booking
                              ? S.t('جارٍ الحجز...')
                              : '${S.t('إتمام الحجز')} · ${Money.fmt0(_total, _currency)}'),
                          onPressed: _booking ? null : _book,
                        ),
                      ),
              ),
            ),
    );
  }
}
