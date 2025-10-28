// lib/body_posture/exercises/exercises_logic/bw_squat_logic.dart
import 'dart:math';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show RepExerciseLogic;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// ----------------------------
/// 🔹 Enum for Squat States
/// ----------------------------
enum SquatState { up, down }

/// ----------------------------
/// 🔹 Safe landmark extension
/// ----------------------------
extension PoseLandmarksExtension on List<PoseLandmark> {
  PoseLandmark? firstWhereOrNull(bool Function(PoseLandmark) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

/// ----------------------------
/// 🔹 Bodyweight Squat Logic
/// ----------------------------
class BWSquatLogic extends RepExerciseLogic {
  int _squatCount = 0;
  SquatState _currentState = SquatState.up;
  String _feedback = "Get Ready";

  static const double _squatDownAngleThreshold = 100.0;
  static const double _squatUpAngleThreshold = 160.0;
  static const double _minLandmarkConfidence = 0.7;

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    if (landmarks.isEmpty || landmarks.first is! PoseLandmark) {
      _feedback = "No body detected";
      return;
    }

    final casted = landmarks.cast<PoseLandmark>();

    final leftHip = casted.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftHip,
    );
    final leftKnee = casted.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftKnee,
    );
    final leftAnkle = casted.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftAnkle,
    );

    final rightHip = casted.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightHip,
    );
    final rightKnee = casted.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightKnee,
    );
    final rightAnkle = casted.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightAnkle,
    );

    if (leftHip == null ||
        leftKnee == null ||
        leftAnkle == null ||
        rightHip == null ||
        rightKnee == null ||
        rightAnkle == null) {
      _feedback = "Ensure body is visible";
      return;
    }

    if (leftHip.likelihood < _minLandmarkConfidence ||
        leftKnee.likelihood < _minLandmarkConfidence ||
        leftAnkle.likelihood < _minLandmarkConfidence ||
        rightHip.likelihood < _minLandmarkConfidence ||
        rightKnee.likelihood < _minLandmarkConfidence ||
        rightAnkle.likelihood < _minLandmarkConfidence) {
      _feedback = "Move closer to camera";
      return;
    }

    final double leftKneeAngle = _getAngle(leftHip, leftKnee, leftAnkle);
    final double rightKneeAngle = _getAngle(rightHip, rightKnee, rightAnkle);
    final double averageKneeAngle = (leftKneeAngle + rightKneeAngle) / 2;

    if (_currentState == SquatState.up) {
      if (averageKneeAngle < _squatDownAngleThreshold) {
        _currentState = SquatState.down;
        _feedback = "Go deeper!";
      } else {
        _feedback = "Stand tall";
      }
    } else if (_currentState == SquatState.down) {
      if (averageKneeAngle > _squatUpAngleThreshold) {
        _squatCount++;
        _currentState = SquatState.up;
        _feedback = "Rep $_squatCount";
      } else {
        _feedback = "Hold squat";
      }
    }
  }

  @override
  void reset() {
    _squatCount = 0;
    _currentState = SquatState.up;
    _feedback = "Reset";
  }

  @override
  String get progressLabel => "Squats: $_squatCount ($_feedback)";

  @override
  int get reps => _squatCount;
}

/// ----------------------------
/// 🔹 Shared angle helper
/// ----------------------------
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
  return angleRad * 180 / pi;
}
