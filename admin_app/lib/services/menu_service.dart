import '../models/menu_item.dart';
import 'api_client.dart';

/// Full CRUD against `/api/menu/`.
///
/// Reads are open to any authenticated user; writes are `IsAdminUser`.
class MenuService {
  MenuService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `GET /api/menu/` — unpaginated. An admin sees unavailable items too;
  /// the visibility filter in `get_queryset()` only narrows for customers.
  Future<List<MenuItem>> fetchAll() async {
    final data = await _client.get('/api/menu/');
    final rows = data is Map<String, dynamic> ? data['results'] : data;
    if (rows is! List) {
      throw ApiException('Unexpected menu response from the server.');
    }
    return rows
        .whereType<Map<String, dynamic>>()
        .map(MenuItem.fromJson)
        .toList();
  }

  /// `POST /api/menu/`
  ///
  /// Sent as multipart whenever a photo is attached, and as JSON otherwise —
  /// there is no point streaming a multipart body for four text fields.
  Future<MenuItem> create({
    required String name,
    required String description,
    required String price,
    required bool isAvailable,
    String? photoPath,
  }) async {
    final fields = {
      'name': name,
      'description': description,
      'price': price,
      'is_available': isAvailable.toString(),
    };

    final data = photoPath == null
        ? await _client.post('/api/menu/', body: fields)
        : await _client.sendFile(
            'POST',
            '/api/menu/',
            fields: fields,
            field: 'photo',
            filePath: photoPath,
          );

    return _one(data);
  }

  /// `PATCH /api/menu/{id}/` — partial, so only the supplied fields change.
  ///
  /// Note the backend defines no PUT; `http_method_names` allows patch only.
  Future<MenuItem> update(
    int id, {
    String? name,
    String? description,
    String? price,
    bool? isAvailable,
    String? photoPath,
  }) async {
    final fields = <String, String>{
      'name': ?name,
      'description': ?description,
      'price': ?price,
      'is_available': ?isAvailable?.toString(),
    };

    final data = photoPath == null
        ? await _client.patch('/api/menu/$id/', body: fields)
        : await _client.sendFile(
            'PATCH',
            '/api/menu/$id/',
            fields: fields,
            field: 'photo',
            filePath: photoPath,
          );

    return _one(data);
  }

  /// Convenience for the availability switch on the list.
  Future<MenuItem> setAvailability(int id, bool isAvailable) =>
      update(id, isAvailable: isAvailable);

  /// `DELETE /api/menu/{id}/`
  ///
  /// An item that appears on existing orders cannot be deleted — historical
  /// receipts must not change — and the server answers 409 telling the admin
  /// to mark it unavailable instead. That message is surfaced as-is.
  Future<void> delete(int id) => _client.delete('/api/menu/$id/');

  MenuItem _one(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected menu response from the server.');
    }
    return MenuItem.fromJson(data);
  }
}
