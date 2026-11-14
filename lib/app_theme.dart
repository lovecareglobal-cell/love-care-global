import 'package:flutter/material.dart';

// DARK PINK THEME - use on ALL pages. Not bright pink.
// In main.dart, wrap your app like this:
//   return MaterialApp(theme: AppTheme.darkPink, home: ...);
// Every page then gets dark pink AppBar + buttons automatically.
// If a page sets its own AppBar colour, change it to AppTheme.darkPink (0xFF880E4F).
class AppTheme {
  static const Color darkPink = Color(0xFF880E4F); // headers, main buttons
  static const Color pink = Color(0xFFAD1457); // secondary buttons / accents
  static const Color pinkSoft = Color(0xFFFCE4EC); // light pink button backgrounds
  static const Color pinkBorder = Color(0xFFF8BBD0); // soft pink borders

  static ThemeData get darkPinkTheme => ThemeData(
        primaryColor: darkPink,
        colorScheme: ColorScheme.fromSeed(seedColor: darkPink, primary: darkPink, secondary: pink),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkPink,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: darkPink,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: darkPink),
        ),
        inputDecorationTheme: InputDecorationTheme(
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: darkPink),
            borderRadius: BorderRadius.circular(8),
          ),
          labelStyle: const TextStyle(color: darkPink),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: darkPink,
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: darkPink,
          unselectedItemColor: Colors.grey,
        ),
      );

  // Backwards-compatible alias
  static ThemeData get darkPink => darkPinkTheme;
}
