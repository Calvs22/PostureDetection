// lib/camera/pose_painter.dart
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// Your existing extension
extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

class PosePainter extends CustomPainter {
  final List<PoseLandmark> landmarks;
  final Size cameraSize; // This is the size of the CameraPreview widget
  final Size imageSize; // This is the actual image size from the camera stream
  final bool isFrontCamera;

  PosePainter({
    required this.landmarks,
    required this.cameraSize,
    required this.imageSize,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintPoint = Paint()
      ..color = Colors.green
      ..strokeWidth = 6.0
      ..style = PaintingStyle.fill;

    final paintLine = Paint()
      ..color = Colors.red
      ..strokeWidth = 4.0;

    // Calculate scale factors based on the camera widget's dimensions
    final double scaleX = cameraSize.width / imageSize.width;
    final double scaleY = cameraSize.height / imageSize.height;

    Offset scaled(PoseLandmark lm) {
      double x = lm.x * scaleX;
      double y = lm.y * scaleY;

      if (isFrontCamera) {
        x = cameraSize.width - x;
      }

      return Offset(x, y);
    }

    if (landmarks.isEmpty) return;

    for (final pair in _fullBodyConnections) {
      final a = landmarks.firstWhereOrNull((e) => e.type == pair[0]);
      final b = landmarks.firstWhereOrNull((e) => e.type == pair[1]);

      if (a != null && b != null) {
        canvas.drawLine(scaled(a), scaled(b), paintLine);
      }
    }

    for (final lm in landmarks) {
      canvas.drawCircle(scaled(lm), 6, paintPoint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is PosePainter &&
        (landmarks != oldDelegate.landmarks ||
            cameraSize != oldDelegate.cameraSize ||
            imageSize != oldDelegate.imageSize ||
            isFrontCamera != oldDelegate.isFrontCamera);
  }
}

final List<List<PoseLandmarkType>> _fullBodyConnections = [
  [PoseLandmarkType.nose, PoseLandmarkType.leftEyeInner],
  [PoseLandmarkType.leftEyeInner, PoseLandmarkType.leftEye],
  [PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeOuter],
  [PoseLandmarkType.leftEyeOuter, PoseLandmarkType.leftEar],
  [PoseLandmarkType.nose, PoseLandmarkType.rightEyeInner],
  [PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye],
  [PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter],
  [PoseLandmarkType.rightEyeOuter, PoseLandmarkType.rightEar],
  [PoseLandmarkType.leftMouth, PoseLandmarkType.rightMouth],
  [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
  [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
  [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
  [PoseLandmarkType.leftWrist, PoseLandmarkType.leftThumb],
  [PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndex],
  [PoseLandmarkType.leftWrist, PoseLandmarkType.leftPinky],
  [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
  [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
  [PoseLandmarkType.rightWrist, PoseLandmarkType.rightThumb],
  [PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndex],
  [PoseLandmarkType.rightWrist, PoseLandmarkType.rightPinky],
  [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
  [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
  [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
  [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
  [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
  [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
  [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex],
  [PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex],
  [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
  [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
  [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex],
  [PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex],
];
