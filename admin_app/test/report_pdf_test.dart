// The printable report must build from real-shaped report data, including
// when a section failed to load and is skipped.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:admin_app/models/payment_report.dart';
import 'package:admin_app/models/report_model.dart';
import 'package:admin_app/services/report_pdf.dart';

void main() {
  final range = DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 23));

  final sales = SalesReport.fromJson({
    'start': '2026-10-01',
    'end': '2026-10-23',
    'days': 23,
    'totals': {
      'revenue': '1250.00',
      'food_sales': '1160.00',
      'delivery_fees': '90.00',
      'orders_placed': 4,
      'orders_delivered': 3,
      'orders_cancelled': 1,
      'average_order_value': '416.67',
    },
    'daily': [
      {
        'date': '2026-10-22',
        'revenue': '1250.00',
        'food_sales': '1160.00',
        'delivery_fees': '90.00',
        'orders_placed': 4,
        'orders_delivered': 3,
        'orders_cancelled': 1,
      },
    ],
  });

  final payments = PaymentReport.fromJson({
    'providers': [
      {'provider': 'paymongo', 'label': 'GCash', 'count': 1, 'gross': '329.00',
       'fees': '8.23', 'refund_count': 0, 'refunds': '0.00', 'net': '320.77'},
      {'provider': 'maya', 'label': 'Maya', 'count': 0, 'gross': '0.00',
       'fees': '0.00', 'refund_count': 0, 'refunds': '0.00', 'net': '0.00'},
      {'provider': 'cod', 'label': 'COD', 'count': 2, 'gross': '921.00',
       'fees': '0.00', 'refund_count': 0, 'refunds': '0.00', 'net': '921.00'},
    ],
    'totals': {'count': 3, 'gross': '1250.00', 'fees': '8.23',
               'refund_count': 0, 'refunds': '0.00', 'net': '1241.77'},
    'refunds_outstanding': {'count': 0, 'amount': '0.00'},
  });

  final transaction = PaymentTransaction.fromJson({
    'order_id': 1,
    'order_number': 'YR-0001',
    'customer': 'maria',
    'invoice_number': 'INV-0001',
    'provider': 'paymongo',
    'reference': 'pay_xyz789',
    'payer': null,
    'amount': '329.00',
    'fee': '8.23',
    'net': '320.77',
    'paid_at': '2026-10-22T10:15:00+08:00',
    'refund': null,
  });

  test('builds a PDF with every section', () async {
    final bytes = await ReportPdf.builtInFont().build(
      ReportData(
        range: range,
        sales: sales,
        payments: payments,
        transactions: [transaction],
      ),
      const ReportSections(),
      PdfPageFormat.a4,
    );

    expect(bytes, isNotEmpty);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('a section that failed to load is skipped, not fatal', () async {
    final bytes = await ReportPdf.builtInFont().build(
      ReportData(range: range),
      const ReportSections(),
      PdfPageFormat.letter,
    );

    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('the file name carries the date range', () {
    expect(
      ReportPdf.fileName(range),
      'yellow-ribbon-report-2026-10-01-to-2026-10-23.pdf',
    );
  });
}
