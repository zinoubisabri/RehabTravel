/// قواعد التحقق من تاريخ ميلاد المسافرين — مطابقة تماماً لقواعد الخادم
/// (BirthDateRules.cs) حتى لا يقبل التطبيق ما يرفضه الخادم والعكس.
///
/// معيار IATA: الرضيع أقل من سنتين — الطفل من سنتين حتى أقل من 12 سنة.
/// يُحتسب العمر في تاريخ الذهاب وتاريخ العودة (أو آخر رحلة في مسار متعدد المدن)،
/// ويجب أن تبقى الفئة صحيحة في كلتيهما.
library;

class BirthRules {
  static const int childMinYears = 2;
  static const int childMaxYears = 12;

  /// العمر الكامل بالسنوات في تاريخ معيّن
  static int ageOn(DateTime birth, DateTime on) {
    var age = on.year - birth.year;
    final b = DateTime(birth.year, birth.month, birth.day);
    final o = DateTime(on.year, on.month, on.day);
    var hadBirthday = DateTime(b.year + age, b.month, b.day);
    if (o.isBefore(hadBirthday)) age--;
    return age;
  }

  /// يتحقق أن تاريخ الميلاد يطابق فئة المسافر.
  /// [type]: 0 = بالغ، 1 = طفل، 2 = رضيع.
  /// يعيد null عند الصحة، وإلا رسالة خطأ عربية توضح السبب.
  static String? validate(int type, DateTime? birth, DateTime depart, DateTime? returnDate) {
    if (type == 0) {
      if (birth == null) return null; // البالغ: اختياري
      if (birth.isAfter(DateTime.now())) return 'تاريخ الميلاد لا يمكن أن يكون في المستقبل.';
      if (ageOn(birth, depart) < childMaxYears) {
        return 'تاريخ الميلاد المُدخل لطفل — غيّر فئة المسافر إلى طفل/رضيع أو صحّح التاريخ.';
      }
      return null;
    }

    // رضيع أو طفل: إجباري
    if (birth == null) {
      return type == 2 ? 'تاريخ ميلاد الرضيع إجباري.' : 'تاريخ ميلاد الطفل إجباري.';
    }
    if (birth.isAfter(DateTime.now())) return 'تاريخ الميلاد لا يمكن أن يكون في المستقبل.';

    final ret = returnDate ?? depart;

    if (type == 2) {
      final ageDep = ageOn(birth, depart);
      if (ageDep < 0) return 'تاريخ ميلاد الرضيع بعد تاريخ السفر — صحّح التاريخ.';
      if (ageDep >= childMinYears) {
        return 'تاريخ الميلاد المُدخل ليس لرضيع (عمره سنتان أو أكثر يوم السفر) — اختر فئة «طفل».';
      }
      if (ageOn(birth, ret) >= childMinYears) {
        return 'سيبلغ هذا الرضيع سنتين قبل رحلة العودة — وفق قواعد الطيران يجب حجزه كـ«طفل».';
      }
    } else {
      final ageDep = ageOn(birth, depart);
      if (ageDep < 0) return 'تاريخ ميلاد الطفل بعد تاريخ السفر — صحّح التاريخ.';
      if (ageDep < childMinYears) {
        return 'تاريخ الميلاد المُدخل ليس لطفل (عمره أقل من سنتين يوم السفر) — اختر فئة «رضيع».';
      }
      if (ageDep >= childMaxYears) {
        return 'تاريخ الميلاد المُدخل ليس لطفل (عمره 12 سنة أو أكثر يوم السفر) — اختر فئة «بالغ».';
      }
      if (ageOn(birth, ret) >= childMaxYears) {
        return 'سيبلغ هذا الطفل 12 سنة قبل رحلة العودة — وفق قواعد الطيران يجب حجزه كـ«بالغ».';
      }
    }
    return null;
  }
}
