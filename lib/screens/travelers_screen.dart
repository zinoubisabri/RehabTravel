import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../strings.dart';

/// شاشة «المسافرون» — حفظ بيانات المسافرين واستخدامهم عند الحجز،
/// مع قراءة الجواز تلقائياً (MRZ) من صورة الاستوديو أو الكاميرا.
class TravelersScreen extends StatefulWidget {
  final AuthState auth;
  const TravelersScreen({super.key, required this.auth});

  @override
  State<TravelersScreen> createState() => _TravelersScreenState();
}

class _TravelersScreenState extends State<TravelersScreen> {
  List<dynamic>? _travelers;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.auth.api.travelers();
      if (mounted) {
        setState(() {
          _travelers = list;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<dynamic> get _filtered => (_travelers ?? [])
      .where((t) => _search.isEmpty ||
          '${t['firstName']} ${t['lastName']} ${t['fullNameAr'] ?? ''} ${t['passportNumber'] ?? ''}'
              .toLowerCase()
              .contains(_search.toLowerCase()))
      .toList();

  Future<void> _delete(Map<String, dynamic> t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('حذف المسافر')),
        content: Text('${t['firstName']} ${t['lastName']}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.t('إلغاء'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.t('حذف'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.auth.api.deleteTraveler(t['id'] as int);
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TravelerFormScreen(auth: widget.auth, existing: existing),
      ),
    );
    if (saved == true) _load();
  }

  String _typeName(String type) => type == 'Child'
      ? S.t('طفل')
      : type == 'Infant'
          ? S.t('رضيع')
          : S.t('بالغ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('المسافرون'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt),
        label: Text(S.t('إضافة')),
      ),
      body: _travelers == null
          ? (_error != null
              ? Center(child: Text(_error!))
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: S.t('بحث بالاسم أو رقم الجواز…'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 10),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Text(S.t(
                            'لا يوجد مسافرون بعد — أضفهم يدوياً أو بقراءة الجواز واستخدمهم عند الحجز.')),
                      ),
                    ),
                  for (final t in _filtered)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF0E3A5D),
                          child: Text(
                            (t['firstName'] ?? '?').toString().isNotEmpty
                                ? t['firstName'].toString()[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text('${t['title'] ?? ''} ${t['firstName']} ${t['lastName']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text([
                          _typeName((t['type'] ?? 'Adult').toString()),
                          if ((t['nationality'] ?? '').toString().isNotEmpty)
                            t['nationality'].toString(),
                          if ((t['passportNumber'] ?? '').toString().isNotEmpty)
                            '${S.t('جواز')}: ${t['passportNumber']}',
                        ].join(' — ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _openForm(
                                  Map<String, dynamic>.from(t as Map)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () =>
                                  _delete(Map<String, dynamic>.from(t as Map)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// نموذج إضافة/تعديل مسافر — يدوي أو بقراءة MRZ من صورة الجواز.
class TravelerFormScreen extends StatefulWidget {
  final AuthState auth;
  final Map<String, dynamic>? existing;
  const TravelerFormScreen({super.key, required this.auth, this.existing});

  @override
  State<TravelerFormScreen> createState() => _TravelerFormScreenState();
}

class _TravelerFormScreenState extends State<TravelerFormScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _fullNameAr = TextEditingController();
  final _motherName = TextEditingController();
  final _nationality = TextEditingController();
  final _passportNumber = TextEditingController();
  final _issueCountry = TextEditingController();
  String _title = 'Mr';
  String _type = 'Adult';
  DateTime? _birthDate;
  DateTime? _passportExpiry;
  String? _passportImagePath;
  bool _saving = false;
  bool _scanning = false;
  String? _message;
  bool _messageOk = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title = (e['title'] ?? 'Mr').toString();
      _type = (e['type'] ?? 'Adult').toString();
      _firstName.text = (e['firstName'] ?? '').toString();
      _lastName.text = (e['lastName'] ?? '').toString();
      _fullNameAr.text = (e['fullNameAr'] ?? '').toString();
      _motherName.text = (e['motherNameAr'] ?? '').toString();
      _nationality.text = (e['nationality'] ?? '').toString();
      _passportNumber.text = (e['passportNumber'] ?? '').toString();
      _issueCountry.text = (e['passportIssueCountry'] ?? '').toString();
      _birthDate = DateTime.tryParse((e['birthDate'] ?? '').toString());
      _passportExpiry =
          DateTime.tryParse((e['passportExpiry'] ?? '').toString());
      _passportImagePath = e['passportImagePath']?.toString();
    }
  }

  Future<void> _pickDate(bool isBirth) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isBirth
          ? (_birthDate ?? DateTime(now.year - 25))
          : (_passportExpiry ?? DateTime(now.year + 5)),
      firstDate: isBirth ? DateTime(1930) : now,
      lastDate: isBirth ? now : DateTime(now.year + 20),
    );
    if (picked != null) {
      setState(() {
        if (isBirth) {
          _birthDate = picked;
        } else {
          _passportExpiry = picked;
        }
      });
    }
  }

  /// قراءة الجواز من الاستوديو أو الكاميرا عبر خدمة OCR المجانية
  Future<void> _scanPassport(ImageSource source) async {
    final photo = await _picker.pickImage(source: source, imageQuality: 92);
    if (photo == null) return;
    setState(() {
      _scanning = true;
      _message = null;
    });
    try {
      final bytes = await photo.readAsBytes();
      final r = await widget.auth.api.scanPassport(bytes, photo.name);
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _messageOk = r['success'] == true;
        _message = r['message']?.toString();
      });
      if (r['success'] == true) {
        setState(() {
          if ((r['firstName'] ?? '').toString().isNotEmpty) {
            _firstName.text = r['firstName'].toString();
          }
          if ((r['lastName'] ?? '').toString().isNotEmpty) {
            _lastName.text = r['lastName'].toString();
          }
          if ((r['passportNumber'] ?? '').toString().isNotEmpty) {
            _passportNumber.text = r['passportNumber'].toString();
          }
          if ((r['nationality'] ?? '').toString().isNotEmpty) {
            _nationality.text = r['nationality'].toString();
          }
          _birthDate = DateTime.tryParse((r['birthDate'] ?? '').toString()) ??
              _birthDate;
          _passportExpiry =
              DateTime.tryParse((r['passportExpiry'] ?? '').toString()) ??
                  _passportExpiry;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _messageOk = false;
          _message = e.message;
        });
      }
    }
  }

  void _showScanOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(S.t('صورة من الاستوديو')),
              onTap: () {
                Navigator.pop(ctx);
                _scanPassport(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(S.t('تصوير بالكاميرا')),
              onTap: () {
                Navigator.pop(ctx);
                _scanPassport(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      setState(() {
        _messageOk = false;
        _message = S.t('الاسم الأول واللقب بالإنجليزية مطلوبان');
      });
      return;
    }
    setState(() => _saving = true);
    final body = {
      'title': _title,
      'type': _type,
      'firstName': _firstName.text.trim().toUpperCase(),
      'lastName': _lastName.text.trim().toUpperCase(),
      'fullNameAr': _fullNameAr.text.trim(),
      'motherNameAr': _motherName.text.trim(),
      'nationality': _nationality.text.trim(),
      'passportNumber': _passportNumber.text.trim().toUpperCase(),
      'passportIssueCountry': _issueCountry.text.trim(),
      'passportImagePath': _passportImagePath,
      'birthDate': _birthDate?.toIso8601String(),
      'passportExpiry': _passportExpiry?.toIso8601String(),
    };
    try {
      if (widget.existing == null) {
        await widget.auth.api.createTraveler(body);
      } else {
        await widget.auth.api.updateTraveler(widget.existing!['id'] as int, body);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _messageOk = false;
        _message = e.message;
      });
    }
  }

  String _fmt(DateTime? d) =>
      d == null ? S.t('اختر') : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null
              ? S.t('إضافة مسافر')
              : S.t('تعديل بيانات المسافر'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // قراءة تلقائية من الجواز
          Card(
            color: const Color(0xFFEEF3F7),
            child: ListTile(
              leading: _scanning
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_outlined,
                      color: Color(0xFF0E3A5D)),
              title: Text(S.t('قراءة تلقائية من صورة الجواز')),
              subtitle: Text(S.t('يُقرأ شريط MRZ وتُملأ البيانات تلقائياً')),
              onTap: _scanning ? null : _showScanOptions,
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _message!,
                style: TextStyle(
                    color: _messageOk ? Colors.green.shade700 : Colors.red),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _title,
                  decoration: InputDecoration(
                      labelText: S.t('الصفة'), border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Mr', child: Text('Mr')),
                    DropdownMenuItem(value: 'Mrs', child: Text('Mrs')),
                    DropdownMenuItem(value: 'Ms', child: Text('Ms')),
                    DropdownMenuItem(value: 'Miss', child: Text('Miss')),
                    DropdownMenuItem(value: 'Mstr', child: Text('Mstr')),
                  ],
                  onChanged: (v) => setState(() => _title = v ?? 'Mr'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _type,
                  decoration: InputDecoration(
                      labelText: S.t('النوع'), border: OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(
                        value: 'Adult', child: Text(S.t('بالغ'))),
                    DropdownMenuItem(
                        value: 'Child', child: Text(S.t('طفل'))),
                    DropdownMenuItem(
                        value: 'Infant', child: Text(S.t('رضيع'))),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'Adult'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _firstName,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
                labelText: S.t('الاسم الأول بالإنجليزية *'),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lastName,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
                labelText: S.t('اللقب بالإنجليزية *'),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fullNameAr,
            decoration: InputDecoration(
                labelText: S.t('الاسم بالعربي'), border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motherName,
            decoration: InputDecoration(
                labelText: S.t('اسم الأم'), border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(S.t('تاريخ الميلاد')),
            trailing: TextButton(
              onPressed: () => _pickDate(true),
              child: Text(_fmt(_birthDate)),
            ),
          ),
          const Divider(height: 0),
          const SizedBox(height: 12),
          TextField(
            controller: _nationality,
            decoration: InputDecoration(
                labelText: S.t('الجنسية'), border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passportNumber,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
                labelText: S.t('رقم جواز السفر'),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(S.t('تاريخ انتهاء الجواز')),
            trailing: TextButton(
              onPressed: () => _pickDate(false),
              child: Text(_fmt(_passportExpiry)),
            ),
          ),
          const Divider(height: 0),
          const SizedBox(height: 12),
          TextField(
            controller: _issueCountry,
            decoration: InputDecoration(
                labelText: S.t('بلد إصدار الجواز'),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_saving ? S.t('جارٍ الحفظ…') : S.t('حفظ المسافر')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
