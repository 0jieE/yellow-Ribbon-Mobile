import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

const _amber = Color(0xFFFFC107);
const _ink = Color(0xFF1F1F1F);

/// Opens the APK link in the browser, which downloads it; tapping the
/// finished download hands it to Android's installer. Returns false when no
/// app could open the link.
Future<bool> openReleaseDownload(AppRelease release) async {
  try {
    return await launchUrl(
      Uri.parse(release.downloadUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// "Update available" with the release notes. Resolves true when the
/// download was started.
Future<bool> showUpdateDialog(
  BuildContext context,
  AppRelease release, {
  required InstalledBuild installed,
}) async {
  final start = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.system_update, color: _ink, size: 30),
      title: Text("Update available, version ${release.version}"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You have version ${installed.version}."
              "${release.sizeLabel == null ? '' : ' Download size ${release.sizeLabel}.'}",
              style: const TextStyle(fontSize: 13.5),
            ),
            if (release.notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                "What's new",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                release.notes,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              "The download opens in your browser. When it finishes, tap "
              "the file and choose Install.",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text("Later"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(96, 44),
            backgroundColor: _amber,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text("Update"),
        ),
      ],
    ),
  );

  if (start != true) return false;

  final opened = await openReleaseDownload(release);
  if (!opened && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text("Couldn't open the download link.")),
    );
  }
  return opened;
}

/// Checks quietly on launch and when the app comes back to the
/// foreground, and offers the update when there is one.
///
/// Nothing is ever shown for a failed check, and "Later" holds for that
/// version until the app is next started.
class UpdatePrompter with WidgetsBindingObserver {
  UpdatePrompter._();

  static final UpdatePrompter instance = UpdatePrompter._();

  /// How long a resume waits after the last check before checking again.
  static const Duration resumeInterval = Duration(hours: 4);

  GlobalKey<NavigatorState>? _navigatorKey;
  DateTime? _lastCheck;
  int? _declinedCode;
  bool _checking = false;
  bool _dialogOpen = false;

  void start(GlobalKey<NavigatorState> navigatorKey) {
    if (_navigatorKey != null) return;
    _navigatorKey = navigatorKey;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last != null && DateTime.now().difference(last) < resumeInterval) {
      return;
    }
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking || _dialogOpen) return;
    _checking = true;

    try {
      final result = await UpdateService.instance.check();
      // A failed check does not count, so the next resume tries again.
      if (result is! UpdateCheckFailed) _lastCheck = DateTime.now();
      if (result is! UpdateAvailable) return;
      if (result.release.versionCode == _declinedCode) return;

      final context = _navigatorKey?.currentContext;
      if (context == null || !context.mounted) return;

      _dialogOpen = true;
      final started = await showUpdateDialog(
        context,
        result.release,
        installed: result.installed,
      );
      if (!started) _declinedCode = result.release.versionCode;
    } finally {
      _dialogOpen = false;
      _checking = false;
    }
  }
}

/// The "Check for updates" row: the installed version, and every state of
/// a manual check.
class AppUpdateTile extends StatefulWidget {
  const AppUpdateTile({super.key});

  @override
  State<AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends State<AppUpdateTile> {
  InstalledBuild? _installed;
  UpdateCheck? _result;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    UpdateService.instance.installed().then((build) {
      if (mounted) setState(() => _installed = build);
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final result = await UpdateService.instance.check();
    if (!mounted) return;
    setState(() {
      _result = result;
      _installed = result.installed;
      _checking = false;
    });
  }

  Future<void> _update(UpdateAvailable available) async {
    await showUpdateDialog(
      context,
      available.release,
      installed: available.installed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final installed = _installed;
    final result = _result;
    final versionText =
        installed == null ? "" : "Version ${installed.version}";

    final String subtitle;
    final Widget trailing;
    VoidCallback? onTap;

    if (_checking) {
      subtitle = "Checking for updates…";
      trailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (result is UpdateAvailable) {
      subtitle = "Version ${result.release.version} is available";
      trailing = FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _amber,
          foregroundColor: Colors.black,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => _update(result),
        child: const Text("Update"),
      );
      onTap = () => _update(result);
    } else if (result is UpToDate) {
      subtitle = "You have the latest version (${result.installed.version})";
      trailing = const Icon(Icons.check_circle, color: Color(0xFF2E7D32));
      onTap = _check;
    } else if (result is UpdateCheckFailed) {
      subtitle = "Couldn't check for updates. Check your connection.";
      trailing = TextButton(onPressed: _check, child: const Text("Retry"));
      onTap = _check;
    } else {
      subtitle = versionText;
      trailing = const Icon(Icons.chevron_right);
      onTap = _check;
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        result is UpdateAvailable ? Icons.system_update : Icons.update,
        color: result is UpdateAvailable ? _ink : Colors.grey.shade700,
      ),
      title: const Text(
        "Check for updates",
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
      ),
      subtitle: Text(
        subtitle.isEmpty ? " " : subtitle,
        style: TextStyle(
          fontSize: 12.5,
          color: result is UpdateCheckFailed
              ? const Color(0xFFC62828)
              : Colors.grey.shade700,
        ),
      ),
      trailing: trailing,
      onTap: _checking ? null : onTap,
    );
  }
}
