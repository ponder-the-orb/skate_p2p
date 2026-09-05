import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game/game_engine.dart';
import '../../media/rejoin_store.dart';
import '../network/packet_codec.dart';

enum ClientPhase { disconnected, lobbyIdle, waitingForPeer, inMatch }

/// Lobby error copy. Written to be read by a player, not a protocol author:
/// the wire's `ERROR 0x0F` codes (PROTOCOL.md §5) never reach the screen as
/// numbers — except in [unknownErrorMessage], where the hex is the one thing a
/// screenshot has to carry for anyone to diagnose it.
const String roomFullMessage = "That room's full — grab a fresh code.";
const String roomNotFoundMessage =
    "No room with that code — it may have expired.";

String unknownErrorMessage(int errorCode) {
  final hex = errorCode.toRadixString(16).padLeft(2, '0').toUpperCase();
  return "Something went sideways (0x$hex). Try again.";
}

class AppState extends ChangeNotifier {
  // Client phase and identity state variables
  ClientPhase _phase = ClientPhase.disconnected;
  int? _playerId;
  int? _peerId;
  int? _roomCode;
  int? _role;
  String? _notice;
  String? _errorNotice;

  bool _isConnected = false;

  /// Reconnect grace (PROTOCOL.md §5). The survivor's view: the peer's socket
  /// dropped but the room is being held. Cosmetic — PEER_LEFT stays the sole
  /// authority on a game actually ending, and the engine is untouched here.
  bool _peerDisconnected = false;
  int _graceSeconds = 0;

  /// The rejoiner's view: JOINED restored the old seat and 0x06 has arrived,
  /// so a STATE_SYNC is owed. It is the ONLY window in which 0x12 is accepted.
  bool _awaitingSync = false;

  /// The engine snapshot. Both clients feed their engines the same events in
  /// the same order, so both snapshots agree (ADR-003).
  GameState _game = const GameState.initial();

  void Function()? _reconnectCallback;
  void Function(Uint8List)? _sendCallback;

  /// Where the last room is remembered across a kill (PROTOCOL.md §5's grace,
  /// turned into a habit). Null until `main.dart` resolves one — and null is a
  /// working state: every use below is null-safe, so a test, or a platform
  /// where the documents directory never answers, simply has the feature off.
  RejoinStore? _rejoinStore;

  /// Set by the lobby's Rejoin tap and cleared by the JOINED or ERROR that
  /// answers it. It exists for exactly one decision: a "room not found" is
  /// only allowed to delete the save if the save is what we tried to use. A
  /// mistyped manual code must never wipe a live game.
  int? _pendingRejoinCode;

  // Getters
  ClientPhase get phase => _phase;
  int? get playerId => _playerId;
  int? get peerId => _peerId;
  int? get roomCode => _roomCode;
  int? get role => _role;
  String? get notice => _notice;
  String? get errorNotice => _errorNotice;

  bool get isConnected => _isConnected;
  GameState get game => _game;
  bool get peerDisconnected => _peerDisconnected;
  int get graceSeconds => _graceSeconds;
  bool get awaitingSync => _awaitingSync;

  /// The attached store, or null when the feature is off. The lobby reads this
  /// to decide whether it can offer a Rejoin at all.
  RejoinStore? get rejoinStore => _rejoinStore;

  /// The code a Rejoin tap is currently waiting on an answer for, or null.
  /// Exposed so the lobby's tap can be asserted without going near the disk.
  int? get pendingRejoinCode => _pendingRejoinCode;

  void setReconnectCallback(void Function() callback) {
    _reconnectCallback = callback;
  }

  /// Wired in `main.dart` to the transport. Kept as a callback so `state/`
  /// never imports the socket layer.
  void setSendCallback(void Function(Uint8List) callback) {
    _sendCallback = callback;
  }

  /// Wired in `main.dart` once `path_provider` has answered. Fire-and-forget:
  /// the app is already running by the time this lands, and the only thing
  /// that changes is whether the next lobby build can offer a Rejoin.
  void attachRejoinStore(RejoinStore store) {
    _rejoinStore = store;
  }

  /// Records that the JOIN now in flight came from the Rejoin button.
  void markRejoinAttempt(int roomCode) {
    _pendingRejoinCode = roomCode;
  }

  /// Keeps the save fresh on game activity, so a long match doesn't age out of
  /// the lobby's window while it is still being played.
  ///
  /// Unawaited on purpose: these run inside notifier paths, and dispatch must
  /// never wait on a disk write (the store serialises its own writes).
  void _touchRejoin() {
    final store = _rejoinStore;
    if (store == null) return;
    unawaited(store.touch());
  }

  void triggerReconnect() {
    _reconnectCallback?.call();
  }

  void setConnectionStatus(bool status) {
    _isConnected = status;
    if (!status) {
      _phase = ClientPhase.disconnected;
    } else {
      if (_phase == ClientPhase.disconnected) {
        _phase = ClientPhase.lobbyIdle;
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Local intents — apply to the engine first, only then put it on the wire.
  // ---------------------------------------------------------------------------

  /// Declares the trick this player is about to attempt.
  /// An empty [name] is a legal "unnamed trick" (PROTOCOL.md §6).
  void setTrick(String name) {
    final myId = _playerId;
    if (myId == null) return;

    if (!_applyLocal(TrickSet(myId, name))) return;
    _send(PacketCodec.encodeTrickSet(senderId: myId, name: name));
  }

  /// Self-reports the result of this player's own attempt.
  void reportResult(bool landed) {
    final myId = _playerId;
    if (myId == null) return;

    if (!_applyLocal(AttemptResult(myId, landed))) return;
    _send(PacketCodec.encodeAttemptResult(senderId: myId, landed: landed));
  }

  /// Votes for a rematch. The engine resets only once both players have voted.
  void voteRematch() {
    final myId = _playerId;
    if (myId == null) return;

    if (!_applyLocal(RematchVote(myId))) return;
    _send(PacketCodec.encodeRematch(senderId: myId));
  }

  /// Applies a decoded game packet from the peer to the engine.
  void applyRemoteEvent(V1Packet packet) {
    final peerId = _peerId;
    if (peerId == null) {
      debugPrint('[-] Dropping game packet: no peer yet');
      return;
    }

    final GameEvent event;
    switch (packet) {
      case TrickSetPacket():
        event = TrickSet(peerId, packet.name);
      case AttemptResultPacket():
        event = AttemptResult(peerId, packet.landed);
      case RematchPacket():
        event = RematchVote(peerId);
      case JoinPacket():
      case JoinedPacket():
      case PeerJoinedPacket():
      case PeerLeftPacket():
      case PeerDisconnectedPacket():
      case PeerReconnectedPacket():
      case StateSyncPacket():
      case ErrorPacket():
        debugPrint('[-] Dropping non-game packet passed to applyRemoteEvent');
        return;
    }

    _game = _game.apply(event);
    if (_game.lastRejectedReason != null) {
      debugPrint(
        '[-] Engine rejected remote event: ${_game.lastRejectedReason}',
      );
    } else {
      _touchRejoin();
    }
    notifyListeners();
  }

  /// Applies a locally-originated event. Returns true when the engine accepted
  /// it — that is, when the matching packet should go on the wire.
  bool _applyLocal(GameEvent event) {
    final next = _game.apply(event);
    _game = next;
    notifyListeners();

    if (next.lastRejectedReason != null) {
      debugPrint('[-] Engine rejected local event: ${next.lastRejectedReason}');
      return false;
    }
    _touchRejoin();
    return true;
  }

  void _send(Uint8List packet) {
    final send = _sendCallback;
    if (send == null) {
      debugPrint('[-] No send callback wired; packet not sent');
      return;
    }
    send(packet);
  }

  // ---------------------------------------------------------------------------
  // Lobby & control flow transitions
  // ---------------------------------------------------------------------------

  void handleJoined({
    required int playerId,
    required int roomCode,
    required int role,
  }) {
    _playerId = playerId;
    _roomCode = roomCode;
    _role = role;
    _errorNotice = null;
    _phase = role == 1 ? ClientPhase.waitingForPeer : ClientPhase.inMatch;

    // The seat is ours; remember it. Whether we got here by creating, typing a
    // code or tapping Rejoin, the answer arrived — so the pending flag has
    // done its job either way.
    _pendingRejoinCode = null;
    final store = _rejoinStore;
    if (store != null) {
      unawaited(store.save(roomCode, playerId));
    }

    notifyListeners();
  }

  /// Sent to BOTH clients when the room fills (PROTOCOL.md §5), so each side
  /// knows both ids and can seed an identical engine. The creator (role 1)
  /// sets first.
  void handlePeerJoined(int peerId) {
    _peerId = peerId;
    _phase = ClientPhase.inMatch;

    final myId = _playerId;
    if (myId != null && _role != null) {
      _game = const GameState.initial().apply(
        _role == 1 ? GameStarted(myId, peerId) : GameStarted(peerId, myId),
      );
    }
    notifyListeners();
  }

  /// `0x05` — the peer dropped and the room is in grace for [graceSeconds].
  /// The engine is deliberately NOT told: nothing about the game has changed
  /// yet, and only PEER_LEFT abandons it.
  void handlePeerDisconnected(int peerId, int graceSeconds) {
    _peerDisconnected = true;
    _graceSeconds = graceSeconds;
    notifyListeners();
  }

  /// `0x06` — the room is whole again. Whoever has a game in progress is the
  /// survivor and owes the returning player one STATE_SYNC; the other side is
  /// the rejoiner and waits for it.
  void handlePeerReconnected(int peerId) {
    _peerDisconnected = false;
    _graceSeconds = 0;
    _peerId = peerId;

    const inProgress = {
      GamePhase.setting,
      GamePhase.defending,
      GamePhase.gameOver,
    };

    if (inProgress.contains(_game.phase)) {
      _sendStateSync();
    } else {
      _awaitingSync = true;
      _phase = ClientPhase.inMatch;
    }
    notifyListeners();
  }

  /// Installs a peer's snapshot, rebuilding the engine state from facts.
  /// Accepted ONLY while awaiting sync (PROTOCOL.md §6) — a 0x12 at any other
  /// moment is dropped and logged, never applied.
  void applyStateSync(StateSyncPacket packet) {
    if (!_awaitingSync) {
      debugPrint('[-] Dropping STATE_SYNC: not awaiting a sync');
      return;
    }

    _game = GameState(
      phase: _enginePhase(packet.phase),
      setterId: packet.setterId,
      defenderId: packet.defenderId,
      letters: Map.unmodifiable(packet.letters),
      currentTrickName: packet.trickName,
      rematchVotes: Set.unmodifiable(packet.rematchVotes),
      firstSetterId: packet.firstSetterId,
      winnerId: packet.winnerId,
      trickDeclared: packet.trickDeclared,
    );

    _awaitingSync = false;
    _peerDisconnected = false;
    _phase = ClientPhase.inMatch;
    _touchRejoin();
    notifyListeners();
  }

  /// The survivor's half of the handshake: the whole game, once.
  void _sendStateSync() {
    final myId = _playerId;
    final game = _game;
    if (myId == null ||
        game.setterId == null ||
        game.defenderId == null ||
        game.firstSetterId == null) {
      debugPrint('[-] Not sending STATE_SYNC: game is not seeded');
      return;
    }

    _send(
      PacketCodec.encodeStateSync(
        senderId: myId,
        phase: _wirePhase(game.phase),
        setterId: game.setterId!,
        defenderId: game.defenderId!,
        firstSetterId: game.firstSetterId!,
        winnerId: game.winnerId,
        letters: game.letters,
        rematchVotes: game.rematchVotes,
        trickDeclared: game.trickDeclared,
        trickName: game.currentTrickName,
      ),
    );
  }

  /// PROTOCOL.md §6: 1 setting · 2 defending · 3 gameOver. Only reachable for
  /// the three in-progress phases, which is all STATE_SYNC can carry.
  static int _wirePhase(GamePhase phase) => switch (phase) {
    GamePhase.defending => 2,
    GamePhase.gameOver => 3,
    _ => 1,
  };

  static GamePhase _enginePhase(int wire) => switch (wire) {
    2 => GamePhase.defending,
    3 => GamePhase.gameOver,
    _ => GamePhase.setting,
  };

  void handlePeerLeft(int peerId) {
    _game = _game.apply(PeerLeft(peerId));
    _notice = "Peer left. Room cleared.";

    // The server has stated the room is dead — a fact off the wire, not a
    // conclusion this client drew, so forgetting the save honors ADR-003
    // rather than bending it. Unawaited like every other store call: dispatch
    // never waits on disk.
    if (_game.phase == GamePhase.abandoned) {
      unawaited(_rejoinStore?.clear() ?? Future<void>.value());
    }

    _clearIdentity();
    triggerReconnect();
  }

  void handleCancel() {
    _notice = "Match canceled.";
    _game = const GameState.initial();
    _clearIdentity();
    triggerReconnect();
  }

  void handleLeaveMatch() {
    _notice = "Left match.";
    _game = const GameState.initial();
    _clearIdentity();
    triggerReconnect();
  }

  void handleRoomError(int errorCode) {
    final wasRejoin = _pendingRejoinCode != null;
    _pendingRejoinCode = null;

    if (errorCode == 0x01) {
      _errorNotice = roomFullMessage;
    } else if (errorCode == 0x02) {
      _errorNotice = roomNotFoundMessage;
      // The room we remembered is gone — grace expired, or it never survived
      // the kill. Forget it, but ONLY when it was the saved code we tried:
      // a fat-fingered manual join must not cost the player their game.
      if (wasRejoin) {
        unawaited(_rejoinStore?.clear() ?? Future<void>.value());
      }
    } else {
      _errorNotice = unknownErrorMessage(errorCode);
    }
    _phase = ClientPhase.lobbyIdle;
    notifyListeners();
  }

  void _clearIdentity() {
    _playerId = null;
    _peerId = null;
    _roomCode = null;
    _role = null;
    _errorNotice = null;
    _peerDisconnected = false;
    _graceSeconds = 0;
    _awaitingSync = false;
  }

  void clearNotice() {
    _notice = null;
    notifyListeners();
  }
}
