import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/media/rejoin_store.dart';

/// `RejoinStore` is a leaf: `dart:io`, `dart:convert` and `dart:core` only. So
/// every one of these runs against a real temp directory rather than a mocked
/// filesystem — no plugins, no emulator, and nothing here can behave
/// differently on the Producer's phone than it does in CI.
void main() {
  late Directory documents;
  late RejoinStore store;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('skate_rejoin_test');
    store = RejoinStore(documents);
  });

  tearDown(() {
    if (documents.existsSync()) {
      documents.deleteSync(recursive: true);
    }
  });

  group('save and load', () {
    test('a saved room comes back whole', () async {
      final at = DateTime.fromMillisecondsSinceEpoch(1757000000000);
      await store.save(41235, 7, at: at);

      final record = await store.load();
      expect(record, isNotNull);
      expect(record!.roomCode, equals(41235));
      expect(record.playerId, equals(7));
      expect(record.savedAt, equals(at));
    });

    test('saving twice keeps only the newer room', () async {
      await store.save(41235, 7);
      await store.save(50000, 9);

      final record = await store.load();
      expect(record!.roomCode, equals(50000));
      expect(record.playerId, equals(9));
    });

    test(
      'the file lands in the injected directory, named rejoin.json',
      () async {
        await store.save(41235, 7);

        expect(store.file.existsSync(), isTrue);
        expect(store.file.path, endsWith('rejoin.json'));
        expect(store.file.parent.path, equals(documents.path));
      },
    );

    test('no save yet is null, not an error', () async {
      expect(await store.load(), isNull);
    });
  });

  group('touch', () {
    test('moves savedAt and leaves the room alone', () async {
      final joined = DateTime.fromMillisecondsSinceEpoch(1757000000000);
      final later = joined.add(const Duration(minutes: 40));

      await store.save(41235, 7, at: joined);
      await store.touch(at: later);

      final record = await store.load();
      expect(record!.savedAt, equals(later));
      // Forty minutes of play, still fresh: the point of touching at all.
      expect(record.roomCode, equals(41235));
      expect(record.playerId, equals(7));
    });

    test('with nothing saved, creates nothing', () async {
      await store.touch();

      expect(store.file.existsSync(), isFalse);
      expect(await store.load(), isNull);
    });
  });

  group('clear', () {
    test('forgets the save', () async {
      await store.save(41235, 7);
      await store.clear();

      expect(await store.load(), isNull);
      expect(store.file.existsSync(), isFalse);
    });

    test('clearing twice is a success', () async {
      await store.save(41235, 7);
      await store.clear();

      await expectLater(store.clear(), completes);
      expect(await store.load(), isNull);
    });

    test('clearing a store that never saved is a success', () async {
      await expectLater(store.clear(), completes);
    });
  });

  group('a file we cannot trust is no save at all', () {
    Future<RejoinRecord?> loadAfterWriting(String body) async {
      store.file.writeAsStringSync(body);
      return store.load();
    }

    test('corrupt JSON reads as null, never throws', () async {
      expect(await loadAfterWriting('{not json at all'), isNull);
    });

    test('valid JSON of the wrong shape reads as null', () async {
      expect(await loadAfterWriting('[1, 2, 3]'), isNull);
    });

    test('a missing field reads as null', () async {
      expect(
        await loadAfterWriting('{"roomCode": 41235, "savedAt": 1757000000000}'),
        isNull,
      );
    });

    test('a field of the wrong type reads as null', () async {
      expect(
        await loadAfterWriting(
          '{"roomCode": "41235", "playerId": 7, "savedAt": 1757000000000}',
        ),
        isNull,
      );
    });

    test('an empty file reads as null', () async {
      expect(await loadAfterWriting(''), isNull);
    });

    test('a corrupt save can be overwritten by a good one', () async {
      await loadAfterWriting('{garbage');
      await store.save(41235, 7);

      expect((await store.load())!.roomCode, equals(41235));
    });
  });

  group('age', () {
    test('is measured from savedAt', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1757000000000);
      final record = RejoinRecord(roomCode: 1, playerId: 2, savedAt: at);

      expect(
        record.age(now: at.add(const Duration(seconds: 90))),
        equals(const Duration(seconds: 90)),
      );
    });
  });

  group('unawaited writes stay in order', () {
    test(
      'a save then a touch fired without awaiting land in sequence',
      () async {
        final joined = DateTime.fromMillisecondsSinceEpoch(1757000000000);
        final later = joined.add(const Duration(minutes: 5));

        // Exactly what AppState does: fire, never wait, inside a notifier path.
        final save = store.save(41235, 7, at: joined);
        final touch = store.touch(at: later);
        await Future.wait([save, touch]);

        final record = await store.load();
        expect(record!.roomCode, equals(41235));
        expect(record.savedAt, equals(later));
      },
    );
  });
}
