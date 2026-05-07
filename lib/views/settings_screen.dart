// lib/views/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _gold = Color(0xFFD4AF37);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<PackageInfo> _getPackageInfo() async {
    return await PackageInfo.fromPlatform();
  }

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
          _Section('APPEARANCE'),
          _Card(isDark: isDark,
            child: _Row(
              icon: isDark ? Icons.dark_mode : Icons.light_mode_outlined,
              title: 'Theme',
              subtitle: isDark ? 'Dark mode' : 'Light mode',
              trailing: Switch(
                value: isDark,
                activeColor: _gold,
                onChanged: (val) => context.read<SettingsService>()
                    .setThemeMode(
                        val ? ThemeMode.dark : ThemeMode.light),
              ),
            ),
          ),

          _Section('LANGUAGE & REGION'),
          _Card(isDark: isDark,
            child: _Row(
              icon: Icons.language_outlined,
              title: 'Language',
              subtitle: settings.locale.languageCode == 'ar'
                  ? 'العربية' : 'English',
              trailing: _GoldDrop<String>(
                value: settings.locale.languageCode,
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'ar', child: Text('العربية')),
                ],
                onChanged: (v) {
                  if (v != null) context.read<SettingsService>()
                      .setLocale(Locale(v));
                },
              ),
            ),
          ),

          _Section('SESSION DEFAULTS'),
          _Card(isDark: isDark,
            child: _Row(
              icon: Icons.sports_tennis_outlined,
              title: 'Default Courts',
              subtitle: '${settings.defaultCourts} courts',
              trailing: _GoldDrop<int>(
                value: settings.defaultCourts,
                items: List.generate(8, (i) => DropdownMenuItem(
                  value: i + 1, child: Text('${i + 1}'))),
                onChanged: (v) {
                  if (v != null) context.read<SettingsService>()
                      .setDefaultCourts(v);
                },
              ),
            ),
          ),
          _Card(isDark: isDark,
            child: _Row(
              icon: Icons.balance_outlined,
              title: 'Default Team Mode',
              subtitle: _modeLabel(settings.defaultTeamMode),
              trailing: _GoldDrop<String>(
                value: settings.defaultTeamMode,
                items: const [
                  DropdownMenuItem(value: 'balanced',
                      child: Text('Balanced')),
                  DropdownMenuItem(value: 'random',
                      child: Text('Random')),
                  DropdownMenuItem(value: 'perLevel',
                      child: Text('Per Level')),
                ],
                onChanged: (v) {
                  if (v != null) context.read<SettingsService>()
                      .setDefaultTeamMode(v);
                },
              ),
            ),
          ),

          _Section('FEEDBACK'),
          _Card(isDark: isDark,
            child: _Row(
              icon: Icons.vibration_outlined,
              title: 'Haptics',
              subtitle: settings.hapticsEnabled ? 'On' : 'Off',
              trailing: Switch(
                value: settings.hapticsEnabled,
                activeColor: _gold,
                onChanged: (v) =>
                    context.read<SettingsService>().setHaptics(v),
              ),
            ),
          ),
          _Card(isDark: isDark,
            child: _Row(
              icon: Icons.volume_up_outlined,
              title: 'Sound',
              subtitle: settings.soundEnabled ? 'On' : 'Off',
              trailing: Switch(
                value: settings.soundEnabled,
                activeColor: _gold,
                onChanged: (v) =>
                    context.read<SettingsService>().setSound(v),
              ),
            ),
          ),

          _Section('SECURITY'),
          _Card(isDark: isDark,
            child: _Row(
              icon: Icons.lock_outline,
              title: 'Admin PIN',
              subtitle: settings.hasPin ? 'PIN is set' : 'No PIN set',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (settings.hasPin)
                  TextButton(
                    onPressed: () =>
                        context.read<SettingsService>().setPin(''),
                    child: const Text('Remove',
                        style: TextStyle(color: Colors.redAccent,
                            fontSize: 13)),
                  ),
                TextButton(
                  onPressed: () => _showPinDialog(context, settings),
                  child: Text(settings.hasPin ? 'Change' : 'Set PIN',
                      style: const TextStyle(color: _gold,
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ]),
            ),
          ),

          _Section('ABOUT'),
        // FIX START: Wrap the About card in a FutureBuilder
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final version = snapshot.data?.version ?? '...';
            final build = snapshot.data?.buildNumber ?? '';
            
            return _Card(
              isDark: isDark,
              child: _Row(
                icon: Icons.info_outline,
                title: 'Aero QMS',
                subtitle: "Version $version ($build)",
                trailing: const SizedBox(),
              ),
            );
          },
        ),
        // FIX END
        const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showPinDialog(BuildContext context, SettingsService settings) {
    final ctrl = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(settings.hasPin ? 'Change PIN' : 'Set Admin PIN'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Enter PIN (4–6 digits)',
                  counterText: ''),
              validator: (v) => (v == null || v.length < 4)
                  ? 'PIN must be at least 4 digits' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: confirm,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  counterText: ''),
              validator: (v) => v != ctrl.text
                  ? 'PINs do not match' : null,
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                context.read<SettingsService>().setPin(ctrl.text);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PIN saved'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Save',
                style: TextStyle(color: _gold,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _modeLabel(String m) => switch (m) {
    'balanced' => 'Balanced',
    'random'   => 'Random',
    'perLevel' => 'Per Level',
    _          => m,
  };
}

// ── Helpers ───────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(text, style: const TextStyle(fontSize: 11,
        fontWeight: FontWeight.w700, color: Color(0xFF94A3B8),
        letterSpacing: 1.4)),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  final bool   isDark;
  const _Card({required this.child, required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1F2937) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: isDark ? const Color(0xFF374151)
              : const Color(0xFFE2E8F0)),
    ),
    child: child,
  );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Widget   trailing;
  const _Row({required this.icon, required this.title,
      required this.subtitle, required this.trailing});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

class _GoldDrop<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _GoldDrop({required this.value, required this.items,
      required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        style: const TextStyle(color: _gold,
            fontWeight: FontWeight.w600, fontSize: 13),
        icon: const Icon(Icons.keyboard_arrow_down,
            color: _gold, size: 18),
        dropdownColor: isDark ? const Color(0xFF1F2937) : Colors.white,
      ),
    );
  }
}