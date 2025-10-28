//lib/body_posture/exercises_logic/calf_stretch_left_logic.dart

//NEED TESTING

import 'dart:async';
import 'dart:math';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show TimeExerciseLogic;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class CalfStretchLeftLogic implements TimeExerciseLogic {
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _isStretching = false;

  // TTS feedback related fields
  DateTime? _lastFeedbackTime;
  static const Duration _feedbackCooldown = Duration(seconds: 5);
  bool _hasProvidedStartingFeedback = false;

  // Error handling related fields
  bool _isSensorStable = true; // Used for sensor state tracking
  int _consecutivePoorFrames = 0;
  static const int _maxPoorFramesBeforeReset = 10;
  bool _isRecoveringFromSensorIssue = false;

  // Define thresholds with tolerance ranges for a LEFT calf stretch
  final double _leftKneeStraightMinAngle =
      155.0; // Lower bound for straight knee
  final double _leftKneeStraightMaxAngle =
      180.0; // Upper bound for straight knee
  final double _rightKneeBentMaxAngle = 135.0; // Upper bound for bent knee
  final double _rightKneeBentMinAngle = 65.0; // Lower bound for bent knee
  final double _armExtendedMinAngle = 145.0; // Lower bound for extended arms
  final double _armExtendedMaxAngle = 180.0; // Upper bound for extended arms

  // Hysteresis margin to prevent rapid state changes
  final double _hysteresisMargin = 5.0;

  // Previous pose state for hysteresis
  bool _wasInPose = false;

  final double _minLandmarkConfidence = 0.7;

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
        _provideTTSFeedback("Tracking resumed. Continue your stretch.");
      }
    }

    if (landmarks.isEmpty) {
      _stopTimer();
      _isStretching = false;
      return;
    }

    final typedLandmarks = landmarks.cast<PoseLandmark>();

    final leftAnkle = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftAnkle,
    );
    final leftKnee = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftKnee,
    );
    final leftHip = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftHip,
    );
    final leftShoulder = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftShoulder,
    );
    final leftElbow = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftElbow,
    );
    final leftWrist = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftWrist,
    );

    final rightAnkle = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightAnkle,
    );
    final rightKnee = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightKnee,
    );
    final rightHip = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightHip,
    );
    final rightShoulder = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightShoulder,
    );
    final rightElbow = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightElbow,
    );
    final rightWrist = typedLandmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightWrist,
    );

    final allLandmarksValid =
        leftAnkle != null &&
        leftKnee != null &&
        leftHip != null &&
        rightAnkle != null &&
        rightKnee != null &&
        rightHip != null &&
        leftAnkle.likelihood >= _minLandmarkConfidence &&
        leftKnee.likelihood >= _minLandmarkConfidence &&
        leftHip.likelihood >= _minLandmarkConfidence &&
        rightAnkle.likelihood >= _minLandmarkConfidence &&
        rightKnee.likelihood >= _minLandmarkConfidence &&
        rightHip.likelihood >= _minLandmarkConfidence;

    if (!allLandmarksValid) {
      _stopTimer();
      _isStretching = false;
      _hasProvidedStartingFeedback = false;
      _provideTTSFeedback(
        "Please ensure your full body is visible to the camera.",
      );
      return;
    }

    final leftKneeAngle = _getAngle(leftHip, leftKnee, leftAnkle);
    final rightKneeAngle = _getAngle(rightHip, rightKnee, rightAnkle);
    final leftElbowAngle = _getAngle(leftShoulder!, leftElbow!, leftWrist!);
    final rightElbowAngle = _getAngle(rightShoulder!, rightElbow!, rightWrist!);

    // Check pose with tolerance ranges
    final isLeftLegStraight =
        leftKneeAngle >= _leftKneeStraightMinAngle &&
        leftKneeAngle <= _leftKneeStraightMaxAngle;
    final isRightLegBent =
        rightKneeAngle >= _rightKneeBentMinAngle &&
        rightKneeAngle <= _rightKneeBentMaxAngle;
    final areArmsExtended =
        leftElbowAngle >= _armExtendedMinAngle &&
        leftElbowAngle <= _armExtendedMaxAngle &&
        rightElbowAngle >= _armExtendedMinAngle &&
        rightElbowAngle <= _armExtendedMaxAngle;

    final currentlyInStretchPose =
        isLeftLegStraight && isRightLegBent && areArmsExtended;

    // Apply hysteresis to prevent rapid state changes using margin
    final shouldStartStretching =
        currentlyInStretchPose &&
        (!_wasInPose ||
            (leftKneeAngle > _leftKneeStraightMinAngle + _hysteresisMargin &&
                rightKneeAngle < _rightKneeBentMaxAngle - _hysteresisMargin));
    final shouldStopStretching =
        !currentlyInStretchPose &&
        (_wasInPose ||
            (leftKneeAngle < _leftKneeStraightMaxAngle - _hysteresisMargin &&
                rightKneeAngle > _rightKneeBentMinAngle + _hysteresisMargin));

    // Update previous pose state
    _wasInPose = currentlyInStretchPose;

    if (shouldStartStretching && !_isStretching) {
      _isStretching = true;
      _startTimer();
      _hasProvidedStartingFeedback = false;
      // Only provide starting feedback if we haven't already
      if (!_hasProvidedStartingFeedback) {
        _provideTTSFeedback("Good position! Hold this stretch.");
        _hasProvidedStartingFeedback = true;
      }
    } else if (shouldStopStretching && _isStretching) {
      _isStretching = false;
      _stopTimer();
      _provideTTSFeedback(
        "Position changed. Timer paused. Return to the stretch position to continue.",
      );
    }

    // Provide periodic feedback during stretch
    if (_isStretching && _elapsedSeconds > 0 && _elapsedSeconds % 15 == 0) {
      _provideTTSFeedback(
        "Keep stretching. You've held for $_elapsedSeconds seconds.",
      );
    }
  }

  void _startTimer() {
    if (_timer != null && _timer!.isActive) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  @override
  void reset() {
    _stopTimer();
    _elapsedSeconds = 0;
    _isStretching = false;
    _lastFeedbackTime = null;
    _hasProvidedStartingFeedback = false;
    _wasInPose = false;
    _isSensorStable = true;
    _consecutivePoorFrames = 0;
    _isRecoveringFromSensorIssue = false;
  }

  @override
  String get progressLabel => 'Time: ${_formatTime(_elapsedSeconds)}';

  @override
  int get seconds => _elapsedSeconds;

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
    // ignore: avoid_print
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
    if (avgConfidence < _minLandmarkConfidence * 0.8) {
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

    // Stop timer but preserve elapsed time
    _stopTimer();
    _isStretching = false;

    // Reset poor frame counter to allow recovery
    _consecutivePoorFrames = 0;
  }

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final v1x = p1.x - p2.x;
    final v1y = p1.y - p2.y;
    final v2x = p3.x - p2.x;
    final v2y = p3.y - p2.y;
    final dotProduct = v1x * v2x + v1y * v2y;
    final magnitude1 = sqrt(v1x * v1x + v1y * v1y);
    final magnitude2 = sqrt(v2x * v2x + v2y * v2y);
    if (magnitude1 == 0 || magnitude2 == 0) return 180.0;
    var cosineAngle = dotProduct / (magnitude1 * magnitude2);
    cosineAngle = max(-1.0, min(1.0, cosineAngle));
    final angleRad = acos(cosineAngle);
    return angleRad * 180 / pi;
  }

  String _formatTime(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60);
    final seconds = (totalSeconds % 60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// Helper extension
extension PoseLandmarkListExtension on Iterable<PoseLandmark> {
  PoseLandmark? firstWhereOrNull(bool Function(PoseLandmark) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
