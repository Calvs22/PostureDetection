//lib/body_posture/exercises_logic/abdominal_crunches_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// -----------------------------------------------------------------------------
// Crunch State Enum
// -----------------------------------------------------------------------------
enum CrunchState { down, up }

// -----------------------------------------------------------------------------
// Old Logic (with ChangeNotifier) - kept for reference
// -----------------------------------------------------------------------------
class AbdominalCrunchesLogic with ChangeNotifier {
  int _crunchCount = 0;
  CrunchState _currentState = CrunchState.down;
  String _feedback = 'Get Ready';

  // Angle thresholds with tolerance ranges
  final double _crunchUpThresholdMinAngle =
      145.0; // Lower bound for up position
  final double _crunchUpThresholdMaxAngle =
      155.0; // Upper bound for up position
  final double _crunchDownThresholdMinAngle =
      170.0; // Lower bound for down position
  final double _crunchDownThresholdMaxAngle =
      180.0; // Upper bound for down position
  final double _minLandmarkConfidence = 0.7;

  // Hysteresis margin to prevent rapid state changes
  final double _hysteresisMargin = 5.0;

  int get crunchCount => _crunchCount;
  String get feedback => _feedback;

  // ADD THIS RESET METHOD
  void reset() {
    _crunchCount = 0;
    _currentState = CrunchState.down;
    _feedback = 'Get Ready';
    notifyListeners();
  }

  void updateCrunchCount(List<PoseLandmark> landmarks) {
    final leftHip = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftHip,
    );
    final leftShoulder = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftShoulder,
    );
    final leftEar = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftEar,
    );

    final rightHip = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightHip,
    );
    final rightShoulder = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightShoulder,
    );
    final rightEar = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightEar,
    );

    final bool allLandmarksValid =
        leftHip != null &&
        leftShoulder != null &&
        leftEar != null &&
        rightHip != null &&
        rightShoulder != null &&
        rightEar != null &&
        leftHip.likelihood >= _minLandmarkConfidence &&
        leftShoulder.likelihood >= _minLandmarkConfidence &&
        leftEar.likelihood >= _minLandmarkConfidence &&
        rightHip.likelihood >= _minLandmarkConfidence &&
        rightShoulder.likelihood >= _minLandmarkConfidence &&
        rightEar.likelihood >= _minLandmarkConfidence;

    if (!allLandmarksValid) {
      _feedback = 'Position not clear';
      return;
    }

    final double leftTorsoAngle = _getAngle(leftHip, leftShoulder, leftEar);
    final double rightTorsoAngle = _getAngle(rightHip, rightShoulder, rightEar);
    final double averageTorsoAngle = (leftTorsoAngle + rightTorsoAngle) / 2;

    switch (_currentState) {
      case CrunchState.down:
        if (averageTorsoAngle < _crunchUpThresholdMaxAngle &&
            averageTorsoAngle > _crunchUpThresholdMinAngle) {
          _currentState = CrunchState.up;
          _feedback = 'Go deeper!';
        } else {
          _feedback = 'Crunch!';
        }
        break;

      case CrunchState.up:
        if (averageTorsoAngle >
                _crunchDownThresholdMinAngle + _hysteresisMargin &&
            averageTorsoAngle < _crunchDownThresholdMaxAngle) {
          _crunchCount++;
          _currentState = CrunchState.down;
          _feedback = 'Rep $_crunchCount';
        } else {
          _feedback = 'Lower back down';
        }
        break;
    }
  }

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final double v1x = p1.x - p2.x;
    final double v1y = p1.y - p2.y;
    final double v2x = p3.x - p2.x;
    final double v2y = p3.y - p2.y;

    final double dotProduct = v1x * v2x + v1y * v2y;
    final double magnitude1 = sqrt(v1x * v1x + v1y * v1y);
    final double magnitude2 = sqrt(v2x * v2x + v2y * v2y);

    if (magnitude1 == 0 || magnitude2 == 0) {
      return 180.0;
    }

    double cosineAngle = dotProduct / (magnitude1 * magnitude2);
    cosineAngle = max(-1.0, min(1.0, cosineAngle));

    double angleRad = acos(cosineAngle);
    return angleRad * 180 / pi;
  }
}

// Safe lookup extension
extension PoseLandmarksExtension on List<PoseLandmark> {
  PoseLandmark? firstWhereOrNull(bool Function(PoseLandmark) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

// -----------------------------------------------------------------------------
// New Logic (RepExerciseLogic only) - FIXED
// -----------------------------------------------------------------------------
class AbdominalCrunchesLogicV2 implements RepExerciseLogic {
  int _count = 0;
  String _feedback = "Get Ready";

  // TTS feedback related fields
  DateTime? _lastFeedbackTime;
  static const Duration _feedbackCooldown = Duration(seconds: 3);

  // Error handling related fields
  bool _isSensorStable = true; // Used for sensor state tracking
  int _consecutivePoorFrames = 0;
  static const int _maxPoorFramesBeforeReset = 10;
  bool _isRecoveringFromSensorIssue = false;

  // Use a persistent instance instead of creating a new one each time
  final AbdominalCrunchesLogic _crunchLogic = AbdominalCrunchesLogic();

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    // Check sensor stability before processing
    _isSensorStable = _checkSensorStability(landmarks);
    if (!_isSensorStable) {
      _consecutivePoorFrames++;

      if (_consecutivePoorFrames >= _maxPoorFramesBeforeReset) {
        _handleSensorFailure();
      }
      return;
    }

    // Reset poor frame counter on good frame
    if (_consecutivePoorFrames > 0) {
      _consecutivePoorFrames = 0;

      // If recovering from sensor issue, provide feedback
      if (_isRecoveringFromSensorIssue) {
        _isRecoveringFromSensorIssue = false;
        _feedback = "Tracking resumed. Continue your exercise.";
        _provideTTSFeedback(_feedback);
      }
    }

    // Use the persistent instance instead of creating a new one
    _crunchLogic.updateCrunchCount(landmarks.cast<PoseLandmark>());

    _count = _crunchLogic.crunchCount;
    _feedback = _crunchLogic.feedback;

    // Provide TTS feedback for important events
    if (_feedback == 'Rep $_count' ||
        _feedback.contains('Go deeper') ||
        _feedback.contains('Position not clear')) {
      _provideTTSFeedback(_feedback);
    }
  }

  @override
  void reset() {
    _count = 0;
    _feedback = "Counter Reset";
    _lastFeedbackTime = null;
    _isSensorStable = true;
    _consecutivePoorFrames = 0;
    _isRecoveringFromSensorIssue = false;
    // Reset the crunch logic instance
    _crunchLogic.reset();
    _provideTTSFeedback("Counter reset. Get ready to start.");
  }

  @override
  String get progressLabel => "Reps: $_count ($_feedback)";

  @override
  int get reps => _count;

  // New method for TTS feedback with cooldown
  void _provideTTSFeedback(String message) {
    final now = DateTime.now();

    // Skip feedback if we're in cooldown period
    if (_lastFeedbackTime != null &&
        now.difference(_lastFeedbackTime!) < _feedbackCooldown) {
      return;
    }

    // Update last feedback time
    _lastFeedbackTime = now;

    // In a real implementation, this would call a TTS service
    // For now, we'll just print the message
    print("TTS: $message");
  }

  // New method for checking sensor stability
  bool _checkSensorStability(List landmarks) {
    // Check if we have enough landmarks
    if (landmarks.length < 10) {
      return false;
    }

    // Check if landmarks have reasonable confidence
    double avgConfidence =
        landmarks.fold(0.0, (sum, landmark) => sum + landmark.likelihood) /
        landmarks.length;

    // Consider sensor unstable if average confidence is too low
    if (avgConfidence < 0.7 * 0.8) {
      // 80% of the min confidence threshold
      return false;
    }

    return true;
  }

  // New method for handling sensor failure
  void _handleSensorFailure() {
    if (!_isRecoveringFromSensorIssue) {
      _isRecoveringFromSensorIssue = true;
      _provideTTSFeedback(
        "Camera tracking issue detected. Please ensure you're visible in the frame.",
      );
    }

    // Reset poor frame counter to allow recovery
    _consecutivePoorFrames = 0;
  }
}
