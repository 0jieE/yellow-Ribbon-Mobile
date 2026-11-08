import 'package:flutter/material.dart';

/// The palette shared by all three apps.
///
/// Kept in one file here rather than repeated per screen, because the admin
/// app has a dozen of them and the amber had already drifted between
/// `Colors.amber` and the exact brand value in different places.
const kAmber = Color(0xFFFFC107);
const kInk = Color(0xFF1F1F1F);
const kCanvas = Color(0xFFF6F6F6);

/// Muted text — captions, labels, secondary lines.
const kMuted = Color(0xFF757575);

/// Money. One colour everywhere, so a total never looks like a warning.
const kMoney = Color(0xFF1F1F1F);

class AdminTheme {
  const AdminTheme._();

  static ThemeData get data => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kCanvas,

        colorScheme: ColorScheme.fromSeed(
          seedColor: kAmber,
          primary: kAmber,
        ),

        // Left-aligned and bold: this is a console, and a centred title
        // wastes the space where the screen's identity should sit.
        appBarTheme: const AppBarTheme(
          backgroundColor: kAmber,
          foregroundColor: kInk,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: kInk,
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),

        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kAmber,
            foregroundColor: kInk,
            elevation: 0,
            // Height only. A width floor of `double.infinity` breaks any
            // button that shares a Row with another.
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14.5,
            ),
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kInk,
            minimumSize: const Size(0, 48),
            side: const BorderSide(color: Color(0xFFDADADA)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),

        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kAmber,
          foregroundColor: kInk,
          elevation: 3,
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: kMuted, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kAmber, width: 1.6),
          ),
        ),

        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titleTextStyle: const TextStyle(
            color: kInk,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
          contentTextStyle: const TextStyle(color: kInk, fontSize: 14),
        ),

        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
        ),

        dividerTheme: const DividerThemeData(
          color: Color(0xFFEDEDED),
          thickness: 1,
        ),

        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: kInk,
          contentTextStyle: TextStyle(color: Colors.white, fontSize: 13.5),
        ),
      );
}
