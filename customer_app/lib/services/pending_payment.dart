import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers which order the customer went off to PayMongo to pay for.
///
/// The return deep link is a bare `yellowribbon://payment/success` — it
/// carries no order id, because PayMongo only knows the redirect URL it was
/// handed. Persisted rather than held in memory: the customer leaves for an
/// external browser, and Android is free to kill the app while they are gone.
class PendingPayment {
  PendingPayment({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static final PendingPayment instance = PendingPayment();

  final FlutterSecureStorage _storage;

  static const _key = 'pending_payment_order_id';

  Future<void> remember(int orderId) =>
      _storage.write(key: _key, value: '$orderId');

  Future<int?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  /// Reads and clears in one step, so a stale id cannot redirect a later
  /// launch that has nothing to do with a payment.
  Future<int?> take() async {
    final id = await read();
    await clear();
    return id;
  }

  Future<void> clear() => _storage.delete(key: _key);
}
