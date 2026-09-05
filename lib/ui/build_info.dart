/// What build this is, baked in at compile time. The lobby prints it so a
/// screenshot from a tester carries its own version number.
///
/// Store builds pass the real thing (T4.6 wires it into the release command):
/// `flutter build appbundle --dart-define=APP_VERSION=1.0.0-beta`.
///
/// Must stay `const`: `String.fromEnvironment` is only guaranteed to read the
/// define inside a const context — the same trap `relayUrl` documents.
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'dev',
);
