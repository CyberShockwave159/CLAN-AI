import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fetches the deployed `version.json` and returns its `version` string, or
/// null when the fetch fails (offline, missing file, parse error).
typedef PwaVersionFetcher = Future<String?> Function();

/// Reads the app's own `version.json` (resolved against the page's base href,
/// so sub-path hosting like `/CLAN-AI/` works). Non-web platforms and failures
/// yield null.
Future<String?> fetchPwaVersion() async {
  if (!kIsWeb) {
    return null;
  }
  try {
    final uri = Uri.base
        .resolve('version.json')
        .replace(queryParameters: {'_': '${DateTime.now().millisecondsSinceEpoch}'});
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      return null;
    }
    final info = jsonDecode(response.body);
    if (info is! Map) {
      return null;
    }
    final version = info['version'];
    return version is String && version.isNotEmpty ? version : null;
  } catch (_) {
    return null;
  }
}

/// Polls the deployed `version.json` and reports when a newer build is live.
///
/// Web-only in practice ([start] is invoked from `main.dart` under `kIsWeb`);
/// natively it is never constructed. The baseline is the first version the app
/// boots against — established on the first *successful* fetch, so an offline
/// boot never warns spuriously. Once an update is detected, listeners are
/// notified exactly once and polling stops (the UI offers a reload).
class PwaUpdateChecker extends ChangeNotifier {
  PwaUpdateChecker({
    this.checkInterval = const Duration(minutes: 5),
    PwaVersionFetcher? versionFetcher,
  }) : _versionFetcher = versionFetcher ?? fetchPwaVersion;

  final Duration checkInterval;
  final PwaVersionFetcher _versionFetcher;

  Timer? _timer;
  bool _started = false;
  bool _updateNotified = false;
  String? _baselineVersion;

  /// Version the app booted against (null until the first successful fetch).
  String? get baselineVersion => _baselineVersion;

  /// True after a newer version has been reported to listeners.
  bool get updateNotified => _updateNotified;

  /// Kicks off the polling loop (idempotent) and runs an immediate check.
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _timer = Timer.periodic(checkInterval, (_) => checkNow());
    checkNow();
  }

  /// Performs a single check against the deployed version.
  Future<void> checkNow() async {
    if (_updateNotified) {
      return;
    }
    final deployed = await _versionFetcher();
    if (deployed == null || deployed.isEmpty) {
      return;
    }
    if (_baselineVersion == null) {
      _baselineVersion = deployed;
      return;
    }
    if (deployed != _baselineVersion) {
      _updateNotified = true;
      _timer?.cancel();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}