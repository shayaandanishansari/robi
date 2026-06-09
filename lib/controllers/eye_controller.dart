import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/vision_service.dart';

/// Tracks the user's face continuously. Built once and never rebuilt on
/// conversation-state changes, so face-following never resets.
class EyeController extends StateNotifier<Offset> {
  final VisionService _visionService;
  StreamSubscription? _visionSubscription;

  EyeController({required VisionService vision})
      : _visionService = vision,
        super(const Offset(0.5, 0.5)) {
    _startTracking();
  }

  void _startTracking() {
    _visionSubscription = _visionService.faceDataStream.listen((data) {
      final offset = data.normalizedOffset;
      // Hold the last position when no face is present (offset == null).
      if (offset != null) state = offset;
    });
  }

  @override
  void dispose() {
    _visionSubscription?.cancel();
    super.dispose();
  }
}
