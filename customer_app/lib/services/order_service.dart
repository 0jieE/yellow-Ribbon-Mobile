import '../models/cart_item.dart';
import '../models/order_model.dart';
import 'api_client.dart';

class OrderService {
  OrderService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `POST /api/orders/`
  ///
  /// Sends only what the server needs: which menu items, how many, and where
  /// to deliver. Prices, subtotal, delivery fee, total and the order number
  /// are all produced server-side — the client cannot influence them.
  ///
  /// The backend geofences [latitude]/[longitude] against the Kidapawan City
  /// service area *before* creating anything, and answers 400 with a readable
  /// message when the address is out of range.
  Future<AppOrder> placeOrder({
    required List<CartItem> items,
    required String deliveryAddress,
    required String latitude,
    required String longitude,
    required String paymentType,
    String deliveryNotes = '',
  }) async {
    final data = await _client.post(
      '/api/orders/',
      body: {
        'items': items.map((item) => item.toOrderItemJson()).toList(),
        'delivery_address': deliveryAddress,
        'delivery_latitude': latitude,
        'delivery_longitude': longitude,
        'delivery_notes': deliveryNotes,
        'payment_type': paymentType,
      },
    );

    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected order response from the server.');
    }
    return AppOrder.fromJson(data);
  }

  /// `GET /api/orders/` — the caller's own orders, newest first per the
  /// backend's ordering. Scoped server-side; there is no way to read anyone
  /// else's.
  Future<List<AppOrder>> fetchOrders() async {
    final data = await _client.get('/api/orders/');
    final rows = data is Map<String, dynamic> ? data['results'] : data;
    if (rows is! List) {
      throw ApiException('Unexpected orders response from the server.');
    }
    return rows
        .whereType<Map<String, dynamic>>()
        .map(AppOrder.fromJson)
        .toList();
  }

  /// `GET /api/orders/{id}/`
  Future<AppOrder> fetchOrder(int id) async {
    final data = await _client.get('/api/orders/$id/');
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected order response from the server.');
    }
    return AppOrder.fromJson(data);
  }

  /// `POST /api/orders/{id}/cancel/` — permitted only while the order is
  /// still pending; the server rejects anything later with a 400.
  Future<AppOrder> cancelOrder(int id, {String reason = ''}) async {
    final data = await _client.post(
      '/api/orders/$id/cancel/',
      body: {'cancel_reason': reason},
    );
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected cancellation response from the server.');
    }
    return AppOrder.fromJson(data);
  }

  /// `GET /api/orders/delivery-quote/?lat=&lng=` — what delivering to this
  /// pin costs.
  ///
  /// The store can charge per km, so the fee depends on the address. The
  /// order is charged exactly the quoted fee; the server recomputes it on
  /// placement rather than trusting this.
  Future<DeliveryQuote> deliveryQuote({
    required String latitude,
    required String longitude,
  }) async {
    final data = await _client.get(
      '/api/orders/delivery-quote/',
      query: {'lat': latitude, 'lng': longitude},
    );
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected delivery quote from the server.');
    }
    return DeliveryQuote.fromJson(data);
  }
}

class DeliveryQuote {
  DeliveryQuote({
    required this.deliveryFee,
    required this.distanceKm,
    required this.withinServiceArea,
    required this.mode,
  });

  final double deliveryFee;
  final double distanceKm;
  final bool withinServiceArea;

  /// `flat` or `per_km`.
  final String mode;

  bool get isPerKm => mode == 'per_km';

  factory DeliveryQuote.fromJson(Map<String, dynamic> json) => DeliveryQuote(
        deliveryFee: double.tryParse('${json['delivery_fee']}') ?? 0,
        distanceKm: double.tryParse('${json['distance_km']}') ?? 0,
        withinServiceArea: (json['within_service_area'] ?? false) as bool,
        mode: (json['mode'] ?? 'flat') as String,
      );
}
