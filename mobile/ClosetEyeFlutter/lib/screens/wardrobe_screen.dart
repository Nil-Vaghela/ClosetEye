import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/clothing_item.dart';
import 'add_item_screen.dart';

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  List<ClothingItem> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiClient.getWardrobe();
      setState(() {
        _items = (data as List).map((j) => ClothingItem.fromJson(j)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<ClothingItem> get _filtered => _filter == 'All'
      ? _items
      : _items.where((i) => i.category == _filter).toList();

  Future<void> _delete(ClothingItem item) async {
    try {
      await ApiClient.deleteItem(item.id);
      setState(() => _items.remove(item));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString(),
            style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ['All', ...ClothingItem.categories];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _AddFab(onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddItemScreen()),
        );
        _load();
      }),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.gold,
        backgroundColor: AppColors.surface,
        child: CustomScrollView(
          slivers: [
            // ── Filter chips ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final cat = cats[i];
                    final sel = _filter == cat;
                    return GestureDetector(
                      onTap: () => setState(() => _filter = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 0),
                        decoration: BoxDecoration(
                          gradient: sel ? AppColors.accent : null,
                          color: sel ? null : AppColors.glassMid,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: sel
                                ? Colors.transparent
                                : AppColors.glassBorder,
                          ),
                          boxShadow: sel
                              ? [
                                  BoxShadow(
                                    color:
                                        AppColors.gold.withOpacity(0.4),
                                    blurRadius: 12,
                                  )
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            cat,
                            style: TextStyle(
                              
                              color: sel
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: sel
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── States ──────────────────────────────────────────────────────
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.gold, strokeWidth: 2),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('😔', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(
                          
                          color: AppColors.textSecondary,
                        )),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _load,
                      child: const Text('Retry',
                          style: TextStyle(
                            
                            color: AppColors.gold,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ]),
                ),
              )
            else if (_filtered.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('👚', style: TextStyle(fontSize: 56)),
                    const SizedBox(height: 18),
                    const Text(
                      'Your closet is empty',
                      style: TextStyle(
                        
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap + and snap a photo',
                      style: TextStyle(
                        
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ]),
                ),
              )
            else
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(20, 8, 20, 110),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _ItemCard(
                      item: _filtered[i],
                      onDelete: () => _delete(_filtered[i]),
                    ),
                    childCount: _filtered.length,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.72,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Item card ─────────────────────────────────────────────────────────────────
class _ItemCard extends StatelessWidget {
  final ClothingItem item;
  final VoidCallback onDelete;
  const _ItemCard({required this.item, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glassMid,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Expanded(
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22)),
                    child: CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => Container(
                        color: AppColors.surface,
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.gold, strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surface,
                        child: const Center(
                          child: Text('👕',
                              style: TextStyle(fontSize: 44)),
                        ),
                      ),
                    ),
                  ),
                  // Delete button
                  Positioned(
                    top: 8, right: 8,
                    child: GestureDetector(
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          title: const Text('Remove item?',
                              style: TextStyle(
                                
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              )),
                          content: const Text(
                            'This will remove it from your wardrobe.',
                            style: TextStyle(
                              
                              color: AppColors.textSecondary,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel',
                                  style: TextStyle(
                                    
                                    color: AppColors.textMuted,
                                  )),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                onDelete();
                              },
                              child: const Text('Remove',
                                  style: TextStyle(
                                    
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w700,
                                  )),
                            ),
                          ],
                        ),
                      ),
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ]),
              ),
              // Label
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.category,
                      style: const TextStyle(
                        
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.color != null)
                      Text(item.color!,
                          style: const TextStyle(
                            
                            color: AppColors.textMuted,
                            fontSize: 11,
                          )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Floating add button ───────────────────────────────────────────────────────
class _AddFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AddFab({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            gradient: AppColors.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(0.55),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: AppColors.goldDark.withOpacity(0.35),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded,
              color: Colors.white, size: 30),
        ),
      );
}
