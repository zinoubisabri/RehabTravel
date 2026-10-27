import 'package:flutter/material.dart';
import '../hotel_text.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';
import 'hotel_booking_screen.dart';

/// صفحة تفاصيل الفندق — معرض صور + وصف + كل خيارات الإقامة المتاحة
class HotelDetailsScreen extends StatefulWidget {
  final AuthState auth;
  final HotelOffer offer;
  final String checkIn;
  final String checkOut;
  final int rooms;
  final int adults;
  final List<int> childrenAges;

  const HotelDetailsScreen({
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
  State<HotelDetailsScreen> createState() => _HotelDetailsScreenState();
}

class _HotelDetailsScreenState extends State<HotelDetailsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _hotel;
  List<HotelOffer> _rates = [];
  final _pageCtrl = PageController();
  int _photoIndex = 0;

  String get _occ {
    if (widget.childrenAges.isEmpty) return '';
    final rooms = <String>['${widget.adults}:${widget.childrenAges.join(',')}'];
    for (var r = 1; r < widget.rooms; r++) {
      rooms.add('2');
    }
    return rooms.join('~');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.auth.api.hotelDetails(
        widget.offer.hotelCode,
        widget.checkIn,
        widget.checkOut,
        rooms: widget.rooms,
        adults: widget.adults,
        occ: _occ,
      );
      if (!mounted) return;
      setState(() {
        _hotel = d;
        _rates = ((d['rates'] ?? []) as List)
            .map((o) => HotelOffer.fromJson(Map<String, dynamic>.from(o)))
            .toList();
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

  void _book(HotelOffer rate) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HotelBookingScreen(
          auth: widget.auth,
          offer: rate,
          checkIn: widget.checkIn,
          checkOut: widget.checkOut,
          rooms: widget.rooms,
          adults: widget.adults,
          childrenAges: widget.childrenAges,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final images = ((_hotel?['images'] ?? []) as List)
        .map((e) => e.toString())
        .where((e) => e.startsWith('http'))
        .toList();
    final name = _hotel?['name']?.toString().isNotEmpty == true
        ? _hotel!['name'].toString()
        : offer.hotelName;

    return Scaffold(
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: () {
                              setState(() {
                                _loading = true;
                                _error = null;
                              });
                              _load();
                            },
                            child: Text(S.t('إعادة المحاولة'))),
                      ],
                    ),
                  ),
                )
              : ListView(
                  children: [
                    // معرض الصور
                    if (images.isNotEmpty)
                      SizedBox(
                        height: 240,
                        child: Stack(
                          children: [
                            PageView.builder(
                              controller: _pageCtrl,
                              itemCount: images.length,
                              onPageChanged: (i) =>
                                  setState(() => _photoIndex = i),
                              itemBuilder: (_, i) => Image.network(
                                images[i],
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.hotel, size: 64),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0;
                                      i < images.length.clamp(0, 10);
                                      i++)
                                    Container(
                                      width: 7,
                                      height: 7,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: i == _photoIndex
                                            ? Colors.white
                                            : Colors.white54,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (images.length > 1)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${_photoIndex + 1}/${images.length}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(name,
                                    style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.bold)),
                              ),
                              Text(
                                '★' *
                                    ((_hotel?['starRating'] ??
                                                offer.starRating) as num)
                                        .toInt()
                                        .clamp(0, 5),
                                style: const TextStyle(
                                    color: Color(0xFFD9A441), fontSize: 15),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if ((_hotel?['address'] ?? '').toString().isNotEmpty)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on_outlined,
                                    size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${_hotel!['address']}${(_hotel?['city'] ?? '').toString().isNotEmpty ? ' — ${_hotel!['city']}' : ''}${(_hotel?['country'] ?? '').toString().isNotEmpty ? '، ${_hotel!['country']}' : ''}',
                                    style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 6),
                          Text(
                            '${widget.checkIn} ← ${widget.checkOut} • ${_hotel?['nights'] ?? offer.nights} ${S.t('ليالٍ')} • ${widget.rooms} ${S.t('غرفة')}',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13),
                          ),
                          if ((_hotel?['description'] ?? '')
                              .toString()
                              .isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(S.t('عن الفندق'),
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(
                              _hotel!['description'].toString(),
                              style: const TextStyle(fontSize: 13, height: 1.7),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Text(
                              '${S.t('خيارات الإقامة المتاحة')} (${_rates.length})',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          if (_rates.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                  S.t('لا توجد أسعار متاحة لهذه التواريخ — جرّب تواريخ أخرى.')),
                            ),
                          for (final rate in _rates)
                            Card(
                              elevation: 1,
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(localizeHotelText(rate.roomType),
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold)),
                                          Text(localizeHotelText(rate.mealPlan),
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      Colors.grey.shade600)),
                                          Text(
                                            rate.refundable
                                                ? S.t('إلغاء مجاني')
                                                : S.t('غير قابل للاسترداد'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: rate.refundable
                                                  ? const Color(0xFF1E7A45)
                                                  : Colors.red.shade400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          Money.fmt0(rate.totalPrice, rate.currency),
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0E3A5D)),
                                        ),
                                        const SizedBox(height: 6),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 18)),
                                          onPressed: () => _book(rate),
                                          child: Text(S.t('احجز')),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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
