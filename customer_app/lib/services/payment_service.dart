import 'api_client.dart';

/// The result of asking the backend to start an online payment.
class CheckoutSession {
  CheckoutSession({
    required this.orderNumber,
    required this.amount,
    required this.checkoutUrl,
    required this.provider,
  });

  final String orderNumber;
  final String amount;

  /// The gateway's hosted page — PayMongo's for GCash, Maya's for Maya. The
  /// customer pays there and is returned to the app through the
  /// `yellowribbon://payment/...` deep link.
  final String checkoutUrl;

  /// `paymongo` or `maya`.
  final String provider;

  factory CheckoutSession.fromJson(Map<String, dynamic> json) => CheckoutSession(
        orderNumber: (json['order_number'] ?? '') as String,
        amount: '${json['amount'] ?? ''}',
        checkoutUrl: (json['checkout_url'] ?? '') as String,
        provider: (json['provider'] ?? '') as String,
      );
}

/// `POST /api/payments/sync/` — where the gateway says the payment stands.
class PaymentSync {
  PaymentSync({
    required this.paid,
    required this.settled,
    required this.gatewayStatus,
  });

  /// The order is paid (now or earlier).
  final bool paid;

  /// This very call settled it — the moment to tell the customer.
  final bool settled;

  /// Maya's own status, e.g. `PAYMENT_SUCCESS`, `PENDING_TOKEN`; empty when
  /// nothing was looked up.
  final String gatewayStatus;

  factory PaymentSync.fromJson(Map<String, dynamic> json) => PaymentSync(
        paid: (json['paid'] ?? false) as bool,
        settled: (json['settled'] ?? false) as bool,
        gatewayStatus: (json['gateway_status'] ?? '') as String,
      );
}

class PaymentService {
  PaymentService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `POST /api/payments/checkout/` — body `{"order_id": N}`.
  ///
  /// Only valid for a GCash or Maya order still sitting in `pending_payment`.
  /// The backend reuses a live checkout rather than opening a new one on
  /// every tap, and replaces a dead one, so calling this twice is safe.
  Future<CheckoutSession> startCheckout(int orderId) async {
    final data = await _client.post(
      '/api/payments/checkout/',
      body: {'order_id': orderId},
    );
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected checkout response from the server.');
    }

    final session = CheckoutSession.fromJson(data);
    if (session.checkoutUrl.isEmpty) {
      throw ApiException('The server did not return a payment link.');
    }
    return session;
  }

  /// `POST /api/payments/sync/` — body `{"order_id": N}`.
  ///
  /// Maya sends us no webhook, so this is how a Maya payment is confirmed:
  /// the server asks Maya with its secret key and settles the order if Maya
  /// says it was paid in full. Safe to call repeatedly.
  Future<PaymentSync> sync(int orderId) async {
    final data = await _client.post(
      '/api/payments/sync/',
      body: {'order_id': orderId},
    );
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected payment status from the server.');
    }
    return PaymentSync.fromJson(data);
  }
}
