/// نماذج البيانات المشتركة مع RehabTravel.Api
/// ملاحظة: الأنواع enum تُرسل كأرقام (القيمة الافتراضية في System.Text.Json):
/// TripType: OneWay=0, RoundTrip=1
/// PassengerType: Adult=0, Child=1, Infant=2
/// PaymentMethod: Wallet=0

class FlightOption {
  final String flightId;
  final String airlineCode;
  final String airlineName;
  final String flightNumber;
  final String departAirport;
  final String arriveAirport;
  final String departTime; // "HH:mm:ss" من TimeSpan
  final String arriveTime;
  final int durationMinutes;
  final int stops;
  final int apiProviderId;
  final List<FareOption> fares;

  FlightOption.fromJson(Map<String, dynamic> j)
      : flightId = j['flightId'] ?? '',
        airlineCode = j['airlineCode'] ?? '',
        airlineName = j['airlineName'] ?? '',
        flightNumber = j['flightNumber'] ?? '',
        departAirport = j['departAirport'] ?? '',
        arriveAirport = j['arriveAirport'] ?? '',
        departTime = (j['departTime'] ?? '').toString(),
        arriveTime = (j['arriveTime'] ?? '').toString(),
        durationMinutes = j['durationMinutes'] ?? 0,
        stops = j['stops'] ?? 0,
        apiProviderId = j['apiProviderId'] ?? 0,
        fares = ((j['fares'] ?? []) as List)
            .map((f) => FareOption.fromJson(f))
            .toList();
}

class FareOption {
  final int classBandId;
  final String classBandName;
  final String bandName; // رمز فئة الأجرة الخام (cbname) — يُستخدم في تسعيرة QQ
  final String classCode;
  final int availableSeats;
  final String currency;
  final num price;
  final num tax;
  final bool isAvailable;
  // شروط الرحلة والأمتعة المسموحة — نصوص فئة الأجرة من شركة الطيران (cbtext)
  final List<String> fareRules;

  FareOption.fromJson(Map<String, dynamic> j)
      : classBandId = j['classBandId'] ?? 0,
        classBandName = j['classBandName'] ?? '',
        bandName = j['bandName'] ?? '',
        classCode = j['classCode'] ?? '',
        availableSeats = j['availableSeats'] ?? 0,
        currency = j['currency'] ?? '',
        price = j['price'] ?? 0,
        tax = j['tax'] ?? 0,
        isAvailable = j['isAvailable'] ?? false,
        fareRules = [
          for (final r in (j['fareRules'] as List? ?? const [])) r.toString(),
        ];

  num get totalPrice => price + tax;
}

class ProviderResult {
  final int providerId;
  final String providerName;
  final String? error;
  // نسبتا الخصم على سعر البالغ — نفس قيم الموقع (الافتراضي: طفل 25%، رضيع 90%)
  final num childDiscountPercent;
  final num infantDiscountPercent;
  final List<FlightOption> outboundFlights;
  final List<FlightOption> returnFlights;

  ProviderResult.fromJson(Map<String, dynamic> j)
      : providerId = j['providerId'] ?? 0,
        providerName = j['providerName'] ?? '',
        error = j['error'],
        childDiscountPercent = j['childDiscountPercent'] ?? 25,
        infantDiscountPercent = j['infantDiscountPercent'] ?? 90,
        outboundFlights = ((j['outboundFlights'] ?? []) as List)
            .map((f) => FlightOption.fromJson(f))
            .toList(),
        returnFlights = ((j['returnFlights'] ?? []) as List)
            .map((f) => FlightOption.fromJson(f))
            .toList();
}

class BookingListItem {
  final int id;
  final String reference;
  final String route;
  final String departDate;
  final String status;
  final num totalAmount;
  final String currency;
  final int passengerCount;
  final bool hasTicket;
  final String? ticketNumbers;

  BookingListItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? 0,
        reference = j['reference'] ?? '',
        route = j['route'] ?? '',
        departDate = j['departDate'] ?? '',
        status = j['status'] ?? '',
        totalAmount = j['totalAmount'] ?? 0,
        currency = j['currency'] ?? '',
        passengerCount = j['passengerCount'] ?? 0,
        hasTicket = j['hasTicket'] ?? false,
        ticketNumbers = j['ticketNumbers'];
}

class HotelOffer {
  final int? apiProviderId;
  final String hotelCode;
  final String imageUrl;
  final String hotelName;
  final String city;
  final int starRating;
  final String roomType;
  final String mealPlan;
  final int nights;
  final num totalPrice;
  final String currency;
  final bool refundable;
  final String rateKey;
  final String source;
  final double? latitude;   // إحداثيات الفندق للخريطة
  final double? longitude;

  HotelOffer.fromJson(Map<String, dynamic> j)
      : apiProviderId = j['apiProviderId'],
        latitude = (j['latitude'] as num?)?.toDouble(),
        longitude = (j['longitude'] as num?)?.toDouble(),
        hotelCode = j['hotelCode'] ?? '',
        imageUrl = j['imageUrl'] ?? '',
        hotelName = j['hotelName'] ?? '',
        city = j['city'] ?? '',
        starRating = j['starRating'] ?? 0,
        roomType = j['roomType'] ?? '',
        mealPlan = j['mealPlan'] ?? '',
        nights = j['nights'] ?? 0,
        totalPrice = j['totalPrice'] ?? 0,
        currency = j['currency'] ?? '',
        refundable = j['refundable'] ?? false,
        rateKey = j['rateKey'] ?? '',
        source = j['source'] ?? 'Api';
}

class UmrahPackage {
  final int id;
  final String seasonName;
  final String name;
  final String departureDate;
  final String returnDate;
  final int nightsMakkah;
  final int nightsMadinah;
  final String makkahHotel;
  final String madinahHotel;
  final num priceFrom;
  final String currency;
  final int capacity;
  final int bookedCount;

  UmrahPackage.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? 0,
        seasonName = j['seasonName'] ?? '',
        name = j['name'] ?? '',
        departureDate = j['departureDate'] ?? '',
        returnDate = j['returnDate'] ?? '',
        nightsMakkah = j['nightsMakkah'] ?? 0,
        nightsMadinah = j['nightsMadinah'] ?? 0,
        makkahHotel = j['makkahHotel'] ?? '',
        madinahHotel = j['madinahHotel'] ?? '',
        priceFrom = j['priceFrom'] ?? 0,
        currency = j['currency'] ?? 'LYD',
        capacity = j['capacity'] ?? 0,
        bookedCount = j['bookedCount'] ?? 0;

  int get availableSeats => capacity - bookedCount;
}

class WalletInfo {
  final num balance;
  final num balanceUsd;
  final num balanceEur;
  final String siteCurrency;
  final String currency;
  final List<Map<String, dynamic>> transactions;

  WalletInfo.fromJson(Map<String, dynamic> j)
      : balance = j['balance'] ?? 0,
        balanceUsd = j['balanceUsd'] ?? 0,
        balanceEur = j['balanceEur'] ?? 0,
        siteCurrency = (j['siteCurrency'] ?? 'LYD').toString(),
        currency = j['currency'] ?? 'LYD',
        transactions = ((j['transactions'] ?? []) as List)
            .cast<Map<String, dynamic>>();

  /// رصيد محفظة عملة الموقع (التي يُخصم منها)
  num get siteBalance => siteCurrency == 'USD'
      ? balanceUsd
      : siteCurrency == 'EUR'
          ? balanceEur
          : balance;
}

class AppNotification {
  final int id;
  final String title;
  final String body;
  final String? imageUrl;
  final bool isRead;
  final String createdAt;

  AppNotification.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? 0,
        title = j['title'] ?? '',
        body = j['body'] ?? '',
        imageUrl = (j['imageUrl'] as String?)?.isNotEmpty == true
            ? j['imageUrl'] as String
            : null,
        isRead = j['isRead'] ?? false,
        createdAt = j['createdAt'] ?? '';
}

/// مطار من قاعدة البيانات (ثنائي اللغة) — يُدار من لوحة التحكم.
class Airport {
  final int id;
  final String code;
  final String name;
  final String nameEn;
  final String city;
  final String cityEn;
  final String country;
  final String countryEn;

  Airport.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? 0,
        code = j['code'] ?? '',
        name = j['name'] ?? '',
        nameEn = j['nameEn'] ?? '',
        city = j['city'] ?? '',
        cityEn = j['cityEn'] ?? '',
        country = j['country'] ?? '',
        countryEn = j['countryEn'] ?? '';

  String displayName(bool isAr) =>
      isAr ? '$city — $name ($code)' : '$cityEn — $nameEn ($code)';
}

// ---------- الشرائح الإلكترونية eSIM ----------

class EsimCountry {
  final String iso;
  final String name;
  final String flagEmoji;
  final int planCount;

  EsimCountry.fromJson(Map<String, dynamic> j)
      : iso = j['iso'] ?? '',
        name = j['name'] ?? '',
        flagEmoji = j['flagEmoji'] ?? '🌍',
        planCount = j['planCount'] ?? 0;
}

class EsimPlan {
  final String planId;
  final String name;
  final num dataGb;
  final int validityDays;
  final bool isUnlimited;
  final String networkType;
  final String carriers;
  final bool supportsHotspot;
  final num retailPriceUsd;
  final num priceLyd;

  EsimPlan.fromJson(Map<String, dynamic> j)
      : planId = j['planId'] ?? '',
        name = j['name'] ?? '',
        dataGb = j['dataGb'] ?? 0,
        validityDays = j['validityDays'] ?? 0,
        isUnlimited = j['isUnlimited'] ?? false,
        networkType = j['networkType'] ?? '',
        carriers = j['carriers'] ?? '',
        supportsHotspot = j['supportsHotspot'] ?? false,
        retailPriceUsd = j['retailPriceUsd'] ?? 0,
        priceLyd = j['priceLyd'] ?? 0;
}

class EsimOrderListItem {
  final int id;
  final String orderNumber;
  final String planName;
  final String countryName;
  final num dataGb;
  final int validityDays;
  final int quantity;
  final num totalAmount;
  final String currency;
  final String status;
  final String createdAt;

  EsimOrderListItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? 0,
        orderNumber = j['orderNumber'] ?? '',
        planName = j['planName'] ?? '',
        countryName = j['countryName'] ?? '',
        dataGb = j['dataGb'] ?? 0,
        validityDays = j['validityDays'] ?? 0,
        quantity = j['quantity'] ?? 1,
        totalAmount = j['totalAmount'] ?? 0,
        currency = j['currency'] ?? 'LYD',
        status = j['status'] ?? '',
        createdAt = (j['createdAt'] ?? '').toString();
}

class EsimItem {
  final int id;
  final String iccid;
  final String lpa;
  final String qrUrl;
  final String status;
  final String expiresAt;

  EsimItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? 0,
        iccid = (j['iccid'] ?? '').toString(),
        lpa = (j['lpa'] ?? '').toString(),
        qrUrl = (j['qrUrl'] ?? '').toString(),
        status = j['status'] ?? '',
        expiresAt = (j['expiresAt'] ?? '').toString();
}

// ---------- الصفحة الرئيسية ----------

class HomeSettings {
  final String heroTitle;
  final String heroSubtitle;

  HomeSettings.fromJson(Map<String, dynamic> j)
      : heroTitle = j['heroTitle'] ?? '',
        heroSubtitle = j['heroSubtitle'] ?? '';
}

class TrendingDestination {
  final String code;
  final String city;
  final String name;
  final String country;
  final num price;
  final String currency;

  TrendingDestination.fromJson(Map<String, dynamic> j)
      : code = j['code'] ?? '',
        city = j['city'] ?? '',
        name = j['name'] ?? '',
        country = j['country'] ?? '',
        price = j['price'] ?? 0,
        currency = j['currency'] ?? 'LYD';
}

/// بيانات التواصل من قاعدة البيانات — تُدار من لوحة التحكم (بيانات التواصل).
class ContactSettings {
  final String phone;
  final String whatsapp;
  final String email;
  final String address;
  final String addressEn;
  final String workingHours;
  final String workingHoursEn;
  final String facebook;
  final String instagram;
  final String twitter;

  ContactSettings.fromJson(Map<String, dynamic> j)
      : phone = j['phone'] ?? '',
        whatsapp = j['whatsapp'] ?? '',
        email = j['email'] ?? '',
        address = j['address'] ?? '',
        addressEn = j['addressEn'] ?? '',
        workingHours = j['workingHours'] ?? '',
        workingHoursEn = j['workingHoursEn'] ?? '',
        facebook = j['facebook'] ?? '',
        instagram = j['instagram'] ?? '',
        twitter = j['twitter'] ?? '';
}


/// وجهة فنادق من الإكمال التلقائي (محلي أو المزود العالمي)
class HotelDestination {
  final String code;
  final String name;
  final String countryName;
  final String source;
  final int hotelCount;

  HotelDestination.fromJson(Map<String, dynamic> j)
      : code = j['code'] ?? '',
        name = j['name'] ?? '',
        countryName = j['countryName'] ?? '',
        source = j['source'] ?? '',
        hotelCount = j['hotelCount'] ?? 0;
}

/// بانر إعلاني للصفحة الرئيسية (يُدار من لوحة الأدمن)
class BannerItem {
  final int id;
  final String title;
  final String imageUrl;
  final String? linkUrl;

  BannerItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? 0,
        title = j['title'] ?? '',
        imageUrl = j['imageUrl'] ?? '',
        linkUrl = (j['linkUrl'] as String?)?.isNotEmpty == true
            ? j['linkUrl'] as String
            : null;
}

/// فئة خدمة إضافية (سيارات/نقل/جولات/تأمين).
class ExtraCategory {
  final String key;
  final String nameAr;
  final String icon;

  ExtraCategory.fromJson(Map<String, dynamic> j)
      : key = j['key'] ?? '',
        nameAr = j['nameAr'] ?? '',
        icon = j['icon'] ?? '🧩';
}

/// عنصر قابل للحجز ضمن خدمة إضافية — السعر نهائي من الخادم (شامل العمولة).
class ExtraItem {
  final int id;
  final String category;
  final String title;
  final String? description;
  final String city;
  final double price;
  final String currency;
  final String? unitLabel;
  final String? imageUrl;

  // مواصفات السيارة (كراء السيارات)
  final String? carType;
  final int? seats;
  final String? fuelType;
  final String? transmission;
  final String? color;
  final String? locationName;
  final double? quoteTotal; // إجمالي الفترة عند البحث بتاريخين (د.ل)
  final int? quoteDays;

  // تفاصيل الجولات والأنشطة
  final String? duration;
  final String? includes;
  final String? meetingPoint;
  final String? guideLanguage;

  ExtraItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? 0,
        category = j['category'] ?? '',
        title = j['title'] ?? '',
        description = (j['description'] as String?)?.isNotEmpty == true
            ? j['description'] as String
            : null,
        city = j['city'] ?? '',
        price = (j['price'] as num?)?.toDouble() ?? 0,
        currency = j['currency'] ?? 'LYD',
        unitLabel = (j['unitLabel'] as String?)?.isNotEmpty == true
            ? j['unitLabel'] as String
            : null,
        imageUrl = (j['imageUrl'] as String?)?.isNotEmpty == true
            ? j['imageUrl'] as String
            : null,
        carType = j['carType'] as String?,
        seats = j['seats'] as int?,
        fuelType = j['fuelType'] as String?,
        transmission = j['transmission'] as String?,
        color = j['color'] as String?,
        locationName = j['locationName'] as String?,
        quoteTotal = (j['quoteTotal'] as num?)?.toDouble(),
        quoteDays = j['quoteDays'] as int?,
        duration = j['duration'] as String?,
        includes = j['includes'] as String?,
        meetingPoint = j['meetingPoint'] as String?,
        guideLanguage = j['guideLanguage'] as String?;
}

/// مكان استلام/تسليم لكراء السيارات.
class CarLocation {
  final int id;
  final String name;
  final String? nameEn;
  final String city;
  final String country;

  CarLocation.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? 0,
        name = j['name'] ?? '',
        nameEn = (j['nameEn'] as String?)?.isNotEmpty == true
            ? j['nameEn'] as String
            : null,
        city = j['city'] ?? '',
        country = j['country'] ?? '';

  String get display =>
      nameEn != null ? '$name — $nameEn' : name;
}

/// حجز خدمة إضافية خاص بالمستخدم.
class ExtraBooking {
  final int id;
  final String itemTitle;
  final String category;
  final String dateFrom;
  final String? dateTo;
  final int quantity;
  final double totalPrice;
  final String currency;
  final String status;
  final bool isPaid;
  final String? pickupLocation;
  final String? dropoffLocation;
  final String? pickupTime;
  final String? dropoffTime;

  ExtraBooking.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? 0,
        itemTitle = j['itemTitle'] ?? '',
        category = j['category'] ?? '',
        dateFrom = j['dateFrom'] ?? '',
        dateTo = (j['dateTo'] as String?)?.isNotEmpty == true
            ? j['dateTo'] as String
            : null,
        quantity = j['quantity'] ?? 1,
        totalPrice = (j['totalPrice'] as num?)?.toDouble() ?? 0,
        currency = j['currency'] ?? 'LYD',
        status = j['status'] ?? 'Pending',
        isPaid = j['isPaid'] ?? false,
        pickupLocation = (j['pickupLocation'] as String?)?.isNotEmpty == true
            ? j['pickupLocation'] as String
            : null,
        dropoffLocation = (j['dropoffLocation'] as String?)?.isNotEmpty == true
            ? j['dropoffLocation'] as String
            : null,
        pickupTime = (j['pickupTime'] as String?)?.isNotEmpty == true
            ? j['pickupTime'] as String
            : null,
        dropoffTime = (j['dropoffTime'] as String?)?.isNotEmpty == true
            ? j['dropoffTime'] as String
            : null;
}
