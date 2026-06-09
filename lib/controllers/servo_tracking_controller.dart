import 'dart:async';
import 'dart:ui' show Offset;
import '../models/robi_state.dart';
import '../services/vision_service.dart';
import '../services/servo_ble_service.dart';

/// Closed-loop visual servoing: nudges the physical pan-tilt mount so the user
/// stays centered in the camera. Driven by the same face-position error the
/// on-screen eye uses, but kept independent of conversation state (constructed
/// once, like EyeController) so tracking never resets.
///
/// Stateless on position: the ESP owns the angle. Each tick, while the face is
/// outside the deadzone, we send ONE 1° nudge token ("left"/"right"/"up"/
/// "down"); the ESP slews 1° and we re-read the face next tick. So a face far
/// off-center streams a token every tick ("1 1 1 1…") until it re-centers, then
/// stops. Self-correcting and immune to app/ESP angle drift.
class ServoTrackingController {
  final VisionService _vision;
  final ServoBleService _servo;
  final RobiState Function() _readState;

  StreamSubscription? _faceSub;
  Timer? _ticker;

  // Latest normalized face offset (0..1, dead-center = 0.5,0.5); null when lost.
  Offset? _latestOffset;

  // --- Tuning -------------------------------------------------------------
  // Ignore small errors so a roughly-centered face doesn't cause hunting.
  static const double _panDeadzone = 0.12;
  static const double _tiltDeadzone = 0.15;
  // How often we evaluate + send (decoupled from camera frame rate).
  static const Duration _tickInterval = Duration(milliseconds: 120);
  // ------------------------------------------------------------------------

  ServoTrackingController({
    required VisionService vision,
    required ServoBleService servo,
    required RobiState Function() readState,
  })  : _vision = vision,
        _servo = servo,
        _readState = readState {
    _start();
  }

  void _start() {
    _servo.connect();
    _faceSub = _vision.faceDataStream.listen((data) {
      // normalizedOffset is null when no face → mark lost so we hold position.
      _latestOffset = data.normalizedOffset;
    });
    _ticker = Timer.periodic(_tickInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    final offset = _latestOffset;
    if (offset == null) return;                       // face lost → hold
    if (_readState() == RobiState.speaking) return;   // pause while Robi speaks

    final ex = offset.dx - 0.5;
    final ey = offset.dy - 0.5;

    // Pan: face mirrored-right (ex>0) → "right". Correct as mounted.
    if (ex.abs() > _panDeadzone) {
      await _servo.sendCommand(ex > 0 ? 'right' : 'left');
    }
    // Tilt: negative error (face above center) → up, positive → down.
    if (ey.abs() > _tiltDeadzone) {
      await _servo.sendCommand(ey > 0 ? 'down' : 'up');
    }
  }

  void dispose() {
    _ticker?.cancel();
    _faceSub?.cancel();
  }
}
