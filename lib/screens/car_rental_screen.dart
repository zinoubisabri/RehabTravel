import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';
import '../widgets/tlync_hint.dart';
import 'login_screen.dart';

/// بحث واحد عن كراء سيارات — يُحفظ محلياً في قسم «آخر بحث».
class CarRecentSearch {
  final String pickup;
  final String dropoff;
  final String fromDate; // yyyy-MM-dd
  final String toDate;
  final String pickupTime;
  final String dropoffTime;

  const CarRecentSearch({
    required this.pickup,
    required this.dropoff,
    required this.fromDate,
    required this.toDate,
    required this.pickupTime,
    required this.dropoffTime,
  });

  Map<String, dynamic> toJson() => {
        'pickup': pickup,
        'dropoff': dropoff,
        'fromDate': fromDate,
        'toDate': toDate,
        'pickupTime': pickupTime,
        'dropoffTime': dropoffTime,
      };

  factory CarRecentSearch.fromJson(Map<String, dynamic> j) => CarRecentSearch(
        pickup: j['pickup'] ?? '',
        dropoff: j['dropoff'] ?? '',
        fromDate: j['fromDate'] ?? '',
        toDate: j['toDate'] ?? '',
        pickupTime: j['pickupTime'] ?? '13:00',
        dropoffTime: j['dropoffTime'] ?? '13:00',
      );
}

/// يحتفظ بآخر 3 عمليات بحث عن سيارات (مفتاح rt_recent_car_searches).
class CarRecentStore {
  static const _key = 'rt_recent_car_searches';
  static const maxItems = 3;

  static Future<List<CarRecentSearch>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((j) => CarRecentSearch.fromJson(Map<String, dynamic>.from(j)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(CarRecentSearch s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await load();
      list.removeWhere((x) =>
          x.pickup == s.pickup &&
          x.dropoff == s.dropoff &&
          x.fromDate == s.fromDate &&
          x.toDate == s.toDate);
      list.insert(0, s);
      if (list.length > maxItems) list.removeRange(maxItems, list.length);
      await prefs.setString(
          _key, jsonEncode(list.map((x) => x.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}

/// صفحة كراء السيارات: اختيار مكان الاستلام والتسليم من قاعدة البيانات
/// (قائمة قابلة للبحث مثل المطارات) + الفترة والوقت ثم عرض السيارات بأسعارها.
class CarRentalScreen extends StatefulWidget {
  final AuthState auth;
  const CarRentalScreen({super.key, required this.auth});

  @override
  State<CarRentalScreen> createState() => _CarRentalScreenState();
}

class _CarRentalScreenState extends State<CarRentalScreen> {
  static const _navy = Color(0xFF1E1E5A);
  static const _gold = Color(0xFFD9A441);

  CarLocation? _pickup;
  CarLocation? _dropoff;
  DateTime _from = DateTime.now().add(const Duration(days: 1));
  DateTime _to = DateTime.now().add(const Duration(days: 3));
  TimeOfDay _fromTime = const TimeOfDay(hour: 13, minute: 0);
  TimeOfDay _toTime = const TimeOfDay(hour: 13, minute: 0);
  int? _passengers; // فارغ = كل السيارات

  List<CarRecentSearch> _recent = [];
  List<ExtraItem>? _results;
  bool _searching = false;
  String? _error;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtT(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    CarRecentStore.load().then((r) {
      if (mounted) setState(() => _recent = r);
    });
  }

  // ---------- اختيار مكان (قائمة من قاعدة البيانات مع بحث — مثل المطارات) ----------
  Future<CarLocation?> _pickLocation(String title) async {
    return showModalBottomSheet<CarLocation>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => CarLocationPickerSheet(auth: widget.auth, title: title),
    );
  }

  Future<void> _selectPickup() async {
    final loc = await _pickLocation(S.t('مكان الاستلام'));
    if (loc == null || !mounted) return;
    setState(() => _pickup = loc);
    // تسهيلاً على المستخدم: بعد اختيار الاستلام تُفتح قائمة التسليم تلقائياً
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _selectDropoff();
  }

  Future<void> _selectDropoff() async {
    final loc = await _pickLocation(S.t('مكان التسليم'));
    if (loc == null || !mounted) return;
    setState(() => _dropoff = loc);
  }

  Future<void> _pickDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: S.t('تاريخ الاستلام والتسليم'),
      locale: S.isAr ? const Locale('ar') : const Locale('en'),
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = range.start;
      _to = range.end;
    });
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

  Future<void> _pickTime(bool pickup) async {
    final t = await showTimePicker(
      context: context,
      initialTime: pickup ? _fromTime : _toTime,
    );
    if (t == null || !mounted) return;
    setState(() {
      if (pickup) {
        _fromTime = t;
      } else {
        _toTime = t;
      }
    });
  }

  Future<void> _search() async {
    if (_pickup == null || _dropoff == null) {
      setState(() => _error = S.t('اختر مكان الاستلام ومكان التسليم من القائمة.'));
      return;
    }
    if (_pickup!.country != _dropoff!.country) {
      setState(() =>
          _error = S.t('مكان الاستلام والتسليم يجب أن يكونا في نفس الدولة.'));
      return;
    }
    if (!_to.isAfter(_from)) {
      setState(() =>
          _error = S.t('تاريخ التسليم يجب أن يكون بعد تاريخ الاستلام.'));
      return;
    }
    setState(() {
      _error = null;
      _searching = true;
      _results = null;
    });
    try {
      List<dynamic> raw = await widget.auth.api.extraCatalog('CarRental',
          location: _pickup!.name, from: _from, to: _to, passengers: _passengers);
      if (raw.isEmpty) {
        // تراجع تدريجي: سيارات نفس المدينة ثم كل السيارات
        raw = await widget.auth.api.extraCatalog('CarRental',
            location: _pickup!.city, from: _from, to: _to, passengers: _passengers);
      }
      if (raw.isEmpty) {
        raw = await widget.auth.api
            .extraCatalog('CarRental', from: _from, to: _to, passengers: _passengers);
      }
      final items = raw
          .whereType<Map>()
          .map((j) => ExtraItem.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      await CarRecentStore.add(CarRecentSearch(
        pickup: _pickup!.name,
        dropoff: _dropoff!.name,
        fromDate: _fmt(_from),
        toDate: _fmt(_to),
        pickupTime: _fmtT(_fromTime),
        dropoffTime: _fmtT(_toTime),
      ));
      final recent = await CarRecentStore.load();
      if (!mounted) return;
      setState(() {
        _results = items;
        _recent = recent;
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

  void _applyRecent(CarRecentSearch r) {
    setState(() {
      _pickup = CarLocation.fromJson({'id': 0, 'name': r.pickup, 'city': '', 'country': ''});
      _dropoff = CarLocation.fromJson({'id': 0, 'name': r.dropoff, 'city': '', 'country': ''});
      _from = DateTime.tryParse(r.fromDate) ?? _from;
      _to = DateTime.tryParse(r.toDate) ?? _to;
      final pt = r.pickupTime.split(':');
      final dt = r.dropoffTime.split(':');
      if (pt.length == 2) {
        _fromTime = TimeOfDay(hour: int.parse(pt[0]), minute: int.parse(pt[1]));
      }
      if (dt.length == 2) {
        _toTime = TimeOfDay(hour: int.parse(dt[0]), minute: int.parse(dt[1]));
      }
    });
  }

  // ---------- واجهة ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        title: Text(S.t('كراء السيارات'),
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
          if (_recent.isNotEmpty) _recentSection(),
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
              Center(child: Text(S.t('لا توجد سيارات متاحة لهذه الفترة/المكان.')))
            else
              for (final c in _results!) _carCard(c),
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
          _locationTile(
            label: S.t('مكان الاستلام'),
            value: _pickup,
            onTap: _selectPickup,
          ),
          const SizedBox(height: 8),
          _locationTile(
            label: S.t('مكان التسليم'),
            value: _dropoff,
            onTap: _selectDropoff,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _infoTile(
                  label: S.t('تاريخ الاستلام'),
                  value: _fmt(_from),
                  icon: Icons.calendar_month_outlined,
                  onTap: _pickDates,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _infoTile(
                  label: S.t('تاريخ التسليم'),
                  value: _fmt(_to),
                  icon: Icons.calendar_month_outlined,
                  onTap: _pickDates,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _infoTile(
                  label: S.t('وقت الاستلام'),
                  value: _fmtT(_fromTime),
                  icon: Icons.access_time,
                  onTap: () => _pickTime(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _infoTile(
                  label: S.t('وقت التسليم'),
                  value: _fmtT(_toTime),
                  icon: Icons.access_time,
                  onTap: () => _pickTime(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _infoTile(
            label: '${S.t('عدد الأشخاص')} (${S.t('اختياري')})',
            value: _passengers == null ? S.t('الكل') : '$_passengers',
            icon: Icons.group_outlined,
            onTap: _pickPassengers,
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

  Widget _locationTile(
      {required String label, required CarLocation? value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F2F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.directions_car_filled_rounded, color: _navy),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          const TextStyle(fontSize: 11.5, color: Colors.grey)),
                  Text(
                    value?.display ?? S.t('اختر من القائمة…'),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: value == null ? Colors.grey : Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  Widget _infoTile(
      {required String label,
      required String value,
      required IconData icon,
      required VoidCallback onTap}) {
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
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(S.t('آخر بحث'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await CarRecentStore.clear();
                setState(() => _recent = []);
              },
              child: Text(S.t('مسح'),
                  style: const TextStyle(color: Colors.red, fontSize: 12.5)),
            ),
          ],
        ),
        for (final r in _recent)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            child: InkWell(
              onTap: () => _applyRecent(r),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _recentChip(r.pickup, _navy),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.compare_arrows, size: 18),
                        ),
                        Expanded(
                          child: _recentChip(r.dropoff, _gold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${r.fromDate} → ${r.toDate} • ${r.pickupTime}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _recentChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(20)),
      alignment: Alignment.center,
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    );
  }

  Widget _carCard(ExtraItem c) {
    final total = c.quoteTotal;
    final days = c.quoteDays ?? 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(c.imageUrl!,
                    width: 120,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                        width: 90,
                        height: 90,
                        child: Icon(Icons.directions_car_filled_rounded,
                            size: 44, color: Colors.grey))),
              )
            else
              const Icon(Icons.directions_car_filled_rounded,
                  size: 60, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 4),
                  _specs(c),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Money.fmt(total ?? c.price),
                              style: const TextStyle(
                                  color: _navy,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              total != null
                                  ? '${Money.fmt(total / (days > 0 ? days : 1))}${S.t('لليوم')} · $days ${S.t('يوم')}'
                                  : '${c.unitLabel ?? ''}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _openBooking(c),
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

  Widget _specs(ExtraItem c) {
    Widget chip(IconData ic, String txt) => Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic, size: 14, color: Colors.black45),
            const SizedBox(width: 3),
            Text(txt,
                style:
                    const TextStyle(fontSize: 11.5, color: Colors.black87)),
          ]),
        );
    return Wrap(
      children: [
        if (c.carType != null) chip(Icons.directions_car_outlined, c.carType!),
        if (c.seats != null) chip(Icons.person_outline, '${c.seats} ${S.t('ركاب')}'),
        if (c.fuelType != null) chip(Icons.local_gas_station_outlined, c.fuelType!),
        if (c.transmission != null) chip(Icons.settings_outlined, c.transmission!),
        if (c.color != null) chip(Icons.palette_outlined, c.color!),
      ],
    );
  }

  // ---------- الحجز: تأكيد مباشر مع خصم المحفظة وفاتورة ----------
  Future<void> _openBooking(ExtraItem car) async {
    if (!widget.auth.isAuthenticated) {
      final logged = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => LoginScreen(auth: widget.auth)),
      );
      if (logged != true || !mounted) return;
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CarBookingSheet(
        auth: widget.auth,
        car: car,
        pickup: _pickup!.name,
        dropoff: _dropoff!.name,
        from: _from,
        to: _to,
        fromTime: _fmtT(_fromTime),
        toTime: _fmtT(_toTime),
        onBooked: () {
          // تحديث النتائج بعد الحجز
        },
      ),
    );
  }
}

/// قائمة أماكن الاستلام/التسليم من قاعدة البيانات مع بحث فوري — مثل قائمة المطارات.
class CarLocationPickerSheet extends StatefulWidget {
  final AuthState auth;
  final String title;
  const CarLocationPickerSheet({required this.auth, required this.title});

  @override
  State<CarLocationPickerSheet> createState() => CarLocationPickerSheetState();
}

class CarLocationPickerSheetState extends State<CarLocationPickerSheet> {
  List<CarLocation> _items = [];
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.auth.api.carLocations(_q.isEmpty ? null : _q);
      if (!mounted) return;
      setState(() {
        _items = raw
            .whereType<Map>()
            .map((j) => CarLocation.fromJson(Map<String, dynamic>.from(j)))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: S.t('ابحث عن مطار أو مدينة…'),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (v) {
                  _q = v.trim();
                  _loading = true;
                  _load();
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(child: Text(S.t('لا توجد أماكن مطابقة')))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final l = _items[i];
                            return ListTile(
                              leading: const Icon(
                                  Icons.directions_car_filled_rounded,
                                  color: Color(0xFF1E1E5A)),
                              title: Text(l.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  '${l.nameEn ?? ''} — ${l.city} / ${l.country}'),
                              onTap: () => Navigator.pop(context, l),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// شاشة تأكيد حجز السيارة — صورة ومواصفات وملخص الفترة ثم خصم مباشر من المحفظة.
class _CarBookingSheet extends StatefulWidget {
  final AuthState auth;
  final ExtraItem car;
  final String pickup;
  final String dropoff;
  final DateTime from;
  final DateTime to;
  final String fromTime;
  final String toTime;
  final VoidCallback onBooked;

  const _CarBookingSheet({
    required this.auth,
    required this.car,
    required this.pickup,
    required this.dropoff,
    required this.from,
    required this.to,
    required this.fromTime,
    required this.toTime,
    required this.onBooked,
  });

  @override
  State<_CarBookingSheet> createState() => _CarBookingSheetState();
}

class _CarBookingSheetState extends State<_CarBookingSheet> {
  static const _navy = Color(0xFF1E1E5A);

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

  String _fmt(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  int get _days {
    final d = widget.to.difference(widget.from).inDays;
    return d < 1 ? 1 : d;
  }

  double get _total => widget.car.quoteTotal ?? widget.car.price * _days;
  double get _finalTotal => (_total - _discount).clamp(0, double.infinity);

  Future<void> _applyCoupon() async {
    final code = _coupon.text.trim();
    if (code.length < 2) return;
    setState(() {
      _couponMsg = null;
      _discount = 0;
    });
    try {
      final r = await widget.auth.api.validateCoupon(code, 'CarRental', _total);
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
        'itemId': widget.car.id,
        'customerName': _name.text.trim(),
        'phone': _phone.text.trim(),
        'dateFrom': widget.from.toIso8601String(),
        'dateTo': widget.to.toIso8601String(),
        'pickupLocation': widget.pickup,
        'dropoffLocation': widget.dropoff,
        'pickupTime': widget.fromTime,
        'dropoffTime': widget.toTime,
        if (_coupon.text.trim().isNotEmpty) 'couponCode': _coupon.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _done = true;
        _bookingId = (resp['bookingId'] as num?)?.toInt();
        _busy = false;
      });
      widget.onBooked();
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
    final c = widget.car;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.imageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(c.imageUrl!,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(c.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 17)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Money.fmt(_total),
                    style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 18)),
                Text('${Money.fmt(_total / _days)}${S.t('لليوم')}',
                    style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        // المواصفات بأيقونات
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _specIcon(Icons.person_outline, '${c.seats ?? '-'} ${S.t('ركاب')}'),
            _specIcon(Icons.directions_car_outlined, c.carType ?? '-'),
            _specIcon(Icons.settings_outlined, c.transmission ?? '-'),
            _specIcon(Icons.local_gas_station_outlined, c.fuelType ?? '-'),
            _specIcon(Icons.palette_outlined, c.color ?? '-'),
          ],
        ),
        const Divider(height: 26),
        // ملخص الاستلام والتسليم
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F2F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _summaryRow(S.t('الاستلام'),
                  '${widget.pickup} — ${_fmt(widget.from)} ${widget.fromTime}'),
              const SizedBox(height: 6),
              _summaryRow(S.t('التسليم'),
                  '${widget.dropoff} — ${_fmt(widget.to)} ${widget.toTime}'),
              const SizedBox(height: 6),
              _summaryRow(S.t('المدة'), '$_days ${S.t('يوم')}'),
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
                Text(Money.fmt(_finalTotal),
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
    final c = widget.car;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 8),
        Text(S.t('تم تأكيد حجز سيارتك ✅'),
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
              Text('🧾 ${S.t('فاتورة حجز السيارة')}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const Divider(height: 18),
              _summaryRow(S.t('مرجع الفاتورة'), 'EXTRA-${(_bookingId ?? 0)}'),
              _summaryRow(S.t('السيارة'), c.title),
              _summaryRow(S.t('الاستلام'),
                  '${widget.pickup} — ${_fmt(widget.from)} ${widget.fromTime}'),
              _summaryRow(S.t('التسليم'),
                  '${widget.dropoff} — ${_fmt(widget.to)} ${widget.toTime}'),
              _summaryRow(S.t('المدة'), '$_days ${S.t('يوم')}'),
              const Divider(height: 18),
              _summaryRow(S.t('الإجمالي المدفوع من المحفظة'),
                  Money.fmt(_finalTotal)),
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

  Widget _summaryRow(String k, String v) {
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
