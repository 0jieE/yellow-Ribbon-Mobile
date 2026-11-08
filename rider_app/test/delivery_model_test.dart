// Parsing tests for the rider delivery payload.
//
// Two things here are safety-critical and worth locking down: the amount the
// rider collects at the door, and `next_statuses`, which is the only thing
// deciding which action buttons appear.

import 'package:flutter_test/flutter_test.dart';

import 'package:rider_app/models/delivery_model.dart';
import 'package:rider_app/models/dashboard_model.dart';

/// A payload shaped like `DeliverySerializer`.
Map<String, dynamic> deliveryJson({
  String status = 'assigned',
  List<String> nextStatuses = const ['failed', 'picked_up'],
  String paymentType = 'cod',
  String paymentStatus = 'unpaid',
  String amountToCollect = '530.00',
  String orderStatus = 'ready',
  Object? proof,
}) {
  return {
    'id': 7,
    'status': status,
    'rider_earnings': '30.00',
    'proof_of_delivery': proof,
    'assigned_at': '2026-08-07T06:00:00Z',
    'picked_up_at': null,
    'delivered_at': null,
    'next_statuses': nextStatuses,
    // Explicitly dynamic: every value here is non-null, so inference would
    // otherwise produce a Map<String, Object> that tests cannot null out.
    'order': <String, dynamic>{
      'id': 12,
      'order_number': 'YR-0012',
      'status': orderStatus,
      'payment_type': paymentType,
      'payment_status': paymentStatus,
      'total': '530.00',
      'delivery_address': '123 Quezon Blvd',
      'delivery_latitude': '7.008300',
      'delivery_longitude': '125.089400',
      'delivery_notes': 'Blue gate',
      'eta_minutes': 15,
      'eta_at': '2026-08-07T06:20:00Z',
      'placed_at': '2026-08-07T06:00:00Z',
      'customer_name': 'Juan Dela Cruz',
      'customer_phone': '09123456789',
      'amount_to_collect': amountToCollect,
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
    },
  };
}

void main() {
  group('amount to collect', () {
    test('an unpaid COD order collects the full total', () {
      final delivery = Delivery.fromJson(deliveryJson());

      expect(delivery.order.amountToCollect, 530.00);
      expect(delivery.order.collectsCash, isTrue);
    });

    test('a paid GCash order collects nothing', () {
      final delivery = Delivery.fromJson(
        deliveryJson(
          paymentType: 'gcash',
          paymentStatus: 'paid',
          amountToCollect: '0.00',
        ),
      );

      expect(delivery.order.amountToCollect, 0);
      expect(delivery.order.collectsCash, isFalse);
    });
  });

  group('next_statuses drives the action buttons', () {
    test('an assigned delivery may be picked up or failed', () {
      final delivery = Delivery.fromJson(deliveryJson());

      expect(delivery.nextStatuses, ['failed', 'picked_up']);
    });

    test('a delivered delivery offers nothing further', () {
      final delivery = Delivery.fromJson(
        deliveryJson(status: 'delivered', nextStatuses: const []),
      );

      expect(delivery.nextStatuses, isEmpty);
      expect(delivery.isTerminal, isTrue);
      expect(delivery.isActive, isFalse);
    });

    test('a missing next_statuses parses as empty rather than throwing', () {
      final json = deliveryJson()..remove('next_statuses');

      expect(Delivery.fromJson(json).nextStatuses, isEmpty);
    });
  });

  group('pinger gating', () {
    test('assigned, picked_up and in_transit are active', () {
      for (final status in ['assigned', 'picked_up', 'in_transit']) {
        expect(
          Delivery.fromJson(deliveryJson(status: status)).isActive,
          isTrue,
          reason: status,
        );
      }
    });

    test('delivered and failed are not active', () {
      for (final status in ['delivered', 'failed']) {
        final delivery = Delivery.fromJson(deliveryJson(status: status));
        expect(delivery.isActive, isFalse, reason: status);
        expect(delivery.isTerminal, isTrue, reason: status);
      }
    });
  });

  group('proof of delivery', () {
    test('cannot be uploaded while merely assigned', () {
      expect(
        Delivery.fromJson(deliveryJson(status: 'assigned')).canUploadProof,
        isFalse,
      );
    });

    test('can be uploaded once picked up', () {
      expect(
        Delivery.fromJson(deliveryJson(status: 'picked_up')).canUploadProof,
        isTrue,
      );
    });

    test('a null photo is not treated as having proof', () {
      expect(Delivery.fromJson(deliveryJson(proof: null)).hasProof, isFalse);
      expect(
        Delivery.fromJson(
          deliveryJson(proof: 'http://x/media/proof.jpg'),
        ).hasProof,
        isTrue,
      );
    });
  });

  test('pickup readiness follows the order status, not the delivery', () {
    expect(
      Delivery.fromJson(deliveryJson(orderStatus: 'ready'))
          .order
          .isReadyForPickup,
      isTrue,
    );
    // The backend refuses picked_up unless the kitchen is done.
    expect(
      Delivery.fromJson(deliveryJson(orderStatus: 'preparing'))
          .order
          .isReadyForPickup,
      isFalse,
    );
  });

  test('order details and coordinates are parsed', () {
    final order = Delivery.fromJson(deliveryJson()).order;

    expect(order.orderNumber, 'YR-0012');
    expect(order.customerName, 'Juan Dela Cruz');
    expect(order.customerPhone, '09123456789');
    expect(order.deliveryNotes, 'Blue gate');
    expect(order.hasDestination, isTrue);
    expect(order.deliveryLatitude, closeTo(7.0083, 1e-9));
    expect(order.deliveryLongitude, closeTo(125.0894, 1e-9));
    expect(order.items.single.menuName, 'Pepperoni');
    expect(order.items.single.lineSubtotal, 500.00);
  });

  test('an order without coordinates degrades instead of throwing', () {
    final json = deliveryJson();
    (json['order'] as Map<String, dynamic>)['delivery_latitude'] = null;
    (json['order'] as Map<String, dynamic>)['delivery_longitude'] = null;

    final order = Delivery.fromJson(json).order;
    expect(order.hasDestination, isFalse);
    expect(order.deliveryAddress, '123 Quezon Blvd');
  });

  test('dashboard totals are parsed from the decimal strings', () {
    final dashboard = RiderDashboard.fromJson({
      'rider_id': 1,
      'name': 'Ana Cruz',
      'is_available': true,
      'assigned': 2,
      'completed': 11,
      'failed': 1,
      'earnings': {'total': '330.00', 'today': '60.00'},
      'today': {'completed': 2},
      'current_location': {
        'latitude': null,
        'longitude': null,
        'updated_at': null,
      },
    });

    expect(dashboard.name, 'Ana Cruz');
    expect(dashboard.isAvailable, isTrue);
    expect(dashboard.assigned, 2);
    expect(dashboard.completed, 11);
    expect(dashboard.failed, 1);
    expect(dashboard.earningsTotal, 330.00);
    expect(dashboard.earningsToday, 60.00);
    expect(dashboard.completedToday, 2);
  });
}
