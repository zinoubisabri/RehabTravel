import 'package:flutter/material.dart';

import '../airport_picker.dart';
import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';

/// تنبيهات انخفاض الأسعار — إنشاء ومتابعة وحذف.
class PriceAlertsScreen extends StatefulWidget {
  final AuthState auth;
  const PriceAlertsScreen({super.key, required this.auth});

  @override
  State<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends State<PriceAlertsScreen> {
  List<Airport>? _airports;
  Airport? _from;
  Airport? _to;
  DateTime _depart = DateTime.now().add(const Duration(days: 30));
  final _price = TextEditingController();

  bool _loading = true;
  String? _message;
  List<dynamic> _alerts = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final list = await widget.auth.api.airports();
      _airports = list
          .map((e) => Airport.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {/* تُعرض رسالة عند المحاولة */}
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.auth.api.myPriceAlerts();
      setState(() {
        _alerts = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _message = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _pickAirport(bool isFrom) async {
    final airports = _airports;
    if (airports == null) return;
    final selected = await Navigator.push<Airport>(
      context,
      MaterialPageRoute(
        builder: (_) => AirportPickerScreen(
          airports: airports,
          selectedCode: isFrom ? _from?.code : _to?.code,
        ),
      ),
    );
    if (selected != null) {
      setState(() => isFrom ? _from = selected : _to = selected);
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _create() async {
    final target = num.tryParse(_price.text.trim());
    if (_from == null || _to == null || target == null || target <= 0) {
      setState(() => _message = S.t('اختر المطارين وأدخل السعر المستهدف.'));
      return;
    }
    try {
      await widget.auth.api.createPriceAlert(
        from: _from!.code,
        to: _to!.code,
        departDate: _fmt(_depart),
        targetPrice: target,
        currency: Money.active,
      );
      _price.clear();
      setState(() => _message = S.t('تم إنشاء التنبيه — سنخبرك عند انخفاض السعر.'));
      await _load();
    } on ApiException catch (e) {
      setState(() => _message = e.message);
    }
  }

  Future<void> _delete(int id) async {
    try {
      await widget.auth.api.deletePriceAlert(id);
      await _load();
    } on ApiException catch (e) {
      setState(() => _message = e.message);
    }
  }

  /// تنبيهات العملة الحالية فقط — تنبيهات العملات الأخرى محفوظة ولا تظهر
  List<dynamic> get _visAlerts => _alerts
      .where((a) => ((a['currency']?.toString() ?? '').isEmpty ? 'LYD' : a['currency'].toString()) == Money.active)
      .toList();

  @override
  Widget build(BuildContext context) {
    final isAr = S.isAr;

    // إعادة رسم فورية عند تبديل العملة
    return ValueListenableBuilder<String>(
      valueListenable: Money.changes,
      builder: (context, activeCur, _) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('تنبيهات انخفاض الأسعار'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---------- إنشاء تنبيه ----------
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.t('🔔 نبّهني بانخفاض السعر'),
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickAirport(true),
                            child: Text(_from != null
                                ? _from!.displayName(isAr)
                                : S.t('من')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickAirport(false),
                            child: Text(_to != null
                                ? _to!.displayName(isAr)
                                : S.t('إلى')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.date_range, size: 18),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _depart,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                              );
                              if (d != null) setState(() => _depart = d);
                            },
                            label: Text(_fmt(_depart)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _price,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText:
                                  '${S.t('السعر المستهدف')} (${Money.symbol})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.notifications_active),
                        label: Text(S.t('أنشئ التنبيه')),
                        onPressed: _create,
                      ),
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
            const SizedBox(height: 8),
            Text(S.t('تنبيهاتي'),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loading && _visAlerts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(S.t('لا توجد تنبيهات بهذه العملة بعد'))),
              ),
            for (final a in _visAlerts)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_active,
                      color: Color(0xFFD9A441)),
                  title: Text(
                      '${a['fromAirport']} ← ${a['toAirport']}'),
                  subtitle: Text(
                      '${(a['departDate'] ?? '').toString().substring(0, 10)} — ${S.t('الهدف:')} ${a['targetPrice']} ${Money.symbolOf(a['currency']?.toString())}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _delete(a['id'] ?? 0),
                  ),
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
