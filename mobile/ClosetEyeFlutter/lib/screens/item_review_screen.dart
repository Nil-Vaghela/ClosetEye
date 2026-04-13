import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/clothing_item.dart';
import '../widgets/blob_bg.dart';
import '../widgets/gradient_button.dart';

enum _ReviewState { loading, review, error }

class ItemReviewScreen extends StatefulWidget {
  final File photo;
  final bool isShoppingMode;

  const ItemReviewScreen({
    super.key,
    required this.photo,
    this.isShoppingMode = false,
  });

  @override
  State<ItemReviewScreen> createState() => _ItemReviewScreenState();
}

class _ItemReviewScreenState extends State<ItemReviewScreen>
    with TickerProviderStateMixin {
  _ReviewState _state = _ReviewState.loading;
  ClothingItem? _item;
  String? _error;

  // Editable fields
  late String _category;
  late String _color;
  late Set<String> _seasons;
  late List<String> _tags;

  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    _uploadItem();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _uploadItem() async {
    setState(() { _state = _ReviewState.loading; _error = null; });
    try {
      final response = widget.isShoppingMode
          ? await ApiClient.uploadShoppingItem(widget.photo)
          : await ApiClient.uploadItem(widget.photo);

      final item = ClothingItem.fromJson(response);
      setState(() {
        _item = item;
        _category = item.category;
        _color = item.colorPrimary ?? 'Unknown';
        _seasons = {'all'};
        _tags = item.tags.toList();
        _state = _ReviewState.review;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _state = _ReviewState.error;
      });
    }
  }

  Future<void> _saveItem() async {
    if (_item == null) return;

    Navigator.pop(context, _item);
  }

  Future<void> _deleteItem() async {
    try {
      await ApiClient.deleteItem(_item!.id);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
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
                      'Review Item',
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
                child: _state == _ReviewState.loading
                    ? _buildLoadingState()
                    : _state == _ReviewState.error
                        ? _buildErrorState()
                        : _buildReviewState(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: Tween(begin: 0.8, end: 1.2).animate(_pulse),
          child: Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.accent,
            ),
            child: const Center(
              child: Text('👗', style: TextStyle(fontSize: 44)),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Scanning your item...',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 32),
        // Step indicators
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIndicator(label: 'Uploading', active: true),
              const SizedBox(height: 8),
              _StepIndicator(label: 'Removing background', active: false),
              const SizedBox(height: 8),
              _StepIndicator(label: 'Detecting attributes', active: false, dots: true),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildErrorState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('😔', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        const Text(
          'Something went wrong',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            _error ?? 'Unknown error',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: GradientButton(
            label: 'Retry',
            onPressed: _uploadItem,
          ),
        ),
      ],
    ),
  );

  Widget _buildReviewState() {
    if (_item == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Your real photo — show full bleed with a subtle rounded card
          Container(
            height: 320,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFF1A1A1A),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _item!.displayImageUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 400),
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.gold,
                        strokeWidth: 2,
                      ),
                    ),
                    errorWidget: (_, __, ___) => const Center(
                      child: Text('👕', style: TextStyle(fontSize: 72)),
                    ),
                  ),
                  // "AI Tagged" badge — attributes detected, photo is yours
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              color: AppColors.gold, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'AI Tagged',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          // AI Detected section
          const Text(
            'AI DETECTED',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 16),
          // Category
          _EditableField(
            label: 'Category',
            value: ClothingItem.categoryLabels[_category] ?? _category,
            onTap: () => _showCategoryPicker(),
          ),
          const SizedBox(height: 12),
          // Color
          _EditableField(
            label: 'Color',
            value: _color,
            showIcon: true,
            onTap: () => _showColorPicker(),
          ),
          const SizedBox(height: 12),
          // Season chips
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Season',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: const ['spring', 'summer', 'fall', 'winter', 'all']
                    .map((s) => _SeasonChip(
                  label: s[0].toUpperCase() + s.substring(1),
                  selected: true, // simplified for now
                ))
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Tags section
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tags',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ..._tags.map((tag) => _TagChip(
                    label: tag,
                    onRemove: () => setState(() => _tags.remove(tag)),
                  )),
                  _TagChip(
                    label: '+',
                    onTap: () => _addTag(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Buttons
          GradientButton(
            label: 'Add to Wardrobe ✓',
            onPressed: _saveItem,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                title: const Text('Discard this item?'),
                content: const Text('This action cannot be undone.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteItem();
                    },
                    child: const Text('Discard', style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
            ),
            child: const Center(
              child: Text(
                'Discard',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: ClothingItem.categories
              .map((cat) => ListTile(
            title: Text(ClothingItem.categoryLabels[cat] ?? cat),
            selected: _category == cat,
            onTap: () {
              setState(() => _category = cat);
              Navigator.pop(context);
            },
          ))
              .toList(),
        ),
      ),
    );
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Color'),
        content: TextField(
          controller: TextEditingController(text: _color),
          onChanged: (v) => setState(() => _color = v),
          decoration: InputDecoration(
            hintText: 'e.g., White, Navy Blue',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.glassBorder),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _addTag() {
    showDialog(
      context: context,
      builder: (_) {
        String newTag = '';
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Add tag'),
          content: TextField(
            onChanged: (v) => newTag = v,
            decoration: InputDecoration(
              hintText: 'e.g., casual, linen',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.glassBorder),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (newTag.isNotEmpty) {
                  setState(() => _tags.add(newTag));
                }
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final String label;
  final bool active;
  final bool dots;

  const _StepIndicator({
    required this.label,
    required this.active,
    this.dots = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (dots)
        const SizedBox(width: 22, child: Text('···', style: TextStyle(
          color: AppColors.gold,
          fontSize: 16,
          letterSpacing: 0,
        )))
      else
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? AppColors.gold : AppColors.glassBorder,
              width: active ? 2 : 1,
            ),
          ),
          child: active
              ? const Center(
                  child: Text('✓', style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  )),
                )
              : null,
        ),
      const SizedBox(width: 12),
      Text(
        label,
        style: TextStyle(
          color: active ? AppColors.textPrimary : AppColors.textMuted,
          fontSize: 14,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ],
  );
}

class _EditableField extends StatelessWidget {
  final String label;
  final String value;
  final bool showIcon;
  final VoidCallback onTap;

  const _EditableField({
    required this.label,
    required this.value,
    required this.onTap,
    this.showIcon = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          if (showIcon) ...[
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withOpacity(0.3),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.edit_rounded,
              color: AppColors.textMuted, size: 16),
        ],
      ),
    ),
  );
}

class _SeasonChip extends StatelessWidget {
  final String label;
  final bool selected;

  const _SeasonChip({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: selected ? AppColors.gold : AppColors.surface,
      borderRadius: BorderRadius.circular(100),
      border: Border.all(
        color: selected ? Colors.transparent : AppColors.glassBorder,
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: selected ? Colors.white : AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _TagChip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  const _TagChip({
    required this.label,
    this.onRemove,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close_rounded,
                  size: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    ),
  );
}
