import '../models/delivery_model.dart';
import 'api_client.dart';

class DeliveryService {
  DeliveryService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `GET /api/rider/deliveries/` — assigned and in-progress, oldest first.
  /// Scoped to the caller server-side; a rider never sees another's work.
  Future<List<Delivery>> fetchActive() => _list('/api/rider/deliveries/');

  /// `GET /api/rider/deliveries/history/` — delivered and failed.
  Future<List<Delivery>> fetchHistory() =>
      _list('/api/rider/deliveries/history/');

  Future<List<Delivery>> _list(String path) async {
    final data = await _client.get(path);
    final rows = data is Map<String, dynamic> ? data['results'] : data;
    if (rows is! List) {
      throw ApiException('Unexpected deliveries response from the server.');
    }
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Delivery.fromJson)
        .toList();
  }

  /// `GET /api/rider/deliveries/{id}/`
  Future<Delivery> fetchOne(int id) async {
    final data = await _client.get('/api/rider/deliveries/$id/');
    return _one(data);
  }

  /// `PATCH /api/rider/deliveries/{id}/status/`
  ///
  /// Walks `picked_up` → `in_transit` → `delivered`, or `failed` from any
  /// active state. The server validates the transition and, for `picked_up`,
  /// additionally refuses unless the kitchen has marked the order ready.
  Future<Delivery> updateStatus(
    int id,
    String status, {
    String failureReason = '',
  }) async {
    final data = await _client.patch(
      '/api/rider/deliveries/$id/status/',
      body: {
        'status': status,
        if (failureReason.isNotEmpty) 'failure_reason': failureReason,
      },
    );
    return _one(data);
  }

  /// `POST /api/rider/deliveries/{id}/proof/` — multipart photo upload.
  Future<Delivery> uploadProof(int id, String filePath) async {
    final data = await _client.postFile(
      '/api/rider/deliveries/$id/proof/',
      field: 'proof_of_delivery',
      filePath: filePath,
    );
    return _one(data);
  }

  Delivery _one(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected delivery response from the server.');
    }
    return Delivery.fromJson(data);
  }
}
