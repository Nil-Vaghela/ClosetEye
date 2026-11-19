import 'package:flutter_test/flutter_test.dart';
import 'package:drape/models/daily_outfit.dart';

void main() {
  test('daily outfit parses API response', () {
    final d = DailyOutfit.fromJson({
      'date': '2026-11-19',
      'cached': false,
      'daily_outfit_id': 'abc',
      'weather': {'temp_c': 8.4, 'condition': 'rainy'},
      'outfits': [
        {
          'items': {'top': 't1', 'bottom': 'b1', 'jacket': 'j1'},
          'item_ids': ['t1', 'b1', 'j1'],
          'confidence_score': 82,
          'breakdown': {'color': 20, 'weather': 22, 'occasion': 18, 'style': 22},
          'reason': 'Layered up for the cold.',
        }
      ],
    });
    expect(d.outfits.single.allItemIds, containsAll(['t1', 'b1', 'j1']));
    expect(d.weather!.tempDisplay, '8°C');
    expect(d.dailyOutfitId, 'abc');
  });
}
