import 'package:flutter/foundation.dart';

import '../../game/game_engine.dart';
import '../network/packet_codec.dart';

enum ClientPhase { disconnected, lobbyIdle, waitingForPeer, inMatch }

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

  /// The engine snapshot. Both clients feed their engines the same events in
  /// the same order, so both snapshots agree (ADR-003).
  GameState _game = const GameState.initial();

  void Function()? _reconnectCallback;
  void Function(Uint8List)? _sendCallback;

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

  void setReconnectCallback(void Function() callback) {
    _reconnectCallback = callback;
  }

  /// Wired in `main.dart` to the transport. Kept as a callback so `state/`
  /// never imports the socket layer.
  void setSendCallback(void Function(Uint8List) callback) {
    _sendCallback = callback;
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
      case ErrorPacket():
        debugPrint('[-] Dropping non-game packet passed to applyRemoteEvent');
        return;
    }

    _game = _game.apply(event);
    if (_game.lastRejectedReason != null) {
      debugPrint(
        '[-] Engine rejected remote event: ${_game.lastRejectedReason}',
      );
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

  void handlePeerLeft(int peerId) {
    _game = _game.apply(PeerLeft(peerId));
    _notice = "Peer left. Room cleared.";
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
    if (errorCode == 0x01) {
      _errorNotice = "Room full";
    } else if (errorCode == 0x02) {
      _errorNotice = "Room not found";
    } else {
      _errorNotice =
          "Error 0x${errorCode.toRadixString(16).padLeft(2, '0').toUpperCase()}";
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
  }

  void clearNotice() {
    _notice = null;
    notifyListeners();
  }
}
