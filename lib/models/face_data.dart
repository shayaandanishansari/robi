import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceData {
  final Offset? center;
  final Size? imageSize;
  final InputImageRotation? rotation;

  FaceData({this.center, this.imageSize, this.rotation});

  factory FaceData.empty() => FaceData(center: null, imageSize: null, rotation: null);

  /// Face center mapped to a normalized [0,1] offset within the frame, accounting
  /// for image rotation and mirroring X (front camera). Returns null when no face
  /// is present. Shared by the on-screen eye and the servo tracking loop so both
  /// read the exact same error signal.
  Offset? get normalizedOffset {
    if (center == null || imageSize == null || rotation == null) return null;

    final bool isRotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;

    final double rotatedW = isRotated ? imageSize!.height : imageSize!.width;
    final double rotatedH = isRotated ? imageSize!.width : imageSize!.height;

    double dx = center!.dx / rotatedW;
    double dy = center!.dy / rotatedH;

    // Mirror X (front-facing camera)
    dx = 1.0 - dx;

    return Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
  }
}
