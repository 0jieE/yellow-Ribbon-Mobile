import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'customer_home.dart';
import 'login.dart';

class HomeRouter extends StatelessWidget {
  const HomeRouter({super.key});

  Future<String?> getRole(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .get();

    if (!doc.exists) return null;
    return doc.data()?["role"];
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 🔥 WAIT STATE (important fix)
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ❌ NOT LOGGED IN
        if (!snapshot.hasData || snapshot.data == null) {
          return const LoginPage();
        }

        final user = snapshot.data!;

        return FutureBuilder<String?>(
          future: getRole(user.uid),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final role = roleSnap.data;

            if (role == "customer") {
              return const CustomerHome();
            }

            return const Scaffold(
              body: Center(
                child: Text("Role not assigned"),
              ),
            );
          },
        );
      },
    );
  }
}