import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../money.dart';
import '../strings.dart';

/// شاشة العمرة بالتدفق الجديد: مدينة الإقلاع ← الرحلة ← البرنامج ← الغرف ← المعتمرون.
/// تُنشأ الفاتورة ويُخصم المبلغ من المحفظة فوراً، وتبقى المراجعة التشغيلية للإدارة.
class UmrahScreen extends StatefulWidget {
  final AuthState auth;
  const UmrahScreen({super.key, required this.auth});

  @override
  State<UmrahScreen> createState() => _UmrahScreenState();
}

class _UmrahScreenState extends State<UmrahScreen> {
  static const _green = Color(0xFF14634B);
  static const _green2 = Color(0xFF1E8E5A);
  static const _gold = Color(0xFFD4AF37);
  static const _navy = Color(0xFF0E3A5D);

  int _step = 1;
  bool _loading = false;
  String? _error;

  List<dynamic> _cities = [];
  Map<String, dynamic>? _city;
  List<dynamic> _trips = [];
  Map<String, dynamic>? _trip;
  List<dynamic> _offers = [];
  Map<String, dynamic>? _offer;

  final Map<String, int> _rooms = {'Double': 0, 'Triple': 0, 'Quad': 0, 'Quint': 0};
  int _children = 0;
  int _infants = 0;

  bool _completeLater = false;
  final List<_PilgrimForm> _pilgrims = [];
  final TextEditingController _couponCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _booking = false;

  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  ApiClient get _api => widget.auth.api;

  Future<void> _loadCities() async {
    setState(() { _loading = true; _error = null; });
    try {
      _cities = await _api.umrahCities();
    } on ApiException catch (e) {
      _error = e.message;
    }
    setState(() => _loading = false);
  }

  Future<void> _selectCity(Map<String, dynamic> c) async {
    setState(() { _city = c; _step = 2; _loading = true; _error = null; });
    try {
      _trips = await _api.umrahTrips(c['id'] as int);
    } on ApiException catch (e) {
      _error = e.message;
      _trips = [];
    }
    setState(() => _loading = false);
  }

  Future<void> _selectTrip(Map<String, dynamic> t) async {
    setState(() { _trip = t; _step = 3; _loading = true; _error = null; });
    try {
      _offers = await _api.umrahTripOffers(t['id'] as int);
    } on ApiException catch (e) {
      _error = e.message;
      _offers = [];
    }
    setState(() => _loading = false);
  }

  void _selectOffer(Map<String, dynamic> o) {
    if (!widget.auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('سجّل الدخول أولاً من تبويب حجوزاتي.'))));
      return;
    }
    setState(() { _offer = o; _children = 0; _infants = 0; _step = 4; });
  }

  double get _childPrice => (_offer?['childPrice'] as num?)?.toDouble() ?? 0;
  double get _infantPrice => (_offer?['infantPrice'] as num?)?.toDouble() ?? 0;

  /// تاريخ السفر (ذهاب الرحلة) — يُستخدم لقاعدة صلاحية الجواز/الإقامة 6 أشهر
  DateTime? get _travelDate => DateTime.tryParse('${_trip?['outboundDate'] ?? ''}');

  // ---------- حسابات الغرف ----------
  static const _roomMeta = {
    'Double': ('الزوجية', 2),
    'Triple': ('الثلاثية', 3),
    'Quad': ('الرباعية', 4),
    'Quint': ('الخماسية', 5),
  };

  double _priceOf(String type) {
    final o = _offer!;
    final key = switch (type) {
      'Double' => 'priceDouble',
      'Triple' => 'priceTriple',
      'Quint' => 'priceQuint',
      _ => 'priceQuad',
    };
    return (o[key] as num?)?.toDouble() ?? 0;
  }

  List<String> get _availableTypes =>
      _roomMeta.keys.where((t) => _priceOf(t) > 0).toList();

  int get _totalRooms => _rooms.values.fold(0, (a, b) => a + b);
  /// البالغون = سعة الغرف المحجوزة
  int get _adultPersons =>
      _rooms.entries.fold(0, (a, e) => a + e.value * _roomMeta[e.key]!.$2);
  int get _totalPersons => _adultPersons + _children + _infants;
  double get _roomsPrice =>
      _rooms.entries.fold(0.0, (a, e) => a + e.value * _roomMeta[e.key]!.$2 * _priceOf(e.key));
  double get _extrasPrice => _children * _childPrice + _infants * _infantPrice;
  double get _totalPrice => _roomsPrice + _extrasPrice;

  /// نوع المعتمر حسب ترتيبه: البالغون أولاً ثم الأطفال ثم الرضّع
  String _pilgrimType(int index) {
    if (index < _adultPersons) return 'Adult';
    if (index < _adultPersons + _children) return 'Child';
    return 'Infant';
  }

  String _pilgrimTypeLabel(int index) => switch (_pilgrimType(index)) {
        'Child' => '🧒 ${S.t('طفل')}',
        'Infant' => '👶 ${S.t('رضيع')}',
        _ => '🧍 ${S.t('بالغ')}',
      };

  static bool _isLibyan(String? nationality) {
    final n = (nationality ?? '').trim();
    if (n.isEmpty) return true;
    final lower = n.toLowerCase();
    return n.contains('ليب') || lower == 'lby' || lower == 'ly' || lower.contains('libya') || lower.contains('libyan');
  }

  void _syncPilgrims() {
    while (_pilgrims.length < _totalPersons) {
      _pilgrims.add(_PilgrimForm());
    }
  }

  // ---------- بناء الواجهة ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('رحلات العمرة 🕋')),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _stepsBar(),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.all(10),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _body()),
        ],
      ),
    );
  }

  Widget _stepsBar() {
    final labels = [S.t('المدينة'), S.t('الرحلة'), S.t('البرنامج'), S.t('الغرف'), S.t('المعتمرون')];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _stepChip(i + 1, labels[i]),
            if (i < labels.length - 1)
              Expanded(child: Container(height: 2, color: i + 1 < _step ? _green : Colors.grey.shade300)),
          ],
        ],
      ),
    );
  }

  Widget _stepChip(int n, String label) {
    final active = _step == n, done = _step > n;
    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: active ? _green : (done ? _green.withValues(alpha: .25) : Colors.grey.shade300),
          child: done
              ? const Icon(Icons.check, size: 14, color: _green)
              : Text('$n', style: TextStyle(fontSize: 12, color: active ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? _green : Colors.grey)),
      ],
    );
  }

  Widget _body() {
    switch (_step) {
      case 1: return _citiesView();
      case 2: return _tripsView();
      case 3: return _offersView();
      case 4: return _roomsView();
      case 5: return _pilgrimsView();
      default: return _successView();
    }
  }

  Widget _backRow(String label, VoidCallback onBack) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: Text(label),
        ),
      ),
    );
  }

  // ═══════════ الخطوة 1: المدن ═══════════
  Widget _citiesView() {
    if (_cities.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(S.t('لا توجد رحلات مجدولة حالياً — تابعنا قريباً')),
      ));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(S.t('من أين تريد الإقلاع؟'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _navy)),
        const SizedBox(height: 14),
        for (final c in _cities)
          _cityCard(c as Map<String, dynamic>),
      ],
    );
  }

  Widget _cityCard(Map<String, dynamic> c) {
    final trips = c['upcomingTrips'] as int? ?? 0;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: trips > 0 ? () => _selectCity(c) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: _green.withValues(alpha: .1), shape: BoxShape.circle),
                child: const Icon(Icons.flight_takeoff, color: _green, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('${c['airportName'] ?? c['airportCode']}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: trips > 0 ? _green.withValues(alpha: .12) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  trips > 0 ? '$trips ${S.t('رحلة')}' : S.t('لا رحلات'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: trips > 0 ? _green : Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// ═══════════════════ الخطوة 2: الرحلات ═══════════════════
  Widget _tripsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _backRow(S.t('تغيير المدينة'), () => setState(() => _step = 1)),
        Text('${S.t('الرحلات من')} ${_city!['name']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _navy)),
        const SizedBox(height: 12),
        if (_trips.isEmpty)
          Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(S.t('لا رحلات قادمة من هذه المدينة')))),
        for (final t in _trips) _tripCard(t as Map<String, dynamic>),
      ],
    );
  }

  Widget _tripCard(Map<String, dynamic> t) {
    final out = '${t['outboundDate']}'.substring(0, 10);
    final ret = '${t['returnDate']}'.substring(0, 10);
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [_navy, Color(0xFF1B6AA5)])),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('✈️ ${t['airline']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text('$out → $ret', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            _legRow(Icons.flight_takeoff, _green, S.t('الذهاب'), out,
                '${t['outboundDepartTime']}', '${t['outboundArriveTime']}',
                '${t['cityName']}', '${t['destinationAirport']}', '${t['outboundFlightNumber']}'),
            const Divider(height: 18),
            _legRow(Icons.flight_land, const Color(0xFF7A1F2B), S.t('العودة'), ret,
                '${t['returnDepartTime']}', '${t['returnArriveTime']}',
                '${t['destinationAirport']}', '${t['cityName']}', '${t['returnFlightNumber']}'),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.luggage, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Expanded(child: Text('${t['baggageAllowance']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${t['offersCount']} ${S.t('برنامج')}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              FilledButton(
                onPressed: (t['offersCount'] as int? ?? 0) > 0 ? () => _selectTrip(t) : null,
                style: FilledButton.styleFrom(backgroundColor: _green),
                child: Text(S.t('عرض البرامج')),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _legRow(IconData icon, Color color, String label, String date, String dep, String arr, String from, String to, String flightNo) {
    return Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label — $date', style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 13)),
          const SizedBox(height: 2),
          Text('$from $dep → $to $arr', style: const TextStyle(fontSize: 13)),
          Text('${S.t('رحلة')} $flightNo', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        ]),
      ),
    ]);
  }

// ═══════════════════ الخطوة 3: العروض ═══════════════════
  Widget _offersView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _backRow(S.t('تغيير الرحلة'), () => setState(() => _step = 2)),
        Text(S.t('اختر البرنامج'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _navy)),
        const SizedBox(height: 12),
        if (_offers.isEmpty)
          Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(S.t('لا توجد برامج على هذه الرحلة بعد')))),
        for (final o in _offers) _offerCard(o as Map<String, dynamic>),
      ],
    );
  }

  Widget _offerCard(Map<String, dynamic> o) {
    final seats = (o['seatsTotal'] as int? ?? 0) - (o['seatsBooked'] as int? ?? 0);
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [_green, _green2])),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${o['programName']}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              Text('${o['seasonName']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(999)),
              child: Text('${(o['nightsMakkah'] as int? ?? 0) + (o['nightsMadinah'] as int? ?? 0)} ${S.t('ليلة')}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: _navy, fontSize: 12.5)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _hotelRow(o, 'makkah', '🕌 ${S.t('مكة')}', '${o['makkahHotelName']}', o['makkahHotelStars'] as int? ?? 0, o['makkahHotel'] as Map<String, dynamic>?, '${o['nightsMakkah']}'),
            const SizedBox(height: 8),
            _hotelRow(o, 'madinah', '🌙 ${S.t('المدينة')}', '${o['madinahHotelName']}', o['madinahHotelStars'] as int? ?? 0, o['madinahHotel'] as Map<String, dynamic>?, '${o['nightsMadinah']}'),
            if ('${o['includes'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _green.withValues(alpha: .07), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('✅ ${S.t('هذا السعر يشمل:')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: _green)),
                  Text('${o['includes']}', style: const TextStyle(fontSize: 12.5)),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              for (final type in ['Double', 'Triple', 'Quad', 'Quint'])
                if (_priceOfFor(o, type) > 0)
                  Expanded(child: _priceCell(_roomMeta[type]!.$1, _priceOfFor(o, type), '${o['currency']}')),
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${S.t('المقاعد:')} ${seats > 0 ? seats : S.t('مكتمل')}',
                  style: TextStyle(fontSize: 12.5, color: seats > 5 ? _green : Colors.orange.shade800, fontWeight: FontWeight.bold)),
              FilledButton(
                onPressed: seats > 0 || (o['seatsTotal'] as int? ?? 0) == 0 ? () => _selectOffer(o) : null,
                style: FilledButton.styleFrom(backgroundColor: _green),
                child: Text(S.t('اختر هذا البرنامج')),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  double _priceOfFor(Map<String, dynamic> o, String type) {
    final key = switch (type) {
      'Double' => 'priceDouble',
      'Triple' => 'priceTriple',
      'Quint' => 'priceQuint',
      _ => 'priceQuad',
    };
    return (o[key] as num?)?.toDouble() ?? 0;
  }

  Widget _priceCell(String label, double price, String currency) {
    final converted = Money.convert(price, currency);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
        Text(converted.toStringAsFixed(0), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _green)),
        Text(Money.symbol, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ]),
    );
  }

  Widget _hotelRow(Map<String, dynamic> o, String tag, String cityLabel, String name, int stars, Map<String, dynamic>? hotel, String nights) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$cityLabel — $nights ${S.t('ليالٍ')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _green2)),
        Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        Text('★' * stars.clamp(0, 5), style: const TextStyle(color: _gold, fontSize: 12)),
        if ('${hotel?['distanceToHaram'] ?? o['distanceFromHaram'] ?? ''}'.isNotEmpty)
          Text('📏 ${hotel?['distanceToHaram'] ?? o['distanceFromHaram']}',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
      ])),
      if (hotel != null)
        TextButton(
          onPressed: () => _showHotelDetails(hotel),
          child: Text(S.t('التفاصيل ←'), style: const TextStyle(fontSize: 12)),
        ),
    ]);
  }

  void _showHotelDetails(Map<String, dynamic> h) {
    final photos = (h['photos'] as List?)?.cast<String>() ?? [];
    final services = '${h['services'] ?? ''}'.split(RegExp(r'[,،]')).where((s) => s.trim().isNotEmpty).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: .75, maxChildSize: .95,
        builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(18), children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text('${h['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          Text('${h['city'] == 'Makkah' ? S.t('مكة المكرمة') : S.t('المدينة المنورة')}  ${'★' * (h['stars'] as int? ?? 0).clamp(0, 5)}',
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _hotelImage(photos[i]),
                ),
              ),
            ),
          ],
          if ('${h['distanceToHaram'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('📏 ${S.t('المسافة إلى الحرم:')} ${h['distanceToHaram']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
          if ('${h['description'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${h['description']}'),
          ],
          if (services.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(S.t('الخدمات:'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in services)
                Chip(label: Text('✓ ${s.trim()}', style: const TextStyle(fontSize: 12)),
                    backgroundColor: _green.withValues(alpha: .08), side: BorderSide.none),
            ]),
          ],
          if ('${h['mapUrl'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse('${h['mapUrl']}'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.map),
              label: Text(S.t('فتح الموقع في الخريطة')),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _hotelImage(String src) {
    if (src.startsWith('data:')) {
      try {
        final bytes = base64Decode(src.split(',').last);
        return Image.memory(bytes, width: 260, height: 190, fit: BoxFit.cover);
      } catch (_) {}
    }
    return Image.network(src, width: 260, height: 190, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(width: 260, color: Colors.grey.shade200, child: const Icon(Icons.image)));
  }


// ═══════════════════ الخطوة 4: الغرف ═══════════════════
  Widget _roomsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _backRow(S.t('تغيير البرنامج'), () => setState(() => _step = 3)),
        Text(S.t('اختر الغرف والأعداد'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _navy)),
        const SizedBox(height: 4),
        Text(S.t('يمكنك الجمع بين أكثر من نوع — الأسعار للشخص الواحد'),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
        const SizedBox(height: 14),
        for (final type in _availableTypes) _roomRow(type),
        // ── المرافقون: طفل واحد لكل غرفة كحد أقصى + رضّع بلا حد (شامل كل شيء) ──
        if (_childPrice > 0 || _infantPrice > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold.withValues(alpha: .5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🧒 ${S.t('المرافقون — أطفال ورضّع')}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 2),
              Text(S.t('يُضاف سعرهم للفاتورة مباشرة — طفل واحد كحد أقصى لكل غرفة، والرضّع بلا حد'),
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 11.5)),
              const SizedBox(height: 10),
              if (_childPrice > 0)
                _companionRow(
                  icon: '🧒',
                  label: S.t('طفل مرافق'),
                  price: _childPrice,
                  note: S.t('طفل واحد لكل غرفة'),
                  count: _children,
                  onMinus: _children > 0 ? () => setState(() => _children--) : null,
                  onPlus: _children < _totalRooms ? () => setState(() => _children++) : null,
                ),
              if (_infantPrice > 0)
                _companionRow(
                  icon: '👶',
                  label: S.t('رضيع مرافق'),
                  price: _infantPrice,
                  note: S.t('بلا حد — لا يشغل مقعد طيران'),
                  count: _infants,
                  onMinus: _infants > 0 ? () => setState(() => _infants--) : null,
                  onPlus: _infants < 10 ? () => setState(() => _infants++) : null,
                ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        // كوبون الخصم
        TextField(
          controller: _couponCtrl,
          decoration: InputDecoration(
            labelText: S.t('كوبون خصم (اختياري)'),
            prefixIcon: const Icon(Icons.discount_outlined, size: 20),
            isDense: true,
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        // شريط الإجمالي
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_navy, _green]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: _green.withValues(alpha: .25), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(
                  '$_totalRooms ${S.t('غرفة')} • $_totalPersons ${S.t('معتمر')}'
                  '${_children > 0 ? ' • 🧒 $_children' : ''}'
                  '${_infants > 0 ? ' • 👶 $_infants' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text(Money.fmt0(_totalPrice, (_offer?['currency'] ?? 'LYD').toString()),
                  style: const TextStyle(color: _gold, fontWeight: FontWeight.w900, fontSize: 22)),
            ]),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(S.t('الإجمالي قبل الخصم — تُنشأ الفاتورة ويُخصم المبلغ فور تأكيد الحجز'),
                  style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _totalRooms > 0
              ? () => setState(() { _syncPilgrims(); _step = 5; })
              : null,
          icon: const Icon(Icons.people_alt),
          label: Text(S.t('متابعة لبيانات المعتمرين'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _roomRow(String type) {
    final meta = _roomMeta[type]!;
    final n = _rooms[type] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: n > 0 ? _green : Colors.grey.shade300, width: n > 0 ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 8)],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(S.t('الغرفة ${meta.$1}'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          Text('${meta.$2} ${S.t('أشخاص')} • ${Money.fmt0(_priceOf(type), (_offer?['currency'] ?? 'LYD').toString())}/${S.t('شخص')}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ])),
        _counter(type),
      ]),
    );
  }

  Widget _companionRow({
    required String icon,
    required String label,
    required double price,
    required String note,
    required int count,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: count > 0 ? _green : Colors.grey.shade300, width: count > 0 ? 2 : 1),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
          Text(
              '${Money.fmt0(price, (_offer?['currency'] ?? 'LYD').toString())} • $note',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        ])),
        _cntBtn(Icons.remove, onMinus),
        SizedBox(
          width: 34,
          child: Center(child: Text('$count', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
        ),
        _cntBtn(Icons.add, onPlus),
      ]),
    );
  }

  Widget _counter(String type) {
    final n = _rooms[type] ?? 0;
    return Row(children: [
      _cntBtn(Icons.remove, n > 0
          ? () => setState(() {
                _rooms[type] = n - 1;
                // طفل واحد لكل غرفة كحد أقصى — قلّص الأطفال عند تقليل الغرف
                if (_children > _totalRooms) _children = _totalRooms;
              })
          : null),
      SizedBox(
        width: 38,
        child: Center(child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
      ),
      _cntBtn(Icons.add, () => setState(() => _rooms[type] = n + 1)),
    ]);
  }

  Widget _cntBtn(IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: onTap != null ? _green : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      );

// ═══════════ الخطوة 5: بيانات المعتمرين + OCR ═══════════
  Widget _pilgrimsView() {
    final list = _pilgrims.take(_totalPersons).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _backRow(S.t('تعديل الغرف'), () => setState(() => _step = 4)),
        Text(S.t('بيانات المعتمرين'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _navy)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(10)),
          child: Text('📸 ${S.t('ارفع صورة الجواز وسيُقرأ تلقائياً (OCR)، ثم أكمل الناقص بالعربية.')}',
              style: const TextStyle(fontSize: 12, color: _navy, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        // خيار الإنهاء باسم العميل فقط
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: SwitchListTile(
            value: _completeLater,
            onChanged: (v) => setState(() => _completeLater = v),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(S.t('إنهاء الفاتورة باسمي فقط'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            subtitle: Text(S.t('ستكمل الإدارة بيانات باقي المعتمرين وتبقى الفاتورة تحت المعالجة'),
                style: const TextStyle(fontSize: 11)),
            activeColor: _green,
          ),
        ),
        if (!_completeLater) ...[
          const SizedBox(height: 12),
          for (var i = 0; i < list.length; i++) _pilgrimCard(i, list[i]),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _booking ? null : _book,
          icon: _booking
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle),
          label: Text(_booking ? S.t('جارٍ إرسال الحجز…') : S.t('تأكيد الحجز وإرسال الفاتورة'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _pilgrimCard(int i, _PilgrimForm p) {
    final foreign = !_isLibyan(p.nationalityCtrl.text);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(8)),
            child: Text('${S.t('معتمر')} ${i + 1}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_pilgrimTypeLabel(i),
                style: const TextStyle(color: _navy, fontWeight: FontWeight.w800, fontSize: 11)),
          ),
          const Spacer(),
          if (p.imagePath != null)
            const Icon(Icons.verified, color: _green2, size: 20),
        ]),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: p.scanning ? null : () => _scanPassport(p),
          icon: p.scanning
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.document_scanner),
          label: Text(p.scanning
              ? S.t('جارٍ قراءة الجواز…')
              : (p.imagePath == null ? S.t('مسح الجواز (OCR)') : S.t('إعادة المسح'))),
          style: OutlinedButton.styleFrom(
            foregroundColor: _green, side: const BorderSide(color: _green),
            minimumSize: const Size(double.infinity, 42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (p.scanError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(p.scanError!, style: const TextStyle(color: Colors.red, fontSize: 11.5)),
          ),
        const SizedBox(height: 12),
        _groupLabel('🇸🇦 ${S.t('الاسم الثلاثي بالعربية')}'),
        _pField(p.firstNameArCtrl, S.t('الاسم'), Icons.person),
        const SizedBox(height: 8),
        _pField(p.fatherNameArCtrl, S.t('اسم الأب'), Icons.person_outline),
        const SizedBox(height: 8),
        _pField(p.lastNameArCtrl, S.t('اللقب'), Icons.family_restroom),
        const SizedBox(height: 12),
        _groupLabel('🛂 ${S.t('الاسم الثلاثي بالإنجليزية — كما في الجواز')}'),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [
            _pField(p.firstNameEnCtrl, 'First Name', Icons.badge_outlined),
            const SizedBox(height: 8),
            _pField(p.fatherNameEnCtrl, 'Father Name', Icons.badge_outlined),
            const SizedBox(height: 8),
            _pField(p.lastNameEnCtrl, 'Last Name', Icons.badge_outlined),
          ]),
        ),
        const SizedBox(height: 12),
        _pField(p.passportCtrl, S.t('رقم الجواز'), Icons.credit_card),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _dateBtn(S.t('انتهاء الجواز'), p.passportExpiry, (d) => setState(() {
              p.passportExpiry = d;
              // تاريخ الإصدار تلقائياً: الانتهاء − 8 سنوات − يوم واحد
              p.passportIssueDate =
                  DateTime(d.year - 8, d.month, d.day).subtract(const Duration(days: 1));
            })),
          ),
          const SizedBox(width: 8),
          Expanded(child: _dateBtn(S.t('إصدار الجواز'), p.passportIssueDate,
              (d) => setState(() => p.passportIssueDate = d))),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              '📅 ${S.t('تاريخ الإصدار يُحسب تلقائياً (الانتهاء − 8 سنوات − يوم) ويمكنك تعديله')}'
              ' — ${S.t('يجب ألا تقل صلاحية الجواز عن 6 أشهر من تاريخ السفر')}',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, height: 1.5)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: p.nationalityCtrl,
              decoration: _pDeco(S.t('الجنسية'), Icons.flag),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: p.gender,
              decoration: _pDeco(S.t('الجنس'), Icons.wc),
              items: [
                DropdownMenuItem(value: 'Male', child: Text(S.t('ذكر'))),
                DropdownMenuItem(value: 'Female', child: Text(S.t('أنثى'))),
              ],
              onChanged: (v) => setState(() => p.gender = v ?? 'Male'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _dateBtn(S.t('تاريخ الميلاد'), p.birthDate, (d) => setState(() => p.birthDate = d)),
        // ── الإقامة — إجبارية لغير الليبيين ──
        if (foreign) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🛂 ${S.t('بيانات الإقامة — إجبارية لغير الليبيين')}',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.orange.shade900)),
              const SizedBox(height: 4),
              Text(S.t('يجب ألا تقل صلاحية الإقامة عن 6 أشهر من تاريخ السفر'),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              const SizedBox(height: 10),
              _pField(p.residenceNumberCtrl, S.t('رقم الإقامة'), Icons.numbers),
              const SizedBox(height: 8),
              _dateBtn(S.t('صلاحية الإقامة'), p.residenceExpiry,
                  (d) => setState(() => p.residenceExpiry = d)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: p.residenceUploading ? null : () => _uploadResidence(p),
                icon: p.residenceUploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(p.residenceImagePath == null ? Icons.upload_file : Icons.check_circle,
                        color: p.residenceImagePath == null ? null : _green2),
                label: Text(p.residenceUploading
                    ? S.t('جارٍ رفع صورة الإقامة…')
                    : (p.residenceImagePath == null
                        ? S.t('إرفاق صورة الإقامة (إجباري)')
                        : S.t('تم إرفاق صورة الإقامة — اضغط للتغيير'))),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade900,
                  side: BorderSide(color: Colors.orange.shade300),
                  minimumSize: const Size(double.infinity, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _groupLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: _green)),
      );

  Future<void> _uploadResidence(_PilgrimForm p) async {
    final XFile? img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(S.t('حجم الصورة كبير — الحد الأقصى 5 ميجابايت'))));
      }
      return;
    }
    setState(() => p.residenceUploading = true);
    try {
      final path = await _api.uploadDocument(bytes, img.name);
      if (path != null) {
        p.residenceImagePath = path;
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(S.t('فشل رفع صورة الإقامة — حاول مجدداً'))));
      }
    } finally {
      if (mounted) setState(() => p.residenceUploading = false);
    }
  }

  Future<void> _scanPassport(_PilgrimForm p) async {
    final XFile? img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (img == null) return;
    setState(() { p.scanning = true; p.scanError = null; });
    try {
      final bytes = await img.readAsBytes();
      final res = await _api.uploadPassportOcr(bytes, img.name);
      if (res['success'] == true) {
        final fn = '${res['firstName'] ?? ''}'.trim();
        final ln = '${res['lastName'] ?? ''}'.trim();
        if (ln.isNotEmpty) p.lastNameEnCtrl.text = ln;
        if (fn.isNotEmpty) {
          // أول كلمة = الاسم الأول، والباقي = اسم الأب
          final parts = fn.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          p.firstNameEnCtrl.text = parts.first;
          if (parts.length > 1) p.fatherNameEnCtrl.text = parts.sublist(1).join(' ');
        }
        if ('${res['passportNumber'] ?? ''}'.isNotEmpty) p.passportCtrl.text = '${res['passportNumber']}';
        if ('${res['nationality'] ?? ''}'.isNotEmpty) {
          p.nationalityCtrl.text = _nationalityFromMrz('${res['nationality']}');
        }
        p.birthDate = DateTime.tryParse('${res['birthDate'] ?? ''}') ?? p.birthDate;
        final exp = DateTime.tryParse('${res['passportExpiry'] ?? ''}');
        if (exp != null) {
          p.passportExpiry = exp;
          // تاريخ الإصدار تلقائياً: الانتهاء − 8 سنوات − يوم واحد
          p.passportIssueDate ??=
              DateTime(exp.year - 8, exp.month, exp.day).subtract(const Duration(days: 1));
        }
        final g = '${res['gender'] ?? ''}';
        if (g == 'Male' || g == 'Female') p.gender = g;
        p.imagePath = res['imagePath']?.toString();
      } else {
        p.scanError = '${res['message'] ?? S.t('تعذّرت قراءة الجواز — أدخل البيانات يدوياً')}';
        p.imagePath ??= res['imagePath']?.toString();
      }
    } on ApiException catch (e) {
      p.scanError = e.message;
    } catch (_) {
      p.scanError = S.t('فشل رفع الصورة — حاول مجدداً');
    }
    if (mounted) setState(() => p.scanning = false);
  }

  /// تحويل رمز الجنسية القادم من منطقة MRZ (ISO) إلى اسم عربي مفهوم
  static String _nationalityFromMrz(String iso) {
    switch (iso.trim().toUpperCase()) {
      case 'LBY': case 'LY': return 'ليبي';
      case 'TUN': return 'تونسي';
      case 'EGY': return 'مصري';
      case 'DZA': return 'جزائري';
      case 'MAR': return 'مغربي';
      case 'SDN': return 'سوداني';
      case 'TCD': return 'تشادي';
      case 'NER': return 'نيجري';
      case 'SYR': return 'سوري';
      case 'PSE': return 'فلسطيني';
      case 'JOR': return 'أردني';
      case 'TUR': return 'تركي';
      default: return iso;
    }
  }

  Widget _pField(TextEditingController c, String label, IconData icon) =>
      TextField(controller: c, decoration: _pDeco(label, icon));

  InputDecoration _pDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _dateBtn(String label, DateTime? value, ValueChanged<DateTime> onPick) => OutlinedButton.icon(
        onPressed: () async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime(now.year - 30),
            firstDate: DateTime(1930),
            lastDate: DateTime(now.year + 15),
          );
          if (d != null) onPick(d);
        },
        icon: const Icon(Icons.date_range, size: 18),
        label: Text(
          value == null ? label : '$label: ${value.year}/${value.month}/${value.day}',
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _navy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

// ═══════════════════ الحجز ═══════════════════
  Future<void> _book() async {
    final list = _pilgrims.take(_totalPersons).toList();
    if (!_completeLater) {
      final travel = _travelDate;
      // الحد الأدنى للصلاحية: 6 أشهر من تاريخ السفر
      final minValidity = travel == null ? null : DateTime(travel.year, travel.month + 6, travel.day);
      String? err;
      for (var i = 0; i < list.length && err == null; i++) {
        final p = list[i];
        final n = i + 1;
        if (p.firstNameArCtrl.text.trim().isEmpty ||
            p.fatherNameArCtrl.text.trim().isEmpty ||
            p.lastNameArCtrl.text.trim().isEmpty) {
          err = '${S.t('أدخل الاسم الثلاثي بالعربية كاملاً للمعتمر رقم')} $n';
        } else if (p.firstNameEnCtrl.text.trim().isEmpty || p.lastNameEnCtrl.text.trim().isEmpty) {
          err = '${S.t('أدخل الاسم واللقب بالإنجليزية كما في الجواز للمعتمر رقم')} $n';
        } else if (p.passportCtrl.text.trim().isEmpty) {
          err = '${S.t('أدخل رقم الجواز للمعتمر رقم')} $n';
        } else if (p.passportExpiry == null) {
          err = '${S.t('حدد تاريخ انتهاء الجواز للمعتمر رقم')} $n';
        } else if (minValidity != null && p.passportExpiry!.isBefore(minValidity)) {
          err = '${S.t('جواز المعتمر رقم')} $n ${S.t('صلاحيته أقل من 6 أشهر من تاريخ السفر')}';
        } else if (p.nationalityCtrl.text.trim().isEmpty) {
          err = '${S.t('أدخل جنسية المعتمر رقم')} $n';
        } else if (!_isLibyan(p.nationalityCtrl.text)) {
          if (p.residenceNumberCtrl.text.trim().isEmpty) {
            err = '${S.t('أدخل رقم الإقامة للمعتمر الأجنبي رقم')} $n';
          } else if (p.residenceExpiry == null) {
            err = '${S.t('حدد تاريخ صلاحية الإقامة للمعتمر رقم')} $n';
          } else if (minValidity != null && p.residenceExpiry!.isBefore(minValidity)) {
            err = '${S.t('إقامة المعتمر رقم')} $n ${S.t('صلاحيتها أقل من 6 أشهر من تاريخ السفر')}';
          } else if (p.residenceImagePath == null) {
            err = '${S.t('أرفق صورة الإقامة للمعتمر الأجنبي رقم')} $n';
          }
        }
      }
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
      }
    }
    setState(() { _booking = true; _error = null; });
    try {
      final res = await _api.bookUmrahTrip({
        'offerId': _offer!['id'],
        'rooms': [
          for (final e in _rooms.entries)
            if (e.value > 0) {'roomType': e.key, 'count': e.value},
        ],
        'childrenCount': _children,
        'infantsCount': _infants,
        'completeLater': _completeLater,
        'pilgrims': _completeLater
            ? <Map<String, dynamic>>[]
            : [for (var i = 0; i < list.length; i++) list[i].toJson(_pilgrimType(i))],
        if (_couponCtrl.text.trim().isNotEmpty) 'couponCode': _couponCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() { _result = res; _step = 6; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

// ═══════════════════ الخطوة 6: النجاح ═══════════════════
  Widget _successView() {
    final r = _result ?? {};
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 88, height: 88,
            decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, color: _green2, size: 56),
          ),
        ),
        const SizedBox(height: 16),
        Center(child: Text(S.t('تم استلام طلب حجزك بنجاح'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
        const SizedBox(height: 10),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _gold),
            ),
            child: Text('${S.t('رقم الحجز:')} ${r['bookingReference'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _navy)),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.receipt_long, color: Colors.orange),
              const SizedBox(width: 8),
              Text(S.t('أُنشئت الفاتورة وخُصم مبلغها'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 6),
            Text(
              '${r['message'] ?? ''}\n'
              '${S.t('خُصم مبلغ')} ${Money.fmt0((r['totalAmount'] as num?) ?? 0, (r['currency'] ?? 'LYD').toString())} '
              '${S.t('من محفظتك فوراً، وتخضع التفاصيل التشغيلية (التأشيرة والتذاكر) لمراجعة الإدارة — ستظهر لك المستندات في صفحة الحجز فور إرفاقها.')}',
              style: TextStyle(color: Colors.grey.shade800, fontSize: 13, height: 1.6),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => setState(() {
            _step = 1;
            _city = null; _trip = null; _offer = null; _result = null;
            _rooms.updateAll((k, v) => 0);
            _children = 0; _infants = 0;
            _pilgrims.clear();
            _completeLater = false;
            _couponCtrl.clear();
          }),
          icon: const Icon(Icons.add),
          label: Text(S.t('حجز جديد'), style: const TextStyle(fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

// ═══════════════════ نموذج بيانات معتمر ═══════════════════
}

class _PilgrimForm {
  // الاسم الثلاثي بالعربية
  final TextEditingController firstNameArCtrl = TextEditingController();
  final TextEditingController fatherNameArCtrl = TextEditingController();
  final TextEditingController lastNameArCtrl = TextEditingController();
  // الاسم الثلاثي بالإنجليزية (كما في الجواز)
  final TextEditingController firstNameEnCtrl = TextEditingController();
  final TextEditingController fatherNameEnCtrl = TextEditingController();
  final TextEditingController lastNameEnCtrl = TextEditingController();
  final TextEditingController passportCtrl = TextEditingController();
  final TextEditingController nationalityCtrl = TextEditingController();
  DateTime? birthDate;
  DateTime? passportExpiry;
  DateTime? passportIssueDate;
  String gender = 'Male';
  String? imagePath;
  bool scanning = false;
  String? scanError;
  // الإقامة — لغير الليبيين
  final TextEditingController residenceNumberCtrl = TextEditingController();
  DateTime? residenceExpiry;
  String? residenceImagePath;
  bool residenceUploading = false;

  String get _fullName =>
      '${firstNameArCtrl.text.trim()} ${fatherNameArCtrl.text.trim()} ${lastNameArCtrl.text.trim()}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  Map<String, dynamic> toJson(String type) => {
        'type': type,
        'fullName': _fullName,
        'firstNameAr': firstNameArCtrl.text.trim(),
        'fatherNameAr': fatherNameArCtrl.text.trim(),
        'lastNameAr': lastNameArCtrl.text.trim(),
        'firstNameEn': firstNameEnCtrl.text.trim().toUpperCase(),
        'fatherNameEn': fatherNameEnCtrl.text.trim().toUpperCase(),
        'lastNameEn': lastNameEnCtrl.text.trim().toUpperCase(),
        if (passportCtrl.text.trim().isNotEmpty) 'passportNumber': passportCtrl.text.trim(),
        if (nationalityCtrl.text.trim().isNotEmpty) 'nationality': nationalityCtrl.text.trim(),
        if (birthDate != null) 'dateOfBirth': birthDate!.toIso8601String().substring(0, 10),
        if (passportExpiry != null) 'passportExpiry': passportExpiry!.toIso8601String().substring(0, 10),
        if (passportIssueDate != null)
          'passportIssueDate': passportIssueDate!.toIso8601String().substring(0, 10),
        'gender': gender,
        if (imagePath != null) 'passportImagePath': imagePath,
        if (residenceNumberCtrl.text.trim().isNotEmpty)
          'residenceNumber': residenceNumberCtrl.text.trim(),
        if (residenceExpiry != null)
          'residenceExpiry': residenceExpiry!.toIso8601String().substring(0, 10),
        if (residenceImagePath != null) 'residenceImagePath': residenceImagePath,
      };
}
