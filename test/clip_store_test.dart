import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/media/clip_store.dart';

/// `ClipStore` is a leaf: `dart:io` and `dart:core` only. So every one of these
/// runs against a real temp directory instead of a mock filesystem — no camera,
/// no plugins, no emulator, and nothing here can behave differently on the
/// Producer's phone than it does on a camera-less VM.
void main() {
  late Directory documents;
  late ClipStore store;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('skate_clips_test');
    store = ClipStore(documents);
  });

  tearDown(() {
    if (documents.existsSync()) {
      documents.deleteSync(recursive: true);
    }
  });

  /// Writes a file straight into the clips directory, standing in for a
  /// recording that has already been adopted.
  File writeClip(DateTime at, {String body = 'x'}) {
    final dir = store.directory..createSync(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}${ClipStore.fileNameFor(at)}',
    )..writeAsStringSync(body);
    return file;
  }

  /// A file the camera plugin has just written somewhere of its own choosing.
  File writeSource(String name, {String body = 'take'}) =>
      File('${documents.path}${Platform.pathSeparator}$name')
        ..writeAsStringSync(body);

  group('the clips directory', () {
    test('is a "clips" child of the documents directory', () {
      expect(
        store.directory.path,
        equals('${documents.path}${Platform.pathSeparator}clips'),
      );
    });

    test('does not exist until something needs it', () {
      expect(store.directory.existsSync(), isFalse);
    });

    test('ensureDirectory creates it and is safe to repeat', () async {
      await store.ensureDirectory();
      await store.ensureDirectory();
      expect(store.directory.existsSync(), isTrue);
    });
  });

  group('naming', () {
    test('is clip_<millisSinceEpoch>.mp4', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1756800000000);
      expect(ClipStore.fileNameFor(at), equals('clip_1756800000000.mp4'));
    });

    test('round-trips through timestampOf', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1756800012345);
      expect(ClipStore.timestampOf(ClipStore.fileNameFor(at)), equals(at));
    });

    test('rejects names that are not ours', () {
      expect(ClipStore.timestampOf('clip_.mp4'), isNull);
      expect(ClipStore.timestampOf('clip_123.mov'), isNull);
      expect(ClipStore.timestampOf('clip_12a3.mp4'), isNull);
      expect(ClipStore.timestampOf('IMG_0001.mp4'), isNull);
      expect(ClipStore.timestampOf('xclip_123.mp4'), isNull);
      expect(ClipStore.timestampOf(''), isNull);
    });
  });

  group('adopt', () {
    test('moves the recording in under a clip name', () async {
      final source = writeSource('REC_from_the_plugin.mp4', body: 'footage');
      final at = DateTime.fromMillisecondsSinceEpoch(1756800000000);

      final clip = await store.adopt(source.path, at: at);

      expect(clip.recordedAt, equals(at));
      expect(
        clip.path,
        equals(
          '${store.directory.path}${Platform.pathSeparator}'
          'clip_1756800000000.mp4',
        ),
      );
      expect(clip.file.readAsStringSync(), equals('footage'));
      // A move, not a copy: the plugin's temp file is not left behind.
      expect(source.existsSync(), isFalse);
    });

    test('creates the clips directory on the way in', () async {
      final source = writeSource('REC_first_ever.mp4');
      expect(store.directory.existsSync(), isFalse);

      await store.adopt(source.path);

      expect(store.directory.existsSync(), isTrue);
    });

    test('the adopted clip is the one list() returns', () async {
      final source = writeSource('REC_listed.mp4');
      final clip = await store.adopt(source.path);

      final listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.path, equals(clip.path));
    });
  });

  group('list', () {
    test('is empty when nothing has ever been recorded', () async {
      expect(await store.list(), isEmpty);
    });

    test(
      'is empty, not an error, when the directory exists but is bare',
      () async {
        await store.ensureDirectory();
        expect(await store.list(), isEmpty);
      },
    );

    test('is newest first', () async {
      final oldest = DateTime.fromMillisecondsSinceEpoch(1000);
      final middle = DateTime.fromMillisecondsSinceEpoch(2000);
      final newest = DateTime.fromMillisecondsSinceEpoch(3000);
      // Written out of order on purpose.
      writeClip(middle);
      writeClip(newest);
      writeClip(oldest);

      final clips = await store.list();

      expect(
        clips.map((clip) => clip.recordedAt).toList(),
        equals([newest, middle, oldest]),
      );
    });

    test('ignores files that are not clips', () async {
      writeClip(DateTime.fromMillisecondsSinceEpoch(1000));
      final dir = store.directory;
      File('${dir.path}${Platform.pathSeparator}notes.txt')
          .writeAsStringSync('hello');
      File('${dir.path}${Platform.pathSeparator}IMG_0002.mp4')
          .writeAsStringSync('someone else');
      Directory('${dir.path}${Platform.pathSeparator}clip_9999.mp4')
          .createSync();

      final clips = await store.list();

      expect(clips, hasLength(1));
      expect(
        clips.single.recordedAt,
        equals(DateTime.fromMillisecondsSinceEpoch(1000)),
      );
    });
  });

  group('delete', () {
    test('removes the file from disk and from the list', () async {
      writeClip(DateTime.fromMillisecondsSinceEpoch(1000));
      writeClip(DateTime.fromMillisecondsSinceEpoch(2000));

      final clips = await store.list();
      await store.delete(clips.first); // the newer one

      final remaining = await store.list();
      expect(remaining, hasLength(1));
      expect(
        remaining.single.recordedAt,
        equals(DateTime.fromMillisecondsSinceEpoch(1000)),
      );
      expect(clips.first.file.existsSync(), isFalse);
    });

    test('deleting the same clip twice is not an error', () async {
      writeClip(DateTime.fromMillisecondsSinceEpoch(1000));
      final clip = (await store.list()).single;

      await store.delete(clip);
      await expectLater(store.delete(clip), completes);
      expect(await store.list(), isEmpty);
    });

    test('leaves the directory in place for the next clip', () async {
      writeClip(DateTime.fromMillisecondsSinceEpoch(1000));
      await store.delete((await store.list()).single);

      expect(store.directory.existsSync(), isTrue);
      expect(await store.list(), isEmpty);
    });
  });

  group('share text', () {
    test('names the trick', () {
      expect(
        ClipStore.shareText('kickflip'),
        equals('Land it or take the letter 🛹 "kickflip" — skate_p2p'),
      );
    });

    test('an unnamed trick becomes "this"', () {
      expect(
        ClipStore.shareText(''),
        equals('Land it or take the letter 🛹 "this" — skate_p2p'),
      );
      expect(ClipStore.shareText(null), equals(ClipStore.shareText('')));
      expect(ClipStore.shareText('   '), equals(ClipStore.shareText('')));
    });

    test('trims the name the player typed', () {
      expect(
        ClipStore.shareText('  heelflip \n'),
        equals('Land it or take the letter 🛹 "heelflip" — skate_p2p'),
      );
    });

    test('carries no room code — codes die with their room', () {
      // The one thing that must never be in here. Five digits in a row would
      // be a link that is dead by the time anyone taps it.
      expect(ClipStore.shareText('nollie 360 flip'), isNot(contains('room')));
      expect(
        RegExp(r'\d{5}').hasMatch(ClipStore.shareText('nollie 360 flip')),
        isFalse,
      );
    });
  });
}
