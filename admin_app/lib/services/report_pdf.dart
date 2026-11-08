import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/payment_report.dart';
import '../models/report_model.dart';

/// Which parts of the report go into the document.
class ReportSections {
  const ReportSections({
    this.sales = true,
    this.riders = true,
    this.menu = true,
    this.payments = true,
  });

  final bool sales;
  final bool riders;
  final bool menu;
  final bool payments;

  bool get isEmpty => !sales && !riders && !menu && !payments;
}

/// The data a printed report is built from. Sections left null are skipped.
class ReportData {
  ReportData({
    required this.range,
    this.sales,
    this.riders,
    this.menu,
    this.payments,
    this.transactions = const [],
  });

  final DateRange range;
  final SalesReport? sales;
  final RiderReport? riders;
  final MenuReport? menu;
  final PaymentReport? payments;
  final List<PaymentTransaction> transactions;
}

/// Lays the reports out as a printable A4/Letter document.
///
/// Built from the same figures the Reports screen shows, so paper and screen
/// always agree. Android's print dialog offers "Save as PDF", which is how a
/// PDF file is made; [share] hands the same document to any app.
class ReportPdf {
  ReportPdf._(this._fonts);

  final _Fonts _fonts;

  /// Noto Sans has the peso sign; the PDF's built-in Helvetica does not. It
  /// is fetched once and cached by `printing`. Offline, the built-in font is
  /// used and amounts are written "PHP 1,234.00" instead.
  static Future<ReportPdf> load() async {
    try {
      final regular = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      return ReportPdf._(_Fonts(regular, bold, hasPeso: true));
    } catch (_) {
      // Any failure — offline, blocked, a bad download — still prints.
      return ReportPdf.builtInFont();
    }
  }

  /// The built-in font only; amounts are written "PHP 1,234.00".
  factory ReportPdf.builtInFont() =>
      ReportPdf._(_Fonts(null, null, hasPeso: false));

  static String fileName(DateRange range) =>
      'yellow-ribbon-report-${range.startParam}-to-${range.endParam}.pdf';

  /// Opens the system print dialog ("Save as PDF" is one of its printers).
  Future<void> printReport(ReportData data, ReportSections sections) =>
      Printing.layoutPdf(
        name: fileName(data.range),
        onLayout: (format) => build(data, sections, format),
      );

  /// Shares the PDF file through the system share sheet.
  Future<void> share(ReportData data, ReportSections sections) async =>
      Printing.sharePdf(
        bytes: await build(data, sections, PdfPageFormat.a4),
        filename: fileName(data.range),
      );

  Future<Uint8List> build(
    ReportData data,
    ReportSections sections,
    PdfPageFormat format,
  ) async {
    final doc = pw.Document(
      title: 'Yellow Ribbon Pizza report',
      author: 'Yellow Ribbon Pizza',
    );
    final generated = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        theme: _fonts.theme,
        header: (context) => _header(data.range, generated),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          if (sections.sales && data.sales != null) ..._sales(data.sales!),
          if (sections.riders && data.riders != null)
            ..._riders(data.riders!),
          if (sections.menu && data.menu != null) ..._menu(data.menu!),
          if (sections.payments && data.payments != null)
            ..._payments(data.payments!, data.transactions),
        ],
      ),
    );

    return doc.save();
  }

  // -- layout ---------------------------------------------------------------

  pw.Widget _header(DateRange range, DateTime generated) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.amber, width: 2),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Yellow Ribbon Pizza',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Report for ${_date(range.start)} to ${_date(range.end)} '
                  '(${range.days} day${range.days == 1 ? '' : 's'})',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          pw.Text(
            'Generated ${_dateTime(generated)}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  pw.Widget _title(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 8),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      );

  pw.Widget _note(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          text,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      );

  /// Label/value pairs in two columns.
  pw.Widget _summary(List<(String, String)> rows) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(2),
      },
      children: [
        for (final (label, value) in rows)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(
                  value,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// A striped table. Columns after the first are right-aligned numbers.
  pw.Widget _table(
    List<String> headers,
    List<List<String>> rows, {
    Map<int, pw.TableColumnWidth>? widths,
    Set<int> leftAligned = const {0},
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      columnWidths: widths,
      headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.amber100),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      border: null,
      headerAlignments: {
        for (var i = 0; i < headers.length; i++)
          i: leftAligned.contains(i)
              ? pw.Alignment.centerLeft
              : pw.Alignment.centerRight,
      },
      cellAlignments: {
        for (var i = 0; i < headers.length; i++)
          i: leftAligned.contains(i)
              ? pw.Alignment.centerLeft
              : pw.Alignment.centerRight,
      },
    );
  }

  // -- sections -------------------------------------------------------------

  List<pw.Widget> _sales(SalesReport report) {
    final t = report.totals;
    final days = report.daily.where((d) => !d.isQuiet).toList();

    return [
      _title('Sales'),
      _summary([
        ('Revenue', _money(t.revenue)),
        ('Food sales', _money(t.foodSales)),
        ('Delivery fees', _money(t.deliveryFees)),
        ('Orders placed', '${t.ordersPlaced}'),
        ('Orders delivered', '${t.ordersDelivered}'),
        ('Orders cancelled', '${t.ordersCancelled}'),
        ('Average order value', _money(t.averageOrderValue)),
      ]),
      pw.SizedBox(height: 10),
      if (days.isEmpty)
        _note('No sales in this period.')
      else
        _table(
          ['Date', 'Placed', 'Delivered', 'Cancelled', 'Food', 'Delivery', 'Revenue'],
          [
            for (final d in days)
              [
                _date(d.date),
                '${d.ordersPlaced}',
                '${d.ordersDelivered}',
                '${d.ordersCancelled}',
                _money(d.foodSales),
                _money(d.deliveryFees),
                _money(d.revenue),
              ],
          ],
        ),
      _note('Revenue counts on the day an order was delivered. Days with no '
          'activity are left out.'),
      pw.SizedBox(height: 16),
    ];
  }

  List<pw.Widget> _riders(RiderReport report) {
    return [
      _title('Riders'),
      _summary([
        ('Deliveries completed', '${report.completed}'),
        ('Deliveries failed', '${report.failed}'),
        ('Rider earnings', _money(report.earnings)),
      ]),
      pw.SizedBox(height: 10),
      if (report.riders.isEmpty)
        _note('No rider accounts.')
      else
        _table(
          ['Rider', 'Completed', 'Failed', 'Success', 'Earnings'],
          [
            for (final r in report.riders)
              [
                '${r.name.isEmpty ? r.username : r.name}'
                    '${r.isActive ? '' : ' (inactive)'}',
                '${r.deliveriesCompleted}',
                '${r.deliveriesFailed}',
                r.successRate == null
                    ? '-'
                    : '${(r.successRate! * 100).toStringAsFixed(0)}%',
                _money(r.earnings),
              ],
          ],
          widths: const {0: pw.FlexColumnWidth(3)},
        ),
      pw.SizedBox(height: 16),
    ];
  }

  List<pw.Widget> _menu(MenuReport report) {
    return [
      _title('Menu'),
      _summary([
        ('Items sold', '${report.quantitySold}'),
        ('Food revenue', _money(report.revenue)),
      ]),
      pw.SizedBox(height: 10),
      if (report.items.isEmpty)
        _note('No menu items.')
      else
        _table(
          ['Item', 'Price', 'Sold', 'Revenue'],
          [
            for (final item in report.items)
              [
                '${item.name}${item.isAvailable ? '' : ' (unavailable)'}',
                _money(item.price),
                '${item.quantitySold}',
                _money(item.revenue),
              ],
          ],
          widths: const {0: pw.FlexColumnWidth(3)},
        ),
      pw.SizedBox(height: 16),
    ];
  }

  List<pw.Widget> _payments(
    PaymentReport report,
    List<PaymentTransaction> transactions,
  ) {
    final t = report.totals;

    return [
      _title('Payments'),
      _table(
        ['Method', 'Payments', 'Taken', 'Gateway fees', 'Refunded', 'Net to store'],
        [
          for (final row in [...report.providers, t])
            [
              row.provider == 'total' ? 'Total' : providerLabel(row.provider),
              '${row.count}',
              _money(row.gross),
              _money(row.fees),
              _money(row.refunds),
              _money(row.net),
            ],
        ],
        widths: const {0: pw.FlexColumnWidth(2.2)},
      ),
      if (report.outstandingRefundCount > 0)
        _note('${report.outstandingRefundCount} refund(s) totalling '
            '${_money(report.outstandingRefundAmount)} not yet completed.'),
      pw.SizedBox(height: 12),
      pw.Text(
        'Transactions',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      if (transactions.isEmpty)
        _note('No payments in this period.')
      else
        _table(
          ['Paid', 'Order', 'Customer', 'Method', 'Reference', 'Amount', 'Fee', 'Net', 'Refund'],
          [
            for (final tx in transactions)
              [
                _dateTime(tx.paidAt),
                tx.orderNumber,
                tx.customer,
                providerLabel(tx.provider),
                tx.reference,
                _money(tx.amount),
                _money(tx.fee),
                _money(tx.net),
                tx.refundStatus ?? '',
              ],
          ],
          leftAligned: const {0, 1, 2, 3, 4, 8},
          widths: const {
            0: pw.FlexColumnWidth(1.6),
            2: pw.FlexColumnWidth(1.6),
            4: pw.FlexColumnWidth(2.2),
          },
        ),
      _note('A payment counts on the day it was paid and a refund on the day '
          'it was refunded. Gateway fees are not returned on refunds.'),
    ];
  }

  // -- formatting -----------------------------------------------------------

  String _money(double value) {
    final negative = value < 0;
    final fixed = value.abs().toStringAsFixed(2);
    final whole = fixed.substring(0, fixed.length - 3);
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final amount = '$grouped${fixed.substring(fixed.length - 3)}';
    final sign = negative ? '-' : '';
    return _fonts.hasPeso ? '$sign₱$amount' : '${sign}PHP $amount';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime value) =>
      '${_months[value.month - 1]} ${value.day}, ${value.year}';

  static String _dateTime(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '${_date(local)} $hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _Fonts {
  _Fonts(this.regular, this.bold, {required this.hasPeso});

  final pw.Font? regular;
  final pw.Font? bold;
  final bool hasPeso;

  pw.ThemeData get theme => regular == null
      ? pw.ThemeData()
      : pw.ThemeData.withFont(base: regular, bold: bold);
}
