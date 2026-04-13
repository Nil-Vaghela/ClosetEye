import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/api_client.dart';
import '../core/secure_storage.dart';
import '../models/user.dart';

enum AuthStatus { loading, unauthenticated, authenticated }

class AppAuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.loading;
  AppUser?   _user;
  String?    _error;

  AuthStatus get status        => _status;
  AppUser?   get user          => _user;
  String?    get error         => _error;
  bool get isLoading           => _status == AuthStatus.loading;
  bool get isAuthenticated     => _status == AuthStatus.authenticated;

  AppAuthProvider() {
    _restoreSession();
  }

  // ── Restore saved session on app launch ───────────────────────────────────
  Future<void> _restoreSession() async {
    final token = await SecureStorage.getToken();
    final user  = await SecureStorage.getUser();
    if (token != null && user != null) {
      _user   = user;
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  // ── Called after Firebase phone OTP verifies successfully ─────────────────
  Future<void> signInWithFirebaseToken(String idToken) async {
    _error = null;
    try {
      final data  = await ApiClient.phoneLogin(idToken);
      final token = data['access_token'] as String;
      final user  = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      await SecureStorage.saveToken(token);
      await SecureStorage.saveUser(user);
      _user   = user;
      _status = AuthStatus.authenticated;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  // ── Update name after profile setup ───────────────────────────────────────
  Future<void> updateProfile(String name) async {
    _error = null;
    try {
      final data = await ApiClient.updateProfile(name: name);
      final updated = AppUser.fromJson(data);
      await SecureStorage.saveUser(updated);
      _user = updated;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // ── Create / update body model ────────────────────────────────────────────
  Future<void> createBodyModel({
    required File photo,
    required int heightCm,
    required int weightKg,
    required String bodyType,
  }) async {
    _error = null;
    try {
      final data = await ApiClient.createBodyModel(
        photo: photo,
        heightCm: heightCm,
        weightKg: weightKg,
        bodyType: bodyType,
      );
      final updated = _user!.copyWith(
        bodyPhotoUrl: data['body_photo_url'] as String?,
        bodySilhouetteUrl: data['body_silhouette_url'] as String?,
        heightCm: data['height_cm'] as int?,
        weightKg: data['weight_kg'] as int?,
        bodyType: data['body_type'] as String?,
        bodyModelReady: data['body_model_ready'] as bool? ?? true,
      );
      await SecureStorage.saveUser(updated);
      _user = updated;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    await SecureStorage.clear();
    _user   = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
