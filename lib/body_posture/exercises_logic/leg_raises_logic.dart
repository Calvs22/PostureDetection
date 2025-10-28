// lib/body_posture/exercises/exercises_logic/leg_raises_logic.dart

//NEED TESTING

// ignore_for_file: cast_from_null_always_fails

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart' show RepExerciseLogic;

/// Handles rep counting for Leg Raises
class LegRaisesLogic implements RepExerciseLogic {
  int _legRaiseCount = 0;
  bool _isLegRaiseRepInProgress = false;

  // Thresholds
  final double _raiseUpAngleThreshold = 120.0;
  final double _raiseDownAngleThreshold = 160.0;
  final double _minLandmarkConfidence = 0.7;
  final double _angleTolerance = 10.0; // Tolerance range for angle thresholds

  // Performance optimization variables
  final double _smoothingFactor = 0.3; // 30% smoothing factor reduces jitter
  double _smoothedHipAngle = 160.0;
  bool _isMovingUp = false;
  bool _isMovingDown = false;
  double _hipVelocity = 0.0;
  DateTime _lastUpdateTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(
    milliseconds: 500,
  ); // Reduced cooldown

  // Enhanced prediction variables
  final List<double> _hipAngleHistory = [];
  final List<DateTime> _timeHistory = [];
  final int _historySize = 5;
  double _predictedHipAngle = 160.0;
  final double _linearExtrapolationWeight = 0.4;
  final double _patternMatchingWeight = 0.3;
  final double _velocityBasedWeight = 0.3;

  // Form analysis variables
  final double _alignmentTolerance = 15.0; // Tolerance for body alignment
  final double _rhythmTolerance =
      0.5; // Tolerance for rhythm consistency (seconds)
  final List<Duration> _repDurations = [];
  DateTime _repStartTime = DateTime.now();

  // TTS variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;
  DateTime _lastFormFeedbackTime = DateTime.now();
  final Duration _formFeedbackCooldown = const Duration(seconds: 3);
  String? _lastFormFeedback;

  LegRaisesLogic() {
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
    final poseLandmarks = landmarks.cast<PoseLandmark>();

    final leftShoulder = poseLandmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.leftShoulder,
      orElse: () => null as PoseLandmark,
    );
    final leftHip = poseLandmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.leftHip,
      orElse: () => null as PoseLandmark,
    );
    final leftKnee = poseLandmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.leftKnee,
      orElse: () => null as PoseLandmark,
    );

    final rightShoulder = poseLandmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.rightShoulder,
      orElse: () => null as PoseLandmark,
    );
    final rightHip = poseLandmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.rightHip,
      orElse: () => null as PoseLandmark,
    );
    final rightKnee = poseLandmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.rightKnee,
      orElse: () => null as PoseLandmark,
    );

    // Check validity
    if (leftShoulder.likelihood < _minLandmarkConfidence ||
        leftHip.likelihood < _minLandmarkConfidence ||
        leftKnee.likelihood < _minLandmarkConfidence ||
        rightShoulder.likelihood < _minLandmarkConfidence ||
        rightHip.likelihood < _minLandmarkConfidence ||
        rightKnee.likelihood < _minLandmarkConfidence) {
      _isLegRaiseRepInProgress = false;
      return;
    }

    // First time starting the exercise
    if (!_hasStarted) {
      _hasStarted = true;
      _repStartTime = DateTime.now();
      _speak("Get into Position");
    }

    // Calculate hip angles
    final double leftHipAngle = _getAngle(leftShoulder, leftHip, leftKnee);
    final double rightHipAngle = _getAngle(rightShoulder, rightHip, rightKnee);
    final double averageHipAngle = (leftHipAngle + rightHipAngle) / 2;

    // Update movement history for prediction
    _updateMovementHistory(averageHipAngle);

    // Calculate velocity for direction tracking
    _calculateVelocity(averageHipAngle);

    // Apply smoothing to reduce jitter
    _smoothedHipAngle =
        _smoothingFactor * averageHipAngle +
        (1 - _smoothingFactor) * _smoothedHipAngle;

    // Enhanced prediction algorithm
    _predictMovement();

    // Use predicted angle for earlier detection
    final double effectiveHipAngle = _predictedHipAngle;

    // Determine movement direction
    _determineMovementDirection(effectiveHipAngle);

    // State machine with enhanced detection
    if (effectiveHipAngle < (_raiseUpAngleThreshold + _angleTolerance) &&
        !_isLegRaiseRepInProgress &&
        _isMovingUp) {
      _isLegRaiseRepInProgress = true;
    } else if (effectiveHipAngle >
            (_raiseDownAngleThreshold - _angleTolerance) &&
        _isLegRaiseRepInProgress &&
        _isMovingDown &&
        DateTime.now().difference(_lastUpdateTime) > _cooldownDuration) {
      _legRaiseCount++;
      _isLegRaiseRepInProgress = false;

      // Record rep duration for rhythm analysis
      final Duration repDuration = DateTime.now().difference(_repStartTime);
      _repDurations.add(repDuration);
      _repStartTime = DateTime.now();

      // Provide feedback during exercise
      if (_legRaiseCount != _lastFeedbackRep) {
        _lastFeedbackRep = _legRaiseCount;

        if (_legRaiseCount % 5 == 0) {
          _speak("$_legRaiseCount reps, keep going!");
        } else if (_legRaiseCount == 10) {
          _speak("Great job! Halfway there!");
        } else if (_legRaiseCount >= 15) {
          _speak("Almost done! You can do it!");
        } else {
          _speak("Good job!");
        }
      }
    }

    // Provide form feedback
    _provideFormFeedback(effectiveHipAngle, leftShoulder, rightShoulder);
  }

  void _updateMovementHistory(double hipAngle) {
    _hipAngleHistory.add(hipAngle);
    _timeHistory.add(DateTime.now());

    // Keep history at the specified size
    if (_hipAngleHistory.length > _historySize) {
      _hipAngleHistory.removeAt(0);
      _timeHistory.removeAt(0);
    }
  }

  void _calculateVelocity(double hipAngle) {
    final DateTime now = DateTime.now();
    final double timeDelta =
        now.difference(_lastUpdateTime).inMilliseconds / 1000.0;

    if (timeDelta > 0) {
      _hipVelocity = (hipAngle - _smoothedHipAngle) / timeDelta;
    }

    _lastUpdateTime = now;
  }

  void _predictMovement() {
    if (_hipAngleHistory.length < 2) {
      _predictedHipAngle = _smoothedHipAngle;
      return;
    }

    // Linear extrapolation prediction
    double linearPrediction = _smoothedHipAngle;

    if (_hipAngleHistory.length >= 2) {
      final double slope =
          (_hipAngleHistory.last -
              _hipAngleHistory[_hipAngleHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;

      // Predict 100ms into the future
      linearPrediction = _smoothedHipAngle + slope * 0.1;
    }

    // Pattern matching prediction for rhythmic exercises
    double patternPrediction = _smoothedHipAngle;

    if (_repDurations.length >= 3) {
      // Calculate average rep duration
      final double avgRepDuration =
          _repDurations.fold(
            0,
            (sum, duration) => sum + duration.inMilliseconds,
          ) /
          _repDurations.length /
          1000.0;

      // Predict based on where we are in the current rep cycle
      final double currentRepProgress =
          DateTime.now().difference(_repStartTime).inMilliseconds /
          1000.0 /
          avgRepDuration;

      if (currentRepProgress < 0.5) {
        // First half of rep (raising legs)
        patternPrediction =
            _raiseDownAngleThreshold -
            (_raiseDownAngleThreshold - _raiseUpAngleThreshold) *
                (currentRepProgress * 2);
      } else {
        // Second half of rep (lowering legs)
        patternPrediction =
            _raiseUpAngleThreshold +
            (_raiseDownAngleThreshold - _raiseUpAngleThreshold) *
                ((currentRepProgress - 0.5) * 2);
      }
    }

    // Velocity-based prediction
    final double velocityPrediction = _smoothedHipAngle + _hipVelocity * 0.1;

    // Weighted combination of all prediction methods
    _predictedHipAngle =
        _linearExtrapolationWeight * linearPrediction +
        _patternMatchingWeight * patternPrediction +
        _velocityBasedWeight * velocityPrediction;
  }

  void _determineMovementDirection(double hipAngle) {
    // Determine direction based on velocity and angle changes
    _isMovingUp = _hipVelocity < -2.0 || hipAngle < _smoothedHipAngle;
    _isMovingDown = _hipVelocity > 2.0 || hipAngle > _smoothedHipAngle;
  }

  void _provideFormFeedback(
    double hipAngle,
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
  ) {
    if (DateTime.now().difference(_lastFormFeedbackTime) >
        _formFeedbackCooldown) {
      String? feedback;

      // Check for common form issues
      if (hipAngle > (_raiseDownAngleThreshold - _angleTolerance)) {
        feedback = "Lower your legs more";
      } else if (hipAngle < (_raiseUpAngleThreshold + _angleTolerance)) {
        feedback = "Raise your legs higher";
      } else if (!_checkBodyAlignment(leftShoulder, rightShoulder)) {
        feedback = "Keep your back flat on the floor";
      } else if (!_checkRhythmConsistency()) {
        feedback = "Maintain a steady rhythm";
      } else if (_legRaiseCount > 0 && _legRaiseCount % 3 == 0) {
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

  bool _checkBodyAlignment(
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
  ) {
    // Calculate shoulder alignment to check if back is flat
    final double shoulderAngle = _getAngle(
      PoseLandmark(
        type: PoseLandmarkType.leftShoulder,
        x: leftShoulder.x,
        y: leftShoulder.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.rightShoulder,
        x: rightShoulder.x,
        y: rightShoulder.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: leftShoulder.x,
        y: leftShoulder.y + 100,
        z: 0.0,
        likelihood: 1.0,
      ),
    );

    // Check if shoulder angle is within tolerance range (close to 180 degrees for flat back)
    return (shoulderAngle > (180 - _alignmentTolerance) &&
        shoulderAngle < (180 + _alignmentTolerance));
  }

  bool _checkRhythmConsistency() {
    if (_repDurations.length < 2) return true;

    // Calculate standard deviation of rep durations
    final double avgDuration =
        _repDurations.fold(
          0,
          (sum, duration) => sum + duration.inMilliseconds,
        ) /
        _repDurations.length;

    double variance = 0;
    for (final duration in _repDurations) {
      variance += pow(duration.inMilliseconds - avgDuration, 2);
    }
    variance /= _repDurations.length;

    final double stdDev = sqrt(variance);

    // Check if standard deviation is within tolerance
    return stdDev < _rhythmTolerance * 1000; // Convert to milliseconds
  }

  @override
  void reset() {
    _legRaiseCount = 0;
    _isLegRaiseRepInProgress = false;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _smoothedHipAngle = 160.0;
    _hipVelocity = 0.0;
    _hipAngleHistory.clear();
    _timeHistory.clear();
    _predictedHipAngle = 160.0;
    _repDurations.clear();
    _lastFormFeedbackTime = DateTime.now();
    _lastFormFeedback = null;
    _speak("Exercise reset");
  }

  @override
  String get progressLabel => "Leg Raises: $_legRaiseCount";

  @override
  int get reps => _legRaiseCount;

  int get seconds => 0;

  // Angle helper
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

    if (angleDeg > 180) angleDeg = 360 - angleDeg;
    return angleDeg;
  }
}
