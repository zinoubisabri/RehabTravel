import 'package:flutter/material.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../money.dart';
import '../strings.dart';
import 'esim_my_screen.dart';
import 'login_screen.dart';
import 'wallet_screen.dart';

/// تصفح وشراء الشرائح الإلكترونية eSIM — الدول ثم الباقات ثم الشراء من المحفظة.
class EsimScreen extends StatefulWidget {
  final AuthState auth;
  const EsimScreen({super.key, required this.auth});

  @override
  State<EsimScreen> createState() => _EsimScreenState();
}

class _EsimScreenState extends State<EsimScreen> {
  List<EsimCountry>? _countries;
  List<EsimCountry>? _filtered;
  String? _error;
  String _query = '';

  /// تصنيف الدول حسب القارة (ISO-3166 alpha-2)
  static const Map<String, String> _isoToContinent = {
    // أفريقيا
    'DZ':'africa','AO':'africa','BJ':'africa','BW':'africa','BF':'africa','BI':'africa','CM':'africa','CV':'africa','CF':'africa','TD':'africa','KM':'africa','CG':'africa','CD':'africa','CI':'africa','DJ':'africa','EG':'africa','GQ':'africa','ER':'africa','SZ':'africa','ET':'africa','GA':'africa','GM':'africa','GH':'africa','GN':'africa','GW':'africa','KE':'africa','LS':'africa','LR':'africa','LY':'africa','MG':'africa','MW':'africa','ML':'africa','MR':'africa','MU':'africa','MA':'africa','MZ':'africa','NA':'africa','NE':'africa','NG':'africa','RW':'africa','ST':'africa','SN':'africa','SC':'africa','SL':'africa','SO':'africa','ZA':'africa','SS':'africa','SD':'africa','TZ':'africa','TG':'africa','TN':'africa','UG':'africa','ZM':'africa','ZW':'africa','EH':'africa',
    // آسيا (تشمل الشرق الأوسط والخليج)
    'AF':'asia','AM':'asia','AZ':'asia','BH':'asia','BD':'asia','BT':'asia','BN':'asia','KH':'asia','CN':'asia','CY':'asia','GE':'asia','IN':'asia','ID':'asia','IR':'asia','IQ':'asia','IL':'asia','JP':'asia','JO':'asia','KZ':'asia','KW':'asia','KG':'asia','LA':'asia','LB':'asia','MY':'asia','MV':'asia','MN':'asia','MM':'asia','NP':'asia','OM':'asia','PK':'asia','PH':'asia','QA':'asia','SA':'asia','SG':'asia','KR':'asia','LK':'asia','SY':'asia','TW':'asia','TJ':'asia','TH':'asia','TL':'asia','TR':'asia','TM':'asia','AE':'asia','UZ':'asia','VN':'asia','YE':'asia','PS':'asia','HK':'asia','MO':'asia',
    // أوروبا
    'AL':'europe','AD':'europe','AT':'europe','BY':'europe','BE':'europe','BA':'europe','BG':'europe','HR':'europe','CZ':'europe','DK':'europe','EE':'europe','FI':'europe','FR':'europe','DE':'europe','GR':'europe','HU':'europe','IS':'europe','IE':'europe','IT':'europe','LV':'europe','LI':'europe','LT':'europe','LU':'europe','MT':'europe','MD':'europe','MC':'europe','ME':'europe','NL':'europe','MK':'europe','NO':'europe','PL':'europe','PT':'europe','RO':'europe','RU':'europe','SM':'europe','RS':'europe','SK':'europe','SI':'europe','ES':'europe','SE':'europe','CH':'europe','UA':'europe','GB':'europe','VA':'europe','XK':'europe',
    // أمريكا الشمالية والوسطى والكاريبي
    'US':'na','CA':'na','MX':'na','GT':'na','BZ':'na','SV':'na','HN':'na','NI':'na','CR':'na','PA':'na','CU':'na','DO':'na','HT':'na','JM':'na','BS':'na','BB':'na','TT':'na','AW':'na','PR':'na','KY':'na','BM':'na','GL':'na','AG':'na','DM':'na','GD':'na','KN':'na','LC':'na','VC':'na','AI':'na','VG':'na','VI':'na','MS':'na','TC':'na',
    // أمريكا اللاتينية (الجنوبية)
    'AR':'latam','BO':'latam','BR':'latam','CL':'latam','CO':'latam','EC':'latam','GY':'latam','PY':'latam','PE':'latam','SR':'latam','UY':'latam','VE':'latam','FK':'latam','GF':'latam',
    // أوقيانوسيا / أستراليا
    'AU':'oceania','NZ':'oceania','FJ':'oceania','PG':'oceania','SB':'oceania','VU':'oceania','NC':'oceania','PF':'oceania','WS':'oceania','KI':'oceania','TO':'oceania','TV':'oceania','FM':'oceania','MH':'oceania','NR':'oceania','PW':'oceania','GU':'oceania','AS':'oceania','CK':'oceania','NU':'oceania',
  };

  static const List<(String, String, String)> _continents = [
    ('africa', '🌍', 'أفريقيا'),
    ('asia', '🌏', 'آسيا'),
    ('europe', '🌍', 'أوروبا'),
    ('na', '🌎', 'أمريكا الشمالية والكاريبي'),
    ('latam', '🌎', 'أمريكا اللاتينية'),
    ('oceania', '🏝️', 'أوقيانوسيا وأستراليا'),
    ('other', '🌐', 'دول أخرى'),
  ];

  EsimCountry? _selected;
  List<EsimPlan>? _plans;
  bool _plansLoading = false;
  String? _plansError;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    setState(() {
      _countries = null;
      _error = null;
    });
    try {
      final list = await widget.auth.api.esimCountries();
      if (!mounted) return;
      setState(() {
        _countries = list
            .map((e) => EsimCountry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _applyFilter();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  void _applyFilter() {
    final all = _countries;
    if (all == null) return;
    final q = _query.trim();
    _filtered = q.isEmpty
        ? all
        : all
            .where((c) =>
                c.name.contains(q) ||
                c.iso.toUpperCase().contains(q.toUpperCase()))
            .toList();
  }

  Future<void> _selectCountry(EsimCountry c) async {
    setState(() {
      _selected = c;
      _plans = null;
      _plansLoading = true;
      _plansError = null;
    });
    try {
      final list = await widget.auth.api.esimPlans(c.iso);
      if (!mounted) return;
      setState(() {
        _plans = list
            .map((e) => EsimPlan.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _plansLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _plansLoading = false;
        _plansError = e.message;
      });
    }
  }

  Future<void> _order(EsimPlan plan) async {
    if (!widget.auth.isAuthenticated) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => LoginScreen(auth: widget.auth)));
      return;
    }

    final purchase = await showDialog<({int qty, String? coupon})>(
      context: context,
      builder: (ctx) {
        int qty = 1;
        final couponCtrl = TextEditingController();
        Map<String, dynamic>? couponResult;
        bool couponBusy = false;
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            final total = plan.priceLyd * qty;
            final discount = couponResult?['valid'] == true
                ? ((couponResult!['discount'] as num?) ?? 0)
                : 0;
            Future<void> checkCoupon() async {
              if (couponCtrl.text.trim().isEmpty) return;
              setDlg(() {
                couponBusy = true;
                couponResult = null;
              });
              try {
                final r = await widget.auth.api.validateCoupon(
                    couponCtrl.text.trim(), 'Esim', total);
                setDlg(() => couponResult = r);
              } on ApiException catch (e) {
                setDlg(() =>
                    couponResult = {'valid': false, 'message': e.message});
              } finally {
                setDlg(() => couponBusy = false);
              }
            }

            return AlertDialog(
            title: Text(plan.name),
            // المحتوى قابل للتمرير + حواف تتقلص مع ظهور لوحة المفاتيح — إصلاح overflow
            insetPadding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: MediaQuery.of(ctx).viewInsets.bottom > 0 ? 12 : 24),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            content: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    '${plan.isUnlimited ? S.t('غير محدود') : '${plan.dataGb} GB'} — ${plan.validityDays} ${S.t('يوم')}'),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: qty > 1 ? () => setDlg(() => qty--) : null,
                    ),
                    Text('$qty',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: qty < 5 ? () => setDlg(() => qty++) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // ---------- قسيمة التخفيض ----------
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: couponCtrl,
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
                      onPressed: couponBusy ? null : checkCoupon,
                      child: Text(couponBusy ? '…' : S.t('تطبيق')),
                    ),
                  ],
                ),
                if (couponResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      couponResult!['message']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: couponResult!['valid'] == true
                            ? Colors.green
                            : Colors.redAccent,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                    '${S.t('الإجمالي:')} ${Money.fmt(total)}'),
                if (discount > 0) ...[
                  Text('🎟 -${Money.fmt(discount)}',
                      style: const TextStyle(color: Colors.green)),
                  Text(
                    '${S.t('بعد الخصم:')} ${Money.fmt((couponResult!['finalAmount'] as num?) ?? total)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: Colors.green),
                  ),
                ],
              ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(S.t('إلغاء')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, (
                  qty: qty,
                  coupon: couponResult?['valid'] == true
                      ? couponCtrl.text.trim()
                      : null
                )),
                child: Text(S.t('شراء من المحفظة')),
              ),
            ],
          );
          },
        );
      },
    );

    if (purchase == null) return;
    final quantity = purchase.qty;

    // مؤشر تنفيذ
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final country = _selected;
      final result = await widget.auth.api.esimOrder(
          plan.planId, quantity, country?.iso ?? '', country?.name ?? '',
          couponCode: purchase.coupon);
      if (!mounted) return;
      Navigator.pop(context); // أغلق المؤشر

      if (result['success'] == true) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(S.t('✅ تم الشراء بنجاح')),
            content: Text(
                '${S.t('رقم الطلب:')} ${result['orderNumber'] ?? ''}\n'
                '${S.t('المبلغ:')} ${Money.fmt((result['totalAmount'] as num?) ?? 0)}\n'
                '${S.t('ستجد رمز QR في صفحة «شرائحي».')}'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EsimMyScreen(auth: widget.auth)),
                  );
                },
                child: Text(S.t('عرض شرائحي')),
              ),
            ],
          ),
        );
      } else {
        _showError(result['message']?.toString() ?? S.t('تعذر تنفيذ الطلب'));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // أغلق المؤشر
      _showError(e.message);
    }
  }

  void _showError(String msg) {
    if (msg.contains('رصيد') || msg.contains('المحفظة')) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(S.t('الرصيد غير كافٍ')),
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(S.t('إلغاء'))),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F6B4A)),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => WalletScreen(auth: widget.auth)));
              },
              child: Text('⚡ ${S.t('اشحن عبر Tlync')}'),
            ),
          ],
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('شرائح إلكترونية eSIM')),
        actions: [
          if (widget.auth.isAuthenticated)
            IconButton(
              icon: const Icon(Icons.sim_card_outlined),
              tooltip: S.t('شرائحي'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EsimMyScreen(auth: widget.auth)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ---------- بحث الدول ----------
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: S.t('ابحث عن دولة…'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() {
                _query = v;
                _applyFilter();
              }),
            ),
          ),

          if (_error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: _loadCountries,
                      child: Text(S.t('إعادة المحاولة')),
                    ),
                  ],
                ),
              ),
            )
          else if (_countries == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: _selected == null ? _buildCountries() : _buildPlans(),
            ),
        ],
      ),
    );
  }

  Widget _buildCountries() {
    final list = _filtered ?? [];
    if (list.isEmpty) {
      return Center(child: Text(S.t('لا نتائج مطابقة')));
    }
    // أثناء البحث: شبكة مسطحة — بدون بحث: تجميع حسب القارة
    if (_query.trim().isNotEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.05,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: list.length,
        itemBuilder: (ctx, i) => _countryCard(list[i]),
      );
    }

    final groups = <String, List<EsimCountry>>{};
    for (final c in list) {
      final cont = _isoToContinent[c.iso.toUpperCase()] ?? 'other';
      groups.putIfAbsent(cont, () => []).add(c);
    }

    final sections = <Widget>[];
    for (final (key, icon, label) in _continents) {
      final items = groups[key];
      if (items == null || items.isEmpty) continue;
      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(S.t(label),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF146C94).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${items.length}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF146C94),
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ));
      sections.add(GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.05,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: items.length,
        itemBuilder: (ctx, i) => _countryCard(items[i]),
      ));
    }
    return ListView(children: sections);
  }

  Widget _countryCard(EsimCountry c) {
    return InkWell(
      onTap: () => _selectCountry(c),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(c.flagEmoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(height: 6),
            Text(c.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            Text('${c.planCount} ${S.t('باقة')}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlans() {
    final c = _selected!;
    return Column(
      children: [
        ListTile(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _selected = null),
          ),
          title: Text('${c.flagEmoji} ${c.name}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: _plansLoading
              ? const Center(child: CircularProgressIndicator())
              : _plansError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_plansError!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: () => _selectCountry(c),
                            child: Text(S.t('إعادة المحاولة')),
                          ),
                        ],
                      ),
                    )
                  : (_plans == null || _plans!.isEmpty)
                      ? Center(child: Text(S.t('لا توجد باقات لهذه الدولة')))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _plans!.length,
                          itemBuilder: (ctx, i) {
                            final p = _plans![i];
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.sim_card,
                                    color: Color(0xFFD97706)),
                                title: Text(p.name),
                                subtitle: Text(
                                  '${p.isUnlimited ? S.t('بيانات غير محدودة') : '${p.dataGb} GB'} • ${p.validityDays} ${S.t('يوم')}'
                                  '${p.networkType.isNotEmpty ? ' • ${p.networkType}' : ''}'
                                  '${p.supportsHotspot ? ' • ${S.t('نقطة اتصال')}' : ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                isThreeLine: true,
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                        Money.fmt(p.priceLyd),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0E3A5D))),
                                  ],
                                ),
                                onTap: () => _order(p),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
