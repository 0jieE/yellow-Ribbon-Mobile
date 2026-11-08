import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // SimpleJWT authenticates on username, not email address.
  final username = TextEditingController();
  final password = TextEditingController();

  final _auth = AuthService();

  bool isLoading = false;
  bool obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => _error = "Enter your username and password.");
      return;
    }

    setState(() {
      isLoading = true;
      _error = null;
    });

    try {
      final user = await _auth.login(
        username: username.text.trim(),
        password: password.text,
      );

      if (!mounted) return;
      setState(() => isLoading = false);

      // Now that there is a JWT, the device can register for pushes. Not
      // awaited: a slow or refused permission prompt should not hold up the
      // login it followed.
      unawaited(PushService.instance.registerToken());

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Signed in as ${user.displayName}")),
      );
    } on ApiException catch (e) {
      // NotAnAdminException lands here too — its message already explains
      // that the account belongs in a different app.
      if (!mounted) return;
      setState(() {
        isLoading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Ink behind the card, so the sign-in screen sets the tone the rest of
      // the app follows rather than looking like a stray form.
      backgroundColor: kInk,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kAmber,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings,
                      size: 38,
                      color: kInk,
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    "Yellow Ribbon",
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: kInk,
                    ),
                  ),
                  const Text(
                    "Store administration",
                    style: TextStyle(fontSize: 12.5, color: kMuted),
                  ),

                  const SizedBox(height: 24),

                  TextField(
                    controller: username,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: "Username",
                      prefixIcon: Icon(Icons.person_outline, color: kMuted),
                      fillColor: kCanvas,
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: password,
                    obscureText: obscurePassword,
                    onSubmitted: (_) => isLoading ? null : login(),
                    decoration: InputDecoration(
                      hintText: "Password",
                      prefixIcon: const Icon(Icons.lock_outline, color: kMuted),
                      fillColor: kCanvas,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: kMuted,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => obscurePassword = !obscurePassword,
                        ),
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC62828).withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 17,
                            color: Color(0xFFC62828),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFB71C1C),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: isLoading ? null : login,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kInk,
                            ),
                          )
                        : const Text("Log in"),
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    "Admin accounts are created with createsuperuser.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: kMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
