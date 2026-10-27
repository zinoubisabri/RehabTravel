import 'package:flutter/material.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';
import '../widgets/tlync_hint.dart';

/// صفحة حجز عمرة كاملة — بيانات كل معتمر (الاسم، الجنس، تاريخ الميلاد، الجواز، الجنسية)
class UmrahBookingScreen extends StatefulWidget {
  final AuthState auth;
  final UmrahPackage package;
  const UmrahBookingScreen({super.key, required this.auth, required this.package});

  @override
  State<UmrahBookingScreen> createState() => _UmrahBookingScreenState();
}

class _PilgrimForm {
  final nameCtrl = TextEditingController();
  final passportCtrl = TextEditingController();
  final nationalityCtrl = TextEditingController(text: 'ليبي');
  String gender = 'M';
  DateTime? dob;
  String typeLabel; // للعرض فقط
  _PilgrimForm(this.typeLabel);
}

class _UmrahBookingScreenState extends State<UmrahBookingScreen> {
  int _adults = 1;
  int _children = 0;
  int _infants = 0;
  String _roomType = 'Quad';
  int _installments = 1;
  bool _busy = false;
  String? _error;
  final _couponCtrl = TextEditingController();
  Map<String, dynamic>? _couponResult;
  bool _couponBusy = false;

  /// تقدير إجمالي الطلب (سعر «من» × عدد المعتمرين) — يُستخدم فقط لمعاينة القسيمة،
  /// والخصم النهائي يُحسب على الخادم على السعر الفعلي.
  double get _estimatedTotal => widget.package.priceFrom.toDouble() * _total;

  Future<void> _checkCoupon() async {
    if (_couponCtrl.text.trim().isEmpty) return;
    setState(() {
      _couponBusy = true;
      _couponResult = null;
    });
    try {
      final r = await widget.auth.api
          .validateCoupon(_couponCtrl.text.trim(), 'Umrah', _estimatedTotal);
      setState(() => _couponResult = r);
    } on ApiException catch (e) {
      setState(() => _couponResult = {'valid': false, 'message': e.message});
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
  }

  // نحتفظ بالنماذج عبر إعادة البناء
  final Map<String, _PilgrimForm> _cache = {};
  List<_PilgrimForm> get _forms {
    final keys = <String>[
      for (var i = 0; i < _adults; i++) 'A$i',
      for (var i = 0; i < _children; i++) 'C$i',
      for (var i = 0; i < _infants; i++) 'I$i',
    ];
    _cache.removeWhere((k, v) => !keys.contains(k));
    return [
      for (var i = 0; i < _adults; i++) _cache.putIfAbsent('A$i', () => _PilgrimForm('${S.t('بالغ')} ${i + 1}')),
      for (var i = 0; i < _children; i++) _cache.putIfAbsent('C$i', () => _PilgrimForm('${S.t('طفل')} ${i + 1}')),
      for (var i = 0; i < _infants; i++) _cache.putIfAbsent('I$i', () => _PilgrimForm('${S.t('رضيع')} ${i + 1}')),
    ];
  }

  int get _total => _adults + _children + _infants;

  Widget _counter(String label, int value, int min, int max, ValueChanged<int> onChanged, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1E7A45)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDob(_PilgrimForm f) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 30),
      firstDate: DateTime(1930),
      lastDate: now,
    );
    if (picked != null) setState(() => f.dob = picked);
  }

  Future<void> _submit() async {
    final forms = _forms;
    for (var i = 0; i < forms.length; i++) {
      final f = forms[i];
      if (f.nameCtrl.text.trim().split(RegExp(r'\s+')).length < 2) {
        setState(() => _error = '${S.t('أدخل الاسم الكامل (ثلاثي على الأقل) لـ:')} ${f.typeLabel}');
        return;
      }
      if (f.passportCtrl.text.trim().length < 5) {
        setState(() => _error = '${S.t('أدخل رقم جواز صحيح لـ:')} ${f.typeLabel}');
        return;
      }
      if (f.dob == null) {
        setState(() => _error = '${S.t('اختر تاريخ الميلاد لـ:')} ${f.typeLabel}');
        return;
      }
    }
    if (_total > widget.package.availableSeats) {
      setState(() => _error = '${S.t('المقاعد المتبقية فقط:')} ${widget.package.availableSeats}');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final pilgrims = <Map<String, dynamic>>[
        for (var i = 0; i < _adults; i++) _pilgrimJson(_cache['A$i']!, 0),
        for (var i = 0; i < _children; i++) _pilgrimJson(_cache['C$i']!, 1),
        for (var i = 0; i < _infants; i++) _pilgrimJson(_cache['I$i']!, 2),
      ];

      final result = await widget.auth.api.bookUmrah({
        'packageId': widget.package.id,
        'roomType': _roomType,
        'installmentsCount': _installments,
        'payFromWallet': true,
        'pilgrims': pilgrims,
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
                '${S.t('رقم الحجز:')} ${result['bookingReference']}\n${S.t('الإجمالي:')} ${Money.fmtOrig((result['totalAmount'] as num?) ?? 0, (result['currency'] ?? 'LYD').toString(), 0)}'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context, true); // رجوع لقائمة البرامج
                  Navigator.pop(context, true); // رجوع للرئيسية/حجوزاتي
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
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Map<String, dynamic> _pilgrimJson(_PilgrimForm f, int type) => {
        'fullName': f.nameCtrl.text.trim(),
        'type': type, // 0 Adult / 1 Child / 2 Infant
        'gender': f.gender,
        'dateOfBirth': f.dob!.toIso8601String(),
        'passportNumber': f.passportCtrl.text.trim(),
        'nationality': f.nationalityCtrl.text.trim().isEmpty ? 'ليبي' : f.nationalityCtrl.text.trim(),
      };

  @override
  Widget build(BuildContext context) {
    final pkg = widget.package;
    final forms = _forms;
    return Scaffold(
      appBar: AppBar(title: Text('${S.t('حجز')}: ${pkg.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ملخص البرنامج
          Card(
            color: const Color(0xFF14532D),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pkg.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('📅 ${pkg.departureDate.substring(0, 10)} — ${pkg.nightsMakkah + pkg.nightsMadinah} ${S.t('ليلة')}',
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // عدد المعتمرين
          Text(S.t('عدد المعتمرين'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _counter(S.t('بالغ'), _adults, 1, 9, (v) => setState(() => _adults = v), Icons.person),
          const SizedBox(height: 8),
          _counter(S.t('طفل (2-11 سنة)'), _children, 0, 6, (v) => setState(() => _children = v), Icons.child_care),
          const SizedBox(height: 8),
          _counter(S.t('رضيع (أقل من سنتين)'), _infants, 0, 4, (v) => setState(() => _infants = v), Icons.baby_changing_station),
          const SizedBox(height: 16),

          // الغرفة والدفع
          DropdownButtonFormField<String>(
            value: _roomType,
            decoration: InputDecoration(labelText: S.t('نوع الغرفة'), border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: 'Quad', child: Text(S.t('رباعي'))),
              DropdownMenuItem(value: 'Triple', child: Text(S.t('ثلاثي'))),
              DropdownMenuItem(value: 'Double', child: Text(S.t('ثنائي'))),
            ],
            onChanged: (v) => setState(() => _roomType = v ?? 'Quad'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _installments,
            decoration: InputDecoration(labelText: S.t('خطة الدفع'), border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: 1, child: Text(S.t('دفعة كاملة'))),
              DropdownMenuItem(value: 2, child: Text(S.t('قسطان'))),
              DropdownMenuItem(value: 3, child: Text(S.t('3 أقساط'))),
              DropdownMenuItem(value: 4, child: Text(S.t('4 أقساط'))),
            ],
            onChanged: (v) => setState(() => _installments = v ?? 1),
          ),
          const SizedBox(height: 20),

          // بيانات المعتمرين
          Text(S.t('بيانات المعتمرين'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final f in forms)
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.typeLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E7A45))),
                    const SizedBox(height: 10),
                    TextField(
                      controller: f.nameCtrl,
                      decoration: InputDecoration(
                          labelText: S.t('الاسم الكامل كما في الجواز'),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.badge_outlined)),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: f.gender,
                            decoration: InputDecoration(
                                labelText: S.t('الجنس'), border: const OutlineInputBorder()),
                            items: [
                              DropdownMenuItem(value: 'M', child: Text(S.t('ذكر'))),
                              DropdownMenuItem(value: 'F', child: Text(S.t('أنثى'))),
                            ],
                            onChanged: (v) => setState(() => f.gender = v ?? 'M'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickDob(f),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                  labelText: S.t('تاريخ الميلاد'), border: const OutlineInputBorder()),
                              child: Text(f.dob == null
                                  ? S.t('اختر')
                                  : '${f.dob!.year}/${f.dob!.month.toString().padLeft(2, '0')}/${f.dob!.day.toString().padLeft(2, '0')}'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: f.passportCtrl,
                            decoration: InputDecoration(
                                labelText: S.t('رقم الجواز'), border: const OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: f.nationalityCtrl,
                            decoration: InputDecoration(
                                labelText: S.t('الجنسية'), border: const OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

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

          const SizedBox(height: 4),
          Text(
            '${S.t('سيُخصم من محفظتك')} ${_installments == 1 ? S.t('كامل المبلغ') : S.t('الدفعة الأولى')} — ${S.t('المقاعد المتاحة:')} ${pkg.availableSeats}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 12),
          // ---------- قسيمة التخفيض ----------
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponCtrl,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: S.t('قسيمة التخفيض (إن وجدت)'),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
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
                  fontSize: 12.5,
                  color: _couponResult!['valid'] == true
                      ? Colors.green
                      : Colors.redAccent,
                ),
              ),
            ),
          if (_couponResult?['valid'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '🎟 ${S.t('الخصم يُطبَّق على السعر النهائي عند التأكيد')}',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_busy ? S.t('جارٍ تأكيد الحجز…') : '${S.t('تأكيد حجز العمرة')} ($_total ${S.t('معتمر')})'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
