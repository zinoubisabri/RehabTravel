import 'dart:async';
import '../hotel_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../main.dart';
import '../models.dart';
import '../money.dart';
import '../recent_searches.dart';
import '../strings.dart';
import 'hotel_details_screen.dart';

/// حجز الفنادق — إكمال تلقائي للوجهة (مخزون محلي + المزود العالمي) ثم نتائج قابلة للحجز.
class HotelsScreen extends StatefulWidget {
  final AuthState auth;
  /// أمر صوتي من المساعد الذكي: مدينة + تواريخ + غرف — يُطبَّق ويبحث تلقائياً
  final String? initialCity;
  final DateTime? initialCheckIn;
  final DateTime? initialCheckOut;
  final int? initialRooms;
  final int? initialAdults;
  const HotelsScreen({
    super.key,
    required this.auth,
    this.initialCity,
    this.initialCheckIn,
    this.initialCheckOut,
    this.initialRooms,
    this.initialAdults,
  });

  @override
  State<HotelsScreen> createState() => _HotelsScreenState();
}

class _HotelsScreenState extends State<HotelsScreen> {
  final _destination = TextEditingController();
  final FocusNode _destFocus = FocusNode();
  DateTime _checkIn = DateTime.now().add(const Duration(days: 14));
  DateTime _checkOut = DateTime.now().add(const Duration(days: 17));
  int _rooms = 1, _adults = 2, _children = 0;
  List<int> _childrenAges = []; // عمر كل طفل (مطلوب للمزود العالمي)

  void _syncChildrenAges() {
    while (_childrenAges.length < _children) {
      _childrenAges.add(7);
    }
    while (_childrenAges.length > _children) {
      _childrenAges.removeLast();
    }
  }

  // الإكمال التلقائي
  Timer? _debounce;
  List<HotelDestination> _suggestions = [];
  bool _suggestLoading = false;
  String? _selectedCode; // كود الوجهة المختارة من القائمة

  bool _loading = false;
  String? _error;
  List<HotelOffer> _offers = [];
  bool _searched = false;
  String? _message;

  // آخر 3 عمليات بحث (مثل صفحة التذاكر)
  List<HotelRecentSearch> _recent = [];

  // الفلاتر والخريطة
  int _fMinStars = 0;          // 0 = الكل
  bool _fRefundable = false;   // قابل للاسترداد فقط
  String _fSort = 'price';     // price / stars
  bool _showMap = false;

  bool get _hasFilters => _fMinStars > 0 || _fRefundable;

  /// النتائج بعد تطبيق الفلاتر والترتيب
  List<HotelOffer> get _visible {
    var list = _offers.where((o) {
      if (_fMinStars > 0 && o.starRating < _fMinStars) return false;
      if (_fRefundable && !o.refundable) return false;
      return true;
    }).toList();
    if (_fSort == 'stars') {
      list.sort((a, b) => b.starRating != a.starRating
          ? b.starRating.compareTo(a.starRating)
          : a.totalPrice.compareTo(b.totalPrice));
    } else {
      list.sort((a, b) => a.totalPrice.compareTo(b.totalPrice));
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    HotelRecentStore.load().then((r) {
      if (mounted) setState(() => _recent = r);
    });
    // أمر صوتي جاهز من المساعد الذكي (الصفحة الرئيسية) — طبّقه وابحث مباشرة
    if (widget.initialCity != null) {
      _destination.text = widget.initialCity!;
      if (widget.initialCheckIn != null) _checkIn = widget.initialCheckIn!;
      if (widget.initialCheckOut != null) _checkOut = widget.initialCheckOut!;
      _rooms = widget.initialRooms ?? 1;
      _adults = widget.initialAdults ?? 2;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _destination.dispose();
    _destFocus.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _onDestinationChanged(String value) {
    _selectedCode = null; // أي تعديل يلغي الاختيار السابق
    _debounce?.cancel();
    final term = value.trim();
    if (term.length < 2) {
      setState(() {
        _suggestions = [];
        _suggestLoading = false;
      });
      return;
    }
    setState(() => _suggestLoading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final list = await widget.auth.api.hotelDestinations(term);
        if (!mounted) return;
        // تجاهل الرد إذا تغيّر النص أثناء الطلب
        if (_destination.text.trim() != term) return;
        setState(() {
          _suggestions = list
              .map((e) => HotelDestination.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _suggestLoading = false;
        });
      } on ApiException {
        if (!mounted) return;
        setState(() {
          _suggestions = [];
          _suggestLoading = false;
        });
      }
    });
  }

  void _pickDestination(HotelDestination d) {
    _destination.text = d.name;
    _selectedCode = d.code;
    _suggestions = [];
    _destFocus.unfocus();
    setState(() {});
  }

  Future<void> _search() async {
    _destFocus.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
      _offers = [];
      _suggestions = [];
    });
    try {
      // نرسل كود الوجهة المختار إن وُجد (أدق للمزود العالمي) وإلا النص الحر
      final result = await widget.auth.api.searchHotels(
        destination: _selectedCode ?? _destination.text.trim(),
        checkIn: _fmt(_checkIn),
        checkOut: _fmt(_checkOut),
        rooms: _rooms,
        adults: _adults,
        children: _children,
        childrenAges: _childrenAges,
      );
      if (!mounted) return;
      setState(() {
        final all = ((result['offers'] ?? []) as List)
            .map((o) => HotelOffer.fromJson(Map<String, dynamic>.from(o)))
            .toList();
        // لا تكرار: نفس الفندق (من أي مزود) يظهر مرة واحدة بأرخص عرض
        final cheapest = <String, HotelOffer>{};
        for (final o in all) {
          final key = '${o.hotelName.trim().toLowerCase()}|${o.city.trim().toLowerCase()}';
          final cur = cheapest[key];
          if (cur == null || o.totalPrice < cur.totalPrice) cheapest[key] = o;
        }
        _offers = cheapest.values.toList()
          ..sort((a, b) => a.totalPrice.compareTo(b.totalPrice));
        // حفظ في «آخر بحث» (آخر 3 عمليات)
        HotelRecentStore.add(HotelRecentSearch(
          destination: _selectedCode ?? _destination.text.trim(),
          destinationLabel: _destination.text.trim(),
          checkIn: _fmt(_checkIn),
          checkOut: _fmt(_checkOut),
          rooms: _rooms,
          adults: _adults,
          children: _children,
        )).then((_) => HotelRecentStore.load()).then((r) {
          if (mounted) setState(() => _recent = r);
        });
        // رسالة المزود (مثلاً انتهت مهلة أو وجهة غير مدعومة) تظهر بدل صمتٍ محيّر
        final apiErr = result['apiError']?.toString();
        _error = _offers.isEmpty && apiErr != null && apiErr.isNotEmpty
            ? apiErr
            : null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// خريطة النتائج: كل فندق علامة سعر بأرخص عرض — الضغط على العلامة يفتح التفاصيل.
  Widget _buildMap() {
    final points = _visible
        .where((o) => o.latitude != null && o.longitude != null)
        .toList();
    if (points.isEmpty) return const SizedBox.shrink();
    final center = LatLng(
      points.map((e) => e.latitude!).reduce((a, b) => a + b) / points.length,
      points.map((e) => e.longitude!).reduce((a, b) => a + b) / points.length,
    );
    return Container(
      height: 300,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      child: FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: 12),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.rehabtravel.app',
          ),
          MarkerLayer(
            markers: [
              for (final o in points)
                Marker(
                  point: LatLng(o.latitude!, o.longitude!),
                  width: 76,
                  height: 38,
                  child: GestureDetector(
                    onTap: () => _openDetails(o),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E5A),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ],
                      ),
                      child: Text(
                        () {
                          final p = Money.convert(o.totalPrice, o.currency);
                          return p >= 1000
                              ? '${(p / 1000).toStringAsFixed(1)}K'
                              : p.toStringAsFixed(0);
                        }(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// نافذة الفلاتر والترتيب — تظهر عند الضغط على الزر.
  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.t('الفلتر والترتيب'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 12),
              Text(S.t('ترتيب حسب'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              RadioListTile<String>(
                value: 'price',
                groupValue: _fSort,
                onChanged: (v) => setSheet(() => _fSort = v!),
                title: Text(S.t('الأرخص أولاً')),
                dense: true,
              ),
              RadioListTile<String>(
                value: 'stars',
                groupValue: _fSort,
                onChanged: (v) => setSheet(() => _fSort = v!),
                title: Text(S.t('الأعلى تقييماً')),
                dense: true,
              ),
              const Divider(),
              Text(S.t('عدد النجوم'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in [0, 3, 4, 5])
                    ChoiceChip(
                      label: Text(s == 0 ? S.t('الكل') : '$s ★+'),
                      selected: _fMinStars == s,
                      onSelected: (_) => setSheet(() => _fMinStars = s),
                    ),
                ],
              ),
              CheckboxListTile(
                value: _fRefundable,
                onChanged: (v) => setSheet(() => _fRefundable = v ?? false),
                title: Text(S.t('قابل للاسترداد فقط')),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setSheet(() {
                          _fMinStars = 0;
                          _fRefundable = false;
                          _fSort = 'price';
                        });
                        setState(() {});
                      },
                      child: Text(S.t('إعادة الضبط')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        setState(() {});
                        Navigator.pop(ctx);
                      },
                      child: Text(S.t('عرض النتائج')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetails(HotelOffer offer) {
    if (offer.source == 'Manual' || offer.hotelCode.isEmpty) {
      setState(() => _message =
          S.t('هذا العرض من مخزون الشركة — للحجز تواصل معنا أو احجز من الموقع.'));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HotelDetailsScreen(
          auth: widget.auth,
          offer: offer,
          checkIn: _fmt(_checkIn),
          checkOut: _fmt(_checkOut),
          rooms: _rooms,
          adults: _adults,
          childrenAges: _childrenAges,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('حجز الفنادق'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // بطاقة البحث
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // الوجهة مع إكمال تلقائي
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _destination,
                        focusNode: _destFocus,
                        decoration: InputDecoration(
                          labelText: S.t('الوجهة (المدينة)'),
                          hintText: S.t('اكتب حرفين على الأقل…'),
                          prefixIcon: const Icon(Icons.location_city),
                          suffixIcon: _suggestLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                )
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: _onDestinationChanged,
                      ),
                      if (_suggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Theme.of(context).dividerColor),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _suggestions.length,
                            itemBuilder: (context, i) {
                              final d = _suggestions[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  d.source == 'Local'
                                      ? Icons.verified
                                      : Icons.public,
                                  size: 20,
                                  color: d.source == 'Local'
                                      ? RtTheme.success
                                      : RtTheme.primaryMid,
                                ),
                                title: Text(d.name,
                                    style: const TextStyle(fontSize: 14)),
                                subtitle: d.countryName.isEmpty
                                    ? null
                                    : Text(d.countryName,
                                        style:
                                            const TextStyle(fontSize: 12)),
                                trailing: d.hotelCount > 0
                                    ? Text('${d.hotelCount} 🏨',
                                        style:
                                            const TextStyle(fontSize: 11))
                                    : null,
                                onTap: () => _pickDestination(d),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      alignment: AlignmentDirectional.centerStart,
                    ),
                    icon: const Icon(Icons.date_range),
                    label: Text('${_fmt(_checkIn)}  ←  ${_fmt(_checkOut)}'),
                    onPressed: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                        initialDateRange: DateTimeRange(
                            start: _checkIn, end: _checkOut),
                      );
                      if (range != null) {
                        setState(() {
                          _checkIn = range.start;
                          _checkOut = range.end;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _adults,
                          decoration: InputDecoration(
                              labelText: S.t('بالغ'),
                              border: const OutlineInputBorder()),
                          items: [
                            for (var i = 1; i <= 6; i++)
                              DropdownMenuItem(value: i, child: Text('$i'))
                          ],
                          onChanged: (v) =>
                              setState(() => _adults = v ?? 2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _children,
                          decoration: InputDecoration(
                              labelText: S.t('أطفال'),
                              border: const OutlineInputBorder()),
                          items: [
                            for (var i = 0; i <= 4; i++)
                              DropdownMenuItem(value: i, child: Text('$i'))
                          ],
                          onChanged: (v) => setState(() {
                                _children = v ?? 0;
                                _syncChildrenAges();
                              }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _rooms,
                          decoration: InputDecoration(
                              labelText: S.t('غرف'),
                              border: const OutlineInputBorder()),
                          items: [
                            for (var i = 1; i <= 4; i++)
                              DropdownMenuItem(value: i, child: Text('$i'))
                          ],
                          onChanged: (v) => setState(() => _rooms = v ?? 1),
                        ),
                      ),
                    ],
                  ),
                  if (_children > 0) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(S.t('أعمار الأطفال'),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < _children; i++)
                          SizedBox(
                            width: 110,
                            child: DropdownButtonFormField<int>(
                              value: _childrenAges[i],
                              decoration: InputDecoration(
                                  labelText: '${S.t('طفل')} ${i + 1}',
                                  border: const OutlineInputBorder(),
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 8)),
                              items: [
                                for (var a = 0; a <= 17; a++)
                                  DropdownMenuItem(
                                      value: a, child: Text('$a ${S.t('سنة')}'))
                              ],
                              onChanged: (v) =>
                                  setState(() => _childrenAges[i] = v ?? 7),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.search),
                    label: Text(S.t('ابحث عن فنادق')),
                    onPressed: _loading || _destination.text.trim().isEmpty
                        ? null
                        : _search,
                  ),
                ],
              ),
            ),
          ),

          // ---------- آخر 3 عمليات بحث (مثل صفحة التذاكر) ----------
          if (_recent.isNotEmpty && !_searched) ...[
            Row(
              children: [
                Text(S.t('آخر بحث'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await HotelRecentStore.clear();
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
                child: ListTile(
                  leading: const Icon(Icons.history, color: Color(0xFF0F6B4A)),
                  title: Text(r.destinationLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${r.checkIn} → ${r.checkOut} • ${r.rooms} ${S.t('غرفة')} / ${r.adults} ${S.t('بالغ')}',
                      style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.north_west, size: 16),
                  onTap: () {
                    setState(() {
                      _destination.text = r.destinationLabel;
                      _selectedCode =
                          r.destination != r.destinationLabel ? r.destination : null;
                      _checkIn = DateTime.tryParse(r.checkIn) ?? _checkIn;
                      _checkOut = DateTime.tryParse(r.checkOut) ?? _checkOut;
                      _rooms = r.rooms;
                      _adults = r.adults;
                      _children = r.children;
                      _syncChildrenAges();
                    });
                    _search();
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],

          if (_message != null)
            Card(
              color: const Color(0xFFE4F5EC),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_message!),
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(color: Colors.red.shade700)),
                    ),
                  ],
                ),
              ),
            ),
          // حالة «لا نتائج» الواضحة بدل شاشة فارغة محيّرة
          if (_searched && !_loading && _offers.isEmpty && _error == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.hotel_outlined,
                        size: 44, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(
                      S.t('لا توجد فنادق متاحة لهذه الوجهة والتواريخ — جرّب وجهة أو تواريخ أخرى.'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          // ---------- شريط النتائج: العدد + زر الفلاتر + الخريطة ----------
          if (_searched && _offers.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8)
                ],
              ),
              child: Row(
                children: [
                  Text(
                    '${S.t('عدد الفنادق')} (${_visible.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: S.t('الخريطة'),
                    onPressed: () =>
                        setState(() => _showMap = !_showMap),
                    icon: Icon(
                      _showMap ? Icons.list_rounded : Icons.map_outlined,
                      color: _showMap
                          ? const Color(0xFF0F6B4A)
                          : Colors.black54,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openFilters,
                    icon: Icon(Icons.tune_rounded,
                        size: 18,
                        color: _hasFilters
                            ? const Color(0xFFD9A441)
                            : Colors.black54),
                    label: Text(
                      S.t('الفلتر والترتيب'),
                      style: TextStyle(
                          color: _hasFilters
                              ? const Color(0xFFD9A441)
                              : Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          if (_showMap && _visible.any((o) => o.latitude != null))
            _buildMap()
          else if (_showMap)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  S.t('إحداثيات الفنادق غير متوفرة من المزود لهذه النتائج — تظهر الخريطة عند توفرها.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
              ),
            ),
          for (final offer in _visible)
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (offer.imageUrl.isNotEmpty)
                    Image.network(
                      offer.imageUrl,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(offer.hotelName,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        Text('★' * offer.starRating.clamp(0, 5),
                            style: const TextStyle(
                                color: Color(0xFFD9A441), fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                        '${offer.city} — ${localizeHotelText(offer.roomType)} — ${localizeHotelText(offer.mealPlan)}'),
                    Text(
                      '${offer.nights} ${S.t('ليالٍ')} • ${offer.refundable ? S.t('قابل للاسترداد') : S.t('غير قابل للاسترداد')}',
                      style: TextStyle(
                          fontSize: 12,
                          color: offer.refundable
                              ? const Color(0xFF1E7A45)
                              : Colors.grey),
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Money.fmt0(offer.totalPrice, offer.currency),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0E3A5D))),
                        FilledButton(
                          onPressed: () => _openDetails(offer),
                          child: Text(S.t('التفاصيل')),
                        ),
                      ],
                    ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
