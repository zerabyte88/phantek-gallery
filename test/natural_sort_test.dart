import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/utils/natural_sort.dart';

void main() {
  group('naturalCompare Unit Tests', () {
    test('Guaranteed chapter comparisons pass', () {
      expect(naturalCompare('Chapter 1', 'Chapter 1.1'), lessThan(0));
      expect(naturalCompare('Chapter 1.1', 'Chapter 2'), lessThan(0));
      expect(naturalCompare('Chapter 2', 'Chapter 2.1'), lessThan(0));
      expect(naturalCompare('Chapter 2.1', 'Chapter 2.2'), lessThan(0));
      expect(naturalCompare('Chapter 2.2', 'Chapter 10'), lessThan(0));
      expect(naturalCompare('Chapter 10', 'Chapter 25'), lessThan(0));
      expect(naturalCompare('001.jpg', '002.jpg'), lessThan(0));
      expect(naturalCompare('050.jpg', '050.jpg'), equals(0));
    });

    test('Full chapter list sorts into canonical manga reading order', () {
      final input = [
        'Chapter 25',
        'Chapter 1.1',
        'Chapter 2.2',
        'Chapter 1',
        'Chapter 10',
        'Chapter 2.1',
        'Chapter 2',
      ];
      input.sort(naturalCompare);
      expect(input, [
        'Chapter 1',
        'Chapter 1.1',
        'Chapter 2',
        'Chapter 2.1',
        'Chapter 2.2',
        'Chapter 10',
        'Chapter 25',
      ]);
    });

    test('Numeric padding and sub-decimal chapters', () {
      final pages = ['010.png', '001.png', '002.png', '1.png', '2.png'];
      pages.sort(naturalCompare);
      expect(pages, ['1.png', '001.png', '2.png', '002.png', '010.png']);
    });
  });
}
