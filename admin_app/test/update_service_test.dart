import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:admin_app/services/update_service.dart';

const _installed = InstalledBuild(version: '1.0.1', buildNumber: 2);

String _release({
  int code = 3,
  String url = '${kReleaseDownloadPrefix}v1.0.2/App-1.0.2.apk',
  Object? size = 19293798,
}) =>
    jsonEncode({
      'app': kUpdateAppKey,
      'version': '1.0.2',
      'version_code': code,
      'download_url': url,
      'size': size,
      'sha256': null,
      'notes': '  Faster map  ',
      'published_at': '2026-11-08T10:00:00Z',
    });

void main() {
  group('UpdateService.evaluate', () {
    test('a higher build number is an update', () {
      final result = UpdateService.evaluate(_installed, 200, _release());
      expect(result, isA<UpdateAvailable>());
      final release = (result as UpdateAvailable).release;
      expect(release.version, '1.0.2');
      expect(release.notes, 'Faster map');
      expect(release.sizeLabel, '18 MB');
    });

    test('the same or a lower build number is current', () {
      expect(
        UpdateService.evaluate(_installed, 200, _release(code: 2)),
        isA<UpToDate>(),
      );
      expect(
        UpdateService.evaluate(_installed, 200, _release(code: 1)),
        isA<UpToDate>(),
      );
    });

    test('nothing published yet is current, not an error', () {
      expect(
        UpdateService.evaluate(_installed, 404, '{"error": "none"}'),
        isA<UpToDate>(),
      );
    });

    test('server errors and garbage are failed checks', () {
      expect(UpdateService.evaluate(_installed, 502, ''), isA<UpdateCheckFailed>());
      expect(
        UpdateService.evaluate(_installed, 200, '<html>'),
        isA<UpdateCheckFailed>(),
      );
      expect(UpdateService.evaluate(_installed, 200, '[]'), isA<UpdateCheckFailed>());
    });

    test('a download link outside the repo releases is refused', () {
      expect(
        UpdateService.evaluate(
          _installed,
          200,
          _release(url: 'https://example.com/App-1.0.2.apk'),
        ),
        isA<UpdateCheckFailed>(),
      );
      expect(
        UpdateService.evaluate(
          _installed,
          200,
          _release(url: '${kReleaseDownloadPrefix}v1.0.2/notes.txt'),
        ),
        isA<UpdateCheckFailed>(),
      );
    });

    test('an unknown size has no label', () {
      final result = UpdateService.evaluate(_installed, 200, _release(size: null));
      expect((result as UpdateAvailable).release.sizeLabel, isNull);
    });
  });

  group('UpdateService.check', () {
    test('asks for this app and decides from the answer', () async {
      Uri? asked;
      final service = UpdateService(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response(_release(), 200);
        }),
        installed: () async => _installed,
      );

      expect(await service.check(), isA<UpdateAvailable>());
      expect(asked!.path, '/api/app-version/$kUpdateAppKey/');
    });

    test('a network failure is a failed check, never an exception', () async {
      final service = UpdateService(
        client: MockClient((_) async => throw http.ClientException('offline')),
        installed: () async => _installed,
      );
      expect(await service.check(), isA<UpdateCheckFailed>());
    });

    test('a slow server times out as a failed check', () async {
      final service = UpdateService(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response(_release(), 200);
        }),
        installed: () async => _installed,
      );
      expect(
        await service.check(timeout: const Duration(milliseconds: 20)),
        isA<UpdateCheckFailed>(),
      );
    });
  });
}
