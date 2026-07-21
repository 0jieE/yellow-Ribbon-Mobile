import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Rider Profile"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.amber,
              child: Icon(
                Icons.person,
                size: 60,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Juan Rider",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text("rider@email.com"),
            const SizedBox(height: 30),
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone),
                title: const Text("09123456789"),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.motorcycle),
                title: const Text("Motorcycle Rider"),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.logout),
                label: const Text("Logout"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}