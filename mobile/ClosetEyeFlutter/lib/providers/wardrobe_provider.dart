import 'dart:io';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../models/clothing_item.dart';

class WardrobeProvider extends ChangeNotifier {
  List<ClothingItem> _items = [];
  bool _loading = false;
  int _capsuleScore = 0;
  String? _error;

  // Getters
  List<ClothingItem> get items => _items;
  bool get loading => _loading;
  int get capsuleScore => _capsuleScore;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await ApiClient.getWardrobe();
      _items = (data as List)
          .map((j) => ClothingItem.fromJson(j))
          .toList();

      // Load capsule score
      try {
        final scoreData = await ApiClient.getCapsuleScore();
        _capsuleScore = scoreData['score'] as int? ?? 0;
      } catch (_) {
        _capsuleScore = 0;
      }

      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  Future<ClothingItem> uploadItem(File photo) async {
    try {
      final response = await ApiClient.uploadItem(photo);
      final item = ClothingItem.fromJson(response);
      _items.add(item);
      notifyListeners();
      return item;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteItem(String id) async {
    try {
      await ApiClient.deleteItem(id);
      _items.removeWhere((item) => item.id == id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateItem(String id, Map<String, dynamic> fields) async {
    try {
      final response = await ApiClient.updateItem(id, fields);
      final updatedItem = ClothingItem.fromJson(response);
      final index = _items.indexWhere((item) => item.id == id);
      if (index != -1) {
        _items[index] = updatedItem;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  void refresh() {
    load();
  }
}
