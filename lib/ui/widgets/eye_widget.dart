import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../models/robi_state.dart';
import 'eye_canvas.dart';

class EyeWidget extends ConsumerStatefulWidget {
  const EyeWidget({super.key});

  @override
  ConsumerState<EyeWidget> createState() => _EyeWidgetState();
}

class _EyeWidgetState extends ConsumerState<EyeWidget>
    with TickerProviderStateMixin {
  late final AnimationController _crescentController;
  late final Animation<double> _crescentAnimation;

  // Each word/phrase from outputTranscription triggers a quick scale spike.
  late final AnimationController _wordPulseController;
  late final Animation<double> _wordPulseAnimation;

  // Speaker amplitude fed straight to the painter (via repaint), so it never
  // rebuilds the position-smoothing TweenAnimationBuilder.
  final ValueNotifier<double> _amplitude = ValueNotifier(0.0);
  StreamSubscription<double>? _amplitudeSub;

  @override
  void initState() {
    super.initState();
    _crescentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _crescentAnimation = CurvedAnimation(
      parent: _crescentController,
      curve: Curves.easeInOut,
    );

    _wordPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _wordPulseAnimation = CurvedAnimation(
      parent: _wordPulseController,
      curve: Curves.easeOut,
    );

    _amplitudeSub =
        ref.read(speakerServiceProvider).amplitudeStream.listen((v) {
      _amplitude.value = v;
    });
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _amplitude.dispose();
    _crescentController.dispose();
    _wordPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetOffset = ref.watch(eyeControllerProvider);
    final robiState = ref.watch(robiControllerProvider);

    // Crescent: oval → arch when thinking
    if (robiState == RobiState.thinking) {
      _crescentController.forward();
    } else {
      _crescentController.reverse();
    }

    // Word pulse: each incoming transcription phrase fires a scale spike then decays
    ref.listen(robiTranscriptionProvider, (_, next) {
      if (next.hasValue && robiState == RobiState.speaking) {
        _wordPulseController.reverse(from: 1.0);
      }
    });

    // Position layer: rebuilt only when the face moves (or state changes).
    // Amplitude/expression go into the painter and only trigger repaints.
    return TweenAnimationBuilder<Offset>(
      tween: Tween<Offset>(begin: targetOffset, end: targetOffset),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      builder: (context, offset, _) => CustomPaint(
        size: Size.infinite,
        painter: EyePainter(
          offset: offset,
          amplitude: _amplitude,
          wordPulse: _wordPulseAnimation,
          crescent: _crescentAnimation,
          state: robiState,
        ),
      ),
    );
  }
}
