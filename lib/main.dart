import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/database_service.dart';
import 'services/queue_service.dart';
import 'services/settings_service.dart';
import 'views/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  await DatabaseService.init();

  final settings = SettingsService();
  await settings.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(
          create: (_) => QueueService()..loadFromDatabase(),
        ),
      ],
      child: const AeroApp(),
    ),
  );
}

class AeroApp extends StatelessWidget {
  const AeroApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aero QMS',
      locale: settings.locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: settings.themeMode,
      theme:     _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData(brightness: brightness).textTheme,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor:  const Color(0xFFD4AF37),
        primary:    const Color(0xFFD4AF37),
        brightness: brightness,
        surface:    isDark ? const Color(0xFF0C0A09) : const Color(0xFFF8FAFC),
        onSurface:  isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0C0A09),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? const Color(0xFF1F2937) : const Color(0xFFF8FAFC),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF1C1917),
          fontWeight: FontWeight.bold,
          fontSize: 20,
          letterSpacing: 1.5,
          fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        ),
        iconTheme: IconThemeData(
            color: isDark ? Colors.white : const Color(0xFF1C1917)),
      ),
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0C0A09) : const Color(0xFFF8FAFC),
    );
  }
}