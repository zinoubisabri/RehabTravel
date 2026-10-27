import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../main.dart';
import '../money.dart';
import '../strings.dart';

/// نوع المستند المطلوب عرضه وطباعته.
enum VoucherType { flight, hotel, umrah }

/// شاشة فاوتشر/تذكرة: تجلب البيانات من الـ API، تعرضها بتصميم رسمي،
/// وتطبعها عبر التقاط البطاقة كصورة داخل PDF (يدعم العربية بلا مشاكل خطوط).
class VoucherScreen extends StatefulWidget {
  final AuthState auth;
  final VoucherType type;
  final int id;

  const VoucherScreen({
    super.key,
    required this.auth,
    required this.type,
    required this.id,
  });

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  final GlobalKey _voucherKey = GlobalKey();
  Map<String, dynamic>? _data;
  String? _error;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      Map<String, dynamic> data;
      switch (widget.type) {
        case VoucherType.flight:
          data = await widget.auth.api.ticketView(widget.id);
        case VoucherType.hotel:
          data = await widget.auth.api.hotelVoucher(widget.id);
        case VoucherType.umrah:
          data = await widget.auth.api.umrahBookingDetails(widget.id);
      }
      if (!mounted) return;
      setState(() => _data = data);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = S.t('تعذر تحميل المستند.'));
    }
  }

  String get _title => switch (widget.type) {
        VoucherType.flight => S.t('تذكرة إلكترونية'),
        VoucherType.hotel => S.t('فاوتشر فندق'),
        VoucherType.umrah => S.t('فاوتشر عمرة'),
      };

  /// يلتقط بطاقة الفاوتشر كصورة عالية الدقة ويضعها في PDF ثم يفتح نافذة الطباعة/المشاركة.
  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final boundary = _voucherKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final doc = pw.Document();
      final pwImage = pw.MemoryImage(pngBytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          build: (context) => pw.Center(
            child: pw.Image(pwImage, fit: pw.BoxFit.contain),
          ),
        ),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: 'rehab-travel-${widget.type.name}-${widget.id}.pdf',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('تعذرت الطباعة — حاول مجدداً.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_data != null)
            IconButton(
              tooltip: S.t('طباعة / مشاركة PDF'),
              onPressed: _printing ? null : _print,
              icon: _printing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print),
            ),
        ],
      ),
      body: _data == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                    )
                  : const CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // البطاقة القابلة للطباعة — تُلتقط كصورة كاملة
                  RepaintBoundary(
                    key: _voucherKey,
                    child: _buildVoucher(context),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _printing ? null : _print,
                      icon: const Icon(Icons.print),
                      label: Text(S.t('طباعة / حفظ PDF')),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildVoucher(BuildContext context) {
    final d = _data!;
    // الالتقاط يكون بخلفية بيضاء دائماً حتى في الوضع الليلي
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RtTheme.cardBorder),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الترويسة
          Container(
            padding: const EdgeInsets.all(16),
            decoration:
                const BoxDecoration(gradient: RtTheme.heroGradient),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.network(
                      widget.auth.api.brandingLogoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.flight_takeoff,
                          color: RtTheme.primaryMid,
                          size: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.t('رحاب المسافرين'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Text(_title,
                          style: const TextStyle(
                              color: RtTheme.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Text(
                  (d['reference'] ?? d['orderNumber'] ?? '').toString(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: switch (widget.type) {
              VoucherType.flight => _flightBody(d),
              VoucherType.hotel => _hotelBody(d),
              VoucherType.umrah => _umrahBody(d),
            },
          ),

          // التذييل
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            color: const Color(0xFFF4F7FA),
            child: Text(
              S.t('مستند صادر إلكترونياً من رحاب المسافرين — booking.zinoubi.net'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, color: Colors.black45),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- تذكرة طيران ----------
  Widget _flightBody(Map<String, dynamic> d) {
    final passengers = (d['passengers'] as List? ?? []);
    final segments = (d['segments'] as List? ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(S.t('الحالة'), _statusText(d['status']?.toString() ?? '')),
        _row(S.t('نوع الرحلة'), d['tripType']?.toString() ?? ''),
        _row(S.t('تاريخ الحجز'), _date(d['bookingDate'])),
        if ((d['contactEmail'] ?? '').toString().isNotEmpty)
          _row(S.t('البريد'), d['contactEmail'].toString()),
        if ((d['contactPhone'] ?? '').toString().isNotEmpty)
          _row(S.t('الهاتف'), d['contactPhone'].toString()),
        const Divider(height: 22),
        Text(S.t('الرحلات'),
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: RtTheme.primary)),
        const SizedBox(height: 6),
        for (final s in segments)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s['departAirport']} → ${s['arriveAirport']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      Text(
                        '${(S.isAr ? (s['airlineNameAr'] ?? '') : '') .toString().isNotEmpty && S.isAr ? s['airlineNameAr'] : s['airlineName']} ${s['flightNumber']}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                      // الوزن المسموح وشروط التذكرة — كما كانت وقت الحجز
                      if ((s['baggageInfo'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text('🧳 ${s['baggageInfo']}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E7A45))),
                        ),
                      if ((s['fareRules'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(S.t('شروط التذكرة:'),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black54)),
                              for (final r in (s['fareRules'] ?? '')
                                  .toString()
                                  .split('\n')
                                  .where((x) => x.trim().isNotEmpty))
                                Text('• ${r.trim()}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${_date(s['departDate'])}\n${_time(s['departTime'])}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        const Divider(height: 22),
        Text(S.t('المسافرون'),
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: RtTheme.primary)),
        const SizedBox(height: 6),
        for (final p in passengers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${p['title']} ${p['firstName']} ${p['lastName']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if ((p['ticketNumber'] ?? '').toString().isNotEmpty)
                  Text(
                    p['ticketNumber'].toString(),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: RtTheme.primaryMid),
                  ),
              ],
            ),
          ),
        const Divider(height: 22),
        _totalRow(d['totalAmount'], d['currency']?.toString() ?? 'LYD'),
      ],
    );
  }

  // ---------- فاوتشر فندق ----------
  Widget _hotelBody(Map<String, dynamic> d) {
    final guests = (d['guests'] as List? ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(d['hotelName']?.toString() ?? '',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: RtTheme.primary)),
            ),
            if ((d['starRating'] ?? 0) > 0)
              Text('★' * (d['starRating'] as num).clamp(0, 5).toInt(),
                  style: const TextStyle(color: RtTheme.accent)),
          ],
        ),
        Text(
            '${d['city'] ?? ''} ${(d['country'] ?? '').toString().isNotEmpty ? '— ${d['country']}' : ''}',
            style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
        const Divider(height: 22),
        _row(S.t('الحالة'), _statusText(d['status']?.toString() ?? '')),
        _row(S.t('تسجيل الدخول'), _date(d['checkIn'])),
        _row(S.t('تسجيل الخروج'), _date(d['checkOut'])),
        _row(S.t('الليالي'), '${d['nights'] ?? ''}'),
        _row(S.t('الغرف'), '${d['rooms'] ?? ''}'),
        _row(S.t('نوع الغرفة'), d['roomType']?.toString() ?? ''),
        _row(S.t('الوجبات'), d['mealPlan']?.toString() ?? ''),
        _row(S.t('صاحب الحجز'), d['customerName']?.toString() ?? ''),
        if (guests.isNotEmpty) ...[
          const Divider(height: 22),
          Text(S.t('النزلاء'),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: RtTheme.primary)),
          const SizedBox(height: 4),
          for (final g in guests)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${g['fullName'] ?? ''}',
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
        const Divider(height: 22),
        _totalRow(d['totalAmount'], d['currency']?.toString() ?? 'LYD'),
      ],
    );
  }

  // ---------- فاوتشر عمرة ----------
  Widget _umrahBody(Map<String, dynamic> d) {
    final pilgrims = (d['pilgrims'] as List? ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(d['packageName']?.toString() ?? '',
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: RtTheme.primary)),
        const Divider(height: 22),
        _row(S.t('الحالة'), _statusText(d['status']?.toString() ?? '')),
        _row(S.t('تاريخ السفر'), _date(d['departureDate'])),
        _row(S.t('نوع الغرفة'), d['roomType']?.toString() ?? ''),
        _row(S.t('عدد المعتمرين'), '${d['pilgrimCount'] ?? ''}'),
        if (pilgrims.isNotEmpty) ...[
          const Divider(height: 22),
          Text(S.t('المعتمرون'),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: RtTheme.primary)),
          const SizedBox(height: 4),
          for (final p in pilgrims)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '• ${p['fullName'] ?? ''}'
                '${(p['passportNumber'] ?? '').toString().isNotEmpty ? ' — ${p['passportNumber']}' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
        const Divider(height: 22),
        _totalRow(d['totalAmount'], d['currency']?.toString() ?? 'LYD'),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(dynamic amount, String currency) {
    // الإجمالي في المستند يُعرض بعملة البيع الأصلية كما دُفع — بلا تحويل
    final text =
        amount is num ? Money.fmtOrig(amount, currency) : '$amount $currency';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(S.t('الإجمالي:'),
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: RtTheme.primary)),
        Text(text,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: RtTheme.primary)),
      ],
    );
  }

  String _statusText(String status) {
    return switch (status.toLowerCase()) {
      'confirmed' || 'ticketed' => S.t('مؤكد'),
      'completed' => S.t('مكتمل'),
      'cancelled' => S.t('ملغي'),
      'pending' => S.t('قيد المعالجة'),
      'paid' => S.t('مدفوع'),
      _ => status,
    };
  }

  String _date(dynamic v) {
    if (v == null) return '';
    final dt = DateTime.tryParse(v.toString());
    if (dt == null) return v.toString();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _time(dynamic v) {
    // TimeSpan يصل كنص "HH:MM:SS"
    final s = v?.toString() ?? '';
    return s.length >= 5 ? s.substring(0, 5) : s;
  }
}
