import 'package:flutter/material.dart';

import '../models/menu_item.dart';
import '../services/api_client.dart';
import '../services/menu_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import 'add_pizza_screen.dart';
import 'edit_pizza_screen.dart';

/// Menu CRUD against `/api/menu/`.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final _menu = MenuService();
  final _search = TextEditingController();

  List<MenuItem> _items = [];
  String? _error;
  bool _loading = true;

  /// Ids currently mid-request, so a row's switch can spin on its own.
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _menu.fetchAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// Client-side filter — the menu is small and unpaginated, so there is no
  /// point round-tripping for a search box.
  List<MenuItem> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items
        .where((item) =>
            item.name.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _toggleAvailability(MenuItem item, bool value) async {
    setState(() => _busy.add(item.id));

    try {
      final updated = await _menu.setAvailability(item.id, value);
      if (!mounted) return;
      setState(() {
        final index = _items.indexWhere((i) => i.id == item.id);
        if (index != -1) _items[index] = updated;
        _busy.remove(item.id);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(item.id));
      _snack(e.message);
    }
  }

  Future<void> _delete(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Delete ${item.name}?"),
        content: const Text(
          "If this item appears on past orders the server will refuse, so "
          "that old receipts do not change. Mark it unavailable instead.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _menu.delete(item.id);
      if (!mounted) return;
      setState(() => _items.removeWhere((i) => i.id == item.id));
      _snack("${item.name} deleted.");
    } on ApiException catch (e) {
      if (!mounted) return;
      // A 409 carries the "appears on existing orders" explanation, which is
      // worth a dialog rather than a snackbar.
      if (e.statusCode == 409) {
        _showBlocked(e.message);
      } else {
        _snack(e.message);
      }
    }
  }

  void _showBlocked(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.block, color: Colors.red, size: 32),
        title: const Text("Cannot delete"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = _items.where((i) => i.isAvailable).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Menu"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
            onPressed: _load,
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const AddPizzaScreen()),
          );
          if (created == true) await _load();
        },
        icon: const Icon(Icons.add),
        label: const Text(
          "Add item",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: "Search the menu",
                prefixIcon: const Icon(Icons.search, color: kMuted),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),

          if (!_loading && _error == null && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
              child: Row(
                children: [
                  Text(
                    "${_items.length} item${_items.length == 1 ? '' : 's'}",
                    style: const TextStyle(fontSize: 12, color: kMuted),
                  ),
                  const Spacer(),
                  // The count that matters operationally: how much of the
                  // menu a customer can actually order right now.
                  Text(
                    "$available visible to customers",
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: "Could not load the menu",
        message: _error!,
        onRetry: _load,
      );
    }

    final visible = _visible;

    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.local_pizza_outlined,
        title: _items.isEmpty ? "The menu is empty" : "No matches",
        message: _items.isEmpty
            ? "Nothing is on sale yet. Add your first item with the button "
                "below."
            : "Nothing matches \"${_search.text.trim()}\".",
        onRetry: _load,
      );
    }

    return RefreshIndicator(
      color: kAmber,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final item = visible[index];
          final isBusy = _busy.contains(item.id);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: SizedBox(
                          width: 76,
                          height: 76,
                          child: item.photo == null
                              ? Container(
                                  color: kAmber.withValues(alpha: 0.2),
                                  child: const Icon(
                                    Icons.local_pizza,
                                    color: kInk,
                                    size: 30,
                                  ),
                                )
                              : Image.network(
                                  item.photo!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    color: kCanvas,
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                      color: kMuted,
                                    ),
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(width: 13),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15.5,
                                color: kInk,
                              ),
                            ),
                            if (item.description.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                item.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: kMuted,
                                  height: 1.35,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              "₱${item.price.toStringAsFixed(2)}",
                              style: const TextStyle(
                                color: kInk,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const Divider(height: 20),

                  Row(
                    children: [
                      // Availability reads as a state, not a setting label —
                      // it is the thing the admin scans the list for.
                      Icon(
                        item.isAvailable
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 16,
                        color: item.isAvailable
                            ? const Color(0xFF2E7D32)
                            : kMuted,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          item.isAvailable ? "On sale" : "Hidden",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: item.isAvailable
                                ? const Color(0xFF2E7D32)
                                : kMuted,
                          ),
                        ),
                      ),

                      if (isBusy)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        Switch(
                          value: item.isAvailable,
                          activeThumbColor: Colors.white,
                          activeTrackColor: const Color(0xFF2E7D32),
                          onChanged: (value) =>
                              _toggleAvailability(item, value),
                        ),

                      IconButton(
                        tooltip: "Edit",
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        color: kInk,
                        onPressed: () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditPizzaScreen(item: item),
                            ),
                          );
                          if (changed == true) await _load();
                        },
                      ),
                      IconButton(
                        tooltip: "Delete",
                        icon: const Icon(Icons.delete_outline, size: 20),
                        color: const Color(0xFFC62828),
                        onPressed: () => _delete(item),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
