/// `GET /api/admin/reports/payments/` — where the money went, per gateway.
///
/// A payment counts on the day it was paid and a refund on the day it was
/// refunded. `net = gross - fees - refunds`; gateway fees are not returned on
/// a refund, so a fully refunded order leaves a small negative net.
class PaymentProviderRow {
  PaymentProviderRow({
    required this.provider,
    required this.label,
    required this.count,
    required this.gross,
    required this.fees,
    required this.refundCount,
    required this.refunds,
    required this.net,
  });

  /// `paymongo`, `maya` or `cod`.
  final String provider;
  final String label;
  final int count;
  final double gross;
  final double fees;
  final int refundCount;
  final double refunds;
  final double net;

  factory PaymentProviderRow.fromJson(Map<String, dynamic> json) =>
      PaymentProviderRow(
        provider: (json['provider'] ?? '') as String,
        label: (json['label'] ?? json['provider'] ?? '') as String,
        count: _toInt(json['count']),
        gross: _toDouble(json['gross']),
        fees: _toDouble(json['fees']),
        refundCount: _toInt(json['refund_count']),
        refunds: _toDouble(json['refunds']),
        net: _toDouble(json['net']),
      );
}

class PaymentReport {
  PaymentReport({
    required this.providers,
    required this.totals,
    required this.outstandingRefundCount,
    required this.outstandingRefundAmount,
  });

  /// Always all three providers, zeros included.
  final List<PaymentProviderRow> providers;
  final PaymentProviderRow totals;

  /// Refunds still pending or failed, of any date — the ones to chase.
  final int outstandingRefundCount;
  final double outstandingRefundAmount;

  factory PaymentReport.fromJson(Map<String, dynamic> json) {
    final rows = json['providers'];
    final totals = json['totals'];
    final outstanding = json['refunds_outstanding'];
    final outstandingMap =
        outstanding is Map<String, dynamic> ? outstanding : const {};

    return PaymentReport(
      providers: rows is List
          ? rows
              .whereType<Map<String, dynamic>>()
              .map(PaymentProviderRow.fromJson)
              .toList()
          : const [],
      totals: PaymentProviderRow.fromJson({
        'provider': 'total',
        'label': 'Total',
        ...(totals is Map<String, dynamic> ? totals : const {}),
      }),
      outstandingRefundCount: _toInt(outstandingMap['count']),
      outstandingRefundAmount: _toDouble(outstandingMap['amount']),
    );
  }
}

/// One settled payment, from `GET /api/admin/reports/payments/transactions/`.
class PaymentTransaction {
  PaymentTransaction({
    required this.orderId,
    required this.orderNumber,
    required this.customer,
    required this.invoiceNumber,
    required this.provider,
    required this.reference,
    required this.amount,
    required this.fee,
    required this.net,
    this.payer,
    this.paidAt,
    this.refundStatus,
  });

  final int orderId;
  final String orderNumber;
  final String customer;
  final String invoiceNumber;
  final String provider;
  final String reference;
  final String? payer;
  final double amount;

  /// Snapshotted at settlement, so later rate changes don't rewrite history.
  final double fee;
  final double net;
  final DateTime? paidAt;

  /// Null when the payment was never refunded.
  final String? refundStatus;

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    final refund = json['refund'];
    return PaymentTransaction(
      orderId: _toInt(json['order_id']),
      orderNumber: (json['order_number'] ?? '') as String,
      customer: '${json['customer'] ?? ''}',
      invoiceNumber: (json['invoice_number'] ?? '') as String,
      provider: (json['provider'] ?? '') as String,
      reference: '${json['reference'] ?? ''}',
      payer: json['payer'] as String?,
      amount: _toDouble(json['amount']),
      fee: _toDouble(json['fee']),
      net: _toDouble(json['net']),
      paidAt: DateTime.tryParse('${json['paid_at']}'),
      refundStatus:
          refund is Map<String, dynamic> ? refund['status'] as String? : null,
    );
  }
}

class PaymentTransactionPage {
  PaymentTransactionPage({required this.count, required this.results, this.next});

  final int count;
  final List<PaymentTransaction> results;
  final String? next;

  bool get hasMore => next != null;

  factory PaymentTransactionPage.fromJson(Map<String, dynamic> json) {
    final rows = json['results'];
    return PaymentTransactionPage(
      count: _toInt(json['count']),
      next: json['next'] as String?,
      results: rows is List
          ? rows
              .whereType<Map<String, dynamic>>()
              .map(PaymentTransaction.fromJson)
              .toList()
          : const [],
    );
  }
}

/// How a provider id reads to the store.
String providerLabel(String provider) => switch (provider) {
      'paymongo' => 'GCash',
      'maya' => 'Maya',
      'cod' => 'Cash on delivery',
      _ => provider,
    };

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
