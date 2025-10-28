// lib/exercises/knee_to_chest_stretch_right.dart

//NEED TESTING

import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show TimeExerciseLogic;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class KneeToChestStretchRightLogic implements TimeExerciseLogic {
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _isHoldingPose = false;

  // Threshold values for accurate detection
  final double _rightKneeBentThresholdAngle =
      120.0; // Angle of right Hip-Knee-Ankle when bent
  final double _leftKneeStraightThresholdAngle =
      170.0; // Angle of left Hip-Knee-Ankle when straight
  final double _kneeLiftThresholdY =
      0.15; // Vertical Y-difference between right knee and shoulder
  final double _minLandmarkConfidence =
      0.7; // Minimum confidence for detected landmarks
  final double _angleTolerance = 10.0; // Tolerance range for angle thresholds

  // Performance optimization variables
  final double _smoothingFactor = 0.3; // 30% smoothing factor reduces jitter
  double _smoothedRightKneeAngle = 180.0;
  double _smoothedLeftKneeAngle = 180.0;
  double _smoothedKneeLiftRatio = 0.0;
  double _rightKneeVelocity = 0.0;
  double _leftKneeVelocity = 0.0;
  double _kneeLiftVelocity = 0.0;
  DateTime _lastUpdateTime = DateTime.now();

  // Enhanced prediction variables
  final List<double> _rightKneeAngleHistory = [];
  final List<double> _leftKneeAngleHistory = [];
  final List<double> _kneeLiftRatioHistory = [];
  final List<DateTime> _timeHistory = [];
  final int _historySize = 5;
  double _predictedRightKneeAngle = 180.0;
  double _predictedLeftKneeAngle = 180.0;
  double _predictedKneeLiftRatio = 0.0;
  final double _linearExtrapolationWeight = 0.4;
  final double _patternMatchingWeight = 0.3;
  final double _velocityBasedWeight = 0.3;

  // Form analysis variables
  final double _spineStraightnessTolerance =
      10.0; // Tolerance for spine straightness
  final List<bool> _poseStabilityHistory = [];
  final int _stabilityCheckInterval = 3; // Check stability every 3 seconds
  DateTime _lastStabilityCheck = DateTime.now();

  // Performance monitoring variables
  final List<Duration> _holdDurations = [];
  DateTime _holdStartTime = DateTime.now();
  double _poseStabilityPercentage = 100.0; // Percentage of time in correct pose
  int _totalPoseChecks = 0;
  int _correctPoseChecks = 0;

  // TTS variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackSecond = 0;
  DateTime _lastFormFeedbackTime = DateTime.now();
  final Duration _formFeedbackCooldown = const Duration(seconds: 4);
  String? _lastFormFeedback;

  // Error handling variables
  int _consecutiveErrors = 0;
  final int _maxConsecutiveErrors = 3;

  KneeToChestStretchRightLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    _isTtsInitialized = true;
  }

  Future<void> _speak(String text) async {
    if (_isTtsInitialized) {
      await _flutterTts.speak(text);
    }
  }

  Future<void> _speakWithRate(String text, double rate) async {
    if (_isTtsInitialized) {
      const originalRate = 0.5; // We set this in _initTts
      await _flutterTts.setSpeechRate(rate);
      await _flutterTts.speak(text);
      await _flutterTts.setSpeechRate(originalRate);
    }
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    final List<PoseLandmark> poseLandmarks = landmarks.cast<PoseLandmark>();

    // --- Landmark Retrieval ---
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final leftKnee = _getLandmark(poseLandmarks, PoseLandmarkType.leftKnee);
    final leftAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.leftAnkle);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final rightKnee = _getLandmark(poseLandmarks, PoseLandmarkType.rightKnee);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);
    final rightShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.rightShoulder,
    );
    final leftShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.leftShoulder,
    );

    // Validate landmarks
    final bool allValid = _areLandmarksValid([
      leftHip,
      leftKnee,
      leftAnkle,
      rightHip,
      rightKnee,
      rightAnkle,
      rightShoulder,
      leftShoulder,
    ]);

    if (!allValid) {
      _handleLandmarkError();
      return;
    }

    // First time starting
    if (!_hasStarted) {
      _hasStarted = true;
      _speak("Get into position");
    }

    // --- Pose Detection Logic ---
    final double leftKneeAngle = _getAngle(leftHip!, leftKnee!, leftAnkle!);
    final double rightKneeAngle = _getAngle(rightHip!, rightKnee!, rightAnkle!);

    // Calculate body reference measurements
    final double shoulderDistance = _getDistance(rightShoulder!, leftShoulder!);

    // Vertical difference (Y-axis: top = smaller value, bottom = larger value)
    final double kneeShoulderYDifference = rightKnee.y - rightShoulder.y;
    final double kneeLiftRatio = kneeShoulderYDifference / shoulderDistance;

    // Update movement history for prediction
    _updateMovementHistory(rightKneeAngle, leftKneeAngle, kneeLiftRatio);

    // Calculate velocities for direction tracking
    _calculateVelocities(rightKneeAngle, leftKneeAngle, kneeLiftRatio);

    // Apply smoothing to reduce jitter
    _smoothedRightKneeAngle =
        _smoothingFactor * rightKneeAngle +
        (1 - _smoothingFactor) * _smoothedRightKneeAngle;
    _smoothedLeftKneeAngle =
        _smoothingFactor * leftKneeAngle +
        (1 - _smoothingFactor) * _smoothedLeftKneeAngle;
    _smoothedKneeLiftRatio =
        _smoothingFactor * kneeLiftRatio +
        (1 - _smoothingFactor) * _smoothedKneeLiftRatio;

    // Enhanced prediction algorithm
    _predictMovement();

    // Use predicted values for earlier detection
    final double effectiveRightKneeAngle = _predictedRightKneeAngle;
    final double effectiveLeftKneeAngle = _predictedLeftKneeAngle;
    final double effectiveKneeLiftRatio = _predictedKneeLiftRatio;

    // Check pose with tolerance ranges
    bool currentlyInPose = false;
    if (effectiveRightKneeAngle <
            (_rightKneeBentThresholdAngle + _angleTolerance) &&
        effectiveLeftKneeAngle >
            (_leftKneeStraightThresholdAngle - _angleTolerance) &&
        effectiveKneeLiftRatio < _kneeLiftThresholdY) {
      currentlyInPose = true;
    }

    // Update performance metrics
    _updatePerformanceMetrics(currentlyInPose);

    // Update state
    if (currentlyInPose && !_isHoldingPose) {
      _isHoldingPose = true;
      _holdStartTime = DateTime.now();
      _startTimer();
    } else if (!currentlyInPose && _isHoldingPose) {
      _isHoldingPose = false;
      _stopTimer();

      // Record hold duration
      if (_elapsedSeconds > 0) {
        _holdDurations.add(Duration(seconds: _elapsedSeconds));
      }

      _speak("Adjust your position");
    }

    // Feedback every second
    if (_isHoldingPose &&
        _elapsedSeconds > 0 &&
        _elapsedSeconds != _lastFeedbackSecond) {
      _lastFeedbackSecond = _elapsedSeconds;

      if (_elapsedSeconds % 5 == 0) {
        _speak("Keep holding, $_elapsedSeconds seconds");
      } else if (_elapsedSeconds == 10) {
        _speak("Great job! Halfway there");
      } else if (_elapsedSeconds >= 15) {
        _speak("Almost done! You can do it");
      }
    }

    // Provide form feedback
    _provideFormFeedback(
      effectiveRightKneeAngle,
      effectiveLeftKneeAngle,
      effectiveKneeLiftRatio,
      rightHip,
      leftHip,
      rightShoulder,
      leftShoulder,
    );
  }

  void _updateMovementHistory(
    double rightKneeAngle,
    double leftKneeAngle,
    double kneeLiftRatio,
  ) {
    _rightKneeAngleHistory.add(rightKneeAngle);
    _leftKneeAngleHistory.add(leftKneeAngle);
    _kneeLiftRatioHistory.add(kneeLiftRatio);
    _timeHistory.add(DateTime.now());

    // Keep history at the specified size
    if (_rightKneeAngleHistory.length > _historySize) {
      _rightKneeAngleHistory.removeAt(0);
      _leftKneeAngleHistory.removeAt(0);
      _kneeLiftRatioHistory.removeAt(0);
      _timeHistory.removeAt(0);
    }
  }

  void _calculateVelocities(
    double rightKneeAngle,
    double leftKneeAngle,
    double kneeLiftRatio,
  ) {
    final DateTime now = DateTime.now();
    final double timeDelta =
        now.difference(_lastUpdateTime).inMilliseconds / 1000.0;

    if (timeDelta > 0) {
      _rightKneeVelocity =
          (rightKneeAngle - _smoothedRightKneeAngle) / timeDelta;
      _leftKneeVelocity = (leftKneeAngle - _smoothedLeftKneeAngle) / timeDelta;
      _kneeLiftVelocity = (kneeLiftRatio - _smoothedKneeLiftRatio) / timeDelta;
    }

    _lastUpdateTime = now;
  }

  void _predictMovement() {
    if (_rightKneeAngleHistory.length < 2) {
      _predictedRightKneeAngle = _smoothedRightKneeAngle;
      _predictedLeftKneeAngle = _smoothedLeftKneeAngle;
      _predictedKneeLiftRatio = _smoothedKneeLiftRatio;
      return;
    }

    // Linear extrapolation prediction
    double linearRightKneePrediction = _smoothedRightKneeAngle;
    double linearLeftKneePrediction = _smoothedLeftKneeAngle;
    double linearLiftPrediction = _smoothedKneeLiftRatio;

    if (_rightKneeAngleHistory.length >= 2) {
      final double rightKneeSlope =
          (_rightKneeAngleHistory.last -
              _rightKneeAngleHistory[_rightKneeAngleHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;
      final double leftKneeSlope =
          (_leftKneeAngleHistory.last -
              _leftKneeAngleHistory[_leftKneeAngleHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;
      final double liftSlope =
          (_kneeLiftRatioHistory.last -
              _kneeLiftRatioHistory[_kneeLiftRatioHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;

      // Predict 100ms into the future
      linearRightKneePrediction =
          _smoothedRightKneeAngle + rightKneeSlope * 0.1;
      linearLeftKneePrediction = _smoothedLeftKneeAngle + leftKneeSlope * 0.1;
      linearLiftPrediction = _smoothedKneeLiftRatio + liftSlope * 0.1;
    }

    // Pattern matching prediction
    double patternRightKneePrediction = _smoothedRightKneeAngle;
    double patternLeftKneePrediction = _smoothedLeftKneeAngle;
    double patternLiftPrediction = _smoothedKneeLiftRatio;

    // For a stretch exercise, we expect the user to move into position and hold
    // If we have history of holds, we can predict when they might be entering/exiting the pose
    if (_holdDurations.isNotEmpty) {
      final double avgHoldDuration =
          _holdDurations.fold(0, (sum, duration) => sum + duration.inSeconds) /
          _holdDurations.length;

      // Predict based on where we are in the current hold cycle
      if (_isHoldingPose) {
        final double currentHoldProgress =
            DateTime.now().difference(_holdStartTime).inSeconds /
            avgHoldDuration;

        if (currentHoldProgress > 0.8) {
          // Near end of typical hold, predict exiting pose
          patternRightKneePrediction = _rightKneeBentThresholdAngle + 20;
          patternLeftKneePrediction = _leftKneeStraightThresholdAngle - 20;
          patternLiftPrediction = _kneeLiftThresholdY + 0.05;
        }
      }
    }

    // Velocity-based prediction
    final double velocityRightKneePrediction =
        _smoothedRightKneeAngle + _rightKneeVelocity * 0.1;
    final double velocityLeftKneePrediction =
        _smoothedLeftKneeAngle + _leftKneeVelocity * 0.1;
    final double velocityLiftPrediction =
        _smoothedKneeLiftRatio + _kneeLiftVelocity * 0.1;

    // Weighted combination of all prediction methods
    _predictedRightKneeAngle =
        _linearExtrapolationWeight * linearRightKneePrediction +
        _patternMatchingWeight * patternRightKneePrediction +
        _velocityBasedWeight * velocityRightKneePrediction;

    _predictedLeftKneeAngle =
        _linearExtrapolationWeight * linearLeftKneePrediction +
        _patternMatchingWeight * patternLeftKneePrediction +
        _velocityBasedWeight * velocityLeftKneePrediction;

    _predictedKneeLiftRatio =
        _linearExtrapolationWeight * linearLiftPrediction +
        _patternMatchingWeight * patternLiftPrediction +
        _velocityBasedWeight * velocityLiftPrediction;
  }

  void _updatePerformanceMetrics(bool currentlyInPose) {
    // Update pose stability metrics
    _totalPoseChecks++;
    if (currentlyInPose) {
      _correctPoseChecks++;
    }

    // Calculate stability percentage
    if (_totalPoseChecks > 0) {
      _poseStabilityPercentage = (_correctPoseChecks / _totalPoseChecks) * 100;
    }

    // Check stability at intervals
    if (DateTime.now().difference(_lastStabilityCheck).inSeconds >=
        _stabilityCheckInterval) {
      _poseStabilityHistory.add(currentlyInPose);
      _lastStabilityCheck = DateTime.now();

      // Keep only recent history
      if (_poseStabilityHistory.length > 10) {
        _poseStabilityHistory.removeAt(0);
      }
    }
  }

  void _handleLandmarkError() {
    _consecutiveErrors++;

    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      _stopTimer();
      _isHoldingPose = false;
      _speak("Please ensure your full body is visible");
    }
  }

  void _provideFormFeedback(
    double rightKneeAngle,
    double leftKneeAngle,
    double kneeLiftRatio,
    PoseLandmark rightHip,
    PoseLandmark leftHip,
    PoseLandmark rightShoulder,
    PoseLandmark leftShoulder,
  ) {
    if (DateTime.now().difference(_lastFormFeedbackTime) >
        _formFeedbackCooldown) {
      String? feedback;

      // Check for common form issues
      if (rightKneeAngle > (_rightKneeBentThresholdAngle + _angleTolerance)) {
        feedback = "Bend your right knee more";
      } else if (leftKneeAngle <
          (_leftKneeStraightThresholdAngle - _angleTolerance)) {
        feedback = "Straighten your left leg more";
      } else if (kneeLiftRatio > _kneeLiftThresholdY) {
        feedback = "Lift your right knee higher";
      } else if (!_checkHipAlignment(rightHip, leftHip)) {
        feedback = "Keep your hips level";
      } else if (!_checkSpineStraightness(rightShoulder, rightHip)) {
        feedback = "Keep your back straight";
      } else if (_poseStabilityPercentage < 80.0) {
        feedback = "Try to hold the position more steadily";
      } else if (_elapsedSeconds > 0 && _elapsedSeconds % 7 == 0) {
        // Positive feedback for good form
        feedback = "Excellent form!";
      }

      // Provide feedback if new issue detected
      if (feedback != null && feedback != _lastFormFeedback) {
        _speakWithRate(feedback, 0.4);
        _lastFormFeedbackTime = DateTime.now();
        _lastFormFeedback = feedback;
      }
    }
  }

  bool _checkHipAlignment(PoseLandmark rightHip, PoseLandmark leftHip) {
    // Check if hips are level (similar Y-coordinates)
    final double hipYDifference = (rightHip.y - leftHip.y).abs();
    final double hipDistance = _getDistance(rightHip, leftHip);
    final double hipAlignmentRatio = hipYDifference / hipDistance;

    // Check if hip alignment is within tolerance
    return hipAlignmentRatio < 0.05; // 5% of hip distance
  }

  bool _checkSpineStraightness(PoseLandmark shoulder, PoseLandmark hip) {
    // Calculate spine angle to check if back is straight
    final double spineAngle = _getAngle(
      PoseLandmark(
        type: PoseLandmarkType.leftShoulder,
        x: shoulder.x,
        y: shoulder.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: hip.x,
        y: hip.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.leftKnee,
        x: hip.x,
        y: hip.y + 100,
        z: 0.0,
        likelihood: 1.0,
      ),
    );

    // Check if spine angle is within tolerance range (close to 180 degrees for straight back)
    return (spineAngle > (180 - _spineStraightnessTolerance) &&
        spineAngle < (180 + _spineStraightnessTolerance));
  }

  @override
  void reset() {
    _stopTimer();
    _elapsedSeconds = 0;
    _isHoldingPose = false;
    _hasStarted = false;
    _lastFeedbackSecond = 0;
    _smoothedRightKneeAngle = 180.0;
    _smoothedLeftKneeAngle = 180.0;
    _smoothedKneeLiftRatio = 0.0;
    _rightKneeVelocity = 0.0;
    _leftKneeVelocity = 0.0;
    _kneeLiftVelocity = 0.0;
    _rightKneeAngleHistory.clear();
    _leftKneeAngleHistory.clear();
    _kneeLiftRatioHistory.clear();
    _timeHistory.clear();
    _predictedRightKneeAngle = 180.0;
    _predictedLeftKneeAngle = 180.0;
    _predictedKneeLiftRatio = 0.0;
    _holdDurations.clear();
    _poseStabilityHistory.clear();
    _poseStabilityPercentage = 100.0;
    _totalPoseChecks = 0;
    _correctPoseChecks = 0;
    _lastFormFeedbackTime = DateTime.now();
    _lastFormFeedback = null;
    _consecutiveErrors = 0;
    _speak("Exercise reset");
  }

  @override
  String get progressLabel => 'Time: ${_formatTime(_elapsedSeconds)}';

  int get reps => 0; // Not a rep-based exercise

  @override
  int get seconds => _elapsedSeconds; // A time-based exercise

  void _startTimer() {
    if (_timer != null && _timer!.isActive) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  // --- Helpers ---
  PoseLandmark? _getLandmark(
    List<PoseLandmark> landmarks,
    PoseLandmarkType type,
  ) {
    try {
      return landmarks.firstWhere((l) => l.type == type);
    } catch (_) {
      return null;
    }
  }

  bool _areLandmarksValid(List<PoseLandmark?> landmarks) {
    return landmarks.every(
      (l) => l != null && l.likelihood >= _minLandmarkConfidence,
    );
  }

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final double v1x = p1.x - p2.x;
    final double v1y = p1.y - p2.y;
    final double v2x = p3.x - p2.x;
    final double v2y = p3.y - p2.y;

    final double dotProduct = v1x * v2x + v1y * v2y;
    final double magnitude1 = sqrt(v1x * v1x + v1y * v1y);
    final double magnitude2 = sqrt(v2x * v2x + v2y * v2y);

    if (magnitude1 == 0 || magnitude2 == 0) return 180.0;

    double cosine = dotProduct / (magnitude1 * magnitude2);
    cosine = max(-1.0, min(1.0, cosine));

    return acos(cosine) * 180 / pi;
  }

  double _getDistance(PoseLandmark p1, PoseLandmark p2) {
    final double dx = p1.x - p2.x;
    final double dy = p1.y - p2.y;
    return sqrt(dx * dx + dy * dy);
  }

  String _formatTime(int seconds) {
    final int minutes = (seconds ~/ 60);
    final int secs = (seconds % 60);
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
