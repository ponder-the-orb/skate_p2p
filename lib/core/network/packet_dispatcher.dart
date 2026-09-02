import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../state/app_state.dart';
import 'packet_codec.dart';

/// Routes validated inbound packets to state changes.
///
/// Every inbound frame is protocol v1 (PROTOCOL.md §2–§6). Control opcodes
/// (`0x00–0x0F`) drive the connection/lobby handlers; game opcodes
/// (`0x10–0x2F`) are handed to the engine via [AppState.applyRemoteEvent].
///
/// Validation discipline follows PROTOCOL.md §3: malformed input is
/// dropped and logged, never thrown on.
class PacketDispatcher {
  final AppState appState;

  PacketDispatcher(this.appState);

  void dispatch(dynamic message) {
    if (message is! List<int>) {
      _drop('non-binary message (${message.runtimeType})');
      return;
    }

    final bytes = Uint8List.fromList(message);

    if (bytes.isEmpty) {
      _drop('empty packet');
      return;
    }

    final packet = PacketCodec.decode(bytes);
    if (packet == null) {
      // Drop and log is handled inside decode.
      return;
    }

    switch (packet) {
      case JoinedPacket():
        debugPrint(
          '[<<] RECV JOINED (0x02) | '
          'PlayerID: ${packet.playerId} | Room: ${packet.roomCode} | Role: ${packet.role}',
        );
        appState.handleJoined(
          playerId: packet.playerId,
          roomCode: packet.roomCode,
          role: packet.role,
        );
      case PeerJoinedPacket():
        debugPrint('[<<] RECV PEER_JOINED (0x03) | Peer: ${packet.peerId}');
        appState.handlePeerJoined(packet.peerId);
      case PeerLeftPacket():
        debugPrint('[<<] RECV PEER_LEFT (0x04) | Peer: ${packet.peerId}');
        appState.handlePeerLeft(packet.peerId);
      case PeerDisconnectedPacket():
        debugPrint(
          '[<<] RECV PEER_DISCONNECTED (0x05) | '
          'Peer: ${packet.peerId} | Grace: ${packet.graceSeconds}s',
        );
        appState.handlePeerDisconnected(packet.peerId, packet.graceSeconds);
      case PeerReconnectedPacket():
        debugPrint(
          '[<<] RECV PEER_RECONNECTED (0x06) | Peer: ${packet.peerId}',
        );
        appState.handlePeerReconnected(packet.peerId);
      case ErrorPacket():
        debugPrint('[<<] RECV ERROR (0x0F) | Code: ${packet.errorCode}');
        appState.handleRoomError(packet.errorCode);
      case TrickSetPacket():
        debugPrint('[<<] RECV TRICK_SET (0x10) | Name: "${packet.name}"');
        appState.applyRemoteEvent(packet);
      case AttemptResultPacket():
        debugPrint(
          '[<<] RECV ATTEMPT_RESULT (0x11) | '
          '${packet.landed ? "landed" : "bailed"}',
        );
        appState.applyRemoteEvent(packet);
      case StateSyncPacket():
        debugPrint(
          '[<<] RECV STATE_SYNC (0x12) | '
          'phase ${packet.phase} | letters ${packet.letters}',
        );
        appState.applyStateSync(packet);
      case RematchPacket():
        debugPrint('[<<] RECV REMATCH (0x13)');
        appState.applyRemoteEvent(packet);
      case JoinPacket():
        _drop('client received JOIN packet');
    }
  }

  void _drop(String reason) {
    debugPrint('[-] Dropping packet: $reason');
  }
}
