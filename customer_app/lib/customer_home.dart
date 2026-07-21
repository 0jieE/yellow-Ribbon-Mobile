import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'customer/menu_screen.dart';

class CustomerHome extends StatelessWidget {
  const CustomerHome({super.key});

  Future<bool> confirmExit(BuildContext context) async {
    return await showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: const Text(
                "Logout",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: const Text(
                "Do you want to logout and return to login screen?",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    Navigator.pop(context, true);
                  },
                  child: const Text("Logout"),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    const primaryYellow = Color(0xFFFFC107);

    return WillPopScope(
      onWillPop: () async {
        return await confirmExit(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F6F6),

        // 🟡 YELLOW APPBAR
        appBar: AppBar(
          backgroundColor: primaryYellow,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            "Yellow Ribbon Pizza",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                final shouldLogout = await confirmExit(context);

                if (shouldLogout) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    "/",
                    (route) => false,
                  );
                }
              },
            )
          ],
        ),

        // BODY
        body: const MenuScreen(),
      ),
    );
  }
}