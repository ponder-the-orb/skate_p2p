import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/ui/data/trick_presets.dart';

void main() {
  group('trickPresets', () {
    test('offers a usable number of tricks', () {
      expect(trickPresets, isNotEmpty);
    });

    test('has no blank entries', () {
      for (final name in trickPresets) {
        expect(name.trim(), isNotEmpty, reason: 'blank entry in trickPresets');
      }
    });

    test('has no duplicates', () {
      expect(trickPresets.toSet().length, trickPresets.length);
    });

    // The one wire-derived constraint on this list: TRICK_SET carries the name
    // behind a uint8 `nameLen`, so 254 UTF-8 bytes is the ceiling
    // (PROTOCOL.md §6). A preset that cannot be sent is not a preset.
    test('every name fits TRICK_SET — at most 254 UTF-8 bytes', () {
      for (final name in trickPresets) {
        expect(
          utf8.encode(name).length,
          lessThanOrEqualTo(254),
          reason: '"$name" is too long for TRICK_SET',
        );
      }
    });
  });
}
