import 'dart:math';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// ---------------------------------------------------------------------------
/// Glute Kickback (Right Leg) - Time based logic
/// ---------------------------------------------------------------------------
class GluteKickbackRightLogic extends TimeExerciseLogic {
  int _seconds = 0;
  String _feedback = "Get Ready";

  DateTime? _startTime;
  bool _isHolding = false;

  final double _angleThreshold = 160.0; // Angle at hip (standing) vs extended
  final double _minConfidence = 0.7;

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    if (landmarks.isEmpty) return;

    final rightHip = _getLandmark(landmarks, PoseLandmarkType.rightHip);
    final rightKnee = _getLandmark(landmarks, PoseLandmarkType.rightKnee);
    final rightAnkle = _getLandmark(landmarks, PoseLandmarkType.rightAnkle);

    if (rightHip == null || rightKnee == null || rightAnkle == null) {
      _feedback = "Position not detected";
      return;
    }

    if (rightHip.likelihood < _minConfidence ||
        rightKnee.likelihood < _minConfidence ||
        rightAnkle.likelihood < _minConfidence) {
      _feedback = "Low confidence in landmarks";
      return;
    }

    // Angle at the knee
    final kneeAngle = _getAngle(rightHip, rightKnee, rightAnkle);

    if (kneeAngle < _angleThreshold) {
      if (!_isHolding) {
        _isHolding = true;
        _startTime = DateTime.now();
        _feedback = "Hold...";
      } else {
        final elapsed = DateTime.now().difference(_startTime!).inSeconds;
        _seconds = elapsed;
        _feedback = "Holding $_seconds s";
      }
    } else {
      _isHolding = false;
      _startTime = null;
      _feedback = "Kick back your right leg";
    }
  }

  @override
  void reset() {
    _seconds = 0;
    _feedback = "Counter Reset";
    _isHolding = false;
    _startTime = null;
  }

  @override
  String get progressLabel => "Time: $_seconds s ($_feedback)";

  @override
  int get seconds => _seconds;



  /// Utility: Safe landmark getter
  PoseLandmark? _getLandmark(List<dynamic> landmarks, PoseLandmarkType type) {
    try {
      return landmarks.cast<PoseLandmark>().firstWhere((l) => l.type == type);
    } catch (_) {
      return null;
    }
  }

  /// Utility: Angle calculation
  double _getAngle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final ab = Point(a.x - b.x, a.y - b.y);
    final cb = Point(c.x - b.x, c.y - b.y);

    final dot = ab.x * cb.x + ab.y * cb.y;
    final magAB = sqrt(ab.x * ab.x + ab.y * ab.y);
    final magCB = sqrt(cb.x * cb.x + cb.y * cb.y);

    if (magAB == 0 || magCB == 0) return 180.0;

    double cosine = dot / (magAB * magCB);
    cosine = cosine.clamp(-1.0, 1.0);

    return acos(cosine) * 180 / pi;
  }
}
