import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audio_session/audio_session.dart';

class SpeakerService {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlayerInited = false;
  bool _isFeeding = false;

  final _accumulator = BytesBuilder(copy: false);

  final _amplitudeController = StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  final _playbackDoneController = StreamController<void>.broadcast();
  Stream<void> get onPlaybackDone => _playbackDoneController.stream;

  bool get hasAudioPending => _accumulator.length > 0 || _isFeeding;

  // Amplitude profile recorded as chunks arrive, replayed in-sync during playback.
  final _amplitudeHistory = <double>[];
  double _totalAudioBytes = 0.0;
  int _timerTickCount = 0;
  Timer? _amplitudeKeepAliveTimer;

  Future<void> configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,
    ));
    await session.setActive(true);
    debugPrint("SpeakerService: Audio session configured.");
  }

  Future<void> openPlayer() async {
    await _player.openPlayer();
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 24000,
      bufferSize: 8192,
      interleaved: true,
    );
    _isPlayerInited = true;
    debugPrint("SpeakerService: Player opened and streaming.");
  }

  void playChunk(Uint8List chunk) {
    if (!_isPlayerInited || !_player.isOpen()) return;
    _totalAudioBytes += chunk.length;
    _accumulator.add(chunk);
    _analyzeAmplitude(chunk);
    _startAmplitudeKeepAlive();
    _drainAccumulator();
  }

  Future<void> _drainAccumulator() async {
    if (_isFeeding) return;
    _isFeeding = true;
    try {
      while (_accumulator.length > 0 && _player.isOpen()) {
        if (!_player.isPlaying) {
          debugPrint("SpeakerService: Player not playing — restarting stream.");
          await _player.startPlayerFromStream(
            codec: Codec.pcm16,
            numChannels: 1,
            sampleRate: 24000,
            bufferSize: 8192,
            interleaved: true,
          );
        }
        final data = _accumulator.takeBytes();
        await _player.feedUint8FromStream(data);
      }
    } catch (e) {
      debugPrint("SpeakerService: Feed error: $e");
    } finally {
      _isFeeding = false;
      _playbackDoneController.add(null);
    }
  }

  void _startAmplitudeKeepAlive() {
    if (_amplitudeKeepAliveTimer != null) return;
    _timerTickCount = 0;
    _amplitudeKeepAliveTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!hasAudioPending) {
        _resetAmplitudeState();
        _amplitudeController.add(0.0);
        return;
      }
      if (_amplitudeHistory.isEmpty || _totalAudioBytes <= 0) return;

      _timerTickCount++;
      // Replay recorded amplitude profile proportional to actual audio duration.
      // audioDurationTicks = how many 50ms ticks the audio lasts.
      final audioDurationTicks = _totalAudioBytes / (24000.0 * 2.0 * 0.05);
      final progress = (_timerTickCount / audioDurationTicks) % 1.0;
      final idx = (progress * (_amplitudeHistory.length - 1)).round()
          .clamp(0, _amplitudeHistory.length - 1);
      _amplitudeController.add(_amplitudeHistory[idx]);
    });
  }

  void _resetAmplitudeState() {
    _amplitudeKeepAliveTimer?.cancel();
    _amplitudeKeepAliveTimer = null;
    _amplitudeHistory.clear();
    _totalAudioBytes = 0.0;
    _timerTickCount = 0;
  }

  // Flush pending audio on interruption. Player stays running continuously.
  void stop() {
    _accumulator.clear();
    _resetAmplitudeState();
    _amplitudeController.add(0.0);
  }

  void _analyzeAmplitude(Uint8List chunk) {
    if (chunk.isEmpty) return;
    final Int16List int16Data = chunk.buffer.asInt16List(chunk.offsetInBytes, chunk.length ~/ 2);
    double sum = 0;
    for (int i = 0; i < int16Data.length; i++) {
      sum += int16Data[i].abs();
    }
    final amp = ((sum / int16Data.length) / 32768.0).clamp(0.0, 1.0);
    _amplitudeHistory.add(amp);
    _amplitudeController.add(amp);
  }

  void dispose() async {
    _accumulator.clear();
    _resetAmplitudeState();
    if (_player.isOpen()) {
      await _player.stopPlayer();
      await _player.closePlayer();
    }
    _amplitudeController.close();
    _playbackDoneController.close();
  }
}
