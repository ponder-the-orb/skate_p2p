import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/ui/build_info.dart';

void main() {
  // Like `relayUrl`, the override is compile-time
  // (`--dart-define=APP_VERSION=...`) and cannot be exercised from a unit
  // test; T4.6 wires the real value into store builds and the Producer's
  // manual pass proves it. What a test can pin is the default every
  // un-flagged build — and CI, and every dev run — gets.
  test('appVersion defaults to dev when no APP_VERSION define is passed', () {
    expect(appVersion, 'dev');
  });
}
