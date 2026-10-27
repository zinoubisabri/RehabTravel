import 'package:flutter/material.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';
import 'esim_my_screen.dart';
import 'voucher_screen.dart';

/// حجوزاتي — كل خدمة في تبويب مستقل: طيران / فنادق / عمرة / شرائح / خدماتي
class MyBookingsScreen extends StatefulWidget {
  final AuthState auth;
  const MyBookingsScreen({super.key, required this.auth});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  bool _loading = true;
  String? _message;
  List<BookingListItem> _bookings = [];
  List<dynamic> _umrahBookings = [];
  List<dynamic> _hotelBookings = [];
  List<EsimOrderListItem> _esimOrders = [];
  List<ExtraBooking> _extraBookings = [];

  // ---------- فلتر العملة: لا يظهر للعميل إلا معاملات عملته الحالية ----------
  bool _curMatch(String? c) => (c == null || c.isEmpty ? 'LYD' : c) == Money.active;

  String get _curLabel => switch (Money.active) {
        'USD' => S.t('دولار أمريكي'),
        'EUR' => S.t('يورو'),
        _ => S.t('دينار ليبي'),
      };

  List<BookingListItem> get _visFlights =>
      _bookings.where((b) => _curMatch(b.currency)).toList();
  List<dynamic> get _visHotels => _hotelBookings
      .where((h) => _curMatch((h['currency'] ?? 'LYD').toString()))
      .toList();
  List<dynamic> get _visUmrah => _umrahBookings
      .where((u) => _curMatch((u['currency'] ?? 'LYD').toString()))
      .toList();
  List<EsimOrderListItem> get _visEsims =>
      _esimOrders.where((e) => _curMatch(e.currency)).toList();
  List<ExtraBooking> _visExtras(String? cat) => _extraBookings
      .where((b) => _curMatch(b.currency) && (cat == null || b.category == cat))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.auth.api.myBookings(),
        widget.auth.api.myUmrahBookings(),
        widget.auth.api.myEsimOrders(),
        widget.auth.api.myHotelBookings(),
        widget.auth.api.myExtraBookings(),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = results[0].map((b) => BookingListItem.fromJson(b)).toList();
        _umrahBookings = results[1];
        _esimOrders = results[2]
            .map((e) => EsimOrderListItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _hotelBookings = results[3];
        _extraBookings = results[4]
            .whereType<Map>()
            .map((j) => ExtraBooking.fromJson(Map<String, dynamic>.from(j)))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _issue(BookingListItem b) async {
    try {
      final result = await widget.auth.api.issueTicket(b.id);
      setState(() => _message = result['success'] == true
          ? '${S.t('تم إصدار التذكرة —')} ${b.reference}'
          : result['message']?.toString());
      await _load();
    } on ApiException catch (e) {
      setState(() => _message = e.message);
    }
  }

  Future<void> _void(BookingListItem b) async {
    try {
      final result = await widget.auth.api.voidTicket(b.id);
      setState(() => _message = result['success'] == true
          ? S.t('تم إلغاء التذكرة وإعادة المبلغ حسب السياسة.')
          : result['message']?.toString());
      await _load();
    } on ApiException catch (e) {
      setState(() => _message = e.message);
    }
  }

  String _statusName(String status) {
    switch (status) {
      case 'Ticketed':
        return S.t('صادرة');
      case 'Confirmed':
        return S.t('مؤكد');
      case 'Hold':
        return S.t('مؤقت');
      case 'Cancelled':
        return S.t('ملغاة');
      case 'Refunded':
        return S.t('مستردة');
      case 'Failed':
        return S.t('فاشلة');
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Ticketed':
      case 'Confirmed':
      case 'Completed':
        return const Color(0xFF1E7A45);
      case 'Cancelled':
      case 'Failed':
        return Colors.red.shade700;
      default:
        return Colors.orange.shade800;
    }
  }

  String _esimStatusName(String status) {
    switch (status) {
      case 'Completed':
        return S.t('مكتمل');
      case 'Processing':
        return S.t('قيد التجهيز');
      case 'Pending':
        return S.t('بانتظار الدفع');
      case 'Failed':
        return S.t('فشل — أُعيد المبلغ');
      case 'Cancelled':
        return S.t('ملغي');
      default:
        return status;
    }
  }

  Widget _statusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _statusColor(label).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(_statusName(label),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _statusColor(label))),
    );
  }

  Widget _empty(IconData icon, String text, {bool curNote = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
            if (curNote) ...[
              const SizedBox(height: 8),
              Text(
                '${S.t('المعروض:')} $_curLabel — ${S.t('بدّل عملتك من «المزيد ← عملتي» لرؤية معاملاتك الأخرى')}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // يُعاد الرسم فور تغيير العميل عملته حتى تُفلتر القوائم مباشرة
    return ValueListenableBuilder<String>(
      valueListenable: Money.changes,
      builder: (context, activeCur, _) {
    // خدماتي: كل خدمة في تبويب مستقل (مثل التطبيقات المرجعية)
    int countFor(String cat) => _visExtras(cat).length;

    return DefaultTabController(
      length: 9,
      child: Scaffold(
        appBar: AppBar(
          title: Text(S.t('حجوزاتي')),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '${S.t('✈ طيران')} (${_visFlights.length})'),
              Tab(text: '${S.t('🏨 فنادق')} (${_visHotels.length})'),
              Tab(text: '${S.t('🕋 عمرة')} (${_visUmrah.length})'),
              Tab(text: '📱 eSIM (${_visEsims.length})'),
              Tab(text: '${S.t('🚗 سيارات')} (${countFor('CarRental')})'),
              Tab(text: '${S.t('🚐 نقل المطار')} (${countFor('Transfer')})'),
              Tab(text: '${S.t('🗺️ جولات')} (${countFor('Activity')})'),
              Tab(text: '${S.t('🛡️ تأمين')} (${countFor('Insurance')})'),
              Tab(text: '${S.t('🧳 كل الخدمات')} (${_visExtras(null).length})'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_message != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F0FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_message!),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _flightsTab(),
                        _hotelsTab(),
                        _umrahTab(),
                        _esimTab(),
                        _extrasTab('CarRental'),
                        _extrasTab('Transfer'),
                        _extrasTab('Activity'),
                        _extrasTab('Insurance'),
                        _extrasTab(null),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  // ---------- طيران ----------
  Widget _flightsTab() {
    final list = _visFlights;
    if (list.isEmpty) {
      return _empty(Icons.flight_outlined, S.t('لا توجد حجوزات طيران بعد'),
          curNote: true);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final b = list[i];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(b.reference,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      _statusChip(b.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.route, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('${b.route} — ${b.departDate.substring(0, 10)}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                      '${b.passengerCount} ${S.t('مسافر')} — ${Money.fmtOrig(b.totalAmount, b.currency)}'),
                  if (b.hasTicket && b.ticketNumbers != null)
                    Text('${S.t('التذاكر:')} ${b.ticketNumbers}',
                        style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (b.status == 'Hold' || b.status == 'Confirmed')
                        FilledButton.tonal(
                          onPressed: () => _issue(b),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            minimumSize: const Size(0, 34),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          child: Text(S.t('إصدار التذكرة'),
                              overflow: TextOverflow.ellipsis),
                        ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VoucherScreen(
                                auth: widget.auth,
                                type: VoucherType.flight,
                                id: b.id),
                          ),
                        ),
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: Text(S.t('التذكرة')),
                      ),
                      const SizedBox(width: 8),
                      if (b.hasTicket)
                        OutlinedButton(
                          onPressed: () => _void(b),
                          child: Text(S.t('إلغاء')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- فنادق ----------
  Widget _hotelsTab() {
    final list = _visHotels;
    if (list.isEmpty) {
      return _empty(Icons.hotel_outlined, S.t('لا توجد حجوزات فنادق بعد'),
          curNote: true);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final h = list[i];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF14532D),
                child: Icon(Icons.hotel, color: Colors.white, size: 20),
              ),
              title: Text(h['hotelName'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${h['reference']} — ${h['city']}\n${(h['checkIn'] ?? '').toString().substring(0, 10)} ← ${(h['checkOut'] ?? '').toString().substring(0, 10)}'),
              ),
              isThreeLine: true,
              trailing: Text(
                Money.fmtOrig((h['totalAmount'] as num?) ?? 0,
                    (h['currency'] ?? 'LYD').toString(), 0),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF0E3A5D)),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VoucherScreen(
                      auth: widget.auth, type: VoucherType.hotel, id: h['id'] ?? 0),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- عمرة ----------
  Widget _umrahTab() {
    final list = _visUmrah;
    if (list.isEmpty) {
      return _empty(Icons.mosque_outlined, S.t('لا توجد حجوزات عمرة بعد'),
          curNote: true);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final u = list[i];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF1E7A45),
                child: Icon(Icons.mosque, color: Colors.white, size: 20),
              ),
              title: Text(u['packageName'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${u['reference']} — ${(u['departureDate'] ?? '').toString().substring(0, 10)}\n${u['pilgrimCount']} ${S.t('معتمر')} — ${u['status']}'),
              ),
              isThreeLine: true,
              trailing: Text(
                Money.fmtOrig((u['totalAmount'] as num?) ?? 0,
                    (u['currency'] ?? 'LYD').toString(), 0),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF1E7A45)),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VoucherScreen(
                      auth: widget.auth, type: VoucherType.umrah, id: u['id'] ?? 0),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- خدماتي: سيارات / نقل / جولات / تأمين — كل خدمة في تبويب مستقل ----------
  // [category] = null تعني «كل الخدمات» مجمعة
  Widget _extrasTab(String? category) {
    const catMeta = {
      'CarRental': ('🚗 كراء السيارات', Icons.directions_car_filled_rounded),
      'Transfer': ('🚐 النقل من وإلى المطار', Icons.airport_shuttle_rounded),
      'Activity': ('🗺️ الجولات والأنشطة', Icons.map_rounded),
      'Insurance': ('🛡️ التأمين على السفر', Icons.verified_user_rounded),
    };

    final list = _visExtras(category);

    if (list.isEmpty) {
      final meta = category == null ? null : catMeta[category];
      return _empty(meta?.$2 ?? Icons.luggage_outlined,
          category == null
              ? S.t('لا توجد طلبات خدمات بعد — جرّب كراء السيارات أو النقل المطاري من الرئيسية')
              : '${S.t('لا توجد حجوزات بعد في')} ${meta?.$1 ?? ''}',
          curNote: true);
    }

    if (category != null) {
      // تبويب خدمة واحدة: قائمة مباشرة بدون عناوين تجميع
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          itemBuilder: (_, i) => _extraCard(list[i]),
        ),
      );
    }

    // تبويب «كل الخدمات»: مجمعة بعناوين
    final groups = <String, List<ExtraBooking>>{};
    for (final b in list) {
      groups.putIfAbsent(b.category, () => []).add(b);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text(
                '${catMeta[entry.key]?.$1 ?? entry.key} (${entry.value.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
            ),
            for (final b in entry.value) _extraCard(b),
          ],
        ],
      ),
    );
  }

  Widget _extraCard(ExtraBooking b) {
    final (label, color) = switch (b.status) {
      'Confirmed' => (S.t('مؤكد ✅'), Colors.green),
      'Cancelled' => (S.t('ملغي ❌'), Colors.red),
      _ => (S.t('قيد المراجعة ⏳'), Colors.orange),
    };
    final short = b.dateFrom.length > 10 ? b.dateFrom.substring(0, 10) : b.dateFrom;
    final shortTo = b.dateTo != null
        ? (b.dateTo!.length > 10 ? b.dateTo!.substring(0, 10) : b.dateTo!)
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(b.itemTitle,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                Text('#${b.id}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$short${shortTo != null ? " → $shortTo" : ""} • ×${b.quantity}${b.category == 'CarRental' ? " ${S.t("يوم")}" : ""}',
              style: const TextStyle(color: Colors.black54, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(Money.fmtOrig(b.totalPrice, b.currency),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0E5A8A))),
                Row(children: [
                  if (b.isPaid)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(S.t('💰 مدفوع'),
                          style: const TextStyle(
                              color: Colors.teal, fontSize: 12)),
                    ),
                  Text(label, style: TextStyle(color: color, fontSize: 12)),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _esimTab() {
    final list = _visEsims;
    if (list.isEmpty) {
      return _empty(Icons.sim_card_outlined,
          S.t('لا توجد شرائح إلكترونية بعد'),
          curNote: true);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final e = list[i];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFD97706),
                child: Icon(Icons.sim_card, color: Colors.white, size: 20),
              ),
              title: Text(e.planName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${e.orderNumber}\n${e.countryName} — ${e.dataGb > 0 ? '${e.dataGb} GB' : S.t('غير محدود')} × ${e.quantity} — ${_esimStatusName(e.status)}'),
              ),
              isThreeLine: true,
              trailing: Text(
                Money.fmtOrig(e.totalAmount, e.currency, 0),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EsimMyScreen(auth: widget.auth)),
              ),
            ),
          );
        },
      ),
    );
  }
}
