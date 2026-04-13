import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/clothing_item.dart';
import '../models/shopping_item.dart';
import '../widgets/blob_bg.dart';
import '../widgets/gradient_button.dart';
import 'capture_screen.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  List<ShoppingItem> _items = [];
  List<ClothingItem> _wardrobe = [];
  Set<String> _selectedIds = {};
  bool _loading = false;
  bool _generating = false;
  String? _previewUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final shoppingData = await ApiClient.getShoppingItems();
      final wardrobeData = await ApiClient.getWardrobe();
      setState(() {
        _items = (shoppingData as List?)
                ?.map((j) => ShoppingItem.fromJson(j))
                .toList() ??
            [];
        _wardrobe = (wardrobeData as List?)
                ?.map((j) => ClothingItem.fromJson(j))
                .toList() ??
            [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _deleteItem(ShoppingItem item) async {
    try {
      await ApiClient.deleteShoppingItem(item.id);
      setState(() => _items.removeWhere((i) => i.id == item.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _generatePreview() async {
    if (_selectedIds.isEmpty && _items.isEmpty) return;

    setState(() { _generating = true; _error = null; _previewUrl = null; });
    try {
      final shoppingIds =
          _items.map((i) => i.id).toList().cast<String>();
      final response = await ApiClient.getTryOnPreview(
        itemIds: _selectedIds.toList(),
        shoppingItemIds: shoppingIds,
      );
      setState(() {
        _previewUrl = response['preview_url'] as String?;
        _generating = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _generating = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      body: BlobBg(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Try Before You Buy',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: AppColors.accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.gold,
                          strokeWidth: 2,
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 110),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Subtitle
                            const Text(
                              'Upload clothes you\'re considering — no commitment needed',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Add button
                            GestureDetector(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const CaptureScreen(
                                      isShoppingMode: true,
                                    ),
                                  ),
                                );
                                _loadData();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.gold,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_rounded,
                                        color: AppColors.gold, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Add item to consider',
                                      style: TextStyle(
                                        color: AppColors.gold,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Considering items
                            if (_items.isNotEmpty) ...[
                              const Text(
                                'CONSIDERING',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 140,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _items.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 10),
                                  itemBuilder: (_, i) {
                                    final item = _items[i];
                                    final now = DateTime.now();
                                    final daysLeft =
                                        item.expiresAt.difference(now).inDays;
                                    return Stack(
                                      children: [
                                        Container(
                                          width: 110,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: AppColors.glassBorder,
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: CachedNetworkImage(
                                              imageUrl: item.displayImageUrl,
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) => Container(
                                                color: AppColors.surface,
                                              ),
                                              errorWidget: (_, __, ___) =>
                                                  Container(
                                                color: AppColors.surface,
                                                child: const Center(
                                                  child: Text('👕',
                                                      style: TextStyle(
                                                          fontSize: 24)),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Expiry badge
                                        Positioned(
                                          bottom: 8,
                                          left: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black
                                                  .withOpacity(0.6),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Exp: ${daysLeft}d',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Delete button
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: GestureDetector(
                                            onTap: () => _deleteItem(item),
                                            child: Container(
                                              width: 26,
                                              height: 26,
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withOpacity(0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Center(
                                                child: Icon(Icons.close_rounded,
                                                    color: Colors.white,
                                                    size: 14),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            // Wardrobe selector
                            if (_wardrobe.isNotEmpty) ...[
                              const Text(
                                'MIX WITH YOUR WARDROBE',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 100,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _wardrobe.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (_, i) {
                                    final item = _wardrobe[i];
                                    final selected =
                                        _selectedIds.contains(item.id);
                                    return GestureDetector(
                                      onTap: () => setState(() {
                                        if (selected) {
                                          _selectedIds.remove(item.id);
                                        } else {
                                          _selectedIds.add(item.id);
                                        }
                                      }),
                                      child: Container(
                                        width: 80,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: selected
                                                ? AppColors.gold
                                                : AppColors.glassBorder,
                                            width: selected ? 2 : 1,
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: CachedNetworkImage(
                                            imageUrl: item.displayImageUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (_, __) => Container(
                                              color: AppColors.surface,
                                            ),
                                            errorWidget: (_, __, ___) =>
                                                Container(
                                              color: AppColors.surface,
                                              child: const Center(
                                                child: Text('👕',
                                                    style: TextStyle(
                                                        fontSize: 24)),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),
                              GradientButton(
                                label: 'Try On Together',
                                onPressed: _items.isEmpty
                                    ? null
                                    : _generatePreview,
                                loading: _generating,
                              ),
                            ],
                            // Preview
                            if (_previewUrl != null) ...[
                              const SizedBox(height: 20),
                              const Text(
                                'PREVIEW',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: CachedNetworkImage(
                                  imageUrl: _previewUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: 300,
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.error.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppColors.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
