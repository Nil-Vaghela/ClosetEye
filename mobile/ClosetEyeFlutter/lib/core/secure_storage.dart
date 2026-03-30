import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _tokenKey = 'closeteye_token';
  static const _userKey  = 'closeteye_user';

  static Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  static Future<String?> getToken() =>
      _storage.read(key: _tokenKey);

  static Future<void> saveUser(AppUser user) =>
      _storage.write(key: _userKey, value: jsonEncode(user.toJson()));

  static Future<AppUser?> getUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    return AppUser.fromJson(jsonDecode(raw));
  }

  static Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
