import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';

/// شرائحي — طلبات eSIM الخاصة بالعميل مع رموز QR وحالة التفعيل والإلغاء.
class EsimMyScreen extends StatefulWidget {
  final AuthState auth;
  const EsimMyScreen({super.key, required this.auth});

  @override
  State<EsimMyScreen> createState() => _EsimMyScreenState();
}

class _EsimMyScreenState extends State<EsimMyScreen> {
  bool _loading = true;
  String? _error;
  List<EsimOrderListItem> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.auth.api.myEsimOrders();
      if (!mounted) return;
      setState(() {
        _orders = list
            .map((e) => EsimOrderListItem.fromJson(Map<String, dynamic>.from(e)))
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

  String _statusName(String s) {
    switch (s) {
      case 'Completed':
        return S.t('مكتمل');
      case 'Processing':
        return S.t('قيد التجهيز');
      case 'Pending':
        return S.t('بانتظار الدفع');
      case 'Failed':
        return S.t('فشل — أُعيد المبلغ');
      case 'Cancelled':
        return S.t('ملغي — أُعيد المبلغ');
      default:
        return s;
    }
  }

  Future<void> _showDetails(EsimOrderListItem order) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final d = await widget.auth.api.esimOrderDetails(order.id);
      if (!mounted) return;
      Navigator.pop(context);
      final items = ((d['esims'] ?? []) as List)
          .map((e) => EsimItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final notes = (d['notes'] ?? '').toString();

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(order.planName),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(notes,
                        style: TextStyle(color: Colors.grey.shade700)),
                  ),
                if (items.isEmpty)
                  Text(S.t(
                      'الشريحة قيد التجهيز — حدّث القائمة بعد قليل ليظهر رمز QR.')),
                for (final it in items) ...[
                  if (it.qrUrl.isNotEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Image.network(
                          it.qrUrl,
                          width: 180,
                          height: 180,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image, size: 60),
                        ),
                      ),
                    ),
                  if (it.iccid.isNotEmpty)
                    _copyRow('ICCID', it.iccid),
                  if (it.lpa.isNotEmpty)
                    _copyRow('LPA', it.lpa),
                  if (it.expiresAt.isNotEmpty)
                    Text('${S.t('تنتهي:')} ${it.expiresAt.substring(0, 10)}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  const Divider(),
                ],
              ],
            ),
          ),
          actions: [
            if (order.status == 'Completed' || order.status == 'Processing')
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _cancel(order);
                },
                child: Text(S.t('إلغاء واسترداد'),
                    style: const TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.t('إغلاق')),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _copyRow(String label, String value) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('تم النسخ'))),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ),
            const Icon(Icons.copy, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(EsimOrderListItem order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('إلغاء الشريحة؟')),
        content: Text(S.t(
            'يُلغى التفعيل لدى المزوّد ويُعاد كامل المبلغ لمحفظتك — ممكن فقط إن لم تُفعَّل الشريحة بعد.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('تراجع')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('تأكيد الإلغاء')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final result = await widget.auth.api.cancelEsimOrder(order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message']?.toString() ?? ''),
        backgroundColor:
            result['success'] == true ? Colors.green : Colors.red.shade700,
      ));
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message), backgroundColor: Colors.red.shade700));
    }
  }

  @override
  Widget build(BuildContext context) {
    // فلتر العملة: لا تظهر إلا طلبات بعملة العميل الحالية — ويُعاد الرسم فور تغييرها
    return ValueListenableBuilder<String>(
      valueListenable: Money.changes,
      builder: (context, activeCur, _) {
        final visOrders = _orders
            .where((o) =>
                (o.currency.isEmpty ? 'LYD' : o.currency) == Money.active)
            .toList();
        final curLabel = switch (Money.active) {
          'USD' => S.t('دولار أمريكي'),
          'EUR' => S.t('يورو'),
          _ => S.t('دينار ليبي'),
        };
    return Scaffold(
      appBar: AppBar(title: Text(S.t('شرائحي eSIM'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(child: Text(_error!)),
                      ),
                    ],
                  )
                : visOrders.isEmpty
                    ? ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                                child: Text(
                                    '${S.t('لا توجد شرائح بعد')}\n${S.t('المعروض:')} $curLabel',
                                    textAlign: TextAlign.center)),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: visOrders.length,
                        itemBuilder: (ctx, i) {
                          final o = visOrders[i];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.sim_card,
                                  color: Color(0xFFD97706)),
                              title: Text(o.planName),
                              subtitle: Text(
                                '${o.orderNumber}\n${o.countryName} • ${o.dataGb} GB × ${o.quantity}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              isThreeLine: true,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                      Money.fmtOrig(o.totalAmount, o.currency),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text(_statusName(o.status),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: o.status == 'Completed'
                                              ? Colors.green
                                              : o.status == 'Failed' ||
                                                      o.status == 'Cancelled'
                                                  ? Colors.red
                                                  : Colors.orange)),
                                ],
                              ),
                              onTap: () => _showDetails(o),
                            ),
                          );
                        },
                      ),
      ),
    );
      },
    );
  }
}
