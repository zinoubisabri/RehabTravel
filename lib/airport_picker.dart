import 'package:flutter/material.dart';

import '../models.dart';
import '../strings.dart';

/// شاشة اختيار مطار ببحث فوري — اكتب الكود (TIP) أو الاسم بالعربية أو الإنجليزية.
/// تُرجع المطار المختار عبر Navigator.pop.
class AirportPickerScreen extends StatefulWidget {
  final List<Airport> airports;
  final String? selectedCode;

  const AirportPickerScreen({super.key, required this.airports, this.selectedCode});

  @override
  State<AirportPickerScreen> createState() => _AirportPickerScreenState();
}

class _AirportPickerScreenState extends State<AirportPickerScreen> {
  String _query = '';

  List<Airport> get _filtered {
    final q = _query.trim();
    if (q.isEmpty) return widget.airports;
    final lower = q.toLowerCase();
    return widget.airports
        .where((a) =>
            a.code.toLowerCase().contains(lower) ||
            a.name.contains(q) ||
            a.nameEn.toLowerCase().contains(lower) ||
            a.city.contains(q) ||
            a.cityEn.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = S.isAr;
    final results = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: S.t('اكتب اسم أو كود المطار...'),
            hintStyle: const TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
        ),
      ),
      body: results.isEmpty
          ? Center(child: Text(S.t('لا توجد نتائج مطابقة')))
          : ListView.separated(
              itemCount: results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = results[i];
                final selected = a.code == widget.selectedCode;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: selected
                        ? const Color(0xFF0E3A5D)
                        : const Color(0xFFE3EDF5),
                    child: Text(
                      a.code,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.white : const Color(0xFF0E3A5D),
                      ),
                    ),
                  ),
                  title: Text(isAr ? a.name : a.nameEn),
                  subtitle: Text(isAr
                      ? '${a.city}، ${a.country}'
                      : '${a.cityEn}, ${a.countryEn}'),
                  trailing: selected
                      ? const Icon(Icons.check, color: Color(0xFF0E3A5D))
                      : null,
                  onTap: () => Navigator.pop(context, a),
                );
              },
            ),
    );
  }
}
