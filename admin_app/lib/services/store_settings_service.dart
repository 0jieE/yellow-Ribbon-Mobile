import '../models/store_settings.dart';
import 'api_client.dart';

class StoreSettingsService {
  StoreSettingsService({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const _path = '/api/admin/store-settings/';

  /// `GET /api/admin/store-settings/`
  Future<StoreSettings> fetch() async => _parse(await _client.get(_path));

  /// `PATCH /api/admin/store-settings/` — partial; send only what changed.
  ///
  /// A rejected value comes back as an [ApiException] whose `fields` map
  /// carries the per-field messages, keyed by the JSON names.
  Future<StoreSettings> update(Map<String, String> changes) async =>
      _parse(await _client.patch(_path, body: changes));

  StoreSettings _parse(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected store settings response from the server.');
    }
    return StoreSettings.fromJson(data);
  }
}
