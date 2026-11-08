import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/assigned_orders_screen.dart';
import 'screens/delivery_map_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';
import 'services/api_client.dart';
import 'services/delivery_service.dart';
import 'services/location_pinger.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

class RiderHome extends StatefulWidget {
  const RiderHome({super.key});

  static const int dashboardTab = 0;
  static const int ordersTab = 1;

  /// Sits next to Orders: the map is what a rider opens straight after
  /// collecting from the counter, to decide which bag goes first.
  static const int mapTab = 2;

  static const int historyTab = 3;
  static const int profileTab = 4;

  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  int _selectedIndex = RiderHome.dashboardTab;

  @override
  void initState() {
    super.initState();
    // Start tracking as soon as the app opens with work in hand, rather than
    // waiting for the rider to visit the Orders tab.
    _syncPinger();
  }

  @override
  void dispose() {
    // Leaving the signed-in shell means no more position reports.
    LocationPinger.instance.stop();
    super.dispose();
  }

  Future<void> _syncPinger() async {
    try {
      final deliveries = await DeliveryService().fetchActive();
      LocationPinger.instance.syncWith(deliveries);
    } on ApiException {
      // The Orders tab will try again and show the error properly.
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  /// Rebuilt on every switch so each tab refetches — a rider's workload
  /// changes while they are looking at another screen.
  Widget get _body {
    switch (_selectedIndex) {
      case RiderHome.ordersTab:
        return const AssignedOrdersScreen();
      case RiderHome.mapTab:
        return const DeliveryMapScreen();
      case RiderHome.historyTab:
        return const HistoryScreen();
      case RiderHome.profileTab:
        return const ProfileScreen();
      default:
        // The dashboard's counters jump straight to the list behind them.
        return DashboardScreen(onOpenTab: _onItemTapped);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _body,
      bottomNavigationBar: NavigationBarTheme(
        // Dark bar with an amber active item, matching customer_app. No pill
        // behind the selected icon — the colour change alone marks it, which
        // keeps the bar clean against the dark background.
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
          onDestinationSelected: _onItemTapped,
          height: 70,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.delivery_dining_outlined),
              selectedIcon: Icon(Icons.delivery_dining),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.history),
              selectedIcon: Icon(Icons.history),
              label: 'History',
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
