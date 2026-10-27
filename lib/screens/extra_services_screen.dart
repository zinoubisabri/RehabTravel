import 'package:flutter/material.dart';

import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';
import '../widgets/tlync_hint.dart';
import 'login_screen.dart';

/// الخدمات الإضافية: كراء سيارات، نقل مطار، جولات وأنشطة، تأمين سفر.
/// الكتالوج والأسعار تأتي من الخادم (الوضع التجريبي أو Amadeus حسب إعدادات الأدمن).
class ExtraServicesScreen extends StatefulWidget {
  final AuthState auth;

  /// فئة مُختارة مسبقاً من أزرار الرئيسية (CarRental / Transfer / Activity / Insurance)
  final String? initialCategory;
  const ExtraServicesScreen({super.key, required this.auth, this.initialCategory});

  @override
  State<ExtraServicesScreen> createState() => _ExtraServicesScreenState();
}

class _ExtraServicesScreenState extends State<ExtraServicesScreen> {
  List<ExtraCategory>? _categories;
  List<ExtraItem> _items = [];
  List<ExtraBooking> _my = [];
  String _category = '';
  bool _loading = false;
  bool _showMine = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.auth.api.extraCategories();
      final cats = raw
          .whereType<Map>()
          .map((j) => ExtraCategory.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      if (!mounted) return;
      setState(() => _categories = cats);
      if (cats.isNotEmpty) {
        final wanted = widget.initialCategory;
        final first = cats.any((c) => c.key == wanted)
            ? wanted!
            : cats.first.key;
        await _select(first);
      }
      if (widget.auth.isAuthenticated) await _loadMine();
    } catch (_) {
      if (mounted) setState(() => _categories = []);
    }
  }

  Future<void> _select(String key) async {
    setState(() {
      _category = key;
      _loading = true;
    });
    try {
      final raw = await widget.auth.api.extraCatalog(key);
      if (!mounted) return;
      setState(() {
        _items = raw
            .whereType<Map>()
            .map((j) => ExtraItem.fromJson(Map<String, dynamic>.from(j)))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMine() async {
    try {
      final raw = await widget.auth.api.myExtraBookings();
      if (!mounted) return;
      setState(() => _my = raw
          .whereType<Map>()
          .map((j) => ExtraBooking.fromJson(Map<String, dynamic>.from(j)))
          .toList());
    } catch (_) {}
  }

  /// وضع الخدمة الواحدة: صفحة مستقلة لفئة محددة (من أزرار الرئيسية)
  bool get _singleMode => widget.initialCategory != null;

  String _catName() {
    for (final c in _categories ?? const <ExtraCategory>[]) {
      if (c.key == _category) return '${c.icon} ${c.nameAr}';
    }
    return S.t('الخدمات الإضافية');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_singleMode ? _catName() : S.t('الخدمات الإضافية')),
        actions: [
          if (widget.auth.isAuthenticated)
            TextButton.icon(
              onPressed: () => setState(() => _showMine = !_showMine),
              icon: Icon(_showMine ? Icons.grid_view_rounded : Icons.receipt_long,
                  color: Colors.white, size: 20),
              label: Text(_showMine ? S.t('الكتالوج') : S.t('طلباتي'),
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _categories == null
          ? const Center(child: CircularProgressIndicator())
          : _categories!.isEmpty
              ? Center(child: Text(S.t('الخدمات الإضافية غير متاحة حالياً')))
              : _showMine
                  ? _buildMine()
                  : _buildCatalog(),
    );
  }

  Widget _buildCatalog() {
    return Column(
      children: [
        // في وضع الخدمة الواحدة لا تظهر شريط الفئات — الصفحة مستقلة
        if (!_singleMode)
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _categories!.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final c = _categories![i];
                final selected = c.key == _category;
                return ChoiceChip(
                  label: Text('${c.icon} ${c.nameAr}'),
                  selected: selected,
                  onSelected: (_) => _select(c.key),
                );
              },
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(child: Text(S.t('لا توجد عناصر متاحة حالياً')))
                  : RefreshIndicator(
                      onRefresh: () => _select(_category),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        itemBuilder: (context, i) => _itemCard(_items[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _itemCard(ExtraItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageUrl != null)
            Image.network(item.imageUrl!,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 15, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text(item.city,
                      style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
                ]),
                if (item.description != null) ...[
                  const SizedBox(height: 6),
                  Text(item.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 12.5)),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          TextSpan(
                            text: () {
                              final v = Money.convert(item.price, item.currency);
                              return '${Money.fmt(v, Money.site, v == v.roundToDouble() ? 0 : 2)} ';
                            }(),
                            style: const TextStyle(
                                color: Color(0xFF0E5A8A),
                                fontWeight: FontWeight.w800,
                                fontSize: 17),
                          ),
                          if (item.unitLabel != null)
                            TextSpan(
                              text: item.unitLabel,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _openBooking(item),
                      icon: const Icon(Icons.shopping_bag_outlined, size: 15),
                      label: Text(S.t('احجز الآن')),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0E5A8A),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: const Size(0, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMine() {
    // في وضع الخدمة الواحدة تعرض طلبات هذه الفئة فقط
    final mine = _singleMode
        ? _my.where((b) => b.category == _category).toList()
        : _my;
    if (mine.isEmpty) {
      return Center(child: Text(S.t('لا توجد طلبات بعد — تصفح الكتالوج واحجز.')));
    }
    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: mine.length,
        itemBuilder: (context, i) {
          final b = mine[i];
          final (label, color) = switch (b.status) {
            'Confirmed' => (S.t('مؤكد ✅'), Colors.green),
            'Cancelled' => (S.t('ملغي ❌'), Colors.red),
            _ => (S.t('قيد المراجعة ⏳'), Colors.orange),
          };
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              title: Text(b.itemTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '#${b.id} • ${b.dateFrom.substring(0, b.dateFrom.length > 10 ? 10 : b.dateFrom.length)}'
                  '${b.dateTo != null ? " → ${b.dateTo!.substring(0, b.dateTo!.length > 10 ? 10 : b.dateTo!.length)}" : ""}'
                  ' • ×${b.quantity}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Money.fmt(b.totalPrice, b.currency),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(label,
                      style: TextStyle(color: color, fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openBooking(ExtraItem item) {
    if (!widget.auth.isAuthenticated) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => LoginScreen(auth: widget.auth)));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BookingSheet(
        auth: widget.auth,
        item: item,
        onDone: () {
          _loadMine();
        },
      ),
    );
  }
}

class _BookingSheet extends StatefulWidget {
  final AuthState auth;
  final ExtraItem item;
  final VoidCallback onDone;
  const _BookingSheet(
      {required this.auth, required this.item, required this.onDone});

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();
  final _flightNo = TextEditingController();
  final _notes = TextEditingController();
  final _coupon = TextEditingController();
  double _discount = 0;
  String? _couponMsg;
  DateTime _dateFrom = DateTime.now().add(const Duration(days: 1));
  DateTime? _dateTo;
  int _qty = 1;
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.auth.fullName ?? '';
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _pickup, _dropoff, _flightNo, _notes, _coupon]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _qtyLabel => switch (widget.item.category) {
        'CarRental' => S.t('عدد الأيام'),
        'Insurance' => S.t('عدد المسافرين'),
        'Activity' => S.t('عدد الأشخاص'),
        _ => S.t('الكمية'),
      };

  Future<void> _pickDate(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? _dateFrom : (_dateTo ?? _dateFrom),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = d;
        } else {
          _dateTo = d;
        }
      });
    }
  }

  Future<void> _applyCoupon(double total) async {
    final code = _coupon.text.trim();
    if (code.length < 2) return;
    setState(() {
      _couponMsg = null;
      _discount = 0;
    });
    try {
      final r = await widget.auth.api.validateCoupon(code, widget.item.category, total);
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

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _msg = S.t('الاسم ورقم الهاتف مطلوبان.'));
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final resp = await widget.auth.api.bookExtraService({
        'itemId': widget.item.id,
        'customerName': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'dateFrom': _dateFrom.toIso8601String(),
        'dateTo': _dateTo?.toIso8601String(),
        'quantity': _qty,
        'pickupLocation': _pickup.text.trim(),
        'dropoffLocation': _dropoff.text.trim(),
        'flightNumber': _flightNo.text.trim(),
        'notes': _notes.text.trim(),
        'couponCode': _coupon.text.trim(),
      });
      setState(() {
        _ok = true;
        _msg = resp['message']?.toString() ?? S.t('تم استلام طلبك بنجاح.');
      });
      widget.onDone();
    } catch (e) {
      setState(() => _msg = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// لكراء السيارات: العدد = عدد أيام الفترة تلقائياً (يطابق حساب الخادم)
  Widget _detailRow(IconData ic, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ic, size: 15, color: const Color(0xFF0F6B4A)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('$label: $value',
                style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  int get _effectiveQty {
    if (widget.item.category == 'CarRental' && _dateTo != null) {
      final days = _dateTo!.difference(DateTime(_dateFrom.year, _dateFrom.month, _dateFrom.day)).inDays;
      return days < 1 ? 1 : days;
    }
    return _qty;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final total = item.price * _effectiveQty;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            // تفاصيل الجولة/النشاط بأيقونات — تظهر قبل الحجز
            if (item.category == 'Activity' &&
                (item.duration != null ||
                    item.meetingPoint != null ||
                    item.guideLanguage != null ||
                    item.includes != null)) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7F3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD3E8DD)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🗺️ ${S.t('تفاصيل الجولة')}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(height: 8),
                    if (item.duration != null)
                      _detailRow(Icons.schedule, S.t('المدة'), item.duration!),
                    if (item.meetingPoint != null)
                      _detailRow(Icons.place_outlined, S.t('نقطة اللقاء'),
                          item.meetingPoint!),
                    if (item.guideLanguage != null)
                      _detailRow(Icons.record_voice_over_outlined,
                          S.t('لغة المرشد'), item.guideLanguage!),
                    if (item.includes != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 15, color: Color(0xFF0F6B4A)),
                          const SizedBox(width: 6),
                          Text(S.t('تشمل'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 12.5)),
                        ],
                      ),
                      for (final line in item.includes!
                          .split('\n')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty))
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                              start: 24, top: 2),
                          child: Text('• $line',
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_msg != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: _ok ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_msg!,
                    style: TextStyle(
                        color: _ok ? Colors.green.shade800 : Colors.red.shade800)),
              ),
            if (!_ok) TlyncHint(auth: widget.auth, error: _msg),
            if (_ok)
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(S.t('تم')),
              )
            else ...[
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: S.t('الاسم الكامل') + ' *'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration:
                        InputDecoration(labelText: S.t('رقم الهاتف') + ' *'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration:
                        InputDecoration(labelText: S.t('البريد الإلكتروني')),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(true),
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                        '${S.t("من")}: ${_dateFrom.toIso8601String().substring(0, 10)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_dateTo == null
                        ? S.t('إلى تاريخ (اختياري)')
                        : '${S.t("إلى")}: ${_dateTo!.toIso8601String().substring(0, 10)}'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (item.category == 'CarRental')
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.directions_car_filled, size: 18, color: Color(0xFF0E5A8A)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _dateTo == null
                            ? S.t('الاحتساب بالأيام — حدّد «إلى تاريخ» لحساب الأيام تلقائياً')
                            : '${S.t("عدد الأيام")}: $_effectiveQty ${S.t("يوم")}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ]),
                )
              else
                Row(children: [
                  Text(_qtyLabel),
                  const Spacer(),
                  IconButton(
                    onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_qty',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(
                    onPressed: _qty < 30 ? () => setState(() => _qty++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ]),
              if (item.category == 'Transfer' || item.category == 'CarRental') ...[
                TextField(
                  controller: _pickup,
                  decoration:
                      InputDecoration(labelText: S.t('مكان الاستلام (المطار/الفندق)')),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _dropoff,
                  decoration:
                      InputDecoration(labelText: S.t('مكان التسليم')),
                ),
                const SizedBox(height: 8),
              ],
              if (item.category == 'Transfer') ...[
                TextField(
                  controller: _flightNo,
                  decoration:
                      InputDecoration(labelText: S.t('رقم الرحلة (اختياري)')),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: InputDecoration(labelText: S.t('ملاحظات')),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _coupon,
                      decoration:
                          InputDecoration(labelText: S.t('قسيمة التخفيض (اختياري)')),
                      onChanged: (_) => setState(() {
                        _discount = 0;
                        _couponMsg = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: () => _applyCoupon(total),
                      child: Text(S.t('تطبيق'))),
                ],
              ),
              if (_couponMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_couponMsg!,
                      style: TextStyle(
                          fontSize: 12,
                          color: _discount > 0
                              ? const Color(0xFF0F6B4A)
                              : Colors.red)),
                ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F7FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(S.t('الإجمالي التقديري')),
                        Text(Money.fmt(total, item.currency),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0E5A8A),
                                fontSize: 16,
                                decoration: _discount > 0
                                    ? TextDecoration.lineThrough
                                    : null)),
                      ],
                    ),
                    if (_discount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(S.t('الإجمالي بعد الخصم'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F6B4A))),
                            Text(
                                Money.fmt(
                                    (total - _discount).clamp(0, double.infinity),
                                    item.currency),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F6B4A),
                                    fontSize: 16)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A8A),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(_busy ? S.t('جارٍ الإرسال…') : S.t('تأكيد الطلب')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
