import '../models/payment_report.dart';
import '../models/report_model.dart';
import 'api_client.dart';

/// The three date-range reports under `/api/admin/reports/`.
///
/// The dashboard answers "how are we doing today"; these answer "how did the
/// month go". Both recognise revenue on delivery, so the figures agree.
class ReportService {
  ReportService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// `GET /api/admin/reports/sales/`
  Future<SalesReport> fetchSales(DateRange range) async =>
      SalesReport.fromJson(await _get('/api/admin/reports/sales/', range));

  /// `GET /api/admin/reports/riders/`
  Future<RiderReport> fetchRiders(DateRange range) async =>
      RiderReport.fromJson(await _get('/api/admin/reports/riders/', range));

  /// `GET /api/admin/reports/menu/`
  Future<MenuReport> fetchMenu(DateRange range) async =>
      MenuReport.fromJson(await _get('/api/admin/reports/menu/', range));

  /// `GET /api/admin/reports/payments/`
  Future<PaymentReport> fetchPayments(DateRange range) async =>
      PaymentReport.fromJson(await _get('/api/admin/reports/payments/', range));

  /// `GET /api/admin/reports/payments/transactions/` — newest first, paged.
  Future<PaymentTransactionPage> fetchTransactions(
    DateRange range, {
    int page = 1,
    int? pageSize,
  }) async {
    final data = await _client.get(
      '/api/admin/reports/payments/transactions/',
      query: {
        'start': range.startParam,
        'end': range.endParam,
        'page': '$page',
        'page_size': ?pageSize?.toString(),
      },
    );
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected transactions response from the server.');
    }
    return PaymentTransactionPage.fromJson(data);
  }

  /// The range is always sent explicitly rather than relying on the server's
  /// 30-day default: the picker shows a window, and it has to be the window
  /// the numbers came from.
  Future<Map<String, dynamic>> _get(String path, DateRange range) async {
    final data = await _client.get(
      path,
      query: {'start': range.startParam, 'end': range.endParam},
    );

    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected report response from the server.');
    }
    return data;
  }
}
