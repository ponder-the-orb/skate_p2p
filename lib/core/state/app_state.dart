import 'package:flutter/foundation.dart';

enum ClientPhase { disconnected, lobbyIdle, waitingForPeer, inMatch }

class AppState extends ChangeNotifier {
  // Client phase and identity state variables
  ClientPhase _phase = ClientPhase.disconnected;
  int? _playerId;
  int? _roomCode;
  int? _role;
  String? _notice;
  String? _errorNotice;

  // Game letters & status
  int _localLetters = 0;
  int _peerLetters = 0;
  bool _isConnected = false;
  bool _isMyTurn = true;

  void Function()? _reconnectCallback;

  // Getters
  ClientPhase get phase => _phase;
  int? get playerId => _playerId;
  int? get roomCode => _roomCode;
  int? get role => _role;
  String? get notice => _notice;
  String? get errorNotice => _errorNotice;

  int get localLetters => _localLetters;
  int get peerLetters => _peerLetters;
  bool get isConnected => _isConnected;
  bool get isMyTurn => _isMyTurn;

  void setReconnectCallback(void Function() callback) {
    _reconnectCallback = callback;
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

  void updateLocalScore(int count) {
    _localLetters = count.clamp(0, 5); // S-K-A-T-E maxes out at 5 letters
    notifyListeners();
  }

  void updatePeerScore(int count) {
    _peerLetters = count.clamp(0, 5);
    notifyListeners();
  }

  void setTurnState(bool myTurn) {
    _isMyTurn = myTurn;
    notifyListeners();
  }

  // Lobby & Control flow transitions
  void handleJoined({
    required int playerId,
    required int roomCode,
    required int role,
  }) {
    _playerId = playerId;
    _roomCode = roomCode;
    _role = role;
    _errorNotice = null;
    if (_role == 1) {
      _phase = ClientPhase.waitingForPeer;
    } else {
      _phase = ClientPhase.inMatch;
      _localLetters = 0;
      _peerLetters = 0;
      _isMyTurn = false; // Joiner is defender first (not my turn)
    }
    notifyListeners();
  }

  void handlePeerJoined(int peerId) {
    if (_phase == ClientPhase.waitingForPeer) {
      _phase = ClientPhase.inMatch;
      _localLetters = 0;
      _peerLetters = 0;
      _isMyTurn = true; // Creator is setter first (my turn)
      notifyListeners();
    }
  }

  void handlePeerLeft(int peerId) {
    _notice = "Peer left. Room cleared.";
    _clearIdentity();
    _localLetters = 0;
    _peerLetters = 0;
    triggerReconnect();
  }

  void handleCancel() {
    _notice = "Match canceled.";
    _clearIdentity();
    _localLetters = 0;
    _peerLetters = 0;
    triggerReconnect();
  }

  void handleLeaveMatch() {
    _notice = "Left match.";
    _clearIdentity();
    _localLetters = 0;
    _peerLetters = 0;
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
    _roomCode = null;
    _role = null;
    _errorNotice = null;
  }

  void clearNotice() {
    _notice = null;
    notifyListeners();
  }
}
