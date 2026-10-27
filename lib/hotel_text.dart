import 'strings.dart';

/// يترجم أسماء الغرف والوجبات القادمة بالفرنسية من مزودي الفنادق (JohBooking/3T)
/// إلى العربية أو الإنجليزية حسب لغة التطبيق الحالية.
String localizeHotelText(String? text) {
  if (text == null || text.trim().isEmpty) return '';
  var result = text;
  final ar = S.isAr;
  for (final e in _map) {
    result = result.replaceAllMapped(
      RegExp(e.$1, caseSensitive: false),
      (_) => ar ? e.$2 : e.$3,
    );
  }
  return result;
}

// الترتيب مهم: الأطول أولاً
const _map = <(String, String, String)>[
  (r'logement petit[- ]d[ée]jeuner', 'شامل الإفطار', 'Bed & Breakfast'),
  (r'petit[- ]d[ée]jeuner', 'الإفطار', 'Breakfast'),
  (r'bed and breakfast', 'شامل الإفطار', 'Bed & Breakfast'),
  (r'demi[- ]pension', 'وجبتان (إفطار وعشاء)', 'Half Board'),
  (r'pension compl[èe]te', 'إقامة كاملة', 'Full Board'),
  (r'tout inclus|all inclusive', 'إقامة شاملة كلياً', 'All Inclusive'),
  (r'logement seul', 'إقامة فقط (بدون وجبات)', 'Room Only'),
  (r'chambre quadruple', 'غرفة رباعية', 'Quad Room'),
  (r'chambre triple', 'غرفة ثلاثية', 'Triple Room'),
  (r'chambre double', 'غرفة مزدوجة', 'Double Room'),
  (r'chambre twin', 'غرفة بسريرين', 'Twin Room'),
  (r'chambre (single|individuelle)', 'غرفة مفردة', 'Single Room'),
  (r'chambre sup[ée]rieure', 'غرفة سوبيريور', 'Superior Room'),
  (r'chambre standard', 'غرفة ستاندرد', 'Standard Room'),
  (r'chambre familiale', 'غرفة عائلية', 'Family Room'),
  (r'chambre [ée]conomique', 'غرفة اقتصادية', 'Economy Room'),
  (r'chambre deluxe', 'غرفة ديلوكس', 'Deluxe Room'),
  (r'chambre', 'غرفة', 'Room'),
  (r'suite junior', 'جناح جونيور', 'Junior Suite'),
  (r'suite pr[ée]sidentielle', 'جناح رئاسي', 'Presidential Suite'),
  (r'suite', 'جناح', 'Suite'),
  (r'vue sur mer|vue mer', 'إطلالة على البحر', 'Sea View'),
  (r'vue jardin', 'إطلالة على الحديقة', 'Garden View'),
  (r'vue (sur )?ville', 'إطلالة على المدينة', 'City View'),
  (r'vue piscine', 'إطلالة على المسبح', 'Pool View'),
  (r'non remboursable', 'غير قابل للاسترجاع', 'Non-refundable'),
  (r'annulation gratuite', 'إلغاء مجاني', 'Free cancellation'),
];
