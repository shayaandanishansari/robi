import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import 'widgets/eye_widget.dart';

class FacePage extends ConsumerStatefulWidget {
  const FacePage({super.key});
  @override
  ConsumerState<FacePage> createState() => _FacePageState();
}

class _FacePageState extends ConsumerState<FacePage> {
  @override
  void initState() {
    super.initState();
    // Build the controllers so they request permissions and start the pipeline
    // (robi conversation + eye) and the BLE servo face-following loop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(robiControllerProvider);
      ref.read(servoTrackingProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: EyeWidget()),
    );
  }
}
