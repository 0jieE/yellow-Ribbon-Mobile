import 'dart:async';

import 'package:flutter/material.dart';

import '../rider_home.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/push_service.dart';

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

      // Now that there is a JWT, the handset can register for pushes. Not
      // awaited: a slow or refused permission prompt should not hold up the
      // login it followed.
      unawaited(PushService.instance.registerToken());

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RiderHome()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Welcome, ${user.displayName}")),
      );
    } on ApiException catch (e) {
      // NotARiderException lands here too — its message already explains
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
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.amber,
                    child: Icon(
                      Icons.delivery_dining,
                      size: 40,
                      color: Colors.black,
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    "Yellow Ribbon Rider",
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 24),

                  TextField(
                    controller: username,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: "Username",
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: password,
                    obscureText: obscurePassword,
                    onSubmitted: (_) => isLoading ? null : login(),
                    decoration: InputDecoration(
                      labelText: "Password",
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
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
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : login,
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text("Log in"),
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    "Rider accounts are created by the store admin.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
