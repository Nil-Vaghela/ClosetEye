import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Runtime-configurable server URL.
///
/// Priority:
///   1. Value set via [setServerUrl] (persisted in SecureStorage)
///   2. Compile-time default from --dart-define=SERVER_URL=...
///   3. Hard-coded LAN fallback
///
/// Usage
/// -----
///   // In main() before runApp:
///   await AppConfig.init();
///
///   // Anywhere in the app:
///   final url = AppConfig.baseUrl;  // e.g.  https://abc.ngrok-free.app/api/v1
///
///   // From Dev Settings screen:
///   await AppConfig.setServerUrl('https://abc.ngrok-free.app');
class AppConfig {
  AppConfig._();

  static const _storage  = FlutterSecureStorage();
  static const _storeKey = 'ce_server_url';

  /// Default LAN address — used when no override has been saved.
  /// Change this to your Mac's current LAN IP if you rebuild.
  static const _defaultServer = 'http://10.0.0.14:8000';

  // Compile-time override:  flutter run --dart-define=SERVER_URL=https://...
  static const _compiledServer =
      String.fromEnvironment('SERVER_URL', defaultValue: _defaultServer);

  static String _serverUrl = _compiledServer;

  // ── Public getters ──────────────────────────────────────────────────────────

  /// e.g.  "https://abc.ngrok-free.app"  or  "http://10.0.0.14:8000"
  static String get serverUrl => _serverUrl;

  /// e.g.  "https://abc.ngrok-free.app/api/v1"
  static String get baseUrl => '$_serverUrl/api/v1';

  /// True when a custom (non-default) URL is stored.
  static bool get isCustomUrl => _serverUrl != _defaultServer;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Call once in main() before runApp().
  static Future<void> init() async {
    final stored = await _storage.read(key: _storeKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _serverUrl = _cleanUrl(stored);
    }
  }

  // ── Mutation ────────────────────────────────────────────────────────────────

  /// Persist a new server URL and apply it immediately.
  static Future<void> setServerUrl(String url) async {
    final clean = _cleanUrl(url);
    _serverUrl = clean;
    await _storage.write(key: _storeKey, value: clean);
  }

  /// Clear override, revert to compiled default.
  static Future<void> reset() async {
    _serverUrl = _compiledServer;
    await _storage.delete(key: _storeKey);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Strip trailing slash, trim whitespace.
  static String _cleanUrl(String raw) =>
      raw.trim().replaceAll(RegExp(r'/+$'), '');

  /// Fix image URLs stored with "localhost" origin (Docker stores them this way).
  static String fixUrl(String url) => url
      .replaceFirst('http://localhost:8000', _serverUrl)
      .replaceFirst('https://localhost:8000', _serverUrl);

  // ── Quick-pick presets ───────────────────────────────────────────────────────

  static const List<_ServerPreset> presets = [
    _ServerPreset(
      label: 'LAN (home Wi-Fi)',
      hint: 'http://10.0.0.14:8000',
      icon: '🏠',
    ),
    _ServerPreset(
      label: 'ngrok tunnel',
      hint: 'https://xxxx-xx-xx.ngrok-free.app',
      icon: '🌐',
    ),
    _ServerPreset(
      label: 'Tailscale',
      hint: 'http://100.x.x.x:8000',
      icon: '🔒',
    ),
    _ServerPreset(
      label: 'Production',
      hint: 'https://api.closeteye.app',
      icon: '🚀',
    ),
  ];
}

class _ServerPreset {
  final String label;
  final String hint;
  final String icon;
  const _ServerPreset({required this.label, required this.hint, required this.icon});
}
