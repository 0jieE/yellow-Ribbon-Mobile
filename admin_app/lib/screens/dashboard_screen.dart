import 'package:flutter/material.dart';
import 'orders_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Widget dashboardCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 8,
            offset: const Offset(2, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color.withOpacity(.15),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget menuButton(
      BuildContext context,
      IconData icon,
      String title,
      Color color,
      ) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
  if (title == "Orders") {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OrdersScreen(),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$title screen coming soon"),
      ),
    );
  }
},
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Icon(icon, color: color, size: 38),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xfff5f5f5),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.amber,
        title: const Text(
          "Yellow Ribbon Admin",
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            const Text(
              "Dashboard",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.1,
              children: [

                dashboardCard(
                  icon: Icons.receipt_long,
                  title: "Orders",
                  value: "15",
                  color: Colors.orange,
                ),

                dashboardCard(
                  icon: Icons.pending_actions,
                  title: "Pending",
                  value: "4",
                  color: Colors.red,
                ),

                dashboardCard(
                  icon: Icons.delivery_dining,
                  title: "Deliveries",
                  value: "6",
                  color: Colors.blue,
                ),

                dashboardCard(
                  icon: Icons.attach_money,
                  title: "Revenue",
                  value: "₱8,250",
                  color: Colors.green,
                ),

              ],
            ),

            const SizedBox(height: 30),

            const Text(
              "Management",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.15,
              children: [

                menuButton(
                  context,
                  Icons.shopping_bag,
                  "Orders",
                  Colors.orange,
                ),

                menuButton(
                  context,
                  Icons.local_pizza,
                  "Menu",
                  Colors.red,
                ),

                menuButton(
                  context,
                  Icons.delivery_dining,
                  "Riders",
                  Colors.blue,
                ),

                menuButton(
                  context,
                  Icons.bar_chart,
                  "Reports",
                  Colors.green,
                ),

              ],
            ),
          ],
        ),
      ),
    );
  }
}