// Parsing tests for the order detail payload.
//
// The tracking map depends on `rider_location`, which the backend returns as
// null before a rider is assigned and again once the delivery is finished.
// These lock in that the model degrades to null rather than throwing, so the
// detail screen can fall back to a message instead of crashing.

import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/customer/order_status.dart';
import 'package:customer_app/models/order_model.dart';

/// A minimal detail payload shaped like `OrderSerializer`.
Map<String, dynamic> orderJson({
  String status = 'out_for_delivery',
  Object? riderLocation,
  bool canCancel = false,
  List<Map<String, dynamic>>? statusLogs,
}) {
  return {
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
    'eta_minutes': 15,
    'eta_at': '2026-08-07T06:20:00Z',
    'placed_at': '2026-08-07T06:00:00Z',
    'delivered_at': null,
    'cancelled_at': null,
    'cancel_reason': '',
    'can_cancel': canCancel,
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
    'status_logs': statusLogs ??
        [
          {
            'id': 1,
            'status': 'pending',
            'changed_by': 4,
            'changed_by_username': 'jen',
            'changed_at': '2026-08-07T06:00:00Z',
          },
          {
            'id': 2,
            'status': 'confirmed',
            'changed_by': 1,
            'changed_by_username': 'admin',
            'changed_at': '2026-08-07T06:05:00Z',
          },
        ],
    'rider_location': riderLocation,
  };
}

void main() {
  group('rider_location', () {
    test('is null before assignment and after delivery', () {
      final order = AppOrder.fromJson(orderJson(riderLocation: null));

      expect(order.riderLocation, isNull);
      // The destination is still known, so the screen can explain itself.
      expect(order.hasDestination, isTrue);
    });

    test('parses the decimal strings the serializer sends', () {
      final order = AppOrder.fromJson(
        orderJson(
          riderLocation: {
            'latitude': '7.010000',
            'longitude': '125.090000',
            'updated_at': '2026-08-07T06:10:00Z',
            'delivery_status': 'in_transit',
            'rider_name': 'Ana Cruz',
            'vehicle_type': 'motorcycle',
          },
        ),
      );

      final rider = order.riderLocation;
      expect(rider, isNotNull);
      expect(rider!.latitude, closeTo(7.01, 1e-9));
      expect(rider.longitude, closeTo(125.09, 1e-9));
      expect(rider.riderName, 'Ana Cruz');
      expect(rider.deliveryStatus, 'in_transit');
    });

    test('degrades to null on a malformed payload instead of throwing', () {
      expect(
        AppOrder.fromJson(orderJson(riderLocation: 'nonsense')).riderLocation,
        isNull,
      );
      expect(
        AppOrder.fromJson(
          orderJson(riderLocation: {'latitude': null, 'longitude': null}),
        ).riderLocation,
        isNull,
      );
    });
  });

  group('polling gates', () {
    test('out_for_delivery is pollable and not terminal', () {
      final order = AppOrder.fromJson(orderJson(status: 'out_for_delivery'));

      expect(order.isOutForDelivery, isTrue);
      expect(order.isTerminal, isFalse);
    });

    test('delivered and cancelled are terminal and not pollable', () {
      for (final status in ['delivered', 'cancelled']) {
        final order = AppOrder.fromJson(orderJson(status: status));

        expect(order.isTerminal, isTrue, reason: status);
        expect(order.isOutForDelivery, isFalse, reason: status);
      }
    });

    test('earlier statuses are not pollable', () {
      for (final status in ['pending_payment', 'pending', 'preparing', 'ready']) {
        expect(
          AppOrder.fromJson(orderJson(status: status)).isOutForDelivery,
          isFalse,
          reason: status,
        );
      }
    });
  });

  test('totals, items and the status timeline are parsed', () {
    final order = AppOrder.fromJson(orderJson());

    expect(order.orderNumber, 'YR-0012');
    expect(order.subtotal, 500.00);
    expect(order.deliveryFee, 30.00);
    expect(order.total, 530.00);

    expect(order.items, hasLength(1));
    expect(order.items.single.menuName, 'Pepperoni');
    expect(order.items.single.lineSubtotal, 500.00);

    // Oldest first, as the backend orders status_logs.
    expect(order.statusLogs.map((l) => l.status), ['pending', 'confirmed']);
    expect(order.statusLogs.first.changedAt, isNotNull);

    expect(order.etaMinutes, 15);
    expect(order.etaAt, isNotNull);
  });

  test('an absent status_logs list parses as empty, not an error', () {
    final json = orderJson()..remove('status_logs');

    expect(AppOrder.fromJson(json).statusLogs, isEmpty);
  });

  group('in transit and ETA', () {
    Map<String, dynamic> riderJson(String deliveryStatus) => {
          'latitude': '7.010000',
          'longitude': '125.090000',
          'updated_at': '2026-08-11T06:10:00Z',
          'delivery_status': deliveryStatus,
          'rider_name': 'Ana Cruz',
          'vehicle_type': 'motorcycle',
        };

    test('out for delivery but not yet moving is picked up, step 5 of 7', () {
      final order = AppOrder.fromJson(
        orderJson(
          status: 'out_for_delivery',
          riderLocation: riderJson('picked_up'),
        ),
      );

      expect(order.isInTransit, isFalse);
      expect(order.displayStatus, 'out_for_delivery');
      expect(
        OrderProgress.completed(
          order.status,
          deliveryStatus: order.deliveryStatus,
        ),
        5,
      );
    });

    test('in transit advances to step 6 and badges as In transit', () {
      final order = AppOrder.fromJson(
        orderJson(
          status: 'out_for_delivery',
          riderLocation: riderJson('in_transit'),
        ),
      );

      expect(order.isInTransit, isTrue);
      expect(order.displayStatus, 'in_transit');
      expect(
        OrderProgress.completed(
          order.status,
          deliveryStatus: order.deliveryStatus,
        ),
        6,
      );
      expect(
        OrderProgress.labelFor(
          order.status,
          deliveryStatus: order.deliveryStatus,
        ),
        'On the way',
      );
    });

    test('an unknown delivery status understates rather than overstates', () {
      // rider_location is withheld until the rider reports a position, so the
      // app cannot tell picked_up from in_transit in that window.
      final order = AppOrder.fromJson(
        orderJson(status: 'out_for_delivery', riderLocation: null),
      );

      expect(order.deliveryStatus, isNull);
      expect(
        OrderProgress.completed(
          order.status,
          deliveryStatus: order.deliveryStatus,
        ),
        5,
      );
    });

    test('ETA is withheld until the rider is in transit', () {
      // The backend computes the ETA only on the in_transit trigger, so an
      // eta_minutes arriving any earlier must not be shown.
      final tooEarly = AppOrder.fromJson(
        orderJson(
          status: 'out_for_delivery',
          riderLocation: riderJson('picked_up'),
        ),
      );
      expect(tooEarly.etaMinutes, 15);
      expect(tooEarly.hasEta, isFalse);

      final moving = AppOrder.fromJson(
        orderJson(
          status: 'out_for_delivery',
          riderLocation: riderJson('in_transit'),
        ),
      );
      expect(moving.hasEta, isTrue);
    });

    test('delivered is the final step regardless of delivery status', () {
      final order = AppOrder.fromJson(orderJson(status: 'delivered'));

      expect(
        OrderProgress.completed(order.status),
        OrderProgress.total,
      );
      expect(OrderProgress.labelFor(order.status), 'Delivered');
    });
  });

  test('can_cancel drives the cancel button', () {
    expect(AppOrder.fromJson(orderJson(canCancel: true)).canCancel, isTrue);
    expect(AppOrder.fromJson(orderJson(canCancel: false)).canCancel, isFalse);
  });

  group('payment', () {
    test('no invoice yet parses as null', () {
      final order = AppOrder.fromJson(orderJson());
      expect(order.payment, isNull);
    });

    test('a settled PayMongo payment exposes its reference', () {
      final order = AppOrder.fromJson({
        ...orderJson(status: 'pending'),
        'payment': {
          'invoice_number': 'INV-0007',
          'paymongo_reference': 'pay_xyz789',
          'amount_paid': '530.00',
          'paid_at': '2026-10-23T10:15:00+08:00',
          'test_mode': true,
        },
      });

      final payment = order.payment!;
      expect(payment.invoiceNumber, 'INV-0007');
      expect(payment.paymongoReference, 'pay_xyz789');
      expect(payment.amountPaid, 530.0);
      expect(payment.isPaid, isTrue);
      expect(payment.testMode, isTrue);
    });

    test('an open checkout is not yet paid', () {
      final order = AppOrder.fromJson({
        ...orderJson(status: 'pending_payment'),
        'payment': {
          'invoice_number': 'INV-0008',
          'paymongo_reference': 'src_abc123',
          'amount_paid': '0.00',
          'paid_at': null,
          'test_mode': true,
        },
      });

      expect(order.payment!.isPaid, isFalse);
      expect(order.awaitingPayment, isTrue);
    });

    test('a Maya payment carries the payer and provider', () {
      final order = AppOrder.fromJson({
        ...orderJson(status: 'pending'),
        'payment_type': 'maya',
        'payment': {
          'invoice_number': 'INV-0009',
          'paymongo_reference': 'pay-maya-123',
          'amount_paid': '530.00',
          'paid_at': '2026-10-23T10:15:00+08:00',
          'test_mode': true,
          'provider': 'maya',
          'payer': 'Maya wallet ••••0900',
          'refund': null,
        },
      });

      expect(order.isMaya, isTrue);
      expect(order.isOnlinePayment, isTrue);
      expect(order.paymentMethodLabel, 'Maya');
      expect(order.payment!.provider, 'maya');
      expect(order.payment!.payer, contains('0900'));
      expect(order.payment!.refund, isNull);
    });

    test('a refund on a cancelled order is parsed', () {
      final order = AppOrder.fromJson({
        ...orderJson(status: 'cancelled'),
        'payment_type': 'gcash',
        'payment_status': 'paid',
        'payment': {
          'invoice_number': 'INV-0010',
          'paymongo_reference': 'pay_xyz789',
          'amount_paid': '530.00',
          'paid_at': '2026-10-23T10:15:00+08:00',
          'test_mode': true,
          'provider': 'paymongo',
          'payer': null,
          'refund': {
            'status': 'pending',
            'amount': '530.00',
            'refunded_at': null,
            'reference': null,
          },
        },
      });

      final refund = order.payment!.refund!;
      expect(refund.status, 'pending');
      expect(refund.amount, 530.0);
      expect(refund.refundedAt, isNull);
    });
  });
}
