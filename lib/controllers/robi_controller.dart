import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/robi_state.dart';
import '../services/vision_service.dart';
import '../services/live_gemini_service.dart';
import '../services/mic_service.dart';
import '../services/speaker_service.dart';

class TranscriptionEntry {
  final DateTime timestamp;
  final String role; // 'user' or 'robi'
  final String text;
  TranscriptionEntry({required this.timestamp, required this.role, required this.text});

  @override
  String toString() => '[${timestamp.toIso8601String()}] [$role] $text';
}

class RobiController extends StateNotifier<RobiState> {
  final VisionService _visionService;
  final LiveGeminiService _liveGemini;
  final MicService _mic;
  final SpeakerService _speaker;

  StreamSubscription? _audioSubscription;
  StreamSubscription? _micSubscription;
  StreamSubscription? _visionSubscription;
  StreamSubscription? _interruptionSubscription;
  StreamSubscription? _userTranscriptionSubscription;
  StreamSubscription? _robiTranscriptionSubscription;
  StreamSubscription? _playbackDoneSubscription;
  Timer? _speechEndTimer;
  Timer? _micUnblockTimer;
  Timer? _thinkingTimer;

  // True while Gemini is generating audio. Mic is gated during this window so
  // the speaker output never reaches Gemini and causes an echo loop.
  bool _modelIsSpeaking = false;

  final List<TranscriptionEntry> transcriptionLog = [];

  RobiController({
    required VisionService vision,
    required LiveGeminiService liveGemini,
    required MicService mic,
    required SpeakerService speaker,
  })  : _visionService = vision,
        _liveGemini = liveGemini,
        _mic = mic,
        _speaker = speaker,
        super(RobiState.idle) {
    _start();
  }

  Future<void> _start() async {
    debugPrint("RobiController: Requesting permissions...");
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.microphone] != PermissionStatus.granted) {
      debugPrint("RobiController: Permissions denied.");
      return;
    }

    debugPrint("RobiController: Starting...");

    try {
      await _speaker.configureAudioSession();
      await _speaker.openPlayer();
      await _liveGemini.connect();
      await _visionService.start();
      await _mic.start();
      _setupPipelines();
    } catch (e) {
      debugPrint("RobiController: Initialization error: $e");
    }
  }

  void _setupPipelines() {
    // Mic → Gemini, gated while model is speaking to prevent echo loop
    _micSubscription = _mic.audioStream.listen((chunk) {
      if (!_modelIsSpeaking) {
        _liveGemini.sendAudio(chunk);
      }
    });

    // Camera frames → Gemini
    _visionSubscription = _visionService.imageStream.listen((image) {
      debugPrint("RobiController: Sending vision frame: ${image.length} bytes");
      _liveGemini.sendVideo(image);
    });

    // Gemini → Speaker; block mic and enter speaking state on first audio chunk.
    // Each chunk resets the speech-end timer (our turnComplete replacement).
    _audioSubscription = _liveGemini.audioOutputStream.listen((chunk) {
      if (!_modelIsSpeaking) {
        _modelIsSpeaking = true;
        _thinkingTimer?.cancel();
        _setState(RobiState.speaking);
        debugPrint("RobiController: Mic gated (model speaking).");
      }
      _speaker.playChunk(chunk);
      _resetSpeechEndTimer();
    });

    // User transcription: log it and start the thinking-state debounce timer
    _userTranscriptionSubscription = _liveGemini.userTranscriptionStream.listen((text) {
      transcriptionLog.add(TranscriptionEntry(
        timestamp: DateTime.now(),
        role: 'user',
        text: text,
      ));
      debugPrint("Transcription [user]: $text");

      // Reset timer — if user is still speaking, don't flip to thinking yet
      _thinkingTimer?.cancel();
      if (!_modelIsSpeaking) {
        _thinkingTimer = Timer(const Duration(milliseconds: 400), () {
          if (!_modelIsSpeaking) _setState(RobiState.thinking);
        });
      }
    });

    // Robi transcription: just log it (drives the word-pulse animation)
    _robiTranscriptionSubscription = _liveGemini.robiTranscriptionStream.listen((text) {
      transcriptionLog.add(TranscriptionEntry(
        timestamp: DateTime.now(),
        role: 'robi',
        text: text,
      ));
      debugPrint("Transcription [robi]: $text");
    });

    // Interruption: flush speaker and unblock mic immediately
    _interruptionSubscription = _liveGemini.onInterrupted.listen((_) {
      debugPrint("RobiController: Interrupted by Gemini server.");
      _speechEndTimer?.cancel();
      _micUnblockTimer?.cancel();
      _thinkingTimer?.cancel();
      _playbackDoneSubscription?.cancel();
      _modelIsSpeaking = false;
      _speaker.stop();
      _setState(RobiState.idle);
    });
  }

  // Replaces onTurnComplete: when no Gemini audio chunk arrives for 1s, Robi has
  // finished streaming. Wait for the speaker buffer to drain (so animation lives
  // through the last word), then give room acoustics 1200ms before listening.
  void _resetSpeechEndTimer() {
    _speechEndTimer?.cancel();
    _speechEndTimer = Timer(const Duration(milliseconds: 1000), () {
      debugPrint("RobiController: Audio silence — waiting for playback to finish.");
      _playbackDoneSubscription?.cancel();
      if (!_speaker.hasAudioPending) {
        _startMicUnblockTimer();
      } else {
        _playbackDoneSubscription = _speaker.onPlaybackDone.listen((_) {
          _playbackDoneSubscription?.cancel();
          _startMicUnblockTimer();
        });
      }
    });
  }

  void _startMicUnblockTimer() {
    _micUnblockTimer?.cancel();
    _micUnblockTimer = Timer(const Duration(milliseconds: 1200), () {
      _modelIsSpeaking = false;
      _setState(RobiState.idle);
      debugPrint("RobiController: Mic unblocked.");
    });
  }

  void _setState(RobiState newState) {
    if (state != newState) {
      state = newState;
      debugPrint("RobiController: State → $newState");
    }
  }

  @override
  void dispose() {
    _speechEndTimer?.cancel();
    _micUnblockTimer?.cancel();
    _thinkingTimer?.cancel();
    _audioSubscription?.cancel();
    _micSubscription?.cancel();
    _visionSubscription?.cancel();
    _interruptionSubscription?.cancel();
    _userTranscriptionSubscription?.cancel();
    _robiTranscriptionSubscription?.cancel();
    _playbackDoneSubscription?.cancel();
    super.dispose();
  }
}
