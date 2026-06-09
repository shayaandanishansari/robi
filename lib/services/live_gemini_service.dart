import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LiveGeminiService {
  final String _apiKey = dotenv.get('GEMINI_API_KEY');
  final String _model = "models/gemini-3.1-flash-live-preview";
  late final String _url;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;

  final _audioOutputController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get audioOutputStream => _audioOutputController.stream;

  final _onInterruptedController = StreamController<void>.broadcast();
  Stream<void> get onInterrupted => _onInterruptedController.stream;

  final _onTurnCompleteController = StreamController<void>.broadcast();
  Stream<void> get onTurnComplete => _onTurnCompleteController.stream;

  final _userTranscriptionController = StreamController<String>.broadcast();
  Stream<String> get userTranscriptionStream => _userTranscriptionController.stream;

  final _robiTranscriptionController = StreamController<String>.broadcast();
  Stream<String> get robiTranscriptionStream => _robiTranscriptionController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  LiveGeminiService() {
    _url = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$_apiKey";
  }

  Future<void> connect() async {
    if (_isConnected) return;

    try {
      debugPrint("LiveGemini: Connecting to ${_url.trim()}");
      _channel = WebSocketChannel.connect(Uri.parse(_url.trim()));

      final setupCompleter = Completer<void>();

      _wsSubscription = _channel!.stream.listen((message) {
        if (!setupCompleter.isCompleted) {
          debugPrint("LiveGemini: Handshake successful.");
          setupCompleter.complete();
          _isConnected = true;
          return;
        }
        _handleMessage(message);
      }, onError: (e) {
        debugPrint("LiveGemini: WebSocket Error: $e");
        _isConnected = false;
        if (!setupCompleter.isCompleted) setupCompleter.completeError(e);
      }, onDone: () {
        debugPrint("LiveGemini: Connection closed by server.");
        _isConnected = false;
        if (!setupCompleter.isCompleted) setupCompleter.completeError("Connection closed by server");
      });

      final setup = {
        "setup": {
          "model": _model,
          "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
              "voiceConfig": {
                "prebuiltVoiceConfig": {"voiceName": "Puck"}
              }
            }
          },
          "systemInstruction": {
            "parts": [{"text": "You are Robi, a friendly AI companion. You can see the user through the camera. Keep your responses concise and natural."}]
          },
          "inputAudioTranscription": {},
          "outputAudioTranscription": {}
        }
      };

      debugPrint("LiveGemini: Sending setup message...");
      _channel!.sink.add(jsonEncode(setup));

      await setupCompleter.future.timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint("LiveGemini: Connection failed: $e");
      _isConnected = false;
      rethrow;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final String messageString = (message is Uint8List) ? utf8.decode(message) : message.toString();
      final Map<String, dynamic> response = jsonDecode(messageString);

      final serverContent = response["serverContent"] ?? response["server_content"];
      if (serverContent != null) {
        if (serverContent["interrupted"] == true) {
          debugPrint("LiveGemini: Interrupted flag received.");
          _onInterruptedController.add(null);
        }

        if (serverContent["turnComplete"] == true || serverContent["turn_complete"] == true) {
          debugPrint("LiveGemini: Turn complete.");
          _onTurnCompleteController.add(null);
        }

        final inputTranscription = serverContent["inputTranscription"] ?? serverContent["input_transcription"];
        if (inputTranscription != null && inputTranscription["text"] != null) {
          final text = inputTranscription["text"] as String;
          debugPrint("LiveGemini: User transcription: $text");
          _userTranscriptionController.add(text);
        }

        final outputTranscription = serverContent["outputTranscription"] ?? serverContent["output_transcription"];
        if (outputTranscription != null && outputTranscription["text"] != null) {
          final text = outputTranscription["text"] as String;
          debugPrint("LiveGemini: Robi transcription: $text");
          _robiTranscriptionController.add(text);
        }

        final modelTurn = serverContent["modelTurn"] ?? serverContent["model_turn"];
        if (modelTurn != null) {
          final parts = modelTurn["parts"];
          if (parts != null && parts is List) {
            for (var part in parts) {
              final inlineData = part["inlineData"] ?? part["inline_data"];
              if (inlineData != null && inlineData["data"] != null) {
                final audioData = base64Decode(inlineData["data"]);
                _audioOutputController.add(audioData);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("LiveGemini: Error parsing message: $e");
    }
  }

  void sendAudio(Uint8List audioData) {
    if (!_isConnected || _channel == null) return;

    final message = {
      "realtimeInput": {
        "audio": {
          "data": base64Encode(audioData),
          "mimeType": "audio/pcm;rate=16000"
        }
      }
    };
    _channel!.sink.add(jsonEncode(message));
  }

  void sendVideo(Uint8List imageBytes) {
    if (!_isConnected || _channel == null) return;

    final message = {
      "realtimeInput": {
        "video": {
          "data": base64Encode(imageBytes),
          "mimeType": "image/jpeg"
        }
      }
    };
    _channel!.sink.add(jsonEncode(message));
  }

  void stop() {
    _wsSubscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }

  void dispose() {
    stop();
    _audioOutputController.close();
    _onInterruptedController.close();
    _onTurnCompleteController.close();
    _userTranscriptionController.close();
    _robiTranscriptionController.close();
  }
}
