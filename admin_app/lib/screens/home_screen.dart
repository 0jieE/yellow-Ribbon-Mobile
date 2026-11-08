import 'package:flutter/material.dart';

import '../theme.dart';
import 'dashboard_screen.dart';
import 'menu_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'riders_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const int dashboardTab = 0;
  static const int ordersTab = 1;
  static const int menuTab = 2;
  static const int ridersTab = 3;
  static const int profileTab = 4;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = HomeScreen.dashboardTab;

  /// Status the Orders tab opens on, set by the dashboard's queue rows.
  /// Cleared whenever the bar itself is tapped, because choosing "Orders"
  /// from the bar means all of them.
  String? _ordersFilter;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == HomeScreen.ordersTab) _ordersFilter = null;
    });
  }

  void _openOrders(String? status) {
    setState(() {
      _selectedIndex = HomeScreen.ordersTab;
      _ordersFilter = status;
    });
  }

  /// Rebuilt on every switch so each tab refetches. The queue moves while the
  /// admin is looking at another screen, and a stale count is worse than a
  /// half-second spinner.
  Widget get _body {
    switch (_selectedIndex) {
      case HomeScreen.ordersTab:
        // Keyed on the filter so arriving from a different queue row builds a
        // fresh state rather than reusing the previous one's list.
        return OrdersScreen(
          key: ValueKey(_ordersFilter),
          initialStatus: _ordersFilter,
        );
      case HomeScreen.menuTab:
        return const MenuScreen();
      case HomeScreen.ridersTab:
        return const RidersScreen();
      case HomeScreen.profileTab:
        return const ProfileScreen();
      default:
        // The dashboard's tiles jump straight to the tab behind them, and its
        // queue rows carry the status they were counting.
        return DashboardScreen(
          onOpenTab: _onItemTapped,
          onOpenOrders: _openOrders,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _body,
      bottomNavigationBar: NavigationBarTheme(
        // Dark bar with an amber active item, matching customer_app and
        // rider_app. No pill behind the selected icon — the colour change
        // alone marks it, which keeps the bar clean against the dark.
        data: NavigationBarThemeData(
          backgroundColor: kInk,
          indicatorColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 25,
              color: states.contains(WidgetState.selected)
                  ? kAmber
                  : Colors.white60,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11.5,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: states.contains(WidgetState.selected)
                  ? kAmber
                  : Colors.white60,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onItemTapped,
          height: 70,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: "Dashboard",
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: "Orders",
            ),
            NavigationDestination(
              icon: Icon(Icons.local_pizza_outlined),
              selectedIcon: Icon(Icons.local_pizza),
              label: "Menu",
            ),
            // Promoted out of the dashboard's tile grid: managing riders is
            // day-to-day work, not something to go hunting for.
            NavigationDestination(
              icon: Icon(Icons.delivery_dining_outlined),
              selectedIcon: Icon(Icons.delivery_dining),
              label: "Riders",
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: "Profile",
            ),
          ],
        ),
      ),
    );
  }
}
