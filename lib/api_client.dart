import 'dart:convert';
import 'package:http/http.dart' as http;

import 'strings.dart';

/// عميل HTTP موحد لـ RehabTravel.Api مع دعم JWT.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiClient {
  /// عنوان خادم API — الافتراضي هو خادم الإنتاج، ويمكن تجاوزه وقت البناء:
  /// flutter build apk --dart-define=RT_API_URL=http://localhost:5000/
  static const String baseUrl = String.fromEnvironment(
    'RT_API_URL',
    defaultValue: 'https://api.booking.zinoubi.net/',
  );

  String? token;

  /// آخر جسم خطأ من الخادم (لقراءة حقول مثل requiresVerification).
  Map<String, dynamic>? lastErrorBody;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        // لغة الواجهة — المزود يعيد نتائج الفنادق بها (عربي/إنجليزي)
        'X-User-Lang': S.isAr ? 'ar' : 'en',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    lastErrorBody = null;
    http.Response response;
    try {
    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 120));
        break;
      case 'POST':
        response = await http
            .post(uri,
                headers: _headers,
                body: body == null ? null : jsonEncode(body))
            .timeout(const Duration(seconds: 120));
        break;
      case 'PUT':
        response = await http
            .put(uri,
                headers: _headers,
                body: body == null ? null : jsonEncode(body))
            .timeout(const Duration(seconds: 120));
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 120));
        break;
      default:
        throw ApiException('HTTP method not supported: $method');
    }
    } on ApiException {
      rethrow;
    } catch (_) {
      // انتهاء المهلة أو انقطاع الشبكة
      throw ApiException('تعذر الاتصال بالخادم — تحقق من الإنترنت وحاول مجدداً');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    // محاولة قراءة رسالة الخطأ من الخادم
    try {
      final err = jsonDecode(response.body);
      if (err is Map) {
        lastErrorBody = Map<String, dynamic>.from(err);
        if (err['message'] != null) {
          throw ApiException(err['message'].toString());
        }
      }
    } catch (e) {
      if (e is ApiException) rethrow;
    }
    throw ApiException('خطأ في الاتصال بالخادم (${response.statusCode})');
  }

  // ---------- المصادقة ----------
  // client:'app' → جلسة دائمة مدى الحياة — التطبيق لا يطلب الدخول مجدداً إلا بتسجيل الخروج اليدوي
  Future<Map<String, dynamic>> login(String email, String password) async =>
      await _send('POST', 'api/auth/login',
          {'email': email, 'password': password, 'client': 'app'});

  Future<Map<String, dynamic>> register(
          String fullName, String email, String phone, String password) async =>
      await _send('POST', 'api/auth/register', {
        'fullName': fullName,
        'email': email,
        'phoneNumber': phone,
        'password': password,
        'client': 'app',
      });

  /// تأكيد البريد برمز OTP بعد التسجيل — يرجع جلسة JWT جاهزة عند النجاح
  Future<Map<String, dynamic>> verifyEmail(String email, String code) async =>
      await _send('POST', 'api/auth/verify-email',
          {'email': email, 'code': code, 'client': 'app'});

  /// إعادة إرسال رمز التحقق (رد عام دائماً)
  Future<dynamic> resendCode(String email) async =>
      await _send('POST', 'api/auth/resend-code', {'email': email});

  /// طلب رمز استعادة كلمة السر (يصل بالبريد عند تفعيله + إشعار داخلي)
  Future<dynamic> forgotPassword(String email) async =>
      await _send('POST', 'api/auth/forgot-password', {'email': email});

  /// تعيين كلمة سر جديدة برمز الاستعادة
  Future<dynamic> resetPassword(String token, String newPassword) async =>
      await _send('POST', 'api/auth/reset-password',
          {'token': token, 'newPassword': newPassword});

  /// دخول اجتماعي من التطبيق — Google (Android) / Apple (iOS)
  Future<Map<String, dynamic>> socialAppLogin({
    required String provider,
    required String providerKey,
    String? email,
    String? fullName,
    String? idToken,
  }) async =>
      await _send('POST', 'api/auth/social-app', {
        'provider': provider,
        'providerKey': providerKey,
        'email': email,
        'fullName': fullName,
        'idToken': idToken,
      });

  // ---------- قسائم التخفيض ----------
  // ملاحظة: validateCoupon معرّفة في نهاية الملف (num amount) — لا تكرار هنا.

  /// تسخين سعر الفندق لدى المزود بالخلفية — يُستدعى عند فتح نموذج الحجز
  /// فيكون checkRate جاهزاً عند ضغط «تأكيد» فيقل الانتظار (~10 ثوانٍ).
  void warmHotelRate(String rateKey, int apiProviderId) {
    _send('POST', 'api/hotels/warm-rate',
            {'rateKey': rateKey, 'apiProviderId': apiProviderId})
        .catchError((_) => null); // أفضل جهد — الفشل لا يؤثر على الحجز
  }

  // ---------- الطيران ----------
  Future<Map<String, dynamic>> searchFlights({
    required String from,
    required String to,
    required String departDate,
    String? returnDate,
    required bool roundTrip,
    required int adults,
    required int children,
    required int infants,
  }) async =>
      await _send('POST', 'api/flights/search', {
        'fromAirport': from,
        'toAirport': to,
        'departDate': departDate,
        'returnDate': returnDate,
        'tripType': roundTrip ? 1 : 0,
        'adults': adults,
        'children': children,
        'infants': infants,
      });

  /// تسعيرة حية من شركة الطيران (VRS QQ — صفحة 8 من دليل API):
  /// تُرجع السعر الفعلي لكل نوع مسافر (بالغ/طفل/رضيع) بدل خصومات قاعدة البيانات.
  /// الحقول: apiProviderId, outAirlineCode, outFlightNumber, outClassCode,
  /// outDepartDate, fromAirport, toAirport, adults, children, infants
  /// + اختيارياً: ret*, outDepartTime/outArriveTime/outClassBandName للدقة.
  Future<Map<String, dynamic>> partyQuote(Map<String, dynamic> request) async =>
      await _send('POST', 'api/flights/quote', request);

  Future<Map<String, dynamic>> createBooking(Map<String, dynamic> request) async =>
      await _send('POST', 'api/bookings', request);

  /// هل يُسمح لهذا المستخدم بخيار «حجز مبدئي»؟ — وفق سياسة الإدارة
  Future<bool> holdPermission() async {
    try {
      final r = await _send('GET', 'api/flights/hold-permission');
      return r is Map && r['allowed'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<dynamic>> myBookings() async => await _send('GET', 'api/bookings/my');

  Future<Map<String, dynamic>> issueTicket(int bookingId) async =>
      await _send('POST', 'api/bookings/$bookingId/issue');

  Future<Map<String, dynamic>> voidTicket(int bookingId) async =>
      await _send('POST', 'api/bookings/$bookingId/void');

  Future<Map<String, dynamic>> importPnr(String rloc) async =>
      await _send('POST', 'api/bookings/import-pnr', {'rloc': rloc});

  // ---------- الفنادق ----------
  Future<Map<String, dynamic>> searchHotels({
    required String destination,
    required String checkIn,
    required String checkOut,
    required int rooms,
    required int adults,
    required int children,
    List<int>? childrenAges,
  }) async =>
      await _send('POST', 'api/hotels/search', {
        'destination': destination,
        'checkIn': checkIn,
        'checkOut': checkOut,
        'rooms': rooms,
        'adults': adults,
        'children': children,
        if (childrenAges != null && childrenAges.isNotEmpty)
          'occupancies': [
            {'adults': adults, 'childrenAges': childrenAges},
            for (var r = 1; r < rooms; r++) {'adults': 2, 'childrenAges': <int>[]},
          ],
        'currency': 'LYD',
      });

  /// تفاصيل فندق من المزود: صور + وصف + كل الأسعار المتاحة
  Future<Map<String, dynamic>> hotelDetails(
      String code, String checkIn, String checkOut,
      {int rooms = 1, int adults = 2, String? occ}) async {
    var url =
        'api/hotels/provider-hotel/${Uri.encodeComponent(code)}?checkIn=$checkIn&checkOut=$checkOut&rooms=$rooms&adults=$adults';
    if (occ != null && occ.isNotEmpty) url += '&occ=${Uri.encodeComponent(occ)}';
    return Map<String, dynamic>.from(await _send('GET', url));
  }

  Future<Map<String, dynamic>> bookHotel(Map<String, dynamic> request) async =>
      await _send('POST', 'api/hotels/book', request);

  Future<List<dynamic>> myHotelBookings() async => await _send('GET', 'api/hotels/my');

  // ---------- العمرة ----------
  Future<List<dynamic>> umrahPackages() async => await _send('GET', 'api/umrah/packages');

  Future<Map<String, dynamic>> bookUmrah(Map<String, dynamic> request) async =>
      await _send('POST', 'api/umrah/book', request);

  Future<List<dynamic>> myUmrahBookings() async => await _send('GET', 'api/umrah/my');

  // ---------- الدفع الإلكتروني (Tlync) ----------
  /// gateway=6 = Tlync في PaymentGateway enum — يرجع {success, redirectUrl, paymentReference, message}
  Future<Map<String, dynamic>> initiateTlync(num amount, String productType,
          {String? phone}) async =>
      await _send('POST', 'api/payments/initiate', {
        'gateway': 6,
        'amount': amount,
        'currency': 'LYD',
        'productType': productType,
        'customerPhone': phone,
      });

  /// فحص حالة عملية دفع بمرجعها (بعد العودة من صفحة البوابة)
  Future<Map<String, dynamic>> paymentStatus(String reference) async =>
      await _send('GET', 'api/payments/status/$reference');

  // ---------- المحفظة ----------
  Future<Map<String, dynamic>> wallet() async => await _send('GET', 'api/wallet');

  Future<dynamic> submitDeposit(num amount, String? description,
          {String? receiptPath, String? receiptFileName, String currency = 'LYD'}) async =>
      await _send('POST', 'api/wallet/deposit-requests', {
        'amount': amount,
        'currency': currency,
        'description': description,
        'receiptPath': receiptPath,
        'receiptFileName': receiptFileName,
      });

  /// رفع صورة إيصال الحوالة — يرجع (المسار، اسم الملف) لإرفاقهما بطلب الشحن
  Future<({String path, String fileName})?> uploadDepositReceipt(
      List<int> bytes, String fileName) async {
    final uri = Uri.parse('${baseUrl}api/uploads/deposit-receipt');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (data is Map && data['path'] != null) {
        return (path: data['path'].toString(), fileName: data['fileName']?.toString() ?? fileName);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// رفع مستند عام (صورة إقامة وغيرها) — يرجع المسار لإرفاقه بالطلب
  Future<String?> uploadDocument(List<int> bytes, String fileName) async {
    final uri = Uri.parse('${baseUrl}api/uploads/document');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (data is Map && data['path'] != null) return data['path'].toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------- الولاء والإشعارات ----------
  Future<Map<String, dynamic>> loyaltyBalance() async =>
      await _send('GET', 'api/loyalty/balance');

  Future<int> unreadCount() async =>
      await _send('GET', 'api/notifications/unread-count');

  Future<List<dynamic>> notifications() async =>
      await _send('GET', 'api/notifications/my');

  Future<dynamic> markNotificationRead(int id) async =>
      await _send('POST', 'api/notifications/$id/read');

  Future<dynamic> registerDevice(String token, String platform) async =>
      await _send('POST', 'api/notifications/device-token',
          {'token': token, 'platform': platform});

  // ---------- الخدمات الإضافية (سيارات/نقل/جولات/تأمين) ----------
  Future<List<dynamic>> serviceButtons() async =>
      await _send('GET', 'api/extraservices/buttons');

  Future<List<dynamic>> extraCategories() async =>
      await _send('GET', 'api/extraservices/categories');

  Future<List<dynamic>> extraCatalog(String category,
      {String? location, DateTime? from, DateTime? to, int? passengers}) async {
    var url = 'api/extraservices/catalog?category=$category';
    if (location != null && location.isNotEmpty) {
      url += '&location=${Uri.encodeQueryComponent(location)}';
    }
    if (from != null && to != null) {
      String f(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      url += '&from=${f(from)}&to=${f(to)}';
    }
    if (passengers != null && passengers > 0) {
      url += '&passengers=$passengers';
    }
    return await _send('GET', url);
  }

  Future<List<dynamic>> carLocations([String? query]) async =>
      await _send('GET', 'api/extraservices/car-locations' +
          (query == null || query.isEmpty
              ? ''
              : '?query=${Uri.encodeQueryComponent(query)}'));

  Future<Map<String, dynamic>> bookExtraService(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
          await _send('POST', 'api/extraservices/book', body) as Map);

  Future<List<dynamic>> myExtraBookings() async =>
      await _send('GET', 'api/extraservices/my');

  // ---------- المطارات والتواصل ----------
  Future<List<dynamic>> airports() async => await _send('GET', 'api/airports');

  /// تقويم أرخص الأسعار للمسار — بيانات «cal» من مزود الطيران (مخزنة مؤقتاً في الخادم)
  Future<List<dynamic>> fareCalendar(String from, String to) async =>
      await _send('GET',
          'api/flights/fare-calendar?from=$from&to=$to&days=35');

  Future<Map<String, dynamic>> contactSettings() async =>
      await _send('GET', 'api/contact/settings');

  Future<dynamic> sendContactMessage({
    required String name,
    required String email,
    String? phone,
    required String subject,
    required String message,
  }) async =>
      await _send('POST', 'api/contact/messages', {
        'name': name,
        'email': email,
        'phone': phone,
        'subject': subject,
        'message': message,
      });

  // ---------- تنبيهات الأسعار ----------
  Future<Map<String, dynamic>> createPriceAlert({
    required String from,
    required String to,
    required String departDate,
    required num targetPrice,
    String currency = 'LYD',
  }) async =>
      await _send('POST', 'api/pricealerts', {
        'fromAirport': from,
        'toAirport': to,
        'departDate': departDate,
        'targetPrice': targetPrice,
        'currency': currency,
      });

  Future<List<dynamic>> myPriceAlerts() async =>
      await _send('GET', 'api/pricealerts/my');

  Future<dynamic> deletePriceAlert(int id) async =>
      await _send('DELETE', 'api/pricealerts/$id');

  // ---------- الشرائح الإلكترونية eSIM ----------
  Future<List<dynamic>> esimCountries() async =>
      await _send('GET', 'api/esim/countries');

  Future<List<dynamic>> esimPlans(String countryIso) async =>
      await _send('GET', 'api/esim/plans?country=${Uri.encodeComponent(countryIso)}');

  Future<Map<String, dynamic>> esimOrder(
          String planId, int quantity, String countryCode, String countryName,
          {String? couponCode}) async =>
      await _send('POST', 'api/esim/order', {
        'planId': planId,
        'quantity': quantity,
        'countryCode': countryCode,
        'countryName': countryName,
        if (couponCode != null && couponCode.isNotEmpty) 'couponCode': couponCode,
      });

  Future<List<dynamic>> myEsimOrders() async =>
      await _send('GET', 'api/esim/my');

  Future<Map<String, dynamic>> esimOrderDetails(int id) async =>
      await _send('GET', 'api/esim/my/$id');

  Future<Map<String, dynamic>> cancelEsimOrder(int id) async =>
      await _send('POST', 'api/esim/my/$id/cancel');

  // ---------- الصفحة الرئيسية ----------
  Future<Map<String, dynamic>> homeSettings() async =>
      await _send('GET', 'api/contact/home');

  Future<List<dynamic>> trendingDestinations() async =>
      await _send('GET', 'api/flights/trending');

  // ---------- الوجهات والبانرات ----------
  /// إكمال تلقائي لوجهات الفنادق (مخزون محلي + المزود العالمي) — من حرفين
  Future<List<dynamic>> hotelDestinations(String term) async =>
      await _send('GET', 'api/hotels/destinations?term=${Uri.encodeQueryComponent(term)}');

  /// بانرات إعلانية الصفحة الرئيسية (تُدار من لوحة الأدمن)
  Future<List<dynamic>> banners() async => await _send('GET', 'api/banners');

  /// رابط شعار الشركة المرفوع من لوحة الأدمن (صورة مباشرة)
  String get brandingLogoUrl => '${baseUrl}api/branding/logo';

  // ---------- الفاوتشرات والتذاكر (للعرض والطباعة) ----------
  Future<Map<String, dynamic>> ticketView(int bookingId) async =>
      await _send('GET', 'api/bookings/$bookingId/ticket');

  Future<Map<String, dynamic>> hotelVoucher(int bookingId) async =>
      await _send('GET', 'api/hotels/my/$bookingId/voucher');

  Future<Map<String, dynamic>> umrahBookingDetails(int bookingId) async =>
      await _send('GET', 'api/umrah/my/$bookingId');

  /// معلومات العملات العامة — عملة الموقع + أسعار الصرف (عام بدون توثيق)
  Future<Map<String, dynamic>> currencyInfo() async =>
      Map<String, dynamic>.from(await _send('GET', 'api/currency'));

  /// تحليل أمر المساعد الذكي عبر AI API المدفوع (يُضبط من لوحة الإدارة)
  Future<Map<String, dynamic>> parseAssistant(String text) async =>
      Map<String, dynamic>.from(await _send('POST', 'api/assistant/parse', {'text': text}));

  // ---------- التدفق الجديد: مدينة ← رحلة ← عرض ← فاتورة مدفوعة فوراً ----------
  Future<List<dynamic>> umrahCities() async =>
      await _send('GET', 'api/umrah/departure-cities');

  Future<List<dynamic>> umrahTrips(int cityId) async =>
      await _send('GET', 'api/umrah/trips?cityId=$cityId');

  Future<List<dynamic>> umrahTripOffers(int tripId) async =>
      await _send('GET', 'api/umrah/trips/$tripId/offers');

  Future<Map<String, dynamic>> bookUmrahTrip(Map<String, dynamic> request) async =>
      await _send('POST', 'api/umrah/book-trip', request);

  /// رفع صورة جواز مع قراءة OCR — يرجع الحقول المستخرجة + مسار الصورة
  Future<Map<String, dynamic>> uploadPassportOcr(List<int> bytes, String fileName) async {
    final uri = Uri.parse('${baseUrl}api/uploads/passport-ocr');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'success': false, 'message': 'استجابة غير متوقعة من الخادم'};
    } catch (_) {
      throw ApiException('تعذر الاتصال بالخادم — تحقق من الإنترنت وحاول مجدداً');
    }
  }

  // ---------- المسافرون المحفوظون ----------
  Future<List<dynamic>> travelers() async => await _send('GET', 'api/travelers');

  Future<Map<String, dynamic>> createTraveler(Map<String, dynamic> request) async =>
      await _send('POST', 'api/travelers', request);

  Future<Map<String, dynamic>> updateTraveler(int id, Map<String, dynamic> request) async =>
      await _send('PUT', 'api/travelers/$id', request);

  Future<dynamic> deleteTraveler(int id) async =>
      await _send('DELETE', 'api/travelers/$id');

  /// قراءة بيانات الجواز (MRZ) من صورة — تعبئة تلقائية لنموذج المسافر
  Future<Map<String, dynamic>> scanPassport(List<int> bytes, String fileName) async {
    final uri = Uri.parse('${baseUrl}api/travelers/scan-passport');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'success': false, 'message': 'استجابة غير متوقعة من الخادم'};
    } catch (_) {
      throw ApiException('تعذر الاتصال بالخادم — تحقق من الإنترنت وحاول مجدداً');
    }
  }

  /// رفع صورة جواز المسافر — يرجع المسار لحفظه في سجل المسافر
  Future<String?> uploadTravelerPassport(List<int> bytes, String fileName) async {
    final uri = Uri.parse('${baseUrl}api/uploads/traveler-passport');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (data is Map && data['path'] != null) return data['path'].toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------- قسائم التخفيض ----------
  Future<Map<String, dynamic>> validateCoupon(String code, String serviceType, num amount) async =>
      await _send('POST', 'api/coupons/validate',
          {'code': code, 'serviceType': serviceType, 'amount': amount});

  // ---------- حسابي ----------
  Future<Map<String, dynamic>> profileStatus() async =>
      await _send('GET', 'api/profile/status');

  Future<dynamic> updateProfile(String fullName) async =>
      await _send('PUT', 'api/profile', {'fullName': fullName});

  Future<dynamic> changePassword(String current, String next, String confirm) async =>
      await _send('POST', 'api/profile/change-password',
          {'currentPassword': current, 'newPassword': next, 'confirmPassword': confirm});

  Future<dynamic> requestEmailChange(String newEmail) async =>
      await _send('POST', 'api/profile/request-email-change', {'newEmail': newEmail});

  Future<dynamic> confirmEmailChange(String code) async =>
      await _send('POST', 'api/profile/confirm-email-change', {'code': code});

  Future<dynamic> resendEmailVerification() async =>
      await _send('POST', 'api/profile/resend-email-verification');

  Future<dynamic> confirmEmail(String code) async =>
      await _send('POST', 'api/profile/confirm-email', {'code': code});

  Future<dynamic> requestPhoneChange(String newPhone) async =>
      await _send('POST', 'api/profile/request-phone-change', {'newPhone': newPhone});

  Future<dynamic> confirmPhoneChange(String code) async =>
      await _send('POST', 'api/profile/confirm-phone-change', {'code': code});

  Future<dynamic> requestAccountDeletion() async =>
      await _send('POST', 'api/profile/delete-request');

  /// حفظ عملة العميل المفضلة في حسابه (LYD/USD/EUR) — تتزامن مع الموقع
  Future<Map<String, dynamic>> setMyCurrency(String currency) async =>
      await _send('PUT', 'api/profile/currency', {'currency': currency});

  /// استبدال نقاط الولاء — يُضاف الرصيد لمحفظة الدينار دائماً مهما كانت عملة العميل
  Future<Map<String, dynamic>> redeemLoyalty(int points) async =>
      await _send('POST', 'api/loyalty/redeem', {'points': points});
}
