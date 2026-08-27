import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/packet_dispatcher.dart';
import 'core/network/signaling_service.dart';
import 'core/state/app_state.dart';
import 'ui/screens/match_screen.dart';

/// Relay endpoint. Localhost works through an ADB reverse tunnel in dev.
const String relayUrl = 'ws://127.0.0.1:8080';

void main() {
  final appState = AppState();
  final dispatcher = PacketDispatcher(appState);
  final signalingService = SignalingService();

  signalingService.connect(
    relayUrl,
    onMessage: dispatcher.dispatch,
    onStatusChange: (status) {
      appState.setConnectionStatus(status == 'Connected');
    },
  );

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: MatchScreen(
          appState: appState,
          signalingService: signalingService,
        ),
      ),
    ),
  );
}
