// Widget tests for the login screen.
//
// The app shell can no longer be pumped directly: RiderApp opens on
// SessionGate, which reads the JWT out of the platform keystore, and
// flutter_secure_storage has no implementation under `flutter test`. The
// login screen is the reachable surface without mocking that channel, and it
// is where the input validation lives.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rider_app/screens/login_screen.dart';

void main() {
  testWidgets('the login form asks for a username and password',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Yellow Ribbon Rider'), findsOneWidget);
    // Django keeps the default USERNAME_FIELD, so this must not say "Email".
    expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Log in'), findsOneWidget);
  });

  testWidgets('submitting an empty form complains without calling the API',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
    await tester.pump();

    expect(find.text('Enter your username and password.'), findsOneWidget);
  });

  testWidgets('the password is obscured and can be revealed',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    TextField passwordField() => tester.widget<TextField>(
          find.widgetWithText(TextField, 'Password'),
        );

    expect(passwordField().obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();

    expect(passwordField().obscureText, isFalse);
  });
}
