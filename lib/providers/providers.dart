import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../services/vision_service.dart';
import '../services/live_gemini_service.dart';
import '../services/mic_service.dart';
import '../services/speaker_service.dart';
import '../services/servo_ble_service.dart';
import '../controllers/robi_controller.dart';
import '../controllers/eye_controller.dart';
import '../controllers/servo_tracking_controller.dart';
import '../models/robi_state.dart';

final visionServiceProvider = Provider<VisionService>((ref) {
  final service = VisionService();
  ref.onDispose(() => service.dispose());
  return service;
});

final liveGeminiServiceProvider = Provider<LiveGeminiService>((ref) {
  final service = LiveGeminiService();
  ref.onDispose(() => service.dispose());
  return service;
});

final micServiceProvider = Provider<MicService>((ref) {
  final service = MicService();
  ref.onDispose(() => service.dispose());
  return service;
});

final speakerServiceProvider = Provider<SpeakerService>((ref) {
  final service = SpeakerService();
  ref.onDispose(() => service.dispose());
  return service;
});

final robiControllerProvider = StateNotifierProvider<RobiController, RobiState>((ref) {
  final controller = RobiController(
    vision: ref.watch(visionServiceProvider),
    liveGemini: ref.watch(liveGeminiServiceProvider),
    mic: ref.watch(micServiceProvider),
    speaker: ref.watch(speakerServiceProvider),
  );
  return controller;
});

final robiTranscriptionProvider = StreamProvider<String>((ref) {
  return ref.watch(liveGeminiServiceProvider).robiTranscriptionStream;
});

// Built once and NOT dependent on robiControllerProvider, so face tracking
// is never reset by conversation-state changes.
final eyeControllerProvider = StateNotifierProvider<EyeController, Offset>((ref) {
  final vision = ref.watch(visionServiceProvider);
  return EyeController(vision: vision);
});

final servoBleServiceProvider = Provider<ServoBleService>((ref) {
  final service = ServoBleService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Drives the physical pan-tilt mount from the face error. Independent of
// conversation state (reads RobiState per-tick via ref.read, never watch) so it
// is not rebuilt when Robi changes state, mirroring EyeController.
final servoTrackingProvider = Provider<ServoTrackingController>((ref) {
  final controller = ServoTrackingController(
    vision: ref.watch(visionServiceProvider),
    servo: ref.watch(servoBleServiceProvider),
    readState: () => ref.read(robiControllerProvider),
  );
  ref.onDispose(() => controller.dispose());
  return controller;
});
