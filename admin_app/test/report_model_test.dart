// Tests for the three date-range reports.
//
// The parsing itself is unremarkable; what is worth pinning is the handling
// of the empty and zero cases, because reports are mostly read on quiet days.
// A window with no sales must render a chart, not divide by zero, and "did
// nothing" must stay distinguishable from "failed everything".

import 'package:flutter_test/flutter_test.dart';

import 'package:admin_app/models/report_model.dart';

void main() {
  group('DateRange', () {
    test('a preset is the last N days inclusive of today', () {
      final range = DateRange.lastDays(30, today: DateTime(2026, 8, 12));

      expect(range.startParam, '2026-07-14');
      expect(range.endParam, '2026-08-12');
      // 30 days including both ends, matching the backend's own default.
      expect(range.days, 30);
    });

    test('pads the parameters the server parses with fromisoformat', () {
      final range = DateRange(DateTime(2026, 1, 5), DateTime(2026, 3, 9));

      expect(range.startParam, '2026-01-05');
      expect(range.endParam, '2026-03-09');
    });

    test('equality ignores the time of day', () {
      // The preset chips compare a freshly built range against the current
      // one to decide which is selected; a stray time component would make
      // the matching chip never light up.
      final withTime = DateRange(
        DateTime(2026, 8, 1, 13, 45),
        DateTime(2026, 8, 12, 6, 30),
      );
      final dateOnly = DateRange(DateTime(2026, 8, 1), DateTime(2026, 8, 12));

      expect(withTime, dateOnly);
      expect(withTime.hashCode, dateOnly.hashCode);
    });
  });

  group('SalesReport', () {
    Map<String, dynamic> day(String date, String revenue, {int delivered = 0}) {
      return {
        'date': date,
        'revenue': revenue,
        'food_sales': revenue,
        'delivery_fees': '0.00',
        'orders_placed': delivered,
        'orders_delivered': delivered,
        'orders_cancelled': 0,
      };
    }

    test('parses the totals and the gap-free daily series', () {
      final report = SalesReport.fromJson({
        'start': '2026-08-10',
        'end': '2026-08-12',
        'days': 3,
        'totals': {
          'revenue': '3501.00',
          'food_sales': '3291.00',
          'delivery_fees': '210.00',
          'orders_placed': 14,
          'orders_delivered': 7,
          'orders_cancelled': 5,
          'average_order_value': '500.14',
        },
        'daily': [
          day('2026-08-10', '0.00'),
          day('2026-08-11', '1200.00', delivered: 3),
          day('2026-08-12', '2301.00', delivered: 4),
        ],
      });

      expect(report.days, 3);
      expect(report.totals.revenue, 3501.00);
      expect(report.totals.averageOrderValue, 500.14);
      expect(report.daily, hasLength(3));
      expect(report.peakRevenue, 2301.00);
      expect(report.bestDay!.date.day, 12);
      // The quiet day counts as a day but not a trading one.
      expect(report.tradingDays, 2);
    });

    test('a window with no sales has no peak and no best day', () {
      // The chart divides by the peak, so this is the case that would crash.
      final report = SalesReport.fromJson({
        'start': '2026-08-11',
        'end': '2026-08-12',
        'days': 2,
        'totals': {
          'revenue': '0.00',
          'orders_placed': 0,
          'orders_delivered': 0,
          'orders_cancelled': 0,
          'average_order_value': '0.00',
        },
        'daily': [day('2026-08-11', '0.00'), day('2026-08-12', '0.00')],
      });

      expect(report.peakRevenue, 0);
      expect(report.bestDay, isNull);
      expect(report.tradingDays, 0);
      expect(report.daily.every((d) => d.isQuiet), isTrue);
    });

    test('a malformed payload degrades to empty rather than throwing', () {
      final report = SalesReport.fromJson(const {});

      expect(report.daily, isEmpty);
      expect(report.totals.revenue, 0);
      expect(report.bestDay, isNull);
    });

    test('orders in progress never read as a negative', () {
      // An order placed on the last day of the window and delivered after it
      // is placed-but-not-resolved. Deliveries of orders placed *before* the
      // window can push delivered past placed, which must not go negative.
      final totals = SalesTotals.fromJson({
        'orders_placed': 2,
        'orders_delivered': 9,
        'orders_cancelled': 0,
      });

      expect(totals.unresolved, 0);
    });
  });

  group('RiderReport', () {
    test('parses the roster and its totals', () {
      final report = RiderReport.fromJson({
        'start': '2026-07-14',
        'end': '2026-08-12',
        'totals': {
          'deliveries_completed': 9,
          'deliveries_failed': 1,
          'earnings': '450.00',
        },
        'riders': [
          {
            'rider_id': 1,
            'username': 'ana',
            'name': 'Ana Cruz',
            'is_active': true,
            'deliveries_completed': 8,
            'deliveries_failed': 1,
            'earnings': '400.00',
          },
          {
            'rider_id': 2,
            'username': 'ben',
            'name': 'Ben Diaz',
            'is_active': true,
            'deliveries_completed': 1,
            'deliveries_failed': 0,
            'earnings': '50.00',
          },
          {
            'rider_id': 3,
            'username': 'cara',
            'name': 'Cara Lim',
            'is_active': false,
            'deliveries_completed': 0,
            'deliveries_failed': 0,
            'earnings': '0.00',
          },
        ],
      });

      expect(report.completed, 9);
      expect(report.earnings, 450.00);
      // Idle riders are included on purpose, but not counted as having worked.
      expect(report.riders, hasLength(3));
      expect(report.activeRiders, 2);
    });

    test('doing nothing is not the same as a nought percent success rate', () {
      RiderReportRow row(int completed, int failed) =>
          RiderReportRow.fromJson({
            'rider_id': 1,
            'username': 'ana',
            'name': 'Ana',
            'is_active': true,
            'deliveries_completed': completed,
            'deliveries_failed': failed,
            'earnings': '0.00',
          });

      // Attempted nothing: there is no rate to report, and showing "0%"
      // would read as a rider who failed everything.
      expect(row(0, 0).successRate, isNull);
      expect(row(0, 0).didNothing, isTrue);

      // Attempted and failed everything: that genuinely is 0%.
      expect(row(0, 3).successRate, 0);
      expect(row(0, 3).didNothing, isFalse);

      expect(row(3, 1).successRate, closeTo(0.75, 1e-9));
    });
  });

  group('MenuReport', () {
    test('keeps the server ordering and finds the unsold items', () {
      final report = MenuReport.fromJson({
        'start': '2026-07-14',
        'end': '2026-08-12',
        'totals': {
          'items': 3,
          'quantity_sold': 14,
          'revenue': '5400.00',
        },
        'items': [
          {
            'menu_id': 1,
            'name': 'Pepperoni',
            'price': '399.00',
            'is_available': true,
            'quantity_sold': 10,
            'revenue': '3990.00',
          },
          {
            'menu_id': 2,
            'name': 'Hawaiian',
            'price': '352.50',
            'is_available': true,
            'quantity_sold': 4,
            'revenue': '1410.00',
          },
          {
            'menu_id': 3,
            'name': 'Anchovy',
            'price': '420.00',
            'is_available': false,
            'quantity_sold': 0,
            'revenue': '0.00',
          },
        ],
      });

      // Best first is the server's ordering, and the bars scale off it.
      expect(report.items.first.name, 'Pepperoni');
      expect(report.topSellerQuantity, 10);

      expect(report.unsold, hasLength(1));
      expect(report.unsold.single.name, 'Anchovy');
      expect(report.quantitySold, 14);
    });

    test('an empty menu has no top seller to divide by', () {
      final report = MenuReport.fromJson(const {'items': []});

      expect(report.items, isEmpty);
      expect(report.topSellerQuantity, 0);
      expect(report.unsold, isEmpty);
    });
  });
}
