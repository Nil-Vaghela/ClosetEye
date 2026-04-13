import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/ootd_log.dart';
import '../widgets/blob_bg.dart';
import '../widgets/gradient_button.dart';

class OOTDScreen extends StatefulWidget {
  const OOTDScreen({super.key});

  @override
  State<OOTDScreen> createState() => _OOTDScreenState();
}

class _OOTDScreenState extends State<OOTDScreen> {
  int _streak = 0;
  int _longestStreak = 0;
  List<OOTDLog> _history = [];
  Map<String, bool> _calendarData = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final streakData = await ApiClient.getOOTDStreak();
      final historyData = await ApiClient.getOOTDHistory();
      final now = DateTime.now();
      final calendarData =
          await ApiClient.getOOTDCalendar(now.year, now.month);

      setState(() {
        _streak = streakData['current_streak'] as int? ?? 0;
        _longestStreak = streakData['longest_streak'] as int? ?? 0;
        _history = (historyData as List?)
                ?.map((j) => OOTDLog.fromJson(j))
                .toList() ??
            [];
        _calendarData = Map<String, bool>.from(
          calendarData['calendar'] as Map? ?? {},
        );
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _logOOTD(String note) async {
    try {
      await ApiClient.logOOTD(note: note);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Look logged!')),
        );
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
                      'Outfit of the Day',
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
                            // Streak counter
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.gold.withOpacity(0.12),
                                    AppColors.goldMid.withOpacity(0.06),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.gold.withOpacity(0.22),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: AppColors.accent,
                                    ),
                                    child: const Center(
                                      child: Text('🔥',
                                          style:
                                              TextStyle(fontSize: 32)),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$_streak day streak',
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Personal best: $_longestStreak days',
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            // Quick log
                            const Text(
                              'LOG TODAY\'S LOOK',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.glassBorder,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'What are you wearing today?',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    maxLines: 3,
                                    decoration: InputDecoration(
                                      hintText:
                                          'Add a note about your look',
                                      hintStyle: const TextStyle(
                                        color: AppColors.textHint,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: AppColors.glassBorder,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: AppColors.gold,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    onChanged: (v) {},
                                  ),
                                  const SizedBox(height: 12),
                                  GradientButton(
                                    label: 'Log Today\'s Look',
                                    onPressed: () =>
                                        _logOOTD('Logged from OOTD screen'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            // Calendar
                            const Text(
                              'CALENDAR',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildCalendar(),
                            const SizedBox(height: 32),
                            // Recent history
                            const Text(
                              'RECENT LOGS',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_history.isEmpty)
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('📸',
                                        style:
                                            TextStyle(fontSize: 32)),
                                    const SizedBox(height: 8),
                                    const Text('No logs yet',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                        )),
                                  ],
                                ),
                              )
                            else
                              Column(
                                children: _history.take(7).map((log) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 8),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.glassBorder,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Text('👕',
                                              style: TextStyle(
                                                  fontSize: 20)),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment
                                                      .start,
                                              children: [
                                                Text(
                                                  log.loggedDate,
                                                  style: const TextStyle(
                                                    color: AppColors
                                                        .textPrimary,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                if (log.note != null) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    log.note!,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: AppColors
                                                          .textMuted,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
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

  Widget _buildCalendar() {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final daysInMonth = lastDay.day;
    final firstDayWeekday = firstDay.weekday;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          // Month header
          Text(
            DateFormat('MMMM yyyy').format(now),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          // Day labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map((day) => Text(
                  day,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ))
                .toList(),
          ),
          const SizedBox(height: 8),
          // Days grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.2,
            ),
            itemCount: daysInMonth + firstDayWeekday - 1,
            itemBuilder: (_, i) {
              final dayNum = i - (firstDayWeekday - 1) + 1;
              final isValidDay = dayNum > 0 && dayNum <= daysInMonth;
              final dateStr =
                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${dayNum.toString().padLeft(2, '0')}';
              final logged = _calendarData[dateStr] ?? false;

              return isValidDay
                  ? Container(
                      decoration: BoxDecoration(
                        color: logged
                            ? AppColors.gold.withOpacity(0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: logged
                            ? Border.all(color: AppColors.gold)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          dayNum.toString(),
                          style: TextStyle(
                            color: logged
                                ? AppColors.gold
                                : AppColors.textMuted,
                            fontWeight: logged
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
