import 'package:flutter/material.dart';

import '../auth_state.dart';
import '../strings.dart';
import '../screens/wallet_screen.dart';

/// تلميح «ادفع عبر Tlync» — يظهر تلقائياً عند رسائل خطأ الرصيد غير الكافٍ في أي حجز.
class TlyncHint extends StatelessWidget {
  final AuthState auth;
  final String? error;
  final double? amount;
  const TlyncHint({super.key, required this.auth, this.error, this.amount});

  @override
  Widget build(BuildContext context) {
    final e = error ?? '';
    if (e.isEmpty || (!e.contains('رصيد') && !e.contains('المحفظة'))) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9A441)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.t('يمكنك الدفع إلكترونياً الآن — اشحن محفظتك عبر Tlync وأكمل حجزك.'),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F6B4A),
                padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => WalletScreen(auth: auth, initialAmount: amount)),
            ),
            child: Text('⚡ ${S.t('ادفع عبر Tlync')}',
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
