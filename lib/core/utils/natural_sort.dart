/// Natural alphanumeric string comparator for sorting albums, chapters, and filenames.
///
/// Splits strings into contiguous text vs number chunks (supporting decimal sub-chapters e.g. "1.1", "2.1"
/// or whole integers). Guarantees natural reading order for manga/comic chapters and page files.
int naturalCompare(String a, String b) {
  if (identical(a, b) || a == b) return 0;

  // Split into contiguous chunks of either numbers (including decimal chapters e.g. 1.1) or non-digits
  final regex = RegExp(r'(\d+(?:\.\d+)?|[^\d]+)');
  final matchesA = regex.allMatches(a).map((m) => m.group(0)!).toList();
  final matchesB = regex.allMatches(b).map((m) => m.group(0)!).toList();

  final minLen = matchesA.length < matchesB.length ? matchesA.length : matchesB.length;
  for (var i = 0; i < minLen; i++) {
    final chunkA = matchesA[i];
    final chunkB = matchesB[i];

    final numA = double.tryParse(chunkA);
    final numB = double.tryParse(chunkB);

    if (numA != null && numB != null) {
      final numCmp = numA.compareTo(numB);
      if (numCmp != 0) return numCmp;
      final lenCmp = chunkA.length.compareTo(chunkB.length);
      if (lenCmp != 0) return lenCmp;
    } else {
      final textCmp = chunkA.toLowerCase().compareTo(chunkB.toLowerCase());
      if (textCmp != 0) return textCmp;
      final rawCmp = chunkA.compareTo(chunkB);
      if (rawCmp != 0) return rawCmp;
    }
  }

  return matchesA.length.compareTo(matchesB.length);
}
