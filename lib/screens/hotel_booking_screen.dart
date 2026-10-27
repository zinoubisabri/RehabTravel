import 'package:flutter/material.dart';
import '../hotel_text.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';
import '../widgets/tlync_hint.dart';

/// صفحة بيانات المسافرين لحجز الفندق — كاملة كالتطبيقات العالمية:
/// كل نزيل (اسم + لقب + جنسية + جواز) + بيانات التواصل ثم تأكيد من المحفظة
class HotelBookingScreen extends StatefulWidget {
  final AuthState auth;
  final HotelOffer offer;
  final String checkIn;
  final String checkOut;
  final int rooms;
  final int adults;
  final List<int> childrenAges;

  const HotelBookingScreen({
    super.key,
    required this.auth,
    required this.offer,
    required this.checkIn,
    required this.checkOut,
    required this.rooms,
    required this.adults,
    this.childrenAges = const [],
  });

  @override
  State<HotelBookingScreen> createState() => _HotelBookingScreenState();
}

class _GuestForm {
  final firstCtrl = TextEditingController();
  final lastCtrl = TextEditingController();
  final passportCtrl = TextEditingController();
  final nationalityCtrl = TextEditingController(text: 'ليبي');
  String type; // Adult / Child
  int? age;
  _GuestForm(this.type, this.age);
}

class _HotelBookingScreenState extends State<HotelBookingScreen> {
  late final List<_GuestForm> _guests = [
    for (var i = 0; i < widget.adults; i++) _GuestForm('Adult', null),
    for (final age in widget.childrenAges) _GuestForm('Child', age),
  ];

  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _couponCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  List<dynamic> _travelers = [];
  Map<String, dynamic>? _couponResult;
  bool _couponBusy = false;

  @override
  void initState() {
    super.initState();
    _loadTravelers();
    // تسخين السعر لدى المزود فور فتح النموذج — يجهز checkRate قبل ضغط «تأكيد»
    widget.auth.api.warmHotelRate(widget.offer.rateKey, widget.offer.apiProviderId ?? 0);
  }

  Future<void> _loadTravelers() async {
    try {
      final list = await widget.auth.api.travelers();
      if (mounted) setState(() => _travelers = list);
    } catch (_) {}
  }

  void _fillFromTraveler(_GuestForm g, int id) {
    final t = _travelers.firstWhere((x) => x['id'] == id, orElse: () => null);
    if (t == null) return;
    g.firstCtrl.text = (t['firstName'] ?? '').toString();
    g.lastCtrl.text = (t['lastName'] ?? '').toString();
    g.passportCtrl.text = (t['passportNumber'] ?? '').toString();
    final nat = (t['nationality'] ?? '').toString();
    if (nat.isNotEmpty) g.nationalityCtrl.text = nat;
    setState(() {});
  }

  /// السعر المعروض بعد القسيمة — يتغير أمام المستخدم فور تطبيقها
  num get _finalPrice {
    if (_couponResult?['valid'] == true) {
      final d = (_couponResult!['discount'] as num?) ?? 0;
      return (widget.offer.totalPrice - d).clamp(0, widget.offer.totalPrice);
    }
    return widget.offer.totalPrice;
  }

  Future<void> _checkCoupon() async {
    if (_couponCtrl.text.trim().isEmpty) return;
    setState(() {
      _couponBusy = true;
      _couponResult = null;
    });
    try {
      final r = await widget.auth.api.validateCoupon(
          _couponCtrl.text.trim(), 'Hotel', widget.offer.totalPrice);
      setState(() => _couponResult = r);
    } on ApiException catch (e) {
      setState(() => _couponResult = {'valid': false, 'message': e.message});
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
  }

  String _guestTitle(int i) {
    final g = _guests[i];
    if (g.type == 'Child') {
      return '${S.t('طفل')} (${S.t('العمر')}: ${g.age ?? '-'})';
    }
    return '${S.t('بالغ')} ${i + 1}';
  }

  Future<void> _submit() async {
    for (var i = 0; i < _guests.length; i++) {
      final g = _guests[i];
      if (g.firstCtrl.text.trim().isEmpty || g.lastCtrl.text.trim().isEmpty) {
        setState(() => _error = '${S.t('أدخل الاسم واللقب لكل نزيل كما في جواز السفر')} — ${_guestTitle(i)}');
        return;
      }
      if (g.nationalityCtrl.text.trim().isEmpty) {
        setState(() => _error = '${S.t('أدخل جنسية كل نزيل')} — ${_guestTitle(i)}');
        return;
      }
      if (g.passportCtrl.text.trim().length < 5) {
        setState(() => _error = '${S.t('أدخل رقم جواز ساري لكل نزيل')} — ${_guestTitle(i)}');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final offer = widget.offer;
    try {
      final result = await widget.auth.api.bookHotel({
        'apiProviderId': offer.apiProviderId ?? 0,
        'rateKey': offer.rateKey,
        'hotelName': offer.hotelName,
        'city': offer.city,
        'starRating': offer.starRating,
        'roomType': offer.roomType,
        'mealPlan': offer.mealPlan,
        'checkIn': widget.checkIn,
        'checkOut': widget.checkOut,
        'rooms': widget.rooms,
        'totalAmount': offer.totalPrice,
        'currency': offer.currency,
        'holderName': _guests.first.firstCtrl.text.trim(),
        'holderSurname': _guests.first.lastCtrl.text.trim(),
        'contactEmail': _emailCtrl.text.trim(),
        'contactPhone': _phoneCtrl.text.trim(),
        'guests': [
          for (final g in _guests)
            {
              'fullName': '${g.firstCtrl.text.trim()} ${g.lastCtrl.text.trim()}',
              'type': g.type,
              if (g.type == 'Child' && g.age != null) 'age': g.age,
              'passportNumber': g.passportCtrl.text.trim(),
              'nationality': g.nationalityCtrl.text.trim(),
            }
        ],
        'payFromWallet': true,
        'couponCode':
            _couponResult?['valid'] == true ? _couponCtrl.text.trim() : null,
      });

      if (!mounted) return;
      if (result['success'] == true) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 56),
            title: Text(S.t('تم الحجز بنجاح')),
            content: Text(
                '${S.t('رقم الحجز:')} ${result['bookingReference']}\n${S.t('الإجمالي:')} ${result['totalAmount']} ${result['currency']}'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context, true);
                  Navigator.pop(context, true);
                },
                child: Text(S.t('عرض حجوزاتي')),
              ),
            ],
          ),
        );
      } else {
        setState(() {
          _error = result['message']?.toString() ?? S.t('تعذر الحجز');
          _busy = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    return Scaffold(
      appBar: AppBar(title: Text(S.t('بيانات النزلاء'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ملخص الحجز
          Card(
            color: const Color(0xFF0E3A5D),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer.hotelName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.checkIn} ← ${widget.checkOut} • ${offer.nights} ${S.t('ليالٍ')} • ${localizeHotelText(offer.roomType)} • ${localizeHotelText(offer.mealPlan)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      if (_couponResult?['valid'] == true) ...[
                        Text(
                          Money.fmt0(offer.totalPrice, offer.currency),
                          style: const TextStyle(
                              color: Colors.white54,
                              decoration: TextDecoration.lineThrough,
                              fontSize: 13),
                        ),
                      ],
                      Text(
                        Money.fmt0(_finalPrice, offer.currency),
                        style: const TextStyle(
                            color: Color(0xFFD9A441),
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                      ),
                      if (_couponResult?['valid'] == true) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.discount_outlined,
                            color: Color(0xFFD9A441), size: 16),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(S.t('بيانات التواصل'),
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                      labelText: S.t('البريد الإلكتروني'),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email_outlined)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: S.t('رقم الهاتف'),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.phone_outlined)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text('${S.t('بيانات النزلاء')} (${_guests.length})',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (var i = 0; i < _guests.length; i++)
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _guests[i].type == 'Child'
                              ? Icons.child_care
                              : Icons.person_outline,
                          color: const Color(0xFF0E3A5D),
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_guestTitle(i),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0E3A5D))),
                        ),
                        if (i == 0)
                          Container(
                            margin: const EdgeInsetsDirectional.only(start: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD9A441),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(S.t('صاحب الحجز'),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10)),
                          ),
                      ],
                    ),
                    if (_travelers.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: S.t('👥 تعبئة من المسافرين المحفوظين'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final t in _travelers)
                            DropdownMenuItem<int>(
                              value: t['id'] as int,
                              child: Text('${t['firstName']} ${t['lastName']}', overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (id) =>
                            id == null ? null : _fillFromTraveler(_guests[i], id),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _guests[i].firstCtrl,
                            decoration: InputDecoration(
                                labelText: S.t('الاسم الأول'),
                                border: const OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _guests[i].lastCtrl,
                            decoration: InputDecoration(
                                labelText: S.t('اللقب / العائلة'),
                                border: const OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _guests[i].passportCtrl,
                            decoration: InputDecoration(
                                labelText: S.t('رقم الجواز'),
                                border: const OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _guests[i].nationalityCtrl,
                            decoration: InputDecoration(
                                labelText: S.t('الجنسية'),
                                border: const OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // قسيمة التخفيض
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponCtrl,
                  decoration: InputDecoration(
                      labelText: S.t('🎟 قسيمة تخفيض (اختياري)'),
                      border: const OutlineInputBorder()),
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
              padding: const EdgeInsets.only(top: 6, bottom: 6),
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
          const SizedBox(height: 8),

          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
            ),
          if (_error != null) TlyncHint(auth: widget.auth, error: _error),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_outline),
              label: Text(_busy
                  ? S.t('جارٍ تأكيد الحجز…')
                  : '${S.t('تأكيد والدفع من المحفظة')} — ${Money.fmt0(_finalPrice, offer.currency)}'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
