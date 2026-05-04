// lib/views/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';

const _gold = Color(0xFFD4AF37);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark   = settings.isDark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SETTINGS'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ──────────────────────────────────────
          _SectionHeader('APPEARANCE'),
          _SettingCard(
            icon: isDark ? Icons.dark_mode : Icons.light_mode_outlined,
            title: 'Theme',
            subtitle: isDark ? 'Dark' : 'Light',
            trailing: Switch(
              value: isDark,
              activeColor: _gold,
              onChanged: (val) => context.read<SettingsService>()
                  .setThemeMode(val ? ThemeMode.dark : ThemeMode.light),
            ),
          ),

          // ── Language ────────────────────────────────────────
          _SectionHeader('LANGUAGE & REGION'),
          _SettingCard(
            icon: Icons.language_outlined,
            title: 'Language',
            subtitle: settings.locale.languageCode == 'ar'
                ? 'العربية' : 'English',
            trailing: _GoldDropdown<String>(
              value: settings.locale.languageCode,
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'ar', child: Text('العربية')),
              ],
              onChanged: (val) {
                if (val != null) {
                  context.read<SettingsService>()
                      .setLocale(Locale(val));
                }
              },
            ),
          ),

          // ── Defaults ────────────────────────────────────────
          _SectionHeader('SESSION DEFAULTS'),
          _SettingCard(
            icon: Icons.sports_tennis_outlined,
            title: 'Default Courts',
            subtitle: '${settings.defaultCourts} courts per session',
            trailing: _GoldDropdown<int>(
              value: settings.defaultCourts,
              items: List.generate(8, (i) => DropdownMenuItem(
                value: i + 1,
                child: Text('${i + 1}'),
              )),
              onChanged: (val) {
                if (val != null) {
                  context.read<SettingsService>().setDefaultCourts(val);
                }
              },
            ),
          ),
          _SettingCard(
            icon: Icons.balance_outlined,
            title: 'Default Team Mode',
            subtitle: _teamModeLabel(settings.defaultTeamMode),
            trailing: _GoldDropdown<String>(
              value: settings.defaultTeamMode,
              items: const [
                DropdownMenuItem(value: 'balanced',
                    child: Text('Balanced')),
                DropdownMenuItem(value: 'random',
                    child: Text('Random')),
                DropdownMenuItem(value: 'perLevel',
                    child: Text('Per Level')),
              ],
              onChanged: (val) {
                if (val != null) {
                  context.read<SettingsService>().setDefaultTeamMode(val);
                }
              },
            ),
          ),

          // ── Feedback ────────────────────────────────────────
          _SectionHeader('FEEDBACK'),
          _SettingCard(
            icon: Icons.vibration_outlined,
            title: 'Haptics',
            subtitle: 'Vibration on actions',
            trailing: Switch(
              value: settings.hapticsEnabled,
              activeColor: _gold,
              onChanged: (val) =>
                  context.read<SettingsService>().setHaptics(val),
            ),
          ),
          _SettingCard(
            icon: Icons.volume_up_outlined,
            title: 'Sound',
            subtitle: 'Audio cues',
            trailing: Switch(
              value: settings.soundEnabled,
              activeColor: _gold,
              onChanged: (val) =>
                  context.read<SettingsService>().setSound(val),
            ),
          ),

          // ── Security ────────────────────────────────────────
          _SectionHeader('SECURITY'),
          _SettingCard(
            icon: Icons.lock_outline,
            title: 'Admin PIN',
            subtitle: settings.hasPin ? 'PIN set' : 'No PIN',
            trailing: TextButton(
              onPressed: () => _showPinDialog(context, settings),
              child: Text(
                settings.hasPin ? 'Change' : 'Set PIN',
                style: const TextStyle(
                    color: _gold, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (settings.hasPin)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton(
                onPressed: () => settings.setPin(null),
                child: const Text('Remove PIN',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ),

          // ── About ────────────────────────────────────────────
          _SectionHeader('ABOUT'),
          _SettingCard(
            icon: Icons.info_outline,
            title: 'Aero QMS',
            subtitle: 'Version 1.0.0',
            trailing: const SizedBox(),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showPinDialog(BuildContext context, SettingsService settings) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(settings.hasPin ? 'Change PIN' : 'Set Admin PIN'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Enter 4–6 digit PIN',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.length >= 4) {
                settings.setPin(ctrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save',
                style: TextStyle(color: _gold, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _teamModeLabel(String mode) => switch (mode) {
        'balanced' => 'Balanced',
        'random'   => 'Random',
        'perLevel' => 'Per Level',
        _          => mode,
      };
}

// ── Shared widgets ────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8), letterSpacing: 1.4)),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Widget   trailing;

  const _SettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? const Color(0xFF374151)
                : const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: _gold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 18, color: _gold),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF111827))),
          Text(subtitle, style: const TextStyle(
              fontSize: 12, color: Color(0xFF94A3B8))),
        ])),
        trailing,
      ]),
    );
  }
}

class _GoldDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _GoldDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        style: const TextStyle(
            color: _gold, fontWeight: FontWeight.w600, fontSize: 13),
        icon: const Icon(Icons.keyboard_arrow_down, color: _gold, size: 18),
        dropdownColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1F2937) : Colors.white,
      ),
    );
  }
}