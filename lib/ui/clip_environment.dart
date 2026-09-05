import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

import '../media/clip_store.dart';
import '../media/rejoin_store.dart';

/// The platform edge of the clips feature: the two questions that can only be
/// answered by asking the device, kept in one small file so the screens below
/// stay about screens.
///
/// The trap this exists for: `camera` has **no Linux desktop implementation**
/// and test VMs have no cameras. Every path through here answers "no camera"
/// instead of throwing, so the Producer's PC build and `flutter test` run
/// exactly as they did before this feature landed.

/// Answers "can this device film?". Injected by tests; hardware behaviour
/// belongs to the manual pass (ticket M3-T3.4).
typedef CameraProbe = Future<bool> Function();

/// Camera availability, probed lazily and exactly once per app run.
///
/// Once is deliberate: `availableCameras()` is a platform round trip, and the
/// answer cannot change while the app is alive.
class CameraAvailability {
  CameraAvailability._();

  static CameraProbe _probe = _probePlatform;
  static Future<bool>? _answer;

  /// The probe result. The first caller starts the probe; everyone after that
  /// awaits the same future.
  static Future<bool> get isAvailable => _answer ??= _probe();

  /// Replaces the probe and forgets any cached answer.
  ///
  /// Passing null restores the real one — call that in a `tearDown` so a test
  /// that pretends there is a camera cannot leak that lie into the next test.
  static void debugSetProbe(CameraProbe? probe) {
    _probe = probe ?? _probePlatform;
    _answer = null;
  }

  static Future<bool> _probePlatform() async {
    try {
      final cameras = await availableCameras();
      return cameras.isNotEmpty;
    } catch (_) {
      // MissingPluginException on Linux desktop, CameraException on a device
      // that refuses to enumerate, anything at all in a test VM. All of them
      // mean the same thing to this app: no Record entry, no crash.
      return false;
    }
  }
}

/// The app's real clip store, rooted at the documents directory ADR-008 names.
///
/// `ClipStore` itself takes the directory as an argument precisely so that it
/// never imports Flutter; this function is the one place that bridge is
/// crossed.
Future<ClipStore> resolveClipStore() async =>
    ClipStore(await getApplicationDocumentsDirectory());

/// The app's real rejoin store, rooted at the same documents directory.
///
/// Mirrors [resolveClipStore], and for the same reason: `path_provider` is
/// imported in this file and nowhere else (the ADR-008 rider), so `RejoinStore`
/// stays a leaf that a test can hand a temp directory.
Future<RejoinStore> resolveRejoinStore() async =>
    RejoinStore(await getApplicationDocumentsDirectory());
