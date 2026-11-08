// Parsing tests for the admin order payload.
//
// Two things here are worth locking down: the pagination envelope, which only
// this endpoint uses, and the gating that decides whether the Assign Rider
// button appears — offering it when the server would refuse is the main way
// this screen can mislead.

import 'package:flutter_test/flutter_test.dart';

import 'package:admin_app/models/admin_order_model.dart';
import 'package:admin_app/models/dashboard_model.dart';
import 'package:admin_app/models/order_flow.dart';
import 'package:admin_app/models/rider_model.dart';

Map<String, dynamic> orderJson({
  String status = 'pending',
  List<String> nextStatuses = const ['cancelled', 'confirmed'],
  Object? rider,
}) {
  return <String, dynamic>{
    'id': 12,
    'order_number': 'YR-0012',
    'status': status,
    'payment_type': 'cod',
    'payment_status': 'unpaid',
    'subtotal': '500.00',
    'delivery_fee': '30.00',
    'total': '530.00',
    'delivery_address': '123 Quezon Blvd',
    'delivery_latitude': '7.008300',
    'delivery_longitude': '125.089400',
    'delivery_notes': 'Blue gate',
    'eta_minutes': null,
    'eta_at': null,
    'placed_at': '2026-08-07T06:00:00Z',
    'confirmed_at': null,
    'delivered_at': null,
    'cancelled_at': null,
    'cancel_reason': '',
    'customer': 3,
    'customer_name': 'Juan Dela Cruz',
    'customer_phone': '09123456789',
    'next_statuses': nextStatuses,
    'rider': rider,
    'items': [
      {
        'id': 1,
        'menu': 3,
        'menu_name': 'Pepperoni',
        'quantity': 2,
        'unit_price': '250.00',
        'line_subtotal': '500.00',
      },
    ],
    'status_logs': [
      {
        'id': 1,
        'status': 'pending',
        'changed_by': 4,
        'changed_by_username': 'jen',
        'changed_at': '2026-08-07T06:00:00Z',
      },
    ],
  };
}

const _riderJson = {
  'delivery_id': 5,
  'rider_id': 2,
  'username': 'ana',
  'name': 'Ana Cruz',
  'phone': '09171234567',
  'delivery_status': 'assigned',
  'rider_earnings': '30.00',
};

void main() {
  group('pagination envelope', () {
    test('unwraps count / next / previous / results', () {
      final page = OrderPage.fromJson({
        'count': 40,
        'next': 'http://x/api/admin/orders/?page=2',
        'previous': null,
        'results': [orderJson()],
      });

      expect(page.count, 40);
      expect(page.hasMore, isTrue);
      expect(page.results, hasLength(1));
      expect(page.results.single.orderNumber, 'YR-0012');
    });

    test('the last page reports no more', () {
      final page = OrderPage.fromJson({
        'count': 1,
        'next': null,
        'previous': 'http://x/api/admin/orders/',
        'results': [orderJson()],
      });

      expect(page.hasMore, isFalse);
    });

    test('a bare list still parses, in case pagination is turned off', () {
      final page = OrderPage.fromJson([orderJson()]);

      expect(page.count, 1);
      expect(page.hasMore, isFalse);
      expect(page.results.single.orderNumber, 'YR-0012');
    });
  });

  group('assign rider gating', () {
    test('a pending order cannot be assigned until the store accepts it', () {
      final order = AdminOrder.fromJson(orderJson(status: 'pending'));

      expect(order.isAssigned, isFalse);
      expect(order.canAssignRider, isFalse);
    });

    test('an accepted order can be assigned from confirmed until ready', () {
      for (final status in ['confirmed', 'preparing', 'ready']) {
        expect(
          AdminOrder.fromJson(orderJson(status: status)).canAssignRider,
          isTrue,
          reason: status,
        );
      }
    });

    test('an order already out for delivery cannot be assigned', () {
      expect(
        AdminOrder.fromJson(orderJson(status: 'out_for_delivery')).canAssignRider,
        isFalse,
      );
    });

    test('the server answer wins when it sends one', () {
      final json = orderJson(status: 'confirmed')..['can_assign_rider'] = false;
      expect(AdminOrder.fromJson(json).canAssignRider, isFalse);
    });

    test('an unpaid pending_payment order cannot — the server refuses it', () {
      final order = AdminOrder.fromJson(orderJson(status: 'pending_payment'));

      expect(order.canAssignRider, isFalse);
    });

    test('a finished order cannot be assigned', () {
      for (final status in ['delivered', 'cancelled']) {
        expect(
          AdminOrder.fromJson(orderJson(status: status)).canAssignRider,
          isFalse,
          reason: status,
        );
      }
    });

    test('an already assigned order shows the rider instead of the button', () {
      final order = AdminOrder.fromJson(
        orderJson(status: 'confirmed', rider: _riderJson),
      );

      expect(order.isAssigned, isTrue);
      expect(order.canAssignRider, isFalse);
      expect(order.rider!.name, 'Ana Cruz');
      expect(order.rider!.riderId, 2);
      expect(order.rider!.deliveryStatus, 'assigned');
    });

    test('a null rider is not treated as assigned', () {
      expect(AdminOrder.fromJson(orderJson(rider: null)).rider, isNull);
      expect(AdminOrder.fromJson(orderJson(rider: 'nonsense')).rider, isNull);
    });
  });

  group('next_statuses drives the action buttons', () {
    test('pending offers confirm and cancel', () {
      final order = AdminOrder.fromJson(orderJson());

      expect(order.nextStatuses, ['cancelled', 'confirmed']);
    });

    test('a terminal order offers nothing further', () {
      final order = AdminOrder.fromJson(
        orderJson(status: 'delivered', nextStatuses: const []),
      );

      expect(order.nextStatuses, isEmpty);
      expect(order.isTerminal, isTrue);
    });

    test('a missing next_statuses parses as empty rather than throwing', () {
      final json = orderJson()..remove('next_statuses');

      expect(AdminOrder.fromJson(json).nextStatuses, isEmpty);
    });
  });

  test('items, totals and customer details are parsed', () {
    final order = AdminOrder.fromJson(orderJson());

    expect(order.customerName, 'Juan Dela Cruz');
    expect(order.customerPhone, '09123456789');
    expect(order.subtotal, 500.00);
    expect(order.deliveryFee, 30.00);
    expect(order.total, 530.00);
    expect(order.items.single.menuName, 'Pepperoni');
    expect(order.statusLogs.single.status, 'pending');
  });

  // The backend replaced `active_delivery` with `deliveries_held` plus
  // `current_delivery`, because a rider now collects a batch at the store and
  // works through it. Holding orders and being out on the road stopped being
  // the same thing, and the old model read every rider as free.
  Rider buildRider({
    bool isActive = true,
    bool isAvailable = true,
    int deliveriesHeld = 0,
    Object? currentDelivery,
  }) {
    return Rider.fromJson(<String, dynamic>{
      'id': 2,
      'username': 'ana',
      'email': 'ana@example.com',
      'name': 'Ana Cruz',
      'phone': '09171234567',
      'is_active': isActive,
      'is_available': isAvailable,
      'vehicle_type': 'Motorcycle',
      'plate_number': 'ABC 123',
      'deliveries_held': deliveriesHeld,
      'current_delivery': currentDelivery,
    });
  }

  const onTheRoad = {
    'delivery_id': 5,
    'order_number': 'YR-0012',
    'status': 'in_transit',
  };

  test('rider availability mirrors the server-side filter', () {
    expect(buildRider().isAssignable, isTrue);
    expect(buildRider(isAvailable: false).isAssignable, isFalse);
    expect(buildRider(isActive: false).isAssignable, isFalse);

    final driving = buildRider(deliveriesHeld: 2, currentDelivery: onTheRoad);
    expect(driving.isDriving, isTrue);
    expect(driving.isAssignable, isFalse);
    expect(driving.currentDelivery!.orderNumber, 'YR-0012');
  });

  test('a rider loading up at the store can still take another order', () {
    // The case the old model got wrong in both directions: it would have
    // called this rider free (the field it read was gone), and the previous
    // server rule would have called them busy. Both are wrong — they are
    // holding three and still assignable.
    final loading = buildRider(deliveriesHeld: 3);

    expect(loading.isHolding, isTrue);
    expect(loading.isDriving, isFalse);
    expect(loading.isAssignable, isTrue);
  });

  test('the workload line names the leg being driven', () {
    expect(buildRider().workloadLabel, isEmpty);
    expect(buildRider(deliveriesHeld: 1).workloadLabel, '1 order in hand');
    expect(buildRider(deliveriesHeld: 3).workloadLabel, '3 orders in hand');
    expect(
      buildRider(deliveriesHeld: 3, currentDelivery: onTheRoad).workloadLabel,
      '3 orders · on YR-0012',
    );
  });

  test('a missing current_delivery is absent, not an error', () {
    // Null is the normal shape for most of a shift, not a failure.
    expect(buildRider(currentDelivery: null).currentDelivery, isNull);
    expect(buildRider(currentDelivery: 'nonsense').currentDelivery, isNull);
  });

  test('dashboard counts and money are parsed', () {
    final dashboard = AdminDashboard.fromJson({
      'date': '2026-08-07',
      'today': {
        'orders_placed': 15,
        'orders_delivered': 6,
        'orders_cancelled': 1,
        'revenue': '8250.00',
        'food_sales': '8070.00',
        'delivery_fees': '180.00',
      },
      'status_counts': {
        'pending_payment': 0,
        'pending': 4,
        'confirmed': 2,
        'preparing': 1,
        'ready': 0,
        'out_for_delivery': 2,
        'delivered': 6,
        'cancelled': 1,
      },
      'active_orders': 9,
      'riders': {'total': 3, 'on_duty': 2, 'on_delivery': 1},
    });

    expect(dashboard.date, '2026-08-07');
    expect(dashboard.ordersPlaced, 15);
    expect(dashboard.ordersDelivered, 6);
    expect(dashboard.pending, 4);
    expect(dashboard.revenue, 8250.00);
    expect(dashboard.foodSales, 8070.00);
    expect(dashboard.deliveryFees, 180.00);
    expect(dashboard.activeOrders, 9);
    expect(dashboard.ridersOnDuty, 2);
    expect(dashboard.ridersOnDelivery, 1);
    expect(dashboard.countFor('out_for_delivery'), 2);
    // An unknown status reads as zero rather than throwing.
    expect(dashboard.countFor('nonsense'), 0);
  });

  group('change rider', () {
    test('allowed while the rider has not picked the order up', () {
      final order = AdminOrder.fromJson(
        orderJson(status: 'ready', rider: _riderJson),
      );
      expect(order.canChangeRider, isTrue);
    });

    test('refused once the rider has the food', () {
      final picked = Map<String, dynamic>.from(_riderJson)
        ..['delivery_status'] = 'picked_up';
      final order = AdminOrder.fromJson(
        orderJson(status: 'out_for_delivery', rider: picked),
      );
      expect(order.canChangeRider, isFalse);
    });

    test('nothing to change without a rider', () {
      expect(AdminOrder.fromJson(orderJson(status: 'ready')).canChangeRider, isFalse);
    });
  });

  group('rider-only steps', () {
    test('out for delivery and delivered are never offered to the store', () {
      final order = AdminOrder.fromJson(
        orderJson(
          status: 'ready',
          nextStatuses: const ['cancelled', 'out_for_delivery'],
        ),
      );
      expect(order.adminNextStatuses, ['cancelled']);

      final out = AdminOrder.fromJson(
        orderJson(
          status: 'out_for_delivery',
          nextStatuses: const ['cancelled', 'delivered'],
        ),
      );
      expect(out.adminNextStatuses, ['cancelled']);
    });

    test('the store steps are kept', () {
      final order = AdminOrder.fromJson(orderJson(status: 'pending'));
      expect(order.adminNextStatuses, ['cancelled', 'confirmed']);
    });
  });

  group('next step hint', () {
    test('a ready order without a rider asks for one', () {
      final hint = nextStepHint(AdminOrder.fromJson(orderJson(status: 'ready')));
      expect(hint, contains('Assign one'));
    });

    test('a ready order with a rider waits for the pickup', () {
      final hint = nextStepHint(
        AdminOrder.fromJson(orderJson(status: 'ready', rider: _riderJson)),
      );
      expect(hint, contains('Waiting for Ana Cruz to pick it up'));
    });

    test('a failed delivery points the store at cancelling', () {
      final failed = Map<String, dynamic>.from(_riderJson)
        ..['delivery_status'] = 'failed'
        ..['failure_reason'] = 'Customer not home';
      final order = AdminOrder.fromJson(
        orderJson(status: 'out_for_delivery', rider: failed),
      );
      expect(order.rider!.deliveryFailed, isTrue);
      expect(order.rider!.failureReason, 'Customer not home');
      expect(nextStepHint(order), contains('cancel the order'));
    });

    test('finished orders have no hint', () {
      for (final status in ['delivered', 'cancelled']) {
        expect(nextStepHint(AdminOrder.fromJson(orderJson(status: status))), isNull);
      }
    });
  });
}
