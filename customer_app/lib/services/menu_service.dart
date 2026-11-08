import '../models/menu_item.dart';
import 'api_client.dart';

class MenuService {
  MenuService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `GET /api/menu/`
  ///
  /// Requires a session — the endpoint is `IsAuthenticated`. Customers are
  /// served only `is_available=True` rows, filtered server-side in
  /// `get_queryset()`, so no client-side filtering is needed.
  Future<List<MenuItem>> fetchMenu() async {
    final data = await _client.get('/api/menu/');

    // The customer menu list is unpaginated, but tolerate a paginated shape
    // in case that ever changes.
    final rows = data is Map<String, dynamic> ? data['results'] : data;
    if (rows is! List) {
      throw ApiException('Unexpected menu response from the server.');
    }

    return rows
        .whereType<Map<String, dynamic>>()
        .map(MenuItem.fromJson)
        .toList();
  }

  /// `GET /api/menu/{id}/`
  ///
  /// The visibility rule is enforced in `get_queryset()`, so it applies to
  /// detail as well as list: an item the store has marked unavailable answers
  /// 404 for a customer, even if it is still sitting in their cart. That 404
  /// is worth surfacing — the order would be refused at placement for the
  /// same reason.
  Future<MenuItem> fetchOne(int id) async {
    final data = await _client.get('/api/menu/$id/');
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected menu response from the server.');
    }
    return MenuItem.fromJson(data);
  }
}
