import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/api_config.dart';

/// Which app this build is, as the backend's `/api/app-version/<app>/`
/// names it.
const String kUpdateAppKey = 'customer';

/// New builds are attached to the mobile repo's GitHub releases. A download
/// link from anywhere else is refused rather than handed to the browser.
const String kReleaseDownloadPrefix =
    'https://github.com/0jieE/yellow-Ribbon-Mobile/releases/download/';

/// A build published on the server.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    this.size,
    this.notes = '',
    this.publishedAt,
  });

  /// `1.0.1` — what people read.
  final String version;

  /// The `+N` build number. Only this decides whether a build is newer.
  final int versionCode;

  final String downloadUrl;

  /// Bytes, when the server knows.
  final int? size;

  final String notes;
  final DateTime? publishedAt;

  /// Null when the payload is unusable, so a malformed answer reads as
  /// "nothing to install" instead of an update that cannot download.
  static AppRelease? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final version = json['version'];
    final code = json['version_code'];
    final url = json['download_url'];
    if (version is! String || version.isEmpty) return null;
    if (code is! int) return null;
    if (url is! String ||
        !url.startsWith(kReleaseDownloadPrefix) ||
        !url.toLowerCase().endsWith('.apk')) {
      return null;
    }

    final size = json['size'];
    final notes = json['notes'];
    final published = json['published_at'];

    return AppRelease(
      version: version,
      versionCode: code,
      downloadUrl: url,
      size: size is int && size > 0 ? size : null,
      notes: notes is String ? notes.trim() : '',
      publishedAt: published is String ? DateTime.tryParse(published) : null,
    );
  }

  /// `18.4 MB`, or null when the size is unknown.
  String? get sizeLabel {
    final bytes = size;
    if (bytes == null) return null;
    final mb = bytes / (1024 * 1024);
    return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
  }
}

/// What is installed on this phone.
class InstalledBuild {
  const InstalledBuild({required this.version, required this.buildNumber});

  final String version;
  final int buildNumber;
}

/// The outcome of one check. Never an exception — a sleeping server or a
/// phone without signal is an ordinary result here.
sealed class UpdateCheck {
  const UpdateCheck(this.installed);

  final InstalledBuild installed;
}

class UpToDate extends UpdateCheck {
  const UpToDate(super.installed);
}

class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable(super.installed, this.release);

  final AppRelease release;
}

class UpdateCheckFailed extends UpdateCheck {
  const UpdateCheckFailed(super.installed);
}

/// `GET /api/app-version/<app>/` — no auth, so an expired session cannot
/// get in the way of finding the build that fixes it.
class UpdateService {
  UpdateService({
    http.Client? client,
    Future<InstalledBuild> Function()? installed,
  })  : _client = client ?? http.Client(),
        _installed = installed ?? _fromPackageInfo;

  static final UpdateService instance = UpdateService();

  final http.Client _client;
  final Future<InstalledBuild> Function() _installed;

  InstalledBuild? _cachedBuild;

  static Future<InstalledBuild> _fromPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    return InstalledBuild(
      version: info.version,
      buildNumber: int.tryParse(info.buildNumber) ?? 0,
    );
  }

  Future<InstalledBuild> installed() async =>
      _cachedBuild ??= await _installed();

  /// The free Render instance takes about 50 seconds to wake, so the
  /// default waits a little longer than that.
  Future<UpdateCheck> check({
    Duration timeout = const Duration(seconds: 70),
  }) async {
    final build = await installed();

    try {
      final response = await _client
          .get(ApiConfig.uri('/api/app-version/$kUpdateAppKey/'))
          .timeout(timeout);
      return evaluate(build, response.statusCode, response.body);
    } catch (_) {
      return UpdateCheckFailed(build);
    }
  }

  /// The decision on its own, so it can be tested without a server.
  ///
  /// 404 means nothing has been published yet, which is the same as being
  /// current. Anything else that is not a usable 200 is a failed check.
  static UpdateCheck evaluate(InstalledBuild build, int status, String body) {
    if (status == 404) return UpToDate(build);
    if (status != 200) return UpdateCheckFailed(build);

    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return UpdateCheckFailed(build);
    }

    final release = AppRelease.tryParse(json);
    if (release == null) return UpdateCheckFailed(build);

    return release.versionCode > build.buildNumber
        ? UpdateAvailable(build, release)
        : UpToDate(build);
  }
}
