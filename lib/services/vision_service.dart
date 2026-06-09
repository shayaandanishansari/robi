import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/face_data.dart';

class VisionService {
  static const platform = MethodChannel('com.example.robi/image_utils');

  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isProcessing = false;
  CameraImage? _latestImage;

  final _faceDataController = StreamController<FaceData>.broadcast();
  final _imageStreamController = StreamController<Uint8List>.broadcast();

  Stream<FaceData> get faceDataStream => _faceDataController.stream;
  Stream<Uint8List> get imageStream => _imageStreamController.stream;

  Timer? _captureTimer;
  bool _isLive = false;

  Future<void> start() async {
    if (_cameraController != null) return;

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(enableTracking: true),
    );

    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_processCameraImage);

      _startPeriodicCapture();
    } catch (e) {
      debugPrint("VisionService: Error starting camera: $e");
      await stop();
    }
  }

  void _processCameraImage(CameraImage image) async {
    _latestImage = image;
    if (_isProcessing || _faceDetector == null) return;
    _isProcessing = true;

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage != null) {
        final faces = await _faceDetector!.processImage(inputImage);
        if (faces.isNotEmpty) {
          final face = faces.first;
          _faceDataController.add(FaceData(
            center: Offset(
              face.boundingBox.left + face.boundingBox.width / 2,
              face.boundingBox.top + face.boundingBox.height / 2,
            ),
            imageSize: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: inputImage.metadata?.rotation,
          ));
        } else {
          _faceDataController.add(FaceData.empty());
        }
      }
    } catch (e) {
      debugPrint("VisionService: Error processing image: $e");
    } finally {
      _isProcessing = false;
    }
  }

  void _startPeriodicCapture() {
    _captureTimer?.cancel();
    _isLive = true;
    // Capture every 2 seconds to reduce camera load
    _captureTimer = Timer.periodic(const Duration(milliseconds: 2000), (timer) async {
      if (!_isLive || _latestImage == null || _cameraController == null) return;

      final bytes = await _captureFrame(_latestImage!);
      if (bytes != null) {
        _imageStreamController.add(bytes);
      }
    });
  }

  Future<Uint8List?> _captureFrame(CameraImage image) async {
    try {
      if (Platform.isAndroid) {
        final sensorOrientation = _cameraController!.description.sensorOrientation;
        // NV21 on Android: planes[0] contains all data
        final Uint8List bytes = image.planes.first.bytes;

        final result = await platform.invokeMethod('convertNv21ToJpeg', {
          'bytes': bytes,
          'width': image.width,
          'height': image.height,
          'rotation': sensorOrientation,
        });
        return result as Uint8List?;
      } else if (Platform.isIOS) {
        // iOS implementation would need similar native code for BGRA to JPEG
        // For now, focusing on the Android logs provided
        return null;
      }
    } catch (e) {
      debugPrint("VisionService: Error capturing frame: $e");
    }
    return null;
  }

  InputImage? _buildInputImage(CameraImage image) {
    if (_cameraController == null) return null;
    final sensorOrientation = _cameraController!.description.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      const orientations = {
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };
      var rotationCompensation = orientations[_cameraController!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (_cameraController!.description.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> stop() async {
    _isLive = false;
    _captureTimer?.cancel();
    if (_cameraController != null) {
      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();
      _cameraController = null;
    }
    await _faceDetector?.close();
    _faceDetector = null;
    _latestImage = null;
    _faceDataController.add(FaceData.empty());
  }

  void dispose() {
    stop();
    _faceDataController.close();
    _imageStreamController.close();
  }
}
