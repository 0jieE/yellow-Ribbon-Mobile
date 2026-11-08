import 'package:flutter/material.dart';

import 'customer/menu_screen.dart';
import 'customer/orders_screen.dart';
import 'customer/profile_screen.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// The signed-in shell: Menu, Orders, Profile.
///
/// Each tab owns its own Scaffold and app bar, so this only supplies the
/// navigation bar. Orders and Profile were previously unreachable.
class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key, this.initialTab = 0});

  /// Which tab to open on. Used when a notification or the payment deep link
  /// lands the customer here rather than on the menu.
  final int initialTab;

  static const int menuTab = 0;
  static const int ordersTab = 1;
  static const int profileTab = 2;

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  late int _selectedIndex = widget.initialTab;

  /// Rebuilding a tab on every switch is deliberate: the orders list and the
  /// menu should both be current when the customer returns to them, and both
  /// are cheap single fetches.
  Widget get _body {
    switch (_selectedIndex) {
      case CustomerHome.ordersTab:
        return const OrdersScreen();
      case CustomerHome.profileTab:
        return const ProfileScreen();
      default:
        return const MenuScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      body: _body,
      bottomNavigationBar: NavigationBarTheme(
        // Dark bar with an amber active item, matching the menu cards. No
        // pill behind the selected icon — the colour change alone marks it,
        // which keeps the bar clean against the dark background.
        data: NavigationBarThemeData(
          backgroundColor: _ink,
          indicatorColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 25,
              color: states.contains(WidgetState.selected)
                  ? _amber
                  : Colors.white60,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: states.contains(WidgetState.selected)
                  ? _amber
                  : Colors.white60,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          height: 70,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.local_pizza_outlined),
              selectedIcon: Icon(Icons.local_pizza),
              label: 'Menu',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
