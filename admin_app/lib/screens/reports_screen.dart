import 'package:flutter/material.dart';

import '../models/payment_report.dart';
import '../models/report_model.dart';
import '../services/api_client.dart';
import '../services/report_pdf.dart';
import '../services/report_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/order_status.dart';
import '../widgets/section_card.dart';
import 'order_detail_screen.dart';

/// `/api/admin/reports/` — sales, riders, menu and payments over a date range.
///
/// The dashboard answers "how are we doing today". This answers "how did the
/// month go". Both recognise revenue on delivery, so the two agree on any
/// window that contains today.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _reports = ReportService();

  /// Matches the backend's own default, so the first view is the one the
  /// endpoints would have returned with no parameters.
  DateRange _range = DateRange.lastDays(30);

  late Future<SalesReport> _sales;
  late Future<RiderReport> _riders;
  late Future<MenuReport> _menu;
  late Future<PaymentReport> _payments;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() {
    // All three fire together: switching tabs should not cost a round trip,
    // and the three reports share one range so they are one logical read.
    _sales = _reports.fetchSales(_range);
    _riders = _reports.fetchRiders(_range);
    _menu = _reports.fetchMenu(_range);
    _payments = _reports.fetchPayments(_range);
  }

  Future<void> _reload() async {
    setState(_fetch);
    try {
      await Future.wait([_sales, _riders, _menu, _payments]);
    } on ApiException {
      // Each tab renders its own failure.
    }
  }

  void _setRange(DateRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _fetch();
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _range.start, end: _range.end),
      helpText: "Report period",
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: kInk,
            onPrimary: Colors.white,
            surfaceTint: Colors.transparent,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null) return;

    // The server refuses more than 366 days; catching it here saves a round
    // trip and explains it in the same breath.
    final range = DateRange(picked.start, picked.end);
    if (range.days > 366) {
      _snack("That is ${range.days} days. The longest report is 366.");
      return;
    }
    _setRange(range);
  }

  void _openPrintSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PrintSheet(
        range: _range,
        sales: _sales,
        riders: _riders,
        menu: _menu,
        payments: _payments,
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
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Reports"),
          actions: [
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: "Print or save as PDF",
              onPressed: _openPrintSheet,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: "Refresh",
              onPressed: _reload,
            ),
          ],
          bottom: const TabBar(
            labelColor: kInk,
            unselectedLabelColor: Color(0x991F1F1F),
            indicatorColor: kInk,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            unselectedLabelStyle: TextStyle(fontSize: 13.5),
            tabs: [
              Tab(text: "Sales"),
              Tab(text: "Riders"),
              Tab(text: "Menu"),
              Tab(text: "Payments"),
            ],
          ),
        ),
        body: Column(
          children: [
            _RangeBar(
              range: _range,
              onPreset: _setRange,
              onCustom: _pickCustomRange,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _SalesTab(future: _sales, onRetry: _reload),
                  _RidersTab(future: _riders, onRetry: _reload),
                  _MenuTab(future: _menu, onRetry: _reload),
                  _PaymentsTab(
                    // Keyed on the range so a new window starts the
                    // transaction list over from page one.
                    key: ValueKey(_range),
                    future: _payments,
                    range: _range,
                    onRetry: _reload,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Print / PDF
// ---------------------------------------------------------------------------

/// Pick the sections, then print (the print dialog's "Save as PDF" makes a
/// file) or share the PDF straight to another app.
class _PrintSheet extends StatefulWidget {
  const _PrintSheet({
    required this.range,
    required this.sales,
    required this.riders,
    required this.menu,
    required this.payments,
  });

  final DateRange range;
  final Future<SalesReport> sales;
  final Future<RiderReport> riders;
  final Future<MenuReport> menu;
  final Future<PaymentReport> payments;

  @override
  State<_PrintSheet> createState() => _PrintSheetState();
}

/// Printed transactions are capped so a year-long report stays a sensible
/// size; the cap is said on the sheet when it bites.
const _maxPrintedTransactions = 1000;

class _PrintSheetState extends State<_PrintSheet> {
  final _reports = ReportService();

  bool _sales = true;
  bool _riders = true;
  bool _menu = true;
  bool _payments = true;
  bool _busy = false;
  String? _error;

  ReportSections get _sections => ReportSections(
        sales: _sales,
        riders: _riders,
        menu: _menu,
        payments: _payments,
      );

  /// A report that failed to load is left out rather than failing the whole
  /// document.
  Future<T?> _orNull<T>(bool wanted, Future<T> future) async {
    if (!wanted) return null;
    try {
      return await future;
    } on ApiException {
      return null;
    }
  }

  Future<List<PaymentTransaction>> _allTransactions() async {
    final rows = <PaymentTransaction>[];
    var page = 1;
    while (rows.length < _maxPrintedTransactions) {
      final batch = await _reports.fetchTransactions(
        widget.range,
        page: page,
        pageSize: 100,
      );
      rows.addAll(batch.results);
      if (!batch.hasMore) break;
      page += 1;
    }
    return rows.take(_maxPrintedTransactions).toList();
  }

  Future<void> _run({required bool share}) async {
    final sections = _sections;
    if (sections.isEmpty) {
      setState(() => _error = "Pick at least one section.");
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final results = await Future.wait<Object?>([
        _orNull(sections.sales, widget.sales),
        _orNull(sections.riders, widget.riders),
        _orNull(sections.menu, widget.menu),
        _orNull(sections.payments, widget.payments),
        sections.payments ? _allTransactions() : Future.value(<PaymentTransaction>[]),
        ReportPdf.load(),
      ]);

      final data = ReportData(
        range: widget.range,
        sales: results[0] as SalesReport?,
        riders: results[1] as RiderReport?,
        menu: results[2] as MenuReport?,
        payments: results[3] as PaymentReport?,
        transactions: results[4] as List<PaymentTransaction>,
      );
      final pdf = results[5] as ReportPdf;

      if (share) {
        await pdf.share(data, sections);
      } else {
        await pdf.printReport(data, sections);
      }
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception {
      if (mounted) setState(() => _error = "Could not make the PDF.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Print or save as PDF",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              "${DateRange.isoDate(widget.range.start)} to "
              "${DateRange.isoDate(widget.range.end)}",
              style: const TextStyle(fontSize: 12.5, color: kMuted),
            ),
            const SizedBox(height: 8),
            _check("Sales", _sales, (v) => setState(() => _sales = v)),
            _check("Riders", _riders, (v) => setState(() => _riders = v)),
            _check("Menu", _menu, (v) => setState(() => _menu = v)),
            _check(
              "Payments and transactions",
              _payments,
              (v) => setState(() => _payments = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFC62828)),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _busy ? null : () => _run(share: false),
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
                    )
                  : const Icon(Icons.print_outlined),
              label: const Text("Print / Save as PDF"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(share: true),
              icon: const Icon(Icons.share_outlined),
              label: const Text("Share PDF"),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "To save a PDF file, pick \"Save as PDF\" as the printer.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: kMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: _busy ? null : (v) => onChanged(v ?? false),
      title: Text(label),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: kInk,
    );
  }
}

// ---------------------------------------------------------------------------
// Range picker
// ---------------------------------------------------------------------------

class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.range,
    required this.onPreset,
    required this.onCustom,
  });

  final DateRange range;
  final void Function(DateRange) onPreset;
  final VoidCallback onCustom;

  static const _presets = <int, String>{7: "7 days", 30: "30 days", 90: "90 days"};

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.date_range, size: 15, color: kMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  "${_pretty(range.start)} – ${_pretty(range.end)}"
                  "  ·  ${range.days} days",
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: kInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._presets.entries.map((entry) {
                  final preset = DateRange.lastDays(entry.key);
                  return _chip(
                    entry.value,
                    isSelected: preset == range,
                    onTap: () => onPreset(preset),
                  );
                }),
                _chip(
                  "Custom",
                  icon: Icons.tune,
                  // Selected when the window matches none of the presets.
                  isSelected: !_presets.keys
                      .any((days) => DateRange.lastDays(days) == range),
                  onTap: onCustom,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label, {
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: isSelected ? kInk : kCanvas,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected ? kAmber : kMuted,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : kInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _pretty(DateTime date) =>
      "${date.day} ${_months[date.month - 1]}";
}

/// Shared shape for the three tabs: spinner, error, or content.
class _ReportBody<T> extends StatelessWidget {
  const _ReportBody({
    required this.future,
    required this.onRetry,
    required this.builder,
  });

  final Future<T> future;
  final Future<void> Function() onRetry;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final error = snapshot.error;
          return EmptyState(
            icon: Icons.cloud_off,
            title: "Could not build this report",
            message: error is ApiException
                ? error.message
                : "Something went wrong.",
            onRetry: onRetry,
          );
        }

        return RefreshIndicator(
          color: kAmber,
          onRefresh: onRetry,
          child: builder(snapshot.data as T),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sales
// ---------------------------------------------------------------------------

class _SalesTab extends StatelessWidget {
  const _SalesTab({required this.future, required this.onRetry});

  final Future<SalesReport> future;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _ReportBody<SalesReport>(
      future: future,
      onRetry: onRetry,
      builder: (report) {
        final totals = report.totals;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _HeadlineCard(
              label: "Revenue over ${report.days} days",
              value: "₱${totals.revenue.toStringAsFixed(2)}",
              caption: totals.ordersDelivered == 0
                  ? "Nothing delivered in this window."
                  : "${totals.ordersDelivered} deliveries · "
                      "₱${totals.averageOrderValue.toStringAsFixed(2)} average",
            ),

            const SizedBox(height: 14),

            SectionCard(
              title: "Daily revenue",
              icon: Icons.show_chart,
              child: _RevenueChart(report: report),
            ),

            const SizedBox(height: 14),

            SectionCard(
              title: "Breakdown",
              icon: Icons.payments_outlined,
              child: Column(
                children: [
                  DetailRow(
                    "Food sales",
                    "₱${totals.foodSales.toStringAsFixed(2)}",
                  ),
                  const Divider(height: 1),
                  DetailRow(
                    "Delivery fees",
                    "₱${totals.deliveryFees.toStringAsFixed(2)}",
                  ),
                  const Divider(height: 1),
                  DetailRow(
                    "Total",
                    "₱${totals.revenue.toStringAsFixed(2)}",
                    emphasise: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            SectionCard(
              title: "Orders",
              icon: Icons.receipt_long_outlined,
              child: Column(
                children: [
                  DetailRow("Placed", "${totals.ordersPlaced}"),
                  const Divider(height: 1),
                  DetailRow(
                    "Delivered",
                    "${totals.ordersDelivered}",
                    valueColour: const Color(0xFF2E7D32),
                  ),
                  const Divider(height: 1),
                  DetailRow(
                    "Cancelled",
                    "${totals.ordersCancelled}",
                    valueColour: totals.ordersCancelled > 0
                        ? const Color(0xFFC62828)
                        : null,
                  ),
                  if (totals.unresolved > 0) ...[
                    const Divider(height: 1),
                    DetailRow("Still in progress", "${totals.unresolved}"),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    "Each figure sits on its own date: revenue and deliveries "
                    "on the day delivered, placements on the day ordered. An "
                    "order placed on the last day and delivered after it "
                    "counts as placed but not delivered.",
                    style: TextStyle(fontSize: 11, color: kMuted, height: 1.4),
                  ),
                ],
              ),
            ),

            if (report.bestDay != null) ...[
              const SizedBox(height: 14),
              SectionCard(
                title: "Best day",
                icon: Icons.emoji_events_outlined,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _longDate(report.bestDay!.date),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      "₱${report.bestDay!.revenue.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String _longDate(DateTime date) =>
      "${date.day} ${_months[date.month - 1]} ${date.year}";
}

/// Hand-rolled bar chart.
///
/// No chart package: one screen needs one chart, and a dependency for it
/// would be more code to keep current than this is to read. The series is
/// gap-free from the backend, so a bar per day needs no interpolation.
class _RevenueChart extends StatefulWidget {
  const _RevenueChart({required this.report});

  final SalesReport report;

  @override
  State<_RevenueChart> createState() => _RevenueChartState();
}

class _RevenueChartState extends State<_RevenueChart> {
  /// The bar the admin last tapped, read out above the chart.
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final peak = report.peakRevenue;

    if (report.daily.isEmpty) {
      return const Text(
        "No days in this range.",
        style: TextStyle(fontSize: 12.5, color: kMuted),
      );
    }

    if (peak == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          "Nothing was delivered in this window, so there is no revenue to "
          "chart.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: kMuted),
        ),
      );
    }

    final index = _selected;
    final highlighted = index != null && index < report.daily.length
        ? report.daily[index]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Read-out for the tapped bar, or the peak as a default. Reserved
        // height so tapping does not jog the layout.
        SizedBox(
          height: 34,
          child: highlighted == null
              ? Text(
                  "Peak ₱${peak.toStringAsFixed(2)} · "
                  "${report.tradingDays} of ${report.days} days traded",
                  style: const TextStyle(fontSize: 12, color: kMuted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "₱${highlighted.revenue.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kInk,
                      ),
                    ),
                    Text(
                      "${_dayLabel(highlighted.date)} · "
                      "${highlighted.ordersDelivered} delivered",
                      style: const TextStyle(fontSize: 11, color: kMuted),
                    ),
                  ],
                ),
        ),

        const SizedBox(height: 10),

        SizedBox(
          height: 140,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // Newest on the right is the natural reading order for a
            // timeline, and it is where the eye lands first.
            reverse: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: List.generate(report.daily.length, (i) {
                // Rebuilt back-to-front because the scroll view is reversed.
                final position = report.daily.length - 1 - i;
                final day = report.daily[position];
                return _bar(day, position, peak);
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bar(SalesDay day, int position, double peak) {
    final isSelected = _selected == position;
    // A trading day never renders as nothing: 4px keeps a small day visible
    // and distinguishable from a zero.
    final fraction = day.revenue / peak;
    final height = day.revenue == 0 ? 3.0 : (fraction * 110).clamp(4.0, 110.0);

    return GestureDetector(
      onTap: () => setState(
        () => _selected = isSelected ? null : position,
      ),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 14,
              height: height,
              decoration: BoxDecoration(
                color: day.revenue == 0
                    ? const Color(0xFFE4E4E4)
                    : isSelected
                        ? kInk
                        : kAmber,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 18,
              child: Text(
                '${day.date.day}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: isSelected ? kInk : kMuted,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _dayLabel(DateTime date) =>
      "${date.day} ${_months[date.month - 1]}";
}

// ---------------------------------------------------------------------------
// Riders
// ---------------------------------------------------------------------------

class _RidersTab extends StatelessWidget {
  const _RidersTab({required this.future, required this.onRetry});

  final Future<RiderReport> future;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _ReportBody<RiderReport>(
      future: future,
      onRetry: onRetry,
      builder: (report) {
        if (report.riders.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(30),
            children: const [
              Text(
                "No rider accounts exist yet.",
                textAlign: TextAlign.center,
                style: TextStyle(color: kMuted),
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _HeadlineCard(
              label: "Rider earnings",
              value: "₱${report.earnings.toStringAsFixed(2)}",
              caption: "${report.completed} delivered"
                  "${report.failed > 0 ? ' · ${report.failed} failed' : ''}"
                  " · ${report.activeRiders} of ${report.riders.length} "
                  "riders worked",
            ),

            const SizedBox(height: 14),

            ...report.riders.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RiderRow(row: row, best: report.riders.first),
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              "Completions and earnings are counted on the day delivered. "
              "Failures have no timestamp of their own, so they count on the "
              "day the delivery was assigned.",
              style: TextStyle(fontSize: 11, color: kMuted, height: 1.4),
            ),
          ],
        );
      },
    );
  }
}

class _RiderRow extends StatelessWidget {
  const _RiderRow({required this.row, required this.best});

  final RiderReportRow row;

  /// Top of the list, for scaling the bar. Not necessarily this row.
  final RiderReportRow best;

  @override
  Widget build(BuildContext context) {
    final peak = best.deliveriesCompleted;
    final fraction = peak == 0 ? 0.0 : row.deliveriesCompleted / peak;
    final rate = row.successRate;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: row.isActive ? kInk : kMuted,
                      ),
                    ),
                    Text(
                      "@${row.username}",
                      style: const TextStyle(fontSize: 11, color: kMuted),
                    ),
                  ],
                ),
              ),
              if (!row.isActive)
                const TagPill(label: "Deactivated", colour: kMuted),
              const SizedBox(width: 8),
              Text(
                "₱${row.earnings.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: kInk,
                ),
              ),
            ],
          ),

          const SizedBox(height: 11),

          // Relative bar rather than a raw count: the useful question is
          // who is carrying the load, not how many that happens to be.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: const Color(0xFFEDEDED),
              valueColor: AlwaysStoppedAnimation(
                row.didNothing ? const Color(0xFFE4E4E4) : kAmber,
              ),
            ),
          ),

          const SizedBox(height: 9),

          Row(
            children: [
              _stat(
                Icons.task_alt,
                "${row.deliveriesCompleted}",
                "done",
                const Color(0xFF2E7D32),
              ),
              const SizedBox(width: 16),
              if (row.deliveriesFailed > 0)
                _stat(
                  Icons.error_outline,
                  "${row.deliveriesFailed}",
                  "failed",
                  const Color(0xFFC62828),
                ),
              const Spacer(),
              Text(
                // Distinguishes "attempted nothing" from "failed everything".
                rate == null
                    ? "No deliveries in this period"
                    : "${(rate * 100).round()}% success",
                style: const TextStyle(fontSize: 11, color: kMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label, Color colour) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colour),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: colour,
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 11, color: kMuted)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Menu
// ---------------------------------------------------------------------------

class _MenuTab extends StatelessWidget {
  const _MenuTab({required this.future, required this.onRetry});

  final Future<MenuReport> future;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _ReportBody<MenuReport>(
      future: future,
      onRetry: onRetry,
      builder: (report) {
        if (report.items.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(30),
            children: const [
              Text(
                "The menu is empty.",
                textAlign: TextAlign.center,
                style: TextStyle(color: kMuted),
              ),
            ],
          );
        }

        final unsold = report.unsold;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _HeadlineCard(
              label: "Food sales",
              value: "₱${report.revenue.toStringAsFixed(2)}",
              caption: "${report.quantitySold} items sold across "
                  "${report.itemCount} menu items",
            ),

            const SizedBox(height: 6),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                "Food only — delivery fees are not attributable to an item, "
                "so this is less than total revenue.",
                style: TextStyle(fontSize: 11, color: kMuted, height: 1.4),
              ),
            ),

            const SizedBox(height: 8),

            ...report.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MenuRow(
                  item: item,
                  peak: report.topSellerQuantity,
                ),
              ),
            ),

            if (unsold.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                unsold.length == 1
                    ? "1 item sold nothing in this period."
                    : "${unsold.length} items sold nothing in this period.",
                style: const TextStyle(fontSize: 11.5, color: kMuted),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.peak});

  final MenuReportRow item;

  /// The best seller's quantity, for scaling the bar.
  final int peak;

  @override
  Widget build(BuildContext context) {
    final fraction = peak == 0 ? 0.0 : item.quantitySold / peak;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          color: item.soldNothing ? kMuted : kInk,
                        ),
                      ),
                    ),
                    // A hidden item selling nothing is expected; a visible
                    // one selling nothing is the finding.
                    if (!item.isAvailable) ...[
                      const SizedBox(width: 7),
                      const TagPill(label: "Hidden", colour: kMuted),
                    ],
                  ],
                ),
              ),
              Text(
                "₱${item.revenue.toStringAsFixed(2)}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                  color: item.soldNothing ? kMuted : kInk,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: const Color(0xFFEDEDED),
              valueColor: AlwaysStoppedAnimation(
                item.soldNothing ? const Color(0xFFE4E4E4) : kAmber,
              ),
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Text(
                item.soldNothing
                    ? "None sold"
                    : "${item.quantitySold} sold",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: item.soldNothing ? kMuted : kInk,
                ),
              ),
              const Spacer(),
              Text(
                "₱${item.price.toStringAsFixed(2)} each",
                style: const TextStyle(fontSize: 11, color: kMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------------

/// Where the money went: per gateway, what was taken, what the gateway kept,
/// what was refunded, and what reaches the store. Then every payment, so
/// each one can be traced to its gateway reference.
class _PaymentsTab extends StatefulWidget {
  const _PaymentsTab({
    super.key,
    required this.future,
    required this.range,
    required this.onRetry,
  });

  final Future<PaymentReport> future;
  final DateRange range;
  final Future<void> Function() onRetry;

  @override
  State<_PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<_PaymentsTab> {
  final _reports = ReportService();

  final List<PaymentTransaction> _rows = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loadingRows = false;
  String? _rowsError;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingRows || !_hasMore) return;
    setState(() {
      _loadingRows = true;
      _rowsError = null;
    });
    try {
      final page = await _reports.fetchTransactions(
        widget.range,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _page += 1;
        _rows.addAll(page.results);
        _hasMore = page.hasMore;
        _loadingRows = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRows = false;
        _rowsError = e.message;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _rows.clear();
      _page = 0;
      _hasMore = true;
    });
    await Future.wait([widget.onRetry(), _loadMore()]);
  }

  static String _peso(double value) =>
      "${value < 0 ? '−' : ''}₱${value.abs().toStringAsFixed(2)}";

  @override
  Widget build(BuildContext context) {
    return _ReportBody<PaymentReport>(
      future: widget.future,
      onRetry: _refresh,
      builder: (report) {
        final totals = report.totals;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _HeadlineCard(
              label: "Net to the store",
              value: _peso(totals.net),
              caption: "${totals.count} payments · ${_peso(totals.gross)} "
                  "taken · ${_peso(totals.fees)} gateway fees"
                  "${totals.refundCount > 0 ? ' · ${_peso(totals.refunds)} refunded' : ''}",
            ),

            if (report.outstandingRefundCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFC62828).withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${report.outstandingRefundCount} refund"
                  "${report.outstandingRefundCount == 1 ? '' : 's'} "
                  "(${_peso(report.outstandingRefundAmount)}) not yet "
                  "completed. Open the order to retry.",
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFB71C1C),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 14),

            ...report.providers.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SectionCard(
                  title: providerLabel(row.provider),
                  icon: row.provider == 'cod'
                      ? Icons.payments_outlined
                      : Icons.account_balance_wallet_outlined,
                  trailing: Text(
                    "${row.count} paid",
                    style: const TextStyle(fontSize: 12, color: kMuted),
                  ),
                  child: Column(
                    children: [
                      DetailRow("Taken", _peso(row.gross)),
                      DetailRow("Gateway fees", _peso(-row.fees)),
                      if (row.refundCount > 0)
                        DetailRow(
                          "Refunded (${row.refundCount})",
                          _peso(-row.refunds),
                        ),
                      const Divider(height: 14),
                      DetailRow("Net to store", _peso(row.net), emphasise: true),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),
            const Text(
              "Transactions",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),

            if (_rows.isEmpty && !_loadingRows && _rowsError == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  "No payments in this period.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kMuted),
                ),
              ),

            ..._rows.map((row) => _TransactionRow(row: row)),

            if (_rowsError != null)
              TextButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text("Couldn't load more: $_rowsError"),
              )
            else if (_loadingRows)
              const Padding(
                padding: EdgeInsets.all(14),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_hasMore)
              OutlinedButton(
                onPressed: _loadMore,
                child: const Text("Load more"),
              ),

            const SizedBox(height: 10),
            const Text(
              "A payment counts on the day it was paid and a refund on the day "
              "it was refunded. Gateway fees are worked out from the rates in "
              "Store settings at the time of payment, and are not returned "
              "when an order is refunded.",
              style: TextStyle(fontSize: 11, color: kMuted, height: 1.4),
            ),
          ],
        );
      },
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.row});

  final PaymentTransaction row;

  @override
  Widget build(BuildContext context) {
    final refund = row.refundStatus;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(orderId: row.orderId),
          ),
        ),
        title: Text(
          "${row.orderNumber} · ${providerLabel(row.provider)}",
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
        subtitle: Text(
          [
            row.customer,
            if (row.payer != null) row.payer!,
            if (row.reference.isNotEmpty) row.reference,
            Dates.full(row.paidAt),
          ].join("\n"),
          style: const TextStyle(fontSize: 11.5, color: kMuted, height: 1.35),
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "₱${row.amount.toStringAsFixed(2)}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              refund == null
                  ? "net ₱${row.net.toStringAsFixed(2)}"
                  : "refund $refund",
              style: TextStyle(
                fontSize: 11,
                color: refund == null
                    ? kMuted
                    : refund == 'failed'
                        ? const Color(0xFFC62828)
                        : const Color(0xFFB26A00),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one number a tab is about, on ink.
class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({
    required this.label,
    required this.value,
    required this.caption,
  });

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kInk,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
