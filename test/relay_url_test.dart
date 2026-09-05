import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/main.dart';

void main() {
  // The override is compile-time (`--dart-define=RELAY_URL=...`) and cannot be
  // exercised from a unit test; the Producer's manual pass proves it. What a
  // test can pin is the default every un-flagged build — and CI — gets.
  test('relayUrl defaults to localhost when no RELAY_URL define is passed', () {
    expect(relayUrl, 'ws://127.0.0.1:8080');
  });
}
