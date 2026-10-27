import 'package:flutter/material.dart';

import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';
import '../widgets/tlync_hint.dart';
import 'car_rental_screen.dart';
import 'login_screen.dart';

/// النقل من وإلى المطار: نفس سيناريو كراء السيارات (اختيار من قاعدة البيانات
/// وبحث مسبق ثم حجز بعد عرض المواصفات) لكن بتاريخ واحد + توقيت + رقم رحلة اختياري.
class AirportTransferScreen extends StatefulWidget {
  final AuthState auth;
  const AirportTransferScreen({super.key, required this.auth});

  @override
  State<AirportTransferScreen> createState() => _AirportTransferScreenState();
}

class _AirportTransferScreenState extends State<AirportTransferScreen> {
  static const _navy = Color(0xFF146C94);

  bool _fromAirport = true; // true: من المطار إلى العنوان
  CarLocation? _airport;
  final _address = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 12, minute: 0);
  int? _passengers; // فارغ = كل المركبات
  final _flightNo = TextEditingController();

  List<ExtraItem>? _results;
  bool _searching = false;
  String? _error;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtT(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _address.dispose();
    _flightNo.dispose();
    super.dispose();
  }

  Future<void> _pickAirport() async {
    final loc = await showModalBottomSheet<CarLocation>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => CarLocationPickerSheet(
          auth: widget.auth, title: S.t('اختر المطار')),
    );
    if (loc != null && mounted) setState(() => _airport = loc);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _date,
      helpText: _fromAirport ? S.t('تاريخ الوصول') : S.t('تاريخ المغادرة'),
      locale: S.isAr ? const Locale('ar') : const Locale('en'),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null && mounted) setState(() => _time = t);
  }

  Future<void> _pickPassengers() async {
    final sel = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(S.t('عدد الأشخاص'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            ListTile(
              title: Text(S.t('الكل (بدون تحديد)')),
              onTap: () => Navigator.pop(ctx, 0),
            ),
            for (var n = 1; n <= 9; n++)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('$n'),
                onTap: () => Navigator.pop(ctx, n),
              ),
          ],
        ),
      ),
    );
    if (sel == null || !mounted) return;
    setState(() => _passengers = sel == 0 ? null : sel);
  }

  Future<void> _search() async {
    if (_airport == null) {
      setState(() => _error = S.t('اختر المطار من القائمة.'));
      return;
    }
    if (_address.text.trim().isEmpty) {
      setState(() => _error = S.t('اكتب العنوان أو المنطقة.'));
      return;
    }
    setState(() {
      _error = null;
      _searching = true;
      _results = null;
    });
    try {
      List<dynamic> raw = await widget.auth.api.extraCatalog('Transfer',
          location: _airport!.name, passengers: _passengers);
      if (raw.isEmpty) {
        raw = await widget.auth.api.extraCatalog('Transfer',
            location: _airport!.city, passengers: _passengers);
      }
      if (raw.isEmpty) {
        raw = await widget.auth.api
            .extraCatalog('Transfer', passengers: _passengers);
      }
      final items = raw
          .whereType<Map>()
          .map((j) => ExtraItem.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      if (!mounted) return;
      setState(() {
        _results = items;
        _searching = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error = S.t('تعذر الاتصال بالخادم — حاول مجدداً.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        title: Text(S.t('النقل من وإلى المطار'),
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _searchCard(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 14),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_results != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${S.t('عدد النتائج')}: ${_results!.length}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (_results!.isEmpty)
              Center(child: Text(S.t('لا توجد مركبات متاحة لهذا المكان.')))
            else
              for (final v in _results!) _vehicleCard(v),
          ],
        ],
      ),
    );
  }

  Widget _searchCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          // الاتجاه
          Row(
            children: [
              Expanded(
                child: _dirButton(true, Icons.flight_land,
                    S.t('من المطار إلى العنوان')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dirButton(false, Icons.flight_takeoff,
                    S.t('من العنوان إلى المطار')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _tile(
            label: S.t('المطار'),
            value: _airport?.display ?? S.t('اختر من القائمة…'),
            icon: Icons.flight,
            onTap: _pickAirport,
            grey: _airport == null,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F2F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _address,
              decoration: InputDecoration(
                icon: const Icon(Icons.home_outlined, color: _navy),
                border: InputBorder.none,
                labelText: S.t('العنوان / المنطقة'),
                hintText: S.t('مثال: وسط طرابلس — فندق كورنثيا'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _tile(
                  label: _fromAirport ? S.t('تاريخ الوصول') : S.t('تاريخ المغادرة'),
                  value: _fmt(_date),
                  icon: Icons.calendar_month_outlined,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  label: _fromAirport ? S.t('توقيت الوصول') : S.t('توقيت الانطلاق'),
                  value: _fmtT(_time),
                  icon: Icons.access_time,
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _tile(
                  label: '${S.t('عدد الأشخاص')} (${S.t('اختياري')})',
                  value: _passengers == null ? S.t('الكل') : '$_passengers',
                  icon: Icons.group_outlined,
                  onTap: _pickPassengers,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F2F8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _flightNo,
                    decoration: InputDecoration(
                      icon: const Icon(Icons.confirmation_number_outlined,
                          color: _navy),
                      border: InputBorder.none,
                      labelText: '${S.t('رقم الرحلة')} (${S.t('اختياري')})',
                      hintText: '8U123',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _searching ? null : _search,
              icon: const Icon(Icons.search, color: Colors.white),
              label: Text(S.t('بحث'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dirButton(bool from, IconData icon, String label) {
    final active = _fromAirport == from;
    return InkWell(
      onTap: () => setState(() => _fromAirport = from),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? _navy : const Color(0xFFF1F2F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: active ? Colors.white : Colors.black54),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : Colors.black87),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
      {required String label,
      required String value,
      required IconData icon,
      required VoidCallback onTap,
      bool grey = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F2F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _navy),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(value,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: grey ? Colors.grey : Colors.black87),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vehicleCard(ExtraItem v) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (v.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(v.imageUrl!,
                    width: 110,
                    height: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                        width: 88,
                        height: 88,
                        child: Icon(Icons.airport_shuttle,
                            size: 44, color: Colors.grey))),
              )
            else
              const Icon(Icons.airport_shuttle, size: 60, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14.5)),
                  const SizedBox(height: 4),
                  Wrap(
                    children: [
                      if (v.carType != null)
                        _spec(Icons.airport_shuttle_outlined, v.carType!),
                      if (v.seats != null)
                        _spec(Icons.person_outline,
                            '${v.seats} ${S.t('ركاب')}'),
                      if (v.transmission != null)
                        _spec(Icons.settings_outlined, v.transmission!),
                    ],
                  ),
                  if (v.description != null)
                    Text(v.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.black54)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Money.fmt(v.price),
                              style: const TextStyle(
                                  color: _navy,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(v.unitLabel ?? S.t('للرحلة'),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _openBooking(v),
                        style: FilledButton.styleFrom(
                          backgroundColor: _navy,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(S.t('احجز الآن')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spec(IconData ic, String txt) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 14, color: Colors.black45),
          const SizedBox(width: 3),
          Text(txt,
              style: const TextStyle(fontSize: 11.5, color: Colors.black87)),
        ]),
      );

  Future<void> _openBooking(ExtraItem v) async {
    if (!widget.auth.isAuthenticated) {
      final logged = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen(auth: widget.auth)),
      );
      if (logged != true || !mounted) return;
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _TransferBookingSheet(
        auth: widget.auth,
        vehicle: v,
        fromAirport: _fromAirport,
        airport: _airport!.name,
        address: _address.text.trim(),
        date: _date,
        time: _fmtT(_time),
        passengers: _passengers ?? 1,
        flightNo: _flightNo.text.trim(),
      ),
    );
  }
}

/// شاشة تأكيد حجز النقل — مواصفات المركبة وملخص الرحلة ثم خصم مباشر من المحفظة.
class _TransferBookingSheet extends StatefulWidget {
  final AuthState auth;
  final ExtraItem vehicle;
  final bool fromAirport;
  final String airport;
  final String address;
  final DateTime date;
  final String time;
  final int passengers;
  final String flightNo;

  const _TransferBookingSheet({
    required this.auth,
    required this.vehicle,
    required this.fromAirport,
    required this.airport,
    required this.address,
    required this.date,
    required this.time,
    required this.passengers,
    required this.flightNo,
  });

  @override
  State<_TransferBookingSheet> createState() => _TransferBookingSheetState();
}

class _TransferBookingSheetState extends State<_TransferBookingSheet> {
  static const _navy = Color(0xFF146C94);

  late final TextEditingController _name =
      TextEditingController(text: widget.auth.fullName ?? '');
  final _phone = TextEditingController();
  final _coupon = TextEditingController();
  double _discount = 0;
  String? _couponMsg;
  bool _busy = false;
  String? _error;
  bool _done = false;
  int? _bookingId;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  double get _total => widget.vehicle.price;
  double get _finalTotal => (_total - _discount).clamp(0, double.infinity);

  Future<void> _applyCoupon() async {
    final code = _coupon.text.trim();
    if (code.length < 2) return;
    setState(() {
      _couponMsg = null;
      _discount = 0;
    });
    try {
      final r = await widget.auth.api.validateCoupon(code, 'Transfer', _total);
      if (!mounted) return;
      setState(() {
        if (r['valid'] == true) {
          _discount = (r['discount'] as num?)?.toDouble() ?? 0;
        }
        _couponMsg = r['message']?.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _couponMsg = e.toString().replaceAll('Exception: ', ''));
    }
  }

  String get _pickup => widget.fromAirport ? widget.airport : widget.address;
  String get _dropoff => widget.fromAirport ? widget.address : widget.airport;

  Future<void> _confirm() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _error = S.t('الاسم ورقم الهاتف مطلوبان.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final resp = await widget.auth.api.bookExtraService({
        'itemId': widget.vehicle.id,
        'customerName': _name.text.trim(),
        'phone': _phone.text.trim(),
        'dateFrom': widget.date.toIso8601String(),
        'quantity': widget.passengers,
        'pickupLocation': _pickup,
        'dropoffLocation': _dropoff,
        'pickupTime': widget.time,
        if (widget.flightNo.isNotEmpty) 'flightNumber': widget.flightNo,
        if (_coupon.text.trim().isNotEmpty) 'couponCode': _coupon.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _done = true;
        _bookingId = (resp['bookingId'] as num?)?.toInt();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: _done ? _invoiceView() : _formView(),
      ),
    );
  }

  Widget _formView() {
    final v = widget.vehicle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (v.imageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(v.imageUrl!,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(v.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            const SizedBox(width: 8),
            Text(Money.fmt(_total),
                style: const TextStyle(
                    color: _navy, fontWeight: FontWeight.w900, fontSize: 17)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _specIcon(Icons.person_outline, '${v.seats ?? '-'} ${S.t('ركاب')}'),
            _specIcon(
                Icons.airport_shuttle_outlined, v.carType ?? '-'),
            _specIcon(Icons.settings_outlined, v.transmission ?? '-'),
          ],
        ),
        const Divider(height: 26),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F2F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _row(S.t('من'), _pickup),
              const SizedBox(height: 6),
              _row(S.t('إلى'), _dropoff),
              const SizedBox(height: 6),
              _row(
                  widget.fromAirport
                      ? S.t('تاريخ الوصول')
                      : S.t('تاريخ المغادرة'),
                  '${_fmt(widget.date)} ${widget.time}'),
              const SizedBox(height: 6),
              _row(S.t('عدد الأشخاص'), '${widget.passengers}'),
              if (widget.flightNo.isNotEmpty) ...[
                const SizedBox(height: 6),
                _row(S.t('رقم الرحلة'), widget.flightNo),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: S.t('الاسم الكامل'),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: S.t('رقم الهاتف'),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.red)),
          TlyncHint(auth: widget.auth, error: _error, amount: _finalTotal),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _coupon,
                decoration: InputDecoration(
                  labelText: S.t('قسيمة التخفيض (اختياري)'),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _applyCoupon, child: Text(S.t('تطبيق'))),
          ],
        ),
        if (_couponMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_couponMsg!,
                style: TextStyle(
                    fontSize: 12,
                    color: _discount > 0 ? Colors.green.shade700 : Colors.red)),
          ),
        if (_discount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(S.t('الإجمالي بعد الخصم'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${Money.fmt(_finalTotal)}',
                    style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            S.t('عند التأكيد يُخصم المبلغ فوراً من محفظتك ويصدر الحجز مؤكداً برقم فاتورة.'),
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _busy ? null : _confirm,
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(
                    '${S.t('تأكيد الحجز والدفع من المحفظة')} — ${Money.fmt(_finalTotal)}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _invoiceView() {
    final v = widget.vehicle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 8),
        Text(S.t('تم تأكيد حجز النقل المطاري ✅'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.green.shade200),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text('🧾 ${S.t('فاتورة حجز النقل')}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const Divider(height: 18),
              _row(S.t('مرجع الفاتورة'), 'EXTRA-${(_bookingId ?? 0)}'),
              _row(S.t('المركبة'), v.title),
              _row(S.t('من'), _pickup),
              _row(S.t('إلى'), _dropoff),
              _row(
                  widget.fromAirport
                      ? S.t('تاريخ الوصول')
                      : S.t('تاريخ المغادرة'),
                  '${_fmt(widget.date)} ${widget.time}'),
              _row(S.t('عدد الأشخاص'), '${widget.passengers}'),
              if (widget.flightNo.isNotEmpty)
                _row(S.t('رقم الرحلة'), widget.flightNo),
              const Divider(height: 18),
              _row(S.t('الإجمالي المدفوع من المحفظة'),
                  '${Money.fmt(_finalTotal)}'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(S.t('تم'),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _specIcon(IconData ic, String label) {
    return Column(
      children: [
        Icon(ic, size: 22, color: _navy),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.black87)),
      ],
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
