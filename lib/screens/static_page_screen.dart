import 'package:flutter/material.dart';

import '../strings.dart';

/// صفحات المحتوى الثابت: من نحن / الأسئلة الشائعة / الشروط / الخصوصية — ثنائية اللغة.
enum StaticPageType { about, faq, terms, privacy }

class StaticPageScreen extends StatelessWidget {
  final StaticPageType type;
  const StaticPageScreen({super.key, required this.type});

  String _title() {
    switch (type) {
      case StaticPageType.about:
        return S.t('من نحن');
      case StaticPageType.faq:
        return S.t('الأسئلة الشائعة');
      case StaticPageType.terms:
        return S.t('الشروط والأحكام');
      case StaticPageType.privacy:
        return S.t('سياسة الخصوصية');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = S.isAr;
    return Scaffold(
      appBar: AppBar(title: Text(_title())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _content(isAr),
      ),
    );
  }

  List<Widget> _content(bool isAr) {
    switch (type) {
      case StaticPageType.about:
        return [
          _p(isAr
              ? 'رحاب المسافرين هي منصة ليبية متكاملة لحجوزات السفر: تذاكر الطيران بإصدار فوري من شركات الطيران مباشرة، وحجوزات الفنادق حول العالم، وبرامج العمرة المنظمة بعناية.'
              : 'Rehab Travel is a complete Libyan travel platform: flight tickets issued instantly directly from airlines, hotel bookings worldwide, and carefully organized Umrah packages.'),
          _p(isAr
              ? 'نربط المسافر الليبي بمحركات الحجز العالمية مع الدفع بالدينار الليبي عبر المحفظة الإلكترونية وبوابات الدفع المحلية، وخدمة عملاء على مدار الساعة.'
              : 'We connect Libyan travelers to global booking engines with payment in Libyan dinars via e-wallet and local gateways, plus 24/7 customer support.'),
          _p(isAr
              ? 'رؤيتنا: أن يكون حجز السفر من ليبيا بنفس سهولة وجودة أفضل المواقع العالمية.'
              : 'Our vision: booking travel from Libya should be as easy and polished as the best global sites.'),
        ];
      case StaticPageType.faq:
        final qa = isAr
            ? {
                'كيف أحجز تذكرة طيران؟':
                    'من الشاشة الرئيسية اختر المطارين والتواريخ وعدد المسافرين ثم اضغط "ابحث"، اختر الرحلة المناسبة وأدخل بيانات المسافرين وأكّد الحجز من محفظتك.',
                'كيف أشحن محفظتي؟':
                    'من تبويب "محفظتي" اضغط "شحن المحفظة"، أدخل المبلغ وأرفق إيصال التحويل، وسيراجعه فريقنا ويضيف الرصيد.',
                'متى تصدر التذكرة؟':
                    'فور تأكيد الحجز والدفع تُصدر التذكرة آلياً من شركة الطيران، ويظهر رقمها في صفحة حجوزاتي.',
                'هل يمكنني إلغاء التذكرة؟':
                    'نعم، في نفس يوم الإصدار يمكن إلغاء (Void) التذكرة من صفحة حجوزاتي حسب سياسة شركة الطيران.',
                'ما هي طرق الدفع المتاحة؟':
                    'المحفظة الإلكترونية بالدينار الليبي حالياً، وستُضاف بوابات الدفع الليبية قريباً.',
                'كيف أستفيد من تنبيهات الأسعار؟':
                    'من تبويب "التنبيهات" أنشئ تنبيهاً بمسارك وسعرك المستهدف، وسنرسل لك إشعاراً عند انخفاض السعر.',
              }
            : {
                'How do I book a flight?':
                    'From the home screen pick the airports, dates and passengers, tap "Search", choose your flight, enter passenger details and confirm from your wallet.',
                'How do I top up my wallet?':
                    'From the "Wallet" tab tap "Top up", enter the amount and attach the transfer receipt — our team reviews it and adds the balance.',
                'When is my ticket issued?':
                    'Right after booking and payment the ticket is issued automatically by the airline, and its number appears in My Bookings.',
                'Can I cancel a ticket?':
                    'Yes, on the same day of issuance you can void the ticket from My Bookings per the airline policy.',
                'What payment methods are available?':
                    'The Libyan dinar e-wallet for now; Libyan payment gateways are coming soon.',
                'How do price alerts work?':
                    'From the "Alerts" tab create an alert with your route and target price — we notify you when the fare drops.',
              };
        return [
          for (final e in qa.entries)
            Card(
              child: ExpansionTile(
                title: Text(e.key,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(e.value),
                  ),
                ],
              ),
            ),
        ];
      case StaticPageType.terms:
        return [
          _p(isAr
              ? 'باستخدامك منصة رحاب المسافرين فأنت توافق على الشروط التالية:'
              : 'By using Rehab Travel you agree to the following terms:'),
          _bullet(isAr
              ? 'الحجوزات تخضع لشروط شركات الطيران والفنادق المزوّدة، بما فيها سياسات الإلغاء والاسترداد.'
              : 'Bookings are subject to the airlines\' and hotels\' terms, including cancellation and refund policies.'),
          _bullet(isAr
              ? 'يتحمل المسافر مسؤولية صحة بياناته (الاسم كما في الجواز، تاريخ الميلاد، رقم الجواز).'
              : 'Travelers are responsible for the accuracy of their data (name as in passport, date of birth, passport number).'),
          _bullet(isAr
              ? 'الأسعار المعروضة نهائية عند الدفع وقد تتغير قبل إتمام الحجز حسب توفر المقاعد.'
              : 'Displayed prices are final at payment time and may change before booking completion per seat availability.'),
          _bullet(isAr
              ? 'رصيد المحفظة يُستخدم لحجوزات المنصة ولا يُسترد نقداً إلا بموافقة الإدارة.'
              : 'Wallet balance is used for platform bookings and is refundable in cash only with management approval.'),
        ];
      case StaticPageType.privacy:
        return [
          _p(isAr
              ? 'خصوصيتك أمانة لدينا. توضح هذه السياسة كيفية تعاملنا مع بياناتك:'
              : 'Your privacy matters to us. This policy explains how we handle your data:'),
          _bullet(isAr
              ? 'نحفظ بياناتك الأساسية (الاسم، البريد، الهاتف) وبيانات الحجوزات لتقديم الخدمة فقط.'
              : 'We store your basic data (name, email, phone) and booking data only to provide the service.'),
          _bullet(isAr
              ? 'لا نشارك بياناتك مع أي طرف ثالث خارج مزودي خدمات السفر اللازمين لإتمام حجزك.'
              : 'We never share your data with third parties beyond the travel providers needed to complete your booking.'),
          _bullet(isAr
              ? 'يمكنك طلب حذف حسابك وبياناتك في أي وقت عبر صفحة اتصل بنا.'
              : 'You can request account and data deletion anytime via the Contact page.'),
        ];
    }
  }

  Widget _p(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: const TextStyle(fontSize: 15, height: 1.7)),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ', style: TextStyle(fontSize: 18)),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 15, height: 1.6))),
          ],
        ),
      );
}
