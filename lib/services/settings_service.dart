// lib/services/settings_service.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  late SharedPreferences _prefs;

  ThemeMode _themeMode       = ThemeMode.light;
  Locale    _locale          = const Locale('en');
  int       _defaultCourts   = 2;
  String    _defaultTeamMode = 'balanced';
  bool      _hapticsEnabled  = true;
  bool      _soundEnabled    = false;
  String    _adminPin        = '';

  ThemeMode get themeMode       => _themeMode;
  Locale    get locale          => _locale;
  int       get defaultCourts   => _defaultCourts;
  String    get defaultTeamMode => _defaultTeamMode;
  bool      get hapticsEnabled  => _hapticsEnabled;
  bool      get soundEnabled    => _soundEnabled;
  bool      get hasPin          => _adminPin.isNotEmpty;
  bool      get isDark          => _themeMode == ThemeMode.dark;

  bool validatePin(String pin) => _adminPin == pin;

  Future<void> init() async {
    _prefs         = await SharedPreferences.getInstance();
    _themeMode     = ThemeMode.values[_prefs.getInt('themeMode') ?? 0];
    _locale        = Locale(_prefs.getString('locale') ?? 'en');
    _defaultCourts = _prefs.getInt('defaultCourts') ?? 2;
    _defaultTeamMode = _prefs.getString('defaultTeamMode') ?? 'balanced';
    _hapticsEnabled  = _prefs.getBool('hapticsEnabled') ?? true;
    _soundEnabled    = _prefs.getBool('soundEnabled') ?? false;
    _adminPin        = _prefs.getString('adminPin') ?? '';
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setInt('themeMode', mode.index);
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    await _prefs.setString('locale', locale.languageCode);
    notifyListeners();
  }

  Future<void> setDefaultCourts(int count) async {
    _defaultCourts = count;
    await _prefs.setInt('defaultCourts', count);
    notifyListeners();
  }

  Future<void> setDefaultTeamMode(String mode) async {
    _defaultTeamMode = mode;
    await _prefs.setString('defaultTeamMode', mode);
    notifyListeners();
  }

  Future<void> setHaptics(bool val) async {
    _hapticsEnabled = val;
    await _prefs.setBool('hapticsEnabled', val);
    // Give immediate feedback so user knows it worked
    if (val) HapticFeedback.mediumImpact();
    notifyListeners();
  }

  Future<void> setSound(bool val) async {
    _soundEnabled = val;
    await _prefs.setBool('soundEnabled', val);
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    _adminPin = pin;
    if (pin.isEmpty) {
      await _prefs.remove('adminPin');
    } else {
      await _prefs.setString('adminPin', pin);
    }
    notifyListeners();
  }

  /// Trigger haptic if enabled — call from UI on any action.
  void haptic([HapticFeedbackType type = HapticFeedbackType.medium]) {
    if (!_hapticsEnabled) return;
    switch (type) {
      case HapticFeedbackType.light:
        HapticFeedback.lightImpact();
      case HapticFeedbackType.medium:
        HapticFeedback.mediumImpact();
      case HapticFeedbackType.heavy:
        HapticFeedback.heavyImpact();
      case HapticFeedbackType.selection:
        HapticFeedback.selectionClick();
    }
  }
}

enum HapticFeedbackType { light, medium, heavy, selection }