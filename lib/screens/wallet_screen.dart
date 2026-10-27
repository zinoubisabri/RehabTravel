import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';

class WalletScreen extends StatefulWidget {
  final AuthState auth;
  /// مبلغ مبدئي لشحن Tlync — يُمرَّر من صفحات الحجز عند نقص الرصيد
  final double? initialAmount;
  const WalletScreen({super.key, required this.auth, this.initialAmount});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  WalletInfo? _wallet;
  Map<String, dynamic>? _loyalty;
  String? _message;
  bool _loading = true;
  final _amount = TextEditingController(text: '100');
  final _note = TextEditingController();
  String _depositCurrency = 'LYD';
  final _tlyncAmount = TextEditingController();
  final _tlyncPhone = TextEditingController();
  bool _tlyncBusy = false;
  String? _tlyncMsg;
  final _picker = ImagePicker();
  Uint8List? _receiptBytes;
  String? _receiptName;
  bool _submitting = false;
  bool _redeemBusy = false;

  /// استبدال كل نقاط الولاء برصيد دينار — يُضاف لمحفظة LYD فقط حتى لو اختار العميل عملة أخرى
  Future<void> _redeemAll() async {
    final points = ((_loyalty?['balance'] as num?) ?? 0).toInt();
    if (points <= 0 || _redeemBusy) return;
    setState(() => _redeemBusy = true);
    try {
      final r = await widget.auth.api.redeemLoyalty(points);
      if (!mounted) return;
      setState(() => _message =
          r['message']?.toString() ?? S.t('تم الاستبدال وأُضيف الرصيد لمحفظة الدينار 🇱🇾'));
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = S.t('تعذر الاستبدال — تحقق من الإنترنت وحاول مجدداً'));
    } finally {
      if (mounted) setState(() => _redeemBusy = false);
    }
  }

  static String _curSym(String? c) => c == 'USD'
      ? '\$'
      : c == 'EUR'
          ? '€'
          : 'د.ل';

  /// رصيد محفظة العملة الحالية المختارة — أرصدة العملات الأخرى لا تظهر للعميل إطلاقاً
  num? get _activeBalance => switch (Money.active) {
        'USD' => _wallet?.balanceUsd,
        'EUR' => _wallet?.balanceEur,
        _ => _wallet?.balance,
      };

  String get _activeLabel => switch (Money.active) {
        'USD' => S.t('دولار أمريكي'),
        'EUR' => S.t('يورو'),
        _ => S.t('دينار ليبي'),
      };

  /// سجل المعاملات بالعملة الحالية فقط — معاملات العملات الأخرى مخفية
  List<Map<String, dynamic>> get _visTx => (_wallet?.transactions ?? const [])
      .where((t) =>
          ((t['currency']?.toString() ?? '').isEmpty ? 'LYD' : t['currency'].toString()) ==
          Money.active)
      .toList();

  Future<void> _pickReceipt(ImageSource source) async {
    try {
      final x = await _picker.pickImage(source: source, imageQuality: 80, maxWidth: 1600);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _receiptBytes = bytes;
        _receiptName = x.name;
      });
    } catch (_) {}
  }

  void _clearReceipt() => setState(() {
        _receiptBytes = null;
        _receiptName = null;
      });

  @override
  void initState() {
    super.initState();
    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _tlyncAmount.text = widget.initialAmount!.toStringAsFixed(0);
    }
    // عملة الشحن الافتراضية = عملة العميل الحالية
    _depositCurrency = Money.active;
    _load();
  }

  /// شحن فوري عبر Tlync: إنشاء العملية → فتح صفحة الدفع → استطلاع النتيجة عند العودة
  Future<void> _payTlync() async {
    final amount = num.tryParse(_tlyncAmount.text) ?? 0;
    if (amount < 5) {
      setState(() => _tlyncMsg = S.t('الحد الأدنى للدفع عبر Tlync هو 5 د.ل.'));
      return;
    }
    setState(() {
      _tlyncBusy = true;
      _tlyncMsg = null;
    });
    try {
      final r = await widget.auth.api.initiateTlync(amount, 'WalletTopUp',
          phone: _tlyncPhone.text.trim().isEmpty ? null : _tlyncPhone.text.trim());
      if (r['success'] != true || r['redirectUrl'] == null) {
        setState(() {
          _tlyncMsg = r['message']?.toString() ?? S.t('تعذر بدء الدفع — حاول لاحقاً.');
          _tlyncBusy = false;
        });
        return;
      }
      final ref = r['paymentReference']?.toString();
      final url = Uri.parse(r['redirectUrl'].toString());
      await launchUrl(url, mode: LaunchMode.externalApplication);
      // عاد المستخدم من صفحة البوابة — استطلع النتيجة حتى 5 مرات
      if (ref != null) {
        for (var i = 0; i < 5; i++) {
          await Future.delayed(const Duration(seconds: 2));
          try {
            final st = await widget.auth.api.paymentStatus(ref);
            final s = st['status']?.toString();
            if (s == 'Completed') {
              setState(() {
                _tlyncMsg = '✅ ${S.t('تم الدفع بنجاح وشُحنت محفظتك.')}';
                _tlyncBusy = false;
              });
              await _load();
              return;
            }
            if (s == 'Failed') {
              setState(() {
                _tlyncMsg = '❌ ${S.t('فشلت عملية الدفع — لم يُخصم أي مبلغ نهائياً.')}';
                _tlyncBusy = false;
              });
              return;
            }
          } catch (_) {}
        }
      }
      setState(() {
        _tlyncMsg = '⏳ ${S.t('العملية قيد المعالجة — اسحب للتحديث بعد دقائق.')}';
        _tlyncBusy = false;
      });
      await _load();
    } on ApiException catch (e) {
      setState(() {
        _tlyncMsg = e.message;
        _tlyncBusy = false;
      });
    } catch (_) {
      setState(() {
        _tlyncMsg = S.t('تعذر فتح صفحة الدفع — حاول مجدداً.');
        _tlyncBusy = false;
      });
    }
  }

  Future<void> _load() async {
    await Money.load(widget.auth.api, force: true);
    try {
      final results = await Future.wait([
        widget.auth.api.wallet(),
        widget.auth.api.loyaltyBalance(),
      ]);
      setState(() {
        _wallet = WalletInfo.fromJson(results[0]);
        _loyalty = results[1];
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _message = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _submitDeposit() async {
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      setState(() => _message = S.t('أدخل مبلغاً صحيحاً.'));
      return;
    }
    if (_receiptBytes == null) {
      setState(() => _message = S.t('أرفق صورة الحوالة أولاً — إثبات التحويل مطلوب.'));
      return;
    }
    setState(() => _submitting = true);
    try {
      // 1) ارفع صورة الإيصال ثم 2) أرسل الطلب بمسارها — مثل الموقع تماماً
      final uploaded =
          await widget.auth.api.uploadDepositReceipt(_receiptBytes!, _receiptName ?? 'receipt.jpg');
      if (uploaded == null) {
        setState(() {
          _message = S.t('تعذر رفع صورة الإيصال — حاول مجدداً.');
          _submitting = false;
        });
        return;
      }
      await widget.auth.api.submitDeposit(
        amount,
        _note.text.trim().isEmpty ? null : _note.text.trim(),
        receiptPath: uploaded.path,
        receiptFileName: uploaded.fileName,
        currency: _depositCurrency,
      );
      setState(() {
        _message = S.t('تم إرسال طلب الشحن — سنراجعه ونضيف الرصيد قريباً.');
        _submitting = false;
      });
      _note.clear();
      _clearReceipt();
    } on ApiException catch (e) {
      setState(() {
        _message = e.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // إعادة رسم فورية عند تبديل العملة — يتحدث الرصيد والسجل فوراً
    return ValueListenableBuilder<String>(
      valueListenable: Money.changes,
      builder: (context, activeCur, _) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('محفظتي'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0E3A5D), Color(0xFF1B6AA5)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${S.t('محفظة')} $_activeLabel — ${S.t('الخصم يتم منها')}',
                      style: const TextStyle(color: Colors.white70)),
                  Text(
                    _activeBalance == null
                        ? '…'
                        : '${_activeBalance!.toStringAsFixed(2)} ${Money.symbol}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.t('تُعرض هنا محفظة عملتك الحالية فقط — أرصدة عملاتك الأخرى محفوظة ولا تظهر هنا.'),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFD9A441),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${S.t('🎁 نقاط الولاء:')} ${(_loyalty?['balance'] ?? 0)} ${S.t('نقطة')}',
                    style: const TextStyle(
                        color: Color(0xFF0A2C47), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    S.t('كل نقطة = ${((_loyalty?['redeemValuePerPoint'] as num?) ?? 1).toStringAsFixed(2)} د.ل — الاستبدال يُضاف لمحفظة الدينار دائماً مهما كانت عملتك المختارة.'),
                    style: const TextStyle(
                        color: Color(0xFF0A2C47), fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0A2C47)),
                      onPressed: _redeemBusy ||
                              ((_loyalty?['balance'] as num?) ?? 0) <= 0
                          ? null
                          : _redeemAll,
                      icon: const Icon(Icons.currency_exchange, size: 18),
                      label: _redeemBusy
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(S.t('استبدال الكل برصيد دينار 🇱🇾')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚡ ${S.t('شحن فوري عبر Tlync')}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      S.t('ادفع ببطاقتك أو محفظتك المحلية — يُضاف الرصيد لمحفظة الدينار فور نجاح الدفع.'),
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tlyncAmount,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: S.t('المبلغ (د.ل)'),
                                border: const OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _tlyncPhone,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                                labelText: S.t('رقم هاتفك'),
                                border: const OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F6B4A)),
                          onPressed: _tlyncBusy ? null : _payTlync,
                          icon: const Icon(Icons.payment),
                          label: _tlyncBusy
                              ? const SizedBox(
                                  height: 18, width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(S.t('ادفع الآن عبر Tlync'))),
                    ),
                    if (_tlyncMsg != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_tlyncMsg!, style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.t('شحن المحفظة'),
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        S.t('حوّل المبلغ لحساب الشركة ثم أرسل الطلب هنا.'),
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _depositCurrency,
                      decoration: InputDecoration(
                          labelText: S.t('عملة الشحن'),
                          border: const OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: 'LYD', child: Text('🇱🇾 ${S.t('دينار ليبي')}')),
                        DropdownMenuItem(value: 'USD', child: Text('💵 ${S.t('دولار أمريكي')}')),
                        DropdownMenuItem(value: 'EUR', child: Text('💶 ${S.t('يورو')}')),
                      ],
                      onChanged: (v) =>
                          setState(() => _depositCurrency = v ?? 'LYD'),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                          S.t('يُضاف المبلغ لمحفظة العملة المختارة فقط'),
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amount,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText:
                                    '${S.t('المبلغ')} (${_curSym(_depositCurrency)})',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _note,
                            decoration: InputDecoration(
                                labelText: S.t('رقم الإشعار'),
                                border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(S.t('صورة الحوالة (مطلوبة)'),
                          style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                    ),
                    const SizedBox(height: 4),
                    if (_receiptBytes == null)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _submitting ? null : () => _pickReceipt(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: Text(S.t('من المعرض')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _submitting ? null : () => _pickReceipt(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: Text(S.t('الكاميرا')),
                            ),
                          ),
                        ],
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_receiptBytes!,
                                  height: 56, width: 56, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_receiptName ?? '',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                            IconButton(
                              onPressed: _submitting ? null : _clearReceipt,
                              icon: const Icon(Icons.close, color: Colors.redAccent),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: _submitting ? null : _submitDeposit,
                          child: _submitting
                              ? const SizedBox(
                                  height: 18, width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(S.t('إرسال طلب الشحن'))),
                    ),
                  ],
                ),
              ),
            ),
            if (_message != null)
              Card(
                color: const Color(0xFFE7F0FB),
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
            if (_visTx.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    '${S.t('سجل المعاملات')} — $_activeLabel (${Money.symbol})',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final t in _visTx)
                Card(
                  child: ListTile(
                    title: Text(t['description'] ?? ''),
                    subtitle: Text((t['transactionDate'] ?? '')
                        .toString()
                        .replaceAll('T', ' ')
                        .substring(0, 16)),
                    trailing: Text(
                      '${(t['amount'] as num).toStringAsFixed(2)} ${_curSym(t['currency']?.toString())}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: (t['amount'] as num) >= 0
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ),
                ),
            ] else if (_wallet != null && !_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  S.t('لا توجد معاملات بهذه العملة بعد.'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
    );
      },
    );
  }
}
