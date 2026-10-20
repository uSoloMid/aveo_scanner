import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const Color seed = Color(0xFFFFA000);
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: const Color(0xFF17191C),
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF101214),
    cardTheme: const CardThemeData(color: Color(0xFF202428), elevation: 2),
    navigationBarTheme: const NavigationBarThemeData(height: 72),
    textTheme: const TextTheme(
      displayMedium: TextStyle(fontSize: 38, fontWeight: FontWeight.w700),
      headlineSmall: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
    ),
  );
}
