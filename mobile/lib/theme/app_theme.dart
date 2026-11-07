import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ThemePreset {
  midnightEmber,   // Luxury Dark Steakhouse & Lounge (Charcoal & Ember)
  modernBistro,    // Fresh Farm-to-Table Cafe (Clean Ivory & Sage Emerald)
  cyberKitchen,    // High-Contrast Line KDS (Pitch Black & Electric Cyan)
  tuscanWarm,      // Artisanal Italian Trattoria (Rich Espresso & Tuscan Gold)
}

class ThemePalette {
  final String name;
  final String description;
  final IconData icon;
  final bool isDark;
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHighlight;
  final Color border;
  final Color primary;
  final Color primaryLight;
  final Color primaryGlow;
  final Color statusGreen;
  final Color statusYellow;
  final Color statusRed;
  final Color statusBlue;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  const ThemePalette({
    required this.name,
    required this.description,
    required this.icon,
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHighlight,
    required this.border,
    required this.primary,
    required this.primaryLight,
    required this.primaryGlow,
    required this.statusGreen,
    required this.statusYellow,
    required this.statusRed,
    required this.statusBlue,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });
}

class AppTheme {
  static ThemePreset activePreset = ThemePreset.midnightEmber;

  static final Map<ThemePreset, ThemePalette> palettes = {
    ThemePreset.midnightEmber: const ThemePalette(
      name: 'Midnight Ember',
      description: 'Upscale lounge & steakhouse (Dark)',
      icon: Icons.nightlife_rounded,
      isDark: true,
      background: Color(0xFF0F1115),
      surface: Color(0xFF171A20),
      surfaceElevated: Color(0xFF21252D),
      surfaceHighlight: Color(0xFF2C313C),
      border: Color(0xFF2E3440),
      primary: Color(0xFFFF6B35),
      primaryLight: Color(0xFFFF8E63),
      primaryGlow: Color(0x40FF6B35),
      statusGreen: Color(0xFF10B981),
      statusYellow: Color(0xFFF59E0B),
      statusRed: Color(0xFFEF4444),
      statusBlue: Color(0xFF3B82F6),
      textPrimary: Color(0xFFF3F4F6),
      textSecondary: Color(0xFF9CA3AF),
      textMuted: Color(0xFF6B7280),
    ),
    ThemePreset.modernBistro: const ThemePalette(
      name: 'Modern Bistro',
      description: 'Clean farm-to-table bakery & cafe (Light)',
      icon: Icons.wb_sunny_rounded,
      isDark: false,
      background: Color(0xFFF8FAFC),
      surface: Color(0xFFFFFFFF),
      surfaceElevated: Color(0xFFF1F5F9),
      surfaceHighlight: Color(0xFFE2E8F0),
      border: Color(0xFFE2E8F0),
      primary: Color(0xFF059669),
      primaryLight: Color(0xFF10B981),
      primaryGlow: Color(0x30059669),
      statusGreen: Color(0xFF10B981),
      statusYellow: Color(0xFFD97706),
      statusRed: Color(0xFFDC2626),
      statusBlue: Color(0xFF2563EB),
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF475569),
      textMuted: Color(0xFF94A3B8),
    ),
    ThemePreset.cyberKitchen: const ThemePalette(
      name: 'Cyber Kitchen',
      description: 'High-contrast line KDS display (OLED)',
      icon: Icons.soup_kitchen_rounded,
      isDark: true,
      background: Color(0xFF050505),
      surface: Color(0xFF0D1117),
      surfaceElevated: Color(0xFF161B22),
      surfaceHighlight: Color(0xFF21262D),
      border: Color(0xFF30363D),
      primary: Color(0xFF00E5FF),
      primaryLight: Color(0xFF5DF2FF),
      primaryGlow: Color(0x4500E5FF),
      statusGreen: Color(0xFF00FF88),
      statusYellow: Color(0xFFFFCC00),
      statusRed: Color(0xFFFF3366),
      statusBlue: Color(0xFF00B0FF),
      textPrimary: Color(0xFFFFFFFF),
      textSecondary: Color(0xFFA5D6A7),
      textMuted: Color(0xFF7E8792),
    ),
    ThemePreset.tuscanWarm: const ThemePalette(
      name: 'Tuscan Trattoria',
      description: 'Artisanal Italian eatery (Warm)',
      icon: Icons.local_dining_rounded,
      isDark: true,
      background: Color(0xFF181310),
      surface: Color(0xFF241C18),
      surfaceElevated: Color(0xFF322822),
      surfaceHighlight: Color(0xFF42352E),
      border: Color(0xFF483A32),
      primary: Color(0xFFE5A93C),
      primaryLight: Color(0xFFF1C167),
      primaryGlow: Color(0x40E5A93C),
      statusGreen: Color(0xFF48BB78),
      statusYellow: Color(0xFFED8936),
      statusRed: Color(0xFFE53E3E),
      statusBlue: Color(0xFF4299E1),
      textPrimary: Color(0xFFFAF5ED),
      textSecondary: Color(0xFFC7B8A8),
      textMuted: Color(0xFF8F8073),
    ),
  };

  static ThemePalette get palette => palettes[activePreset] ?? palettes[ThemePreset.midnightEmber]!;

  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get surfaceElevated => palette.surfaceElevated;
  static Color get surfaceHighlight => palette.surfaceHighlight;
  static Color get border => palette.border;
  static Color get primary => palette.primary;
  static Color get primaryLight => palette.primaryLight;
  static Color get primaryGlow => palette.primaryGlow;
  static Color get statusGreen => palette.statusGreen;
  static Color get statusYellow => palette.statusYellow;
  static Color get statusRed => palette.statusRed;
  static Color get statusBlue => palette.statusBlue;
  static Color get textPrimary => palette.textPrimary;
  static Color get textSecondary => palette.textSecondary;
  static Color get textMuted => palette.textMuted;

  static void setPreset(ThemePreset preset) {
    activePreset = preset;
  }

  static ThemeData getThemeData(ThemePreset preset) {
    final p = palettes[preset]!;
    final base = p.isDark ? ThemeData.dark() : ThemeData.light();

    return ThemeData(
      useMaterial3: true,
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: p.background,
      colorScheme: ColorScheme(
        brightness: p.isDark ? Brightness.dark : Brightness.light,
        primary: p.primary,
        onPrimary: p.isDark ? Colors.black : Colors.white,
        secondary: p.primaryLight,
        onSecondary: Colors.white,
        error: p.statusRed,
        onError: Colors.white,
        surface: p.surface,
        onSurface: p.textPrimary,
        surfaceContainerHighest: p.surfaceElevated,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      cardTheme: CardTheme(
        color: p.surface,
        elevation: p.isDark ? 0 : 2,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.border, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: p.textPrimary),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: p.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border, width: 1),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primary,
        unselectedItemColor: p.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.primary, width: 2),
        ),
        labelStyle: TextStyle(color: p.textSecondary),
        hintStyle: TextStyle(color: p.textMuted),
      ),
    );
  }

  static ThemeData get darkTheme => getThemeData(activePreset);
  static ThemeData get themeData => getThemeData(activePreset);

  static void showThemeSheet(BuildContext context, {required Function(ThemePreset) onThemeChanged}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final p = palette;
        return Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: p.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: p.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.palette_rounded, color: p.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Atmosphere & Theme',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: p.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Customize ServeSync for your venue lighting or kitchen workflow.',
                style: TextStyle(fontSize: 13, color: p.textSecondary),
              ),
              const SizedBox(height: 20),
              ...palettes.entries.map((entry) {
                final preset = entry.key;
                final pal = entry.value;
                final isSelected = activePreset == preset;

                return GestureDetector(
                  onTap: () {
                    onThemeChanged(preset);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isSelected ? pal.primary.withOpacity(0.12) : pal.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? pal.primary : pal.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: pal.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: pal.border),
                          ),
                          child: Icon(pal.icon, color: pal.primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pal.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: p.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                pal.description,
                                style: TextStyle(fontSize: 12, color: p.textMuted),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded, color: pal.primary, size: 22)
                        else
                          Row(
                            children: [
                              Container(width: 12, height: 12, decoration: BoxDecoration(color: pal.primary, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Container(width: 12, height: 12, decoration: BoxDecoration(color: pal.background, shape: BoxShape.circle, border: Border.all(color: Colors.grey))),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
