import 'dart:async';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class MicService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final _audioStreamController = StreamController<Uint8List>.broadcast();
  bool _isRecorderInited = false;

  Stream<Uint8List> get audioStream => _audioStreamController.stream;

  Future<void> start() async {
    try {
      if (!_isRecorderInited) {
        await _recorder.openRecorder();
        _isRecorderInited = true;
      }

      if (await Permission.microphone.isGranted) {
        // Start recording to a stream (16kHz Mono PCM)
        // Using voice_communication source for hardware AEC
        await _recorder.startRecorder(
          toStream: _audioStreamController.sink,
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 16000,
          audioSource: AudioSource.voice_communication,
        );
        debugPrint("MicService: Started streaming with flutter_sound.");
      } else {
        debugPrint("MicService: Permission denied.");
      }
    } catch (e) {
      debugPrint("MicService: Error starting stream: $e");
    }
  }

  Future<void> stop() async {
    if (_recorder.isRecording) {
      await _recorder.stopRecorder();
    }
    debugPrint("MicService: Stopped streaming.");
  }

  void dispose() {
    stop();
    _recorder.closeRecorder();
    _audioStreamController.close();
  }
}
