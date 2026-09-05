/// Rejoin persistence — the local half of reconnect grace (PROTOCOL.md §5).
///
/// This is a LEAF layer beside `clip_store.dart`: `dart:io`, `dart:convert`
/// and `dart:core` only, no Flutter imports and no packages (ADR-006's
/// reasoning, applied again). The directory is injected rather than resolved
/// here — that is what keeps the file Flutter-free and what lets the tests
/// point a store at a temp directory.
///
/// It knows nothing about the wire. Grace is entirely the server's rule; all
/// this does is remember the code so the player doesn't have to.
library;

import 'dart:convert';
import 'dart:io';

/// The last room this device sat in, and when it was last heard from.
///
/// [savedAt] is *last activity*, not join time: a forty-minute game must still
/// read fresh, so every applied game packet moves it (see [RejoinStore.touch]).
class RejoinRecord {
  final int roomCode;
  final int playerId;
  final DateTime savedAt;

  const RejoinRecord({
    required this.roomCode,
    required this.playerId,
    required this.savedAt,
  });

  /// How stale this record is, as of [now] (defaults to the wall clock).
  Duration age({DateTime? now}) => (now ?? DateTime.now()).difference(savedAt);

  @override
  String toString() =>
      'RejoinRecord(room: $roomCode, player: $playerId, savedAt: $savedAt)';
}

/// Owns `<app documents>/rejoin.json`: one record, overwritten in place.
///
/// Every method swallows its own failures. A missing file, a half-written
/// file, a directory the OS took away — all of them mean "no save" and none of
/// them may throw, because the callers are notifier paths and a lobby build
/// (PROTOCOL.md §3's validation culture, applied to disk).
class RejoinStore {
  /// The app documents directory. [file] sits directly inside it.
  final Directory documentsDirectory;

  /// Writes are fire-and-forget from `AppState`, so they are chained through
  /// this tail rather than raced: a `touch` can never land before the `save`
  /// it followed.
  ///
  /// Null until the first operation, deliberately — NOT a completed
  /// `Future.value()` sentinel. A future carries the zone it was created in,
  /// and one created at construction time (a test's `setUp`, say) can be a
  /// zone whose microtasks the caller never drains, which would hang the very
  /// first read behind a future that completes nowhere.
  Future<void>? _tail;

  RejoinStore(this.documentsDirectory);

  /// The one file. Named, not timestamped: there is only ever one last game.
  File get file =>
      File('${documentsDirectory.path}${Platform.pathSeparator}rejoin.json');

  /// Remembers a room. [playerId] is stored because it costs nothing and
  /// names the seat in a log; it is NOT needed on the wire — the server
  /// re-seats the original id itself (PROTOCOL.md §5).
  Future<void> save(int roomCode, int playerId, {DateTime? at}) => _serialized(
    () => _write(
      RejoinRecord(
        roomCode: roomCode,
        playerId: playerId,
        savedAt: at ?? DateTime.now(),
      ),
    ),
  );

  /// Rewrites `savedAt` and nothing else, keeping a long game fresh. With no
  /// save on disk this is a no-op — touching is not a way to create one.
  Future<void> touch({DateTime? at}) => _serialized(() async {
    final existing = await _read();
    if (existing == null) return;
    await _write(
      RejoinRecord(
        roomCode: existing.roomCode,
        playerId: existing.playerId,
        savedAt: at ?? DateTime.now(),
      ),
    );
  });

  /// The saved record, or null if there isn't one we can trust.
  ///
  /// Still a Future, though the read itself is synchronous (see [_read]):
  /// callers may have unawaited writes in flight, and a load must queue behind
  /// them rather than race them.
  Future<RejoinRecord?> load() => _serialized(_read);

  /// Forgets the last game. Clearing a save that isn't there is a success.
  Future<void> clear() => _serialized(() async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone, or never ours. Either way: nothing to forget.
    }
  });

  Future<void> _write(RejoinRecord record) async {
    try {
      await documentsDirectory.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'roomCode': record.roomCode,
          'playerId': record.playerId,
          'savedAt': record.savedAt.millisecondsSinceEpoch,
        }),
        flush: true,
      );
    } on FileSystemException {
      // A save we couldn't write is a Rejoin button we won't offer. That is
      // the whole consequence; it is not worth an exception up a notifier.
    }
  }

  /// Reads with the SYNCHRONOUS `dart:io` calls, deliberately.
  ///
  /// Two reasons, and they agree. It is one ~60-byte file read once, in the
  /// lobby's `initState` — far inside a frame budget, unlike the writes, which
  /// fire from notifier paths and therefore stay async (never block dispatch
  /// on disk). And under `testWidgets`, a real async disk future created in
  /// the fake-async zone never completes at all, so an async read here would
  /// make the whole Rejoin button untestable as a widget.
  Future<RejoinRecord?> _read() async {
    final String contents;
    try {
      if (!file.existsSync()) return null;
      contents = file.readAsStringSync();
    } on FileSystemException {
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      return null;
    }

    if (decoded is! Map) return null;
    final roomCode = decoded['roomCode'];
    final playerId = decoded['playerId'];
    final savedAt = decoded['savedAt'];
    if (roomCode is! int || playerId is! int || savedAt is! int) return null;

    return RejoinRecord(
      roomCode: roomCode,
      playerId: playerId,
      savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt),
    );
  }

  /// Runs [operation] after every operation queued before it. Failures break
  /// the chain for their own caller only.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final previous = _tail;
    final result = previous == null
        ? operation()
        : previous.then((_) => operation());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
