import 'package:flutter/foundation.dart';

class AppState extends ChangeNotifier {
  // Flat primitive state variables
  int _localLetters = 0;
  int _peerLetters = 0;
  bool _isConnected = false;
  bool _isMyTurn = true; 

  int get localLetters => _localLetters;
  int get peerLetters => _peerLetters;
  bool get isConnected => _isConnected;
  bool get isMyTurn => _isMyTurn;

  void setConnectionStatus(bool status) {
    _isConnected = status;
    notifyListeners(); // Tells the UI to redraw only when state changes
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

}
