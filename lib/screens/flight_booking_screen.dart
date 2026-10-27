import 'package:flutter/material.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../birth_rules.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';
import '../widgets/tlync_hint.dart';

class FlightBookingScreen extends StatefulWidget {
  final AuthState auth;
  final int providerId;
  final String flightId, classCode, from, to, departDate;
  final num price;
  final String currency;
  final String? returnFlightId, returnClassCode, returnDate;
  final bool roundTrip;
  final int adults, children, infants;

  /// الرحلة والأجرة المختارتان — تُستخدمان لجلب التسعيرة الحية من شركة الطيران
  /// (أسعار الطفل والرضيع الفعلية بدل خصومات قاعدة البيانات) ولعرض شروط الأجرة.
  final FlightOption? outFlight;
  final FareOption? outFare;
  final FlightOption? retFlight;
  final FareOption? retFare;

  const FlightBookingScreen({
    super.key,
    required this.auth,
    required this.providerId,
    required this.flightId,
    required this.classCode,
    required this.from,
    required this.to,
    required this.departDate,
    required this.price,
    required this.currency,
    this.returnFlightId,
    this.returnClassCode,
    this.returnDate,
    required this.roundTrip,
    required this.adults,
    required this.children,
    required this.infants,
    this.outFlight,
    this.outFare,
    this.retFlight,
    this.retFare,
  });

  @override
  State<FlightBookingScreen> createState() => _FlightBookingScreenState();
}

class _PassengerForm {
  String title = 'MR';
  int type; // 0=Adult 1=Child 2=Infant
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final passport = TextEditingController();
  final nationality = TextEditingController(text: 'LY');
  /// تاريخ الميلاد — إجباري للطفل والرضيع ويُطابَق مع العمر يومَي السفر
  DateTime? dob;
  _PassengerForm(this.type);
}

class _FlightBookingScreenState extends State<FlightBookingScreen> {
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _coupon = TextEditingController();
  late final List<_PassengerForm> _passengers;
  bool _issueTicket = true;
  bool _holdAllowed = true; // سياسة الإدارة للحجز المبدئي — تُجلب من الخادم
  bool _busy = false;
  Map<String, dynamic>? _result;
  String? _error;

  List<dynamic> _travelers = [];
  Map<String, dynamic>? _couponResult;
  bool _couponBusy = false;

  /// التسعيرة الحية من شركة الطيران (VRS QQ) — سعر كل نوع مسافر الفعلي
  Map<String, dynamic>? _quote;
  bool _quoteLoading = false;

  @override
  void initState() {
    super.initState();
    _passengers = [
      for (var i = 0; i < widget.adults; i++) _PassengerForm(0),
      for (var i = 0; i < widget.children; i++) _PassengerForm(1),
      for (var i = 0; i < widget.infants; i++) _PassengerForm(2),
    ];
    _loadTravelers();
    _loadQuote();
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

  /// يجلب السعر النهائي من شركة الطيران مباشرة — يشمل أسعار الطفل والرضيع
  /// الحقيقية من رد شركة الطيران (FareStore) وليس خصومات مسجلة محلياً.
  Future<void> _loadQuote() async {
    final out = widget.outFlight;
    if (out == null || widget.outFare == null) return;
    setState(() => _quoteLoading = true);
    try {
      final q = await widget.auth.api.partyQuote({
        'apiProviderId': widget.providerId,
        'outAirlineCode': out.airlineCode,
        'outFlightNumber': out.flightNumber,
        'outClassCode': widget.classCode,
        'outDepartDate': widget.departDate,
        'outDepartTime': out.departTime,
        'outArriveTime': out.arriveTime,
        if (widget.outFare!.bandName.isNotEmpty)
          'outClassBandName': widget.outFare!.bandName,
        'fromAirport': widget.from,
        'toAirport': widget.to,
        if (widget.roundTrip && widget.retFlight != null && widget.returnDate != null) ...{
          'retAirlineCode': widget.retFlight!.airlineCode,
          'retFlightNumber': widget.retFlight!.flightNumber,
          'retClassCode': widget.returnClassCode ?? widget.classCode,
          'retDepartDate': widget.returnDate,
          'retDepartTime': widget.retFlight!.departTime,
          'retArriveTime': widget.retFlight!.arriveTime,
          if ((widget.retFare?.bandName ?? '').isNotEmpty)
            'retClassBandName': widget.retFare!.bandName,
        },
        'adults': widget.adults,
        'children': widget.children,
        'infants': widget.infants,
      });
      if (!mounted) return;
      if (q['success'] == true && ((q['grandTotal'] as num?) ?? 0) > 0) {
        setState(() => _quote = q);
      }
    } catch (_) {
      // التسعيرة الحية محاولة إضافية — يبقى السعر التقديري معروضاً عند الفشل
    } finally {
      if (mounted) setState(() => _quoteLoading = false);
    }
  }

  /// السعر الأساسي المعروض: النهائي من شركة الطيران إن وصل، وإلا التقديري
  num get _basePrice =>
      _quote != null ? ((_quote!['grandTotal'] as num?) ?? widget.price) : widget.price;

  String get _displayCurrency {
    final c = _quote?['currency']?.toString() ?? '';
    return c.isNotEmpty ? c : widget.currency;
  }

  Future<void> _loadTravelers() async {
    try {
      final list = await widget.auth.api.travelers();
      if (mounted) setState(() => _travelers = list);
    } catch (_) {}
  }

  void _fillFromTraveler(_PassengerForm p, int id) {
    final t = _travelers.firstWhere((x) => x['id'] == id, orElse: () => null);
    if (t == null) return;
    p.title = (t['title'] ?? 'Mr').toString().toUpperCase();
    p.firstName.text = (t['firstName'] ?? '').toString();
    p.lastName.text = (t['lastName'] ?? '').toString();
    p.passport.text = (t['passportNumber'] ?? '').toString();
    p.nationality.text = _nationalityToIso2((t['nationality'] ?? '').toString());
    p.dob = DateTime.tryParse((t['birthDate'] ?? '').toString());
    setState(() {});
  }

  /// تحويل الجنسية (اسم عربي أو رمز ثلاثي) إلى الرمز الثنائي
  static String _nationalityToIso2(String value) {
    const map = {
      'LBY': 'LY', 'ليبي': 'LY', 'ليبيا': 'LY',
      'EGY': 'EG', 'مصري': 'EG', 'مصر': 'EG',
      'TUN': 'TN', 'تونسي': 'TN', 'تونس': 'TN',
      'DZA': 'DZ', 'جزائري': 'DZ',
      'MAR': 'MA', 'مغربي': 'MA',
      'TUR': 'TR', 'تركي': 'TR', 'تركيا': 'TR',
      'SAU': 'SA', 'سعودي': 'SA',
      'JOR': 'JO', 'أردني': 'JO',
      'SDN': 'SD', 'سوداني': 'SD',
      'SYR': 'SY', 'سوري': 'SY',
      'PSE': 'PS', 'فلسطيني': 'PS',
      'IRQ': 'IQ', 'عراقي': 'IQ',
      'YEM': 'YE', 'يمني': 'YE',
      'GBR': 'GB', 'USA': 'US',
    };
    final v = value.trim();
    if (map.containsKey(v)) return map[v]!;
    if (v.length == 2) return v.toUpperCase();
    return 'LY';
  }

  /// السعر المعروض بعد القسيمة — يتغير أمام المستخدم فور تطبيقها
  num get _finalPrice {
    if (_couponResult?['valid'] == true) {
      final d = (_couponResult!['discount'] as num?) ?? 0;
      return (_basePrice - d).clamp(0, _basePrice);
    }
    return _basePrice;
  }

  Future<void> _checkCoupon() async {
    if (_coupon.text.trim().isEmpty) return;
    setState(() {
      _couponBusy = true;
      _couponResult = null;
    });
    try {
      final r = await widget.auth.api
          .validateCoupon(_coupon.text.trim(), 'Flight', _basePrice);
      setState(() => _couponResult = r);
    } on ApiException catch (e) {
      setState(() => _couponResult = {'valid': false, 'message': e.message});
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
  }

  Future<void> _submit() async {
    if (_passengers.any(
        (p) => p.firstName.text.trim().isEmpty || p.lastName.text.trim().isEmpty)) {
      setState(() => _error = S.t('أدخل أسماء جميع المسافرين كما في الجواز.'));
      return;
    }
    // تاريخ الميلاد إجباري للرضيع/الطفل ويُطابَق مع الفئة العمرية
    // في تاريخ الذهاب وتاريخ العودة (عند الذهاب والإياب)
    final depDate = DateTime.tryParse(widget.departDate) ?? DateTime.now();
    final retDate = DateTime.tryParse(widget.returnDate ?? '');
    for (final p in _passengers) {
      final dobError = BirthRules.validate(p.type, p.dob, depDate, retDate);
      if (dobError != null) {
        setState(() => _error = S.t(dobError));
        return;
      }
    }
    if (_email.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _error = S.t('أدخل البريد الإلكتروني ورقم الهاتف.'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await widget.auth.api.createBooking({
        'apiProviderId': widget.providerId,
        'outboundFlightId': widget.flightId,
        'outboundClassCode': widget.classCode,
        'returnFlightId': widget.returnFlightId,
        'returnClassCode': widget.returnClassCode,
        'tripType': widget.roundTrip && widget.returnFlightId != null ? 1 : 0,
        'fromAirport': widget.from,
        'toAirport': widget.to,
        'departDate': widget.departDate,
        'returnDate': widget.returnDate,
        'paymentMethod': 0, // Wallet
        'issueTicket': _issueTicket,
        'couponCode': _couponResult?['valid'] == true ? _coupon.text.trim() : null,
        'contactEmail': _email.text.trim(),
        'contactPhone': _phone.text.trim(),
        'passengers': [
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
        ],
      });
      setState(() => _result = result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('إتمام الحجز'))),
      body: _result != null
          ? _resultView()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: const Color(0xFFEEF3F7),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.roundTrip && widget.returnFlightId != null
                              ? '${widget.from} ⇄ ${widget.to}'
                              : '${widget.from} ← ${widget.to}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                            '${widget.departDate}${widget.returnDate != null ? ' — ${S.t('العودة')} ${widget.returnDate}' : ''}'),
                        const SizedBox(height: 6),
                        // حالة التسعيرة الحية من شركة الطيران
                        if (_quoteLoading)
                          Row(children: [
                            const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text(S.t('جارٍ جلب السعر النهائي…'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade700)),
                          ]),
                        if (_quote != null) ...[
                          const SizedBox(height: 6),
                          // تفصيل السعر حسب نوع المسافر — من تسعيرة شركة الطيران مباشرة
                          _quoteRow('🧍 ${S.t('بالغ')}', widget.adults,
                              (_quote!['adultUnitTotal'] as num?)),
                          if (widget.children > 0)
                            _quoteRow('🧒 ${S.t('طفل')}', widget.children,
                                (_quote!['childUnitTotal'] as num?)),
                          if (widget.infants > 0)
                            _quoteRow('👶 ${S.t('رضيع')}', widget.infants,
                                (_quote!['infantUnitTotal'] as num?)),
                          const Divider(height: 14),
                        ],
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (_couponResult?['valid'] == true) ...[
                              Text(
                                Money.fmt0(_basePrice, _displayCurrency),
                                style: const TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            Text(
                              Money.fmt0(_finalPrice, _displayCurrency),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0E3A5D),
                              ),
                            ),
                            if (_quote == null && !_quoteLoading)
                              Text('(${S.t('تقديري')})',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey.shade600)),
                            if (_couponResult?['valid'] == true) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E7A45),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '🎟 -${Money.fmt0(((_couponResult!['discount'] as num?) ?? 0), _displayCurrency)}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // شروط الرحلة والأمتعة المسموحة — نصوص فئة الأجرة من شركة الطيران
                if ((widget.outFare?.fareRules.isNotEmpty ?? false) ||
                    (widget.retFare?.fareRules.isNotEmpty ?? false))
                  Card(
                    color: const Color(0xFFFFFDF5),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🧳 ${S.t('الأمتعة وشروط الأجرة')}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 6),
                          if (widget.outFare?.fareRules.isNotEmpty ?? false) ...[
                            if (widget.roundTrip && widget.retFare != null)
                              Text('${S.t('الذهاب')} — ${widget.outFare!.classBandName}',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700)),
                            for (final r in widget.outFare!.fareRules)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('• $r',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey.shade800)),
                              ),
                          ],
                          if (widget.roundTrip &&
                              widget.retFare != null &&
                              widget.retFare!.fareRules.isNotEmpty &&
                              widget.retFare!.classBandName != widget.outFare?.classBandName) ...[
                            const SizedBox(height: 8),
                            Text('${S.t('العودة')} — ${widget.retFare!.classBandName}',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade700)),
                            for (final r in widget.retFare!.fareRules)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('• $r',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey.shade800)),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                for (var i = 0; i < _passengers.length; i++) _paxCard(i),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                      labelText: S.t('البريد الإلكتروني'),
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: S.t('رقم الهاتف'), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                // قسيمة التخفيض
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _coupon,
                        decoration: InputDecoration(
                            labelText: S.t('🎟 قسيمة تخفيض (اختياري)'),
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _couponBusy ? null : _checkCoupon,
                      child: Text(_couponBusy ? '…' : S.t('تطبيق')),
                    ),
                  ],
                ),
                if (_couponResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _couponResult!['message']?.toString() ?? '',
                      style: TextStyle(
                        color: _couponResult!['valid'] == true
                            ? Colors.green.shade700
                            : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_holdAllowed)
                  SwitchListTile(
                    title: Text(S.t('إصدار فوري من المحفظة')),
                    subtitle: Text(
                        S.t('عند الإيقاف يكون الحجز مؤقتاً (PNR) بدون خصم')),
                    value: _issueTicket,
                    onChanged: (v) => setState(() => _issueTicket = v),
                  ),
                if (_error != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child:
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                  TlyncHint(auth: widget.auth, error: _error),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(_busy
                          ? S.t('جاري تنفيذ الحجز…')
                          : '${S.t('تأكيد الحجز')} — ${Money.fmt0(_finalPrice, _displayCurrency)}'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// سطر في تفصيل التسعيرة المؤكدة: النوع × العدد = الإجمالي (سعر الواحد من شركة الطيران)
  Widget _quoteRow(String label, int count, num? unitTotal) {
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label × $count',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800)),
          Text(
            unitTotal != null
                ? '${Money.fmt0(unitTotal, _displayCurrency)} × $count = ${Money.fmt0(unitTotal * count, _displayCurrency)}'
                : '—',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _paxCard(int index) {
    final p = _passengers[index];
    final typeName = p.type == 0 ? S.t('بالغ') : (p.type == 1 ? S.t('طفل') : S.t('رضيع'));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${S.t('مسافر')} ${index + 1} — $typeName',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_travelers.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: S.t('👥 تعبئة من المسافرين المحفوظين'),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final t in _travelers)
                    DropdownMenuItem<int>(
                      value: t['id'] as int,
                      child: Text('${t['firstName']} ${t['lastName']}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => id == null ? null : _fillFromTraveler(p, id),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: p.firstName,
                    decoration: InputDecoration(
                        labelText: S.t('الاسم الأول'),
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: p.lastName,
                    decoration: InputDecoration(
                        labelText: S.t('اسم العائلة'),
                        border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: p.passport,
                    decoration: InputDecoration(
                        labelText: S.t('رقم الجواز (اختياري)'),
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: p.nationality,
                    decoration: InputDecoration(
                        labelText: S.t('الجنسية'),
                        hintText: 'LY',
                        border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // تاريخ الميلاد — إجباري للطفل والرضيع (يُطابَق مع العمر يومَي السفر)
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

  Widget _resultView() {
    final success = _result!['success'] == true;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(success ? Icons.check_circle : Icons.error,
                size: 72, color: success ? Colors.green : Colors.red),
            const SizedBox(height: 16),
            Text(success ? S.t('تم الحجز بنجاح!') : S.t('تعذر إتمام الحجز'),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if ((_result!['bookingReference'] ?? '').toString().isNotEmpty)
              Text('${S.t('رقم الحجز:')} ${_result!['bookingReference']}',
                  style: const TextStyle(fontSize: 16)),
            Text(_result!['message']?.toString() ?? ''),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              child: Text(S.t('العودة للرئيسية')),
            ),
          ],
        ),
      ),
    );
  }
}
