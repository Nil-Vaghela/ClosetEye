import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'secure_storage.dart';
import 'app_config.dart';

/// Detect MIME type from file path extension.
/// Defaults to image/jpeg — image_picker always outputs JPEG when imageQuality is set.
MediaType _imageMimeType(String filePath) {
  final ext = filePath.split('.').last.toLowerCase();
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heic',
  };
  return MediaType.parse(map[ext] ?? 'image/jpeg');
}

/// Dynamic base URL — reads from AppConfig which can be changed at runtime
/// via the Dev Settings screen (Profile → Server Settings).
String get _baseUrl   => AppConfig.baseUrl;
String get _serverOrigin => AppConfig.serverUrl;

/// Fix image URLs that the backend stored with 'localhost' (works in Docker
/// but not from a real device — delegates to AppConfig.fixUrl).
String fixUrl(String url) => AppConfig.fixUrl(url);

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

  // ── User profile ──────────────────────────────────────────────────────────

  /// Fetch the current user's full profile (including body model status).
  static Future<Map<String, dynamic>> getMe() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/users/me'),
      headers: await _headers(),
    );
    return _parse(res);
  }

  // ── Body Model ────────────────────────────────────────────────────────────

  /// Upload a reference photo + measurements to create the user's body model.
  /// Uses multipart/form-data since we're sending a file alongside fields.
  static Future<Map<String, dynamic>> createBodyModel({
    required File photo,
    required int heightCm,
    required int weightKg,
    required String bodyType,
  }) async {
    final token = await SecureStorage.getToken();
    final uri = Uri.parse('$_baseUrl/users/me/body-model');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['height_cm'] = heightCm.toString()
      ..fields['weight_kg'] = weightKg.toString()
      ..fields['body_type'] = bodyType
      ..files.add(await http.MultipartFile.fromPath(
        'photo',
        photo.path,
        contentType: _imageMimeType(photo.path),
      ));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _parse(res);
  }

  /// Fetch the current user's body model status.
  static Future<Map<String, dynamic>> getBodyModel() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/users/me/body-model'),
      headers: await _headers(),
    );
    return _parse(res);
  }

  // ── Wardrobe ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getWardrobe() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/wardrobe/items'),
      headers: await _headers(),
    );
    return _parse(res) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> uploadItem(File photo) async {
    final token = await SecureStorage.getToken();
    final uri = Uri.parse('$_baseUrl/wardrobe/items');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath(
        'image',
        photo.path,
        contentType: _imageMimeType(photo.path),
      ));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _parse(res);
  }

  static Future<Map<String, dynamic>> getWardrobeItem(String id) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/wardrobe/items/$id'),
      headers: await _headers(),
    );
    return _parse(res);
  }

  static Future<Map<String, dynamic>> updateItem(
    String id,
    Map<String, dynamic> fields,
  ) async {
    final res = await http.patch(
      Uri.parse('$_baseUrl/wardrobe/items/$id'),
      headers: await _headers(),
      body: jsonEncode(fields),
    );
    return _parse(res);
  }

  static Future<void> deleteItem(String id) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/wardrobe/items/$id'),
      headers: await _headers(),
    );
    if (res.statusCode >= 400) throw Exception('Delete failed');
  }

  /// Upload a photo and extract all visible clothing items using AI.
  /// Returns { "original_image_url": "…", "items": [ … ] }.
  static Future<Map<String, dynamic>> extractItems(File photo) async {
    final token = await SecureStorage.getToken();
    final uri = Uri.parse('$_baseUrl/wardrobe/extract-items');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath(
        'image',
        photo.path,
        contentType: _imageMimeType(photo.path),
      ));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _parse(res);
  }

  /// Add selected extracted items to the wardrobe in one call.
  static Future<List<dynamic>> batchAddItems({
    required String originalImageUrl,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/wardrobe/batch-add'),
      headers: await _headers(),
      body: jsonEncode({
        'original_image_url': originalImageUrl,
        'items': items,
      }),
    );
    return _parse(res) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getStyleDna() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/wardrobe/style-dna'),
      headers: await _headers(),
    );
    return _parse(res);
  }

  static Future<Map<String, dynamic>> getCapsuleScore() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/wardrobe/capsule-score'),
      headers: await _headers(),
    );
    return _parse(res);
  }

  static Future<List<dynamic>> getCostPerWear() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/wardrobe/cost-per-wear'),
      headers: await _headers(),
    );
    return _parse(res) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getGapAnalysis() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/wardrobe/gap-analysis'),
      headers: await _headers(),
    );
    return _parse(res);
  }

  // ── Try-on ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getTryOnPreview({
    required List<String> itemIds,
    List<String>? shoppingItemIds,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/tryon/preview'),
      headers: await _headers(),
      body: jsonEncode({
        'item_ids': itemIds,
        if (shoppingItemIds != null) 'shopping_item_ids': shoppingItemIds,
      }),
    );
    return _parse(res);
  }

  /// POST /tryon/flatlay — generate a clean product-style outfit flatlay image.
  /// No model/body — pure fashion editorial board.
  /// Returns { "flatlay_url": "…" }.
  static Future<Map<String, dynamic>> generateFlatlay({
    required List<String> itemIds,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/tryon/flatlay'),
      headers: await _headers(),
      body: jsonEncode({'item_ids': itemIds}),
    );
    return _parse(res);
  }

  // ── Outfits ───────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getOutfits() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/outfits'),
      headers: await _headers(),
    );
    return _parse(res) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> saveOutfit({
    required String name,
    required List<String> itemIds,
    String? previewUrl,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/outfits'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'item_ids': itemIds,
        if (previewUrl != null) 'preview_url': previewUrl,
      }),
    );
    return _parse(res);
  }

  static Future<void> deleteOutfit(String id) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/outfits/$id'),
      headers: await _headers(),
    );
    if (res.statusCode >= 400) throw Exception('Delete failed');
  }

  /// GET /suggestions/ — return saved suggestions instantly (no AI call).
  /// Returns { outfits, is_stale, never_generated, generated_at, shopping_suggestions }.
  static Future<Map<String, dynamic>> getSuggestions() async {
    final uri = Uri.parse('$_baseUrl/suggestions/');
    final res = await http.get(uri, headers: await _headers());
    final parsed = _parse(res);
    if (parsed is Map<String, dynamic>) return parsed;
    return {'outfits': [], 'is_stale': false, 'never_generated': true, 'shopping_suggestions': []};
  }

  /// POST /suggestions/generate — run AI and save to DB (slow, ~30-60s).
  /// Call this only when user taps "Generate" or "Refresh".
  static Future<Map<String, dynamic>> generateSuggestions({
    String? occasion,
    String? season,
  }) async {
    final params = <String, String>{};
    if (occasion != null) params['occasion'] = occasion;
    if (season != null) params['season'] = season;

    final uri = Uri.parse('$_baseUrl/suggestions/generate').replace(queryParameters: params);
    final res = await http.post(uri, headers: await _headers());
    final parsed = _parse(res);
    if (parsed is Map<String, dynamic>) return parsed;
    return {'outfits': [], 'is_stale': false, 'never_generated': false, 'shopping_suggestions': []};
  }

  // ── Shopping ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> uploadShoppingItem(File photo) async {
    final token = await SecureStorage.getToken();
    final uri = Uri.parse('$_baseUrl/shopping/items');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath(
        'image',
        photo.path,
        contentType: _imageMimeType(photo.path),
      ));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _parse(res);
  }

static Future<List<dynamic>> getShoppingItems() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/shopping/items'),
      headers: await _headers(),
    );
    return _parse(res) as List<dynamic>;
  }

  static Future<void> deleteShoppingItem(String id) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/shopping/items/$id'),
      headers: await _headers(),
    );
    if (res.statusCode >= 400) throw Exception('Delete failed');
  }

  // ── OOTD ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> logOOTD({
    String? outfitId,
    List<String>? itemIds,
    String? note,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/ootd'),
      headers: await _headers(),
      body: jsonEncode({
        if (outfitId != null) 'outfit_id': outfitId,
        if (itemIds != null) 'item_ids': itemIds,
        if (note != null) 'note': note,
      }),
    );
    return _parse(res);
  }

  static Future<List<dynamic>> getOOTDHistory() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/ootd'),
      headers: await _headers(),
    );
    return _parse(res) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getOOTDStreak() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/ootd/streak'),
      headers: await _headers(),
    );
    return _parse(res);
  }

  static Future<Map<String, dynamic>> getOOTDCalendar(int year, int month) async {
    final uri = Uri.parse('$_baseUrl/ootd/calendar')
        .replace(queryParameters: {'year': year.toString(), 'month': month.toString()});
    final res = await http.get(uri, headers: await _headers());
    return _parse(res);
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
