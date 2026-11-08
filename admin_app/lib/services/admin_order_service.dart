import '../models/admin_order_model.dart';
import '../models/dashboard_model.dart';
import 'api_client.dart';

class AdminOrderService {
  AdminOrderService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `GET /api/admin/dashboard/`
  Future<AdminDashboard> fetchDashboard() async {
    final data = await _client.get('/api/admin/dashboard/');
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected dashboard response from the server.');
    }
    return AdminDashboard.fromJson(data);
  }

  /// `GET /api/admin/orders/` — paginated, 25 per page.
  ///
  /// [statuses] maps to the `?status=` filter, which the backend accepts
  /// comma-separated. An unknown value is answered with a 400 naming the
  /// valid ones.
  Future<OrderPage> fetchOrders({
    List<String> statuses = const [],
    int page = 1,
  }) async {
    final data = await _client.get(
      '/api/admin/orders/',
      query: {
        if (statuses.isNotEmpty) 'status': statuses.join(','),
        if (page > 1) 'page': page,
      },
    );
    return OrderPage.fromJson(data);
  }

  /// `GET /api/admin/orders/{id}/`
  Future<AdminOrder> fetchOrder(int id) async {
    final data = await _client.get('/api/admin/orders/$id/');
    return _one(data);
  }

  /// `PATCH /api/admin/orders/{id}/status/`
  ///
  /// The server validates the transition against `allowed_transitions` and
  /// rejects an illegal jump with a message naming what is allowed next.
  Future<AdminOrder> updateStatus(
    int id,
    String status, {
    String cancelReason = '',
  }) async {
    final data = await _client.patch(
      '/api/admin/orders/$id/status/',
      body: {
        'status': status,
        if (cancelReason.isNotEmpty) 'cancel_reason': cancelReason,
      },
    );
    return _one(data);
  }

  /// `POST /api/admin/orders/{id}/assign/` — body `{"rider_id": N}`.
  ///
  /// Creates the Delivery and snapshots the rider's earnings. Refused when
  /// the order is unpaid (`pending_payment`), already finished, already
  /// assigned, or when the chosen rider is deactivated or mid-delivery — all
  /// of which arrive as a readable message.
  Future<AdminOrder> assignRider(int orderId, int riderId) async {
    final data = await _client.post(
      '/api/admin/orders/$orderId/assign/',
      body: {'rider_id': riderId},
    );
    return _one(data);
  }

  /// `POST /api/admin/orders/{id}/refund/`
  ///
  /// Retries a failed refund, asks the gateway about a pending one, or starts
  /// one for a cancelled paid order that never got one. Refused (400) when
  /// the order is not cancelled, was never paid, is COD, or is already
  /// refunded.
  Future<AdminOrder> retryRefund(int orderId) async {
    final data = await _client.post('/api/admin/orders/$orderId/refund/');
    return _one(data);
  }

  AdminOrder _one(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected order response from the server.');
    }
    return AdminOrder.fromJson(data);
  }
}
