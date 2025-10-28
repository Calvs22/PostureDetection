// lib/body_posture/exercises_logic/arm_raises_logic.dart

import 'dart:math';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show RepExerciseLogic;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:collection/collection.dart';

class ArmRaisesLogic implements RepExerciseLogic {
  int _armRaiseCount = 0;
  bool _isArmRaiseRepInProgress = false;

  final double _raiseUpAngleThreshold = 120.0;
  final double _raiseDownAngleThreshold = 160.0;
  final double _minLandmarkConfidence = 0.7;

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    final poseLandmarks = landmarks.cast<PoseLandmark>();

    final leftHip = poseLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftHip,
    );
    final leftShoulder = poseLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftShoulder,
    );
    final leftElbow = poseLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftElbow,
    );
    final rightHip = poseLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightHip,
    );
    final rightShoulder = poseLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightShoulder,
    );
    final rightElbow = poseLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightElbow,
    );

    if (leftHip == null ||
        leftShoulder == null ||
        leftElbow == null ||
        rightHip == null ||
        rightShoulder == null ||
        rightElbow == null ||
        leftHip.likelihood < _minLandmarkConfidence ||
        leftShoulder.likelihood < _minLandmarkConfidence ||
        leftElbow.likelihood < _minLandmarkConfidence ||
        rightHip.likelihood < _minLandmarkConfidence ||
        rightShoulder.likelihood < _minLandmarkConfidence ||
        rightElbow.likelihood < _minLandmarkConfidence) {
      if (_isArmRaiseRepInProgress) {
        _isArmRaiseRepInProgress = false;
      }
      return;
    }

    final double leftShoulderAngle = _getAngle(leftHip, leftShoulder, leftElbow);
    final double rightShoulderAngle =
        _getAngle(rightHip, rightShoulder, rightElbow);
    final double averageShoulderAngle =
        (leftShoulderAngle + rightShoulderAngle) / 2;

    if (averageShoulderAngle < _raiseUpAngleThreshold &&
        !_isArmRaiseRepInProgress) {
      _isArmRaiseRepInProgress = true;
    } else if (averageShoulderAngle > _raiseDownAngleThreshold &&
        _isArmRaiseRepInProgress) {
      _armRaiseCount++;
      _isArmRaiseRepInProgress = false;
    }
  }

  @override
  void reset() {
    _armRaiseCount = 0;
    _isArmRaiseRepInProgress = false;
  }

  @override
  String get progressLabel => 'Arm Raises: $_armRaiseCount';

  @override
  int get reps => _armRaiseCount;

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final double v1x = p1.x - p2.x;
    final double v1y = p1.y - p2.y;
    final double v2x = p3.x - p2.x;
    final double v2y = p3.y - p2.y;

    final double dotProduct = v1x * v2x + v1y * v2y;
    final double magnitude1 = sqrt(v1x * v1x + v1y * v1y);
    final double magnitude2 = sqrt(v2x * v2x + v2y * v2y);

    if (magnitude1 == 0 || magnitude2 == 0) return 180.0;

    double cosineAngle = dotProduct / (magnitude1 * magnitude2);
    cosineAngle = max(-1.0, min(1.0, cosineAngle));

    double angleRad = acos(cosineAngle);
    double angleDeg = angleRad * 180 / pi;

    if (angleDeg > 180) {
      angleDeg = 360 - angleDeg;
    }
    return angleDeg;
  }
}