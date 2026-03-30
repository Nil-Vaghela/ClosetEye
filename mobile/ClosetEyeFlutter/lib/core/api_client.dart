import 'dart:convert';
import 'package:http/http.dart' as http;
import 'secure_storage.dart';

/// Change this to your Mac's LAN IP when testing on device.
const _baseUrl = 'http://10.0.0.14:8000/api/v1';

class ApiClient {
  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await SecureStorage.getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> phoneLogin(String firebaseToken) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/phone'),
      headers: await _headers(auth: false),
      body: jsonEncode({'firebase_token': firebaseToken}),
    );
    return _parse(res);
  }

  static Future<Map<String, dynamic>> updateProfile({
    required String name,
    String? avatarUrl,
  }) async {
    final res = await http.patch(
      Uri.parse('$_baseUrl/auth/profile'),
      headers: await _headers(),
      body: jsonEncode({
        'full_name': name,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      }),
    );
    return _parse(res);
  }

  // ── Wardrobe ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getWardrobe() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/wardrobe'),
      headers: await _headers(),
    );
    return _parse(res) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> addItem({
    required String imageBase64,
    required String category,
    String? color,
    String? brand,
    String? notes,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/wardrobe'),
      headers: await _headers(),
      body: jsonEncode({
        'image_base64': imageBase64,
        'category': category,
        if (color != null) 'color': color,
        if (brand != null) 'brand': brand,
        if (notes != null) 'notes': notes,
      }),
    );
    return _parse(res);
  }

  static Future<void> deleteItem(String id) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/wardrobe/$id'),
      headers: await _headers(),
    );
    if (res.statusCode >= 400) throw Exception('Delete failed');
  }

  // ── Outfits ───────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getSuggestions() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/suggestions'),
      headers: await _headers(),
    );
    return _parse(res) as List<dynamic>;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static dynamic _parse(http.Response res) {
    // Guard against non-JSON responses (HTML error pages, plain-text 500s)
    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      throw Exception(
        'Server error ${res.statusCode}: ${res.body.length > 120 ? res.body.substring(0, 120) : res.body}',
      );
    }
    if (res.statusCode >= 400) {
      throw Exception(body['detail'] ?? 'Request failed (${res.statusCode})');
    }
    return body;
  }
}
