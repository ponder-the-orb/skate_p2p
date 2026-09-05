import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/packet_dispatcher.dart';
import 'core/network/signaling_service.dart';
import 'core/state/app_state.dart';
import 'ui/clip_environment.dart';
import 'ui/screens/lobby_screen.dart';
import 'ui/screens/match_screen.dart';

/// Relay endpoint, baked in at compile time. Localhost works through an ADB
/// reverse tunnel in dev; override per build to reach a relay elsewhere:
/// `flutter run --dart-define=RELAY_URL=ws://192.168.1.20:8080`.
///
/// Must stay `const`: `String.fromEnvironment` is only guaranteed to read the
/// define inside a const context.
const String relayUrl = String.fromEnvironment(
  'RELAY_URL',
  defaultValue: 'ws://127.0.0.1:8080',
);

void main() {
  final appState = AppState();
  final dispatcher = PacketDispatcher(appState);
  final signalingService = SignalingService();

  void doConnect() {
    signalingService.connect(
      relayUrl,
      onMessage: dispatcher.dispatch,
      onStatusChange: (status) {
        appState.setConnectionStatus(status == 'Connected');
      },
    );
  }

  appState.setSendCallback(signalingService.sendBinary);

  appState.setReconnectCallback(() {
    signalingService.disconnect();
    doConnect();
  });

  // Fire-and-forget: `path_provider` is a platform round trip and the lobby
  // must not wait on it. Until it lands, Rejoin is simply not offered.
  resolveRejoinStore().then(appState.attachRejoinStore);

  doConnect();

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Consumer<AppState>(
          builder: (context, state, child) {
            if (state.phase == ClientPhase.inMatch) {
              return MatchScreen(appState: state);
            } else {
              return LobbyScreen(
                appState: state,
                signalingService: signalingService,
              );
            }
          },
        ),
      ),
    ),
  );
}
