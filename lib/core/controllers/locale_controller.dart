import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController extends ChangeNotifier {
  static const String _prefsKey = 'app_locale';

  /// `null` => seguir idioma do sistema.
  Locale? _overrideLocale;

  Locale? get locale => _overrideLocale;

  bool get isUsingSystemLocale => _overrideLocale == null;

  String? get overrideLanguageCode => _overrideLocale?.languageCode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = (prefs.getString(_prefsKey) ?? '').trim().toLowerCase();

    if (code.isEmpty) {
      _overrideLocale = null;
      return;
    }

    _overrideLocale = Locale(code);
  }

  Future<void> setLocale(Locale locale) async {
    final next = Locale(locale.languageCode.toLowerCase());

    if (_overrideLocale?.languageCode == next.languageCode) {
      return;
    }

    _overrideLocale = next;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next.languageCode);
  }

  Future<void> useSystemLocale() async {
    if (_overrideLocale == null) return;

    _overrideLocale = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
