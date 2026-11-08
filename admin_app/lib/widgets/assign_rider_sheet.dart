import 'package:flutter/material.dart';

import '../models/rider_model.dart';
import '../services/api_client.dart';
import '../services/rider_admin_service.dart';
import '../theme.dart';
import 'section_card.dart';

/// Picks a rider for an order, populated from
/// `GET /api/admin/riders/available/` — on duty, active, and not already
/// driving a leg.
///
/// Note the rule is narrower than "has no work": riders batch several orders
/// at the store before setting off, so someone already holding two can take a
/// third. Only an `in_transit` rider has left and is excluded.
///
/// Returns the chosen `rider_id`, or null if dismissed. The caller does the
/// POST, so the failure message lands on the screen that asked.
Future<int?> showAssignRiderSheet(
  BuildContext context, {
  required String orderNumber,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AssignRiderSheet(orderNumber: orderNumber),
  );
}

class _AssignRiderSheet extends StatefulWidget {
  const _AssignRiderSheet({required this.orderNumber});

  final String orderNumber;

  @override
  State<_AssignRiderSheet> createState() => _AssignRiderSheetState();
}

class _AssignRiderSheetState extends State<_AssignRiderSheet> {
  final _riders = RiderAdminService();

  late Future<List<Rider>> _future;

  @override
  void initState() {
    super.initState();
    _future = _riders.fetchAvailable();
  }

  void _reload() {
    setState(() => _future = _riders.fetchAvailable());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                Expanded(
                  child: Text(
                    "Assign a rider to ${widget.orderNumber}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: kInk,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _reload,
                  tooltip: "Refresh",
                ),
              ],
            ),

            const SizedBox(height: 2),

            const Text(
              "On duty, and not already out on a delivery. A rider still "
              "loading up at the store can take another order.",
              style: TextStyle(fontSize: 12, color: kMuted),
            ),

            const SizedBox(height: 14),

            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: FutureBuilder<List<Rider>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return _message(
                      Icons.cloud_off,
                      snapshot.error is ApiException
                          ? (snapshot.error as ApiException).message
                          : "Could not load riders.",
                      showRetry: true,
                    );
                  }

                  final riders = snapshot.data ?? const <Rider>[];

                  if (riders.isEmpty) {
                    return _message(
                      Icons.no_accounts,
                      "No riders are free right now. A rider has to go on "
                      "duty in their own app, and anyone already out on a "
                      "delivery cannot take another until they finish it.",
                      showRetry: true,
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: riders.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final rider = riders[index];

                      final vehicle = [
                        if (rider.vehicleType.isNotEmpty) rider.vehicleType,
                        if (rider.plateNumber.isNotEmpty) rider.plateNumber,
                        if (rider.phone.isNotEmpty) rider.phone,
                      ].join(' · ');

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: kAmber,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.delivery_dining,
                            color: kInk,
                          ),
                        ),
                        title: Text(
                          rider.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                          ),
                        ),
                        subtitle: Text(
                          vehicle.isEmpty ? "@${rider.username}" : vehicle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: kMuted),
                        ),
                        // How much they are already carrying. Everyone in
                        // this list is assignable, but the admin should be
                        // able to spread the load rather than pile four bags
                        // on whoever happens to sort first.
                        trailing: rider.isHolding
                            ? TagPill(
                                label: "${rider.deliveriesHeld} in hand",
                                colour: const Color(0xFFB26A00),
                              )
                            : const TagPill(
                                label: "Free",
                                colour: Color(0xFF2E7D32),
                              ),
                        // `id` is the Rider profile id, which is what the
                        // assign endpoint wants — not the user id.
                        onTap: () => Navigator.pop(context, rider.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(IconData icon, String text, {bool showRetry = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          if (showRetry) ...[
            const SizedBox(height: 14),
            ElevatedButton(onPressed: _reload, child: const Text("Retry")),
          ],
        ],
      ),
    );
  }
}
