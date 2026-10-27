import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

/// زر تبديل اللغة (عربي/English) — يحفظ الاختيار في SharedPreferences.
class LangToggleButton extends StatelessWidget {
  const LangToggleButton({super.key});

  Future<void> _toggle() async {
    S.toggle();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rt_lang', S.lang.value);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: S.lang,
      builder: (context, lang, _) => TextButton(
        onPressed: _toggle,
        child: Text(
          lang == 'ar' ? '🌐 EN' : '🌐 عربي',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
