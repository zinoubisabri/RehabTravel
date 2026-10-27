import 'package:flutter/material.dart';

import '../main.dart';
import '../strings.dart';

/// صفحة الشروط والأحكام كاملة — تُعرض بلغة الواجهة الحالية (عربي/إنجليزي)
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _arSections = <String, String>{
    '1. التعريفات':
        '«المنصة»: موقع وتطبيق رحاب المسافرين. «العميل»: كل مستخدم يتصفح أو يحجز عبر المنصة. «المزود»: شركات الطيران والفنادق ومزودو الخدمات الذين تُنفَّذ الحجوزات لديهم.',
    '2. نطاق الخدمة':
        'تعمل رحاب المسافرين كوسيط حجز: تصدر تذاكر الطيران، وتحجز الفنادق وباقات العمرة والشرائح الإلكترونية eSIM بالنيابة عن العميل لدى المزودين. العقد النهائي للخدمة يكون بين العميل والمزود.',
    '3. الحجز والدفع':
        'الأسعار تُعرض بعملة الموقع المختارة (دينار ليبي أو دولار أمريكي أو يورو) وتُؤكَّد لحظة الحجز؛ قد يتغير السعر لدى المزود قبل التأكيد، وعندها لا يُخصم أي مبلغ دون موافقة العميل.\nالدفع يتم من محفظة العميل داخل المنصة أو عبر بوابات الدفع المعتمدة.\nبعد تأكيد الحجز يستلم العميل مرجع الحجز والتذكرة/القسيمة داخل حسابه.',
    '4. الإلغاء والاسترجاع':
        'تخضع الإلغاءات لسياسة المزود (شركة الطيران أو الفندق) وقد تترتب عليها رسوم.\nبعض الحجوزات غير قابلة للإلغاء آلياً؛ عندها يُرسَل طلب يدوي للمزود ويُعالَج خلال مدة عمله.\nالمبالغ المستردة تُعاد إلى محفظة العميل بعد تأكيد المزود.',
    '5. مسؤوليات العميل':
        'إدخال بيانات صحيحة ومطابقة لجواز السفر (الاسم، الرقم، تواريخ الصلاحية).\nالتأكد من متطلبات التأشيرة وصلاحية الجواز (6 أشهر على الأقل) قبل السفر.\nالحضور في الوقت المحدد للرحلة أو تسجيل الدخول للفندق.',
    '6. الحسابات والأمان':
        'العميل مسؤول عن سرية بيانات دخوله. يحق للمنصة تعليق الحسابات المخالفة. تُستخدم بيانات العميل فقط لإتمام الحجوزات وتحسين الخدمة وفق سياسة الخصوصية.',
    '7. السحب على العمرة المجانية':
        'سحب شهري يدخله كل من سجّل ببياناته الصحيحة (الاسم الثلاثي، رقم الجواز، الهاتف).\nمشاركة واحدة لكل جواز في الشهر الواحد. يُعلن الفائز ويُتواصل معه هاتفياً.\nالجائزة غير قابلة للتحويل النقدي وتُحدَّد تفاصيلها عند الإعلان.',
    '8. حدود المسؤولية':
        'لا تتحمل المنصة مسؤولية تأخير أو إلغاء الرحلات من شركات الطيران، أو تغيير سياسات الفنادق، أو القوة القاهرة. دورها يقتصر على الوساطة والمتابعة مع المزود بأقصى جهد.',
    '9. تعديل الشروط':
        'قد تُحدَّث هذه الشروط من وقت لآخر، ويُعد استمرار استخدام المنصة موافقة على النسخة الأحدث.',
    '10. التواصل':
        'لأي استفسار حول هذه الشروط: صفحة «اتصل بنا» أو البريد info@rehabtours.ly.',
  };

  static const _enSections = <String, String>{
    '1. Definitions':
        '“Platform”: the Rehab Travel website and app. “Customer”: any user browsing or booking via the Platform. “Provider”: airlines, hotels and service suppliers fulfilling bookings.',
    '2. Scope of Service':
        'Rehab Travel acts as a booking intermediary: it issues flight tickets and books hotels, Umrah packages and eSIMs on the customer’s behalf with providers. The final service contract is between the customer and the provider.',
    '3. Booking & Payment':
        'Prices are shown in Libyan Dinars and confirmed at booking time; the provider price may change before confirmation, in which case no amount is charged without the customer’s consent.\nPayment is made from the customer’s in-platform wallet or via approved payment gateways.\nAfter confirmation the customer receives the booking reference and ticket/voucher in their account.',
    '4. Cancellation & Refunds':
        'Cancellations follow the provider’s policy (airline or hotel) and fees may apply.\nSome bookings cannot be cancelled automatically; a manual request is then sent to the provider and processed within its business time.\nRefunds are returned to the customer’s wallet after provider confirmation.',
    '5. Customer Responsibilities':
        'Enter accurate data matching the passport (name, number, validity dates).\nCheck visa requirements and passport validity (at least 6 months) before travel.\nArrive on time for flights and hotel check-in.',
    '6. Accounts & Security':
        'The customer is responsible for their login credentials. The Platform may suspend violating accounts. Customer data is used only to complete bookings and improve the service per the privacy policy.',
    '7. Free Umrah Draw':
        'A monthly draw entered by anyone who registers with correct data (full triple name, passport number, phone).\nOne entry per passport per month. The winner is announced and contacted by phone.\nThe prize is not exchangeable for cash; its details are set at announcement.',
    '8. Limitation of Liability':
        'The Platform is not liable for airline delays or cancellations, hotel policy changes, or force majeure. Its role is limited to intermediation and best-effort follow-up with the provider.',
    '9. Changes to These Terms':
        'These terms may be updated from time to time; continued use of the Platform constitutes acceptance of the latest version.',
    '10. Contact':
        'For any questions about these terms: the “Contact Us” page or info@rehabtours.ly.',
  };

  @override
  Widget build(BuildContext context) {
    final sections = S.isAr ? _arSections : _enSections;
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('الشروط والأحكام')),
        backgroundColor: RtTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            S.isAr
                ? 'آخر تحديث: أكتوبر 2026 — شركة رحاب المسافرين، ليبيا.'
                : 'Last updated: October 2026 — Rehab Travel, Libya.',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          for (final e in sections.entries) ...[
            Text(e.key,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: RtTheme.primary)),
            const SizedBox(height: 6),
            Text(e.value, style: const TextStyle(height: 1.7)),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}
