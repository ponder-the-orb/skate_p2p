/// Clips — the local half of ADR-008.
///
/// This is a LEAF layer: `dart:io` and `dart:core` only, no Flutter imports,
/// exactly like `lib/game/` (ADR-006's reasoning, applied again). It can be
/// unit-tested against a temp directory in milliseconds with no camera, no
/// emulator and no plugin registry — which matters here more than anywhere,
/// because the hardware this feature talks to cannot exist in a test VM.
///
/// It knows nothing about the game. A clip is never evidence: recording has
/// zero effect on game state, and the honour system of ARCHITECTURE.md §5 is
/// untouched by it (ADR-008).
library;

import 'dart:io';

/// One recorded clip on disk.
class Clip {
  /// The file itself, inside the store's [ClipStore.directory].
  final File file;

  /// When it was recorded, read back out of the filename.
  final DateTime recordedAt;

  const Clip({required this.file, required this.recordedAt});

  String get path => file.path;

  @override
  String toString() => 'Clip(${file.path})';
}

/// Owns `<app documents>/clips/`: naming, listing, deletion, and the line that
/// goes out with a share.
///
/// The documents directory is passed in rather than resolved here — that is
/// what keeps this file Flutter-free, and it is what lets the tests point a
/// store at a temp directory.
class ClipStore {
  /// The app documents directory. The store's own directory is a child of it.
  final Directory documentsDirectory;

  ClipStore(this.documentsDirectory);

  /// The clips directory. May not exist yet; [ensureDirectory] creates it, and
  /// [list] treats "absent" as "empty" rather than as an error.
  Directory get directory =>
      Directory('${documentsDirectory.path}${Platform.pathSeparator}clips');

  /// The one filename shape: `clip_<millisSinceEpoch>.mp4`. The timestamp is
  /// the identity — it sorts the list and dates the row, so nothing else needs
  /// to be persisted alongside the file.
  static String fileNameFor(DateTime at) =>
      'clip_${at.millisecondsSinceEpoch}.mp4';

  /// Recovers the recording time from a filename, or null if the name isn't
  /// ours. Foreign files in the directory are ignored, never deleted.
  static DateTime? timestampOf(String fileName) {
    final match = RegExp(r'^clip_(\d+)\.mp4$').firstMatch(fileName);
    if (match == null) return null;
    final millis = int.tryParse(match.group(1)!);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<Directory> ensureDirectory() => directory.create(recursive: true);

  /// Moves a freshly recorded file into the store and returns it as a [Clip].
  ///
  /// The camera plugin writes wherever it likes; this is the single step that
  /// makes a recording *a clip*. `rename` is a move within a filesystem and a
  /// failure across one, so the copy-then-delete fallback is not optional.
  Future<Clip> adopt(String sourcePath, {DateTime? at}) async {
    final recordedAt = at ?? DateTime.now();
    final dir = await ensureDirectory();
    final target =
        '${dir.path}${Platform.pathSeparator}${fileNameFor(recordedAt)}';

    final source = File(sourcePath);
    File saved;
    try {
      saved = await source.rename(target);
    } on FileSystemException {
      saved = await source.copy(target);
      try {
        await source.delete();
      } on FileSystemException {
        // The copy is what matters; a stranded original is the plugin's
        // cache directory's problem, not a failed save.
      }
    }
    return Clip(file: saved, recordedAt: recordedAt);
  }

  /// Every clip in the store, newest first. A missing directory is an empty
  /// list — a player who has never recorded is not an error state.
  Future<List<Clip>> list() async {
    final dir = directory;
    if (!await dir.exists()) return const <Clip>[];

    final clips = <Clip>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final at = timestampOf(name);
      if (at == null) continue;
      clips.add(Clip(file: entity, recordedAt: at));
    }

    clips.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return clips;
  }

  /// Deletes a clip. Deleting one that is already gone is a success — two taps
  /// on Delete must not put an error in front of the player.
  Future<void> delete(Clip clip) async {
    try {
      await clip.file.delete();
    } on FileSystemException {
      // Already gone, or never ours to begin with. Either way: nothing to do.
    }
  }

  /// The line that rides along with a shared clip.
  ///
  /// No room code, deliberately: codes die with their room, and a dead link in
  /// somebody's messenger is worse than no link. An unnamed trick becomes
  /// "this", which reads correctly in the sentence.
  static String shareText(String? trickName) {
    final trick = (trickName == null || trickName.trim().isEmpty)
        ? 'this'
        : trickName.trim();
    return 'Land it or take the letter 🛹 "$trick" — skate_p2p';
  }
}
