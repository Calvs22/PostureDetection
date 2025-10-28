//lib/body_posture/exercises_logic/calf_stretch_right_logic.dart

//NEED TESTING

import 'dart:async';
import 'dart:math';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show TimeExerciseLogic;

class CalfStretchRightLogic implements TimeExerciseLogic {
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

  // Angle thresholds with tolerance ranges
  final double _rightKneeStraightMinAngle =
      155.0; // Lower bound for straight knee
  final double _rightKneeStraightMaxAngle =
      180.0; // Upper bound for straight knee
  final double _leftKneeBentMaxAngle = 135.0; // Upper bound for bent knee
  final double _leftKneeBentMinAngle = 65.0; // Lower bound for bent knee
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

    final casted = landmarks.cast<PoseLandmark>();

    final leftAnkle = _getLandmark(casted, PoseLandmarkType.leftAnkle);
    final leftKnee = _getLandmark(casted, PoseLandmarkType.leftKnee);
    final leftHip = _getLandmark(casted, PoseLandmarkType.leftHip);
    final leftShoulder = _getLandmark(casted, PoseLandmarkType.leftShoulder);
    final leftElbow = _getLandmark(casted, PoseLandmarkType.leftElbow);
    final leftWrist = _getLandmark(casted, PoseLandmarkType.leftWrist);

    final rightAnkle = _getLandmark(casted, PoseLandmarkType.rightAnkle);
    final rightKnee = _getLandmark(casted, PoseLandmarkType.rightKnee);
    final rightHip = _getLandmark(casted, PoseLandmarkType.rightHip);
    final rightShoulder = _getLandmark(casted, PoseLandmarkType.rightShoulder);
    final rightElbow = _getLandmark(casted, PoseLandmarkType.rightElbow);
    final rightWrist = _getLandmark(casted, PoseLandmarkType.rightWrist);

    // Validate landmarks
    final allValid = [
      leftAnkle,
      leftKnee,
      leftHip,
      rightAnkle,
      rightKnee,
      rightHip,
      leftShoulder,
      rightShoulder,
      leftElbow,
      rightElbow,
      leftWrist,
      rightWrist,
    ].every((lm) => lm != null && lm.likelihood >= _minLandmarkConfidence);

    if (!allValid) {
      _stopTimer();
      _isStretching = false;
      _hasProvidedStartingFeedback = false;
      _provideTTSFeedback(
        "Please ensure your full body is visible to the camera.",
      );
      return;
    }

    // Calculate angles with null checks
    final rightKneeAngle =
        rightHip != null && rightKnee != null && rightAnkle != null
        ? _getAngle(rightHip, rightKnee, rightAnkle)
        : 180.0;
    final leftKneeAngle =
        leftHip != null && leftKnee != null && leftAnkle != null
        ? _getAngle(leftHip, leftKnee, leftAnkle)
        : 180.0;
    final leftElbowAngle =
        leftShoulder != null && leftElbow != null && leftWrist != null
        ? _getAngle(leftShoulder, leftElbow, leftWrist)
        : 180.0;
    final rightElbowAngle =
        rightShoulder != null && rightElbow != null && rightWrist != null
        ? _getAngle(rightShoulder, rightElbow, rightWrist)
        : 180.0;

    // Check pose with tolerance ranges
    final isRightLegStraight =
        rightKneeAngle >= _rightKneeStraightMinAngle &&
        rightKneeAngle <= _rightKneeStraightMaxAngle;
    final isLeftLegBent =
        leftKneeAngle >= _leftKneeBentMinAngle &&
        leftKneeAngle <= _leftKneeBentMaxAngle;
    final areArmsExtended =
        leftElbowAngle >= _armExtendedMinAngle &&
        leftElbowAngle <= _armExtendedMaxAngle &&
        rightElbowAngle >= _armExtendedMinAngle &&
        rightElbowAngle <= _armExtendedMaxAngle;

    final inPose = isRightLegStraight && isLeftLegBent && areArmsExtended;

    // Apply hysteresis to prevent rapid state changes using margin
    final shouldStartStretching =
        inPose &&
        (!_wasInPose ||
            (rightKneeAngle > _rightKneeStraightMinAngle + _hysteresisMargin &&
                leftKneeAngle < _leftKneeBentMaxAngle - _hysteresisMargin));
    final shouldStopStretching =
        !inPose &&
        (_wasInPose ||
            (rightKneeAngle < _rightKneeStraightMaxAngle - _hysteresisMargin &&
                leftKneeAngle > _leftKneeBentMinAngle + _hysteresisMargin));

    // Update previous pose state
    _wasInPose = inPose;

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
  String get progressLabel => "Time: ${_formatTime(_elapsedSeconds)}";

  @override
  int get seconds => _elapsedSeconds;

  PoseLandmark? _getLandmark(List<PoseLandmark> list, PoseLandmarkType type) {
    for (final lm in list) {
      if (lm.type == type) return lm;
    }
    return null;
  }

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final v1x = p1.x - p2.x;
    final v1y = p1.y - p2.y;
    final v2x = p3.x - p2.x;
    final v2y = p3.y - p2.y;

    final dot = v1x * v2x + v1y * v2y;
    final mag1 = sqrt(v1x * v1x + v1y * v1y);
    final mag2 = sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0 || mag2 == 0) return 180.0;

    var cos = dot / (mag1 * mag2);
    cos = cos.clamp(-1.0, 1.0);

    return acos(cos) * 180 / pi;
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

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

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
}
