// lib/body_posture/exercises/exercises_logic/right_leg_glute_kickback_logic.dart

//NEED TESTING

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';

// Logic class for Right Leg Glute Kickback
class RightLegGluteKickbackLogic implements RepExerciseLogic {
  // CHANGED: implements RepExerciseLogic instead of ExerciseLogic
  int _count = 0;
  bool _isRepInProgress = false;

  // Thresholds for glute kickback detection
  final double _kickbackUpAngleThreshold = 160.0;
  final double _kickbackDownAngleThreshold = 100.0;
  final double _minLandmarkConfidence = 0.7;

  // Tolerance and hysteresis constants
  final double _kickbackAngleTolerance = 10.0; // ±10 degrees tolerance
  final double _hysteresisBuffer = 5.0; // Prevents state flickering

  // Cooldown for rep counting
  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(
    milliseconds: 300,
  ); // 0.3 second cooldown

  // TTS instance and variables
  final FlutterTts _tts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;

  // TTS feedback cooldown
  DateTime? _lastTtsFeedbackTime;
  final Duration _ttsFeedbackCooldown = Duration(seconds: 3);

  // Error handling variables
  DateTime? _lastInvalidLandmarksTime;
  final Duration _gracePeriod = Duration(seconds: 1);
  bool _isInGracePeriod = false;

  // Velocity tracking for anticipation
  double _lastAngle = 0;
  DateTime _lastUpdateTime = DateTime.now();

  // RESTORED: Movement direction tracking - CRITICAL for accurate rep counting
  bool _isMovingUp = false;
  bool _isMovingDown = false;

  // Movement smoothing
  double _smoothedAngle = 0;
  final double _smoothingFactor = 0.3;

  // Enhanced prediction variables
  final List<double> _positionHistory = [];
  final List<DateTime> _timestampHistory = [];
  final int _historySize = 10;

  // Movement pattern recognition
  List<double> _movementPattern = [];
  bool _patternEstablished = false;

  // Prediction weights
  final double _linearWeight = 0.5;
  final double _patternWeight = 0.3;
  final double _velocityWeight = 0.2;

  RightLegGluteKickbackLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _isTtsInitialized = true;
  }

  @override
  String get progressLabel => 'Right Leg Glute Kickbacks: $_count';

  @override
  int get reps => _count; // ADDED: Required getter for RepExerciseLogic interface

  @override
  void update(List landmarks, bool isFrontCamera) {
    // Cast landmarks to the correct type
    final poseLandmarks = landmarks as List<PoseLandmark>;

    // Speak initial message immediately on first update
    if (!_hasStarted) {
      _speak("Get into Position");
      _hasStarted = true;
    }

    // --- Landmark Retrieval ---
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final rightKnee = _getLandmark(poseLandmarks, PoseLandmarkType.rightKnee);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);

    // Validate landmarks
    final bool allNecessaryLandmarksValid = _areLandmarksValid([
      rightHip,
      rightKnee,
      rightAnkle,
    ]);

    // Error handling with grace period
    if (!allNecessaryLandmarksValid) {
      if (!_isInGracePeriod) {
        _lastInvalidLandmarksTime = DateTime.now();
        _isInGracePeriod = true;
        _speak("Adjust position - landmarks unclear");
      } else if (_lastInvalidLandmarksTime != null &&
          DateTime.now().difference(_lastInvalidLandmarksTime!) >
              _gracePeriod) {
        _isRepInProgress = false;
        _isInGracePeriod = false;
        _speak("Position lost - please restart");
        return;
      }
    } else {
      _isInGracePeriod = false;
      _lastInvalidLandmarksTime = null;
    }

    if (rightHip == null || rightKnee == null || rightAnkle == null) {
      _isRepInProgress = false;
      return;
    }

    final double rightLegAngle = _getAngle(rightHip, rightKnee, rightAnkle);

    // Calculate movement velocity for anticipation
    final now = DateTime.now();
    final timeDelta = now.difference(_lastUpdateTime).inMilliseconds / 1000.0;
    final velocity = timeDelta > 0
        ? (rightLegAngle - _lastAngle) / timeDelta
        : 0;

    _lastAngle = rightLegAngle;
    _lastUpdateTime = now;

    // Apply movement smoothing
    _smoothedAngle =
        _smoothedAngle * _smoothingFactor +
        rightLegAngle * (1 - _smoothingFactor);

    // Update prediction history
    _updatePredictionHistory(_smoothedAngle, now);

    // Get enhanced prediction
    final predictedAngle = _predictNextPosition();

    // CRITICAL: Track movement direction for better anticipation
    _isMovingUp = velocity > 30.0; // Moving up threshold (degrees/sec)
    _isMovingDown = velocity < -30.0; // Moving down threshold (degrees/sec)

    // Kickback detection with tolerance and hysteresis
    final bool isKickbackUp = _isRepInProgress
        ? _smoothedAngle > (_kickbackUpAngleThreshold - _hysteresisBuffer)
        : _smoothedAngle >
              (_kickbackUpAngleThreshold - _kickbackAngleTolerance);

    final bool isKickbackDown = _isRepInProgress
        ? _smoothedAngle < (_kickbackDownAngleThreshold + _hysteresisBuffer)
        : _smoothedAngle <
              (_kickbackDownAngleThreshold + _kickbackAngleTolerance);

    // RESTORED: Use prediction for earlier detection - CRUCIAL for accuracy
    final bool willBeKickbackUp = predictedAngle > _kickbackUpAngleThreshold;
    final bool willBeKickbackDown =
        predictedAngle < _kickbackDownAngleThreshold;

    // Form analysis
    _checkForm(
      rightHip,
      rightKnee,
      rightAnkle,
      _smoothedAngle,
      isKickbackUp,
      isKickbackDown,
    );

    // Faster cooldown reset
    if (DateTime.now().difference(_lastRepTime) > _cooldownDuration) {
      if (!_isRepInProgress) {
        _isRepInProgress = true;
      }
    }

    // CRITICAL: Enhanced state detection with prediction and direction
    if ((isKickbackUp && _isMovingUp) || (willBeKickbackUp && _isMovingUp)) {
      if (!_isRepInProgress) {
        _isRepInProgress = true;
      }
    } else if ((isKickbackDown && _isMovingDown) ||
        (willBeKickbackDown && _isMovingDown)) {
      if (_isRepInProgress) {
        _count++;
        _isRepInProgress = false;
        _lastRepTime = DateTime.now();

        // Provide feedback every 5 reps
        if (_count % 5 == 0 && _count != _lastFeedbackRep) {
          _speak("Good job! Keep going!");
          _lastFeedbackRep = _count;
        }

        // Completion feedback
        if (_count == 10) {
          _speak("Almost there! Just a few more!");
        }
      }
    }

    // Check rep rate for performance monitoring
    _checkRepRate();
  }

  @override
  void reset() {
    _count = 0;
    _isRepInProgress = false;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastTtsFeedbackTime = null;
    _lastInvalidLandmarksTime = null;
    _isInGracePeriod = false;

    // Reset performance tracking variables
    _lastAngle = 0;
    _lastUpdateTime = DateTime.now();
    _smoothedAngle = 0;

    // Reset prediction variables
    _positionHistory.clear();
    _timestampHistory.clear();
    _movementPattern.clear();
    _patternEstablished = false;

    // Reset direction tracking
    _isMovingUp = false;
    _isMovingDown = false;

    _lastRepCount = 0;
    _lastRepRateCheck = DateTime.now();

    _speak("Exercise reset");
  }

  // Helper method to get landmark with confidence check
  PoseLandmark? _getLandmark(List landmarks, PoseLandmarkType type) {
    try {
      return landmarks.firstWhere((l) => l.type == type);
    } catch (_) {
      return null;
    }
  }

  // Helper method to validate landmarks
  bool _areLandmarksValid(List<PoseLandmark?> landmarks) {
    return landmarks.every(
      (landmark) =>
          landmark != null && landmark.likelihood >= _minLandmarkConfidence,
    );
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

    double cosine = dot / (mag1 * mag2);
    cosine = max(-1.0, min(1.0, cosine));

    return acos(cosine) * 180 / pi;
  }

  // Form analysis with comprehensive checks
  void _checkForm(
    PoseLandmark? rightHip,
    PoseLandmark? rightKnee,
    PoseLandmark? rightAnkle,
    double angle,
    bool isKickbackUp,
    bool isKickbackDown,
  ) {
    final now = DateTime.now();

    // 1. Check for sufficient kickback height with tolerance
    if (angle < (_kickbackUpAngleThreshold - _kickbackAngleTolerance) &&
        _isRepInProgress) {
      _provideFormFeedback("Kick your leg higher", now);
    }

    // 2. Check for full range of motion
    if (angle > (_kickbackDownAngleThreshold + _kickbackAngleTolerance) &&
        !_isRepInProgress) {
      _provideFormFeedback("Return to starting position", now);
    }

    // 3. Check for hip stability (hips shouldn't move much during kickbacks)
    if (rightHip != null) {
      // This is a simplified check - in practice, you'd need to track hip movement over time
      if (_count > 3) {
        // Only check after a few reps
        _provideFormFeedback("Keep your hips stable", now);
      }
    }

    // 4. Check for steady rhythm
    final Duration timeSinceLastRep = DateTime.now().difference(_lastRepTime);
    if (timeSinceLastRep > Duration(seconds: 2) && _count > 2) {
      _provideFormFeedback("Keep a steady rhythm", now);
    }

    // Positive feedback for good form with tolerance
    if (angle > (_kickbackUpAngleThreshold + _kickbackAngleTolerance) &&
        _count > 3) {
      _provideFormFeedback("Great form! Full extension", now);
    }
  }

  // Helper method for form feedback with cooldown
  void _provideFormFeedback(String message, DateTime now) {
    if (_lastTtsFeedbackTime == null ||
        now.difference(_lastTtsFeedbackTime!) > _ttsFeedbackCooldown) {
      _speak(message);
      _lastTtsFeedbackTime = now;
    }
  }

  // Enhanced TTS helper method with cooldown
  Future<void> _speak(String text) async {
    final now = DateTime.now();
    if (_isTtsInitialized &&
        (_lastTtsFeedbackTime == null ||
            now.difference(_lastTtsFeedbackTime!) > _ttsFeedbackCooldown)) {
      await _tts.setLanguage("en-US");
      await _tts.setPitch(1.0);
      await _tts.speak(text);
      _lastTtsFeedbackTime = now;
    }
  }

  // Performance monitoring
  int _lastRepCount = 0;
  DateTime _lastRepRateCheck = DateTime.now();

  void _checkRepRate() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRepRateCheck).inSeconds;

    if (elapsed >= 5) {
      final repsPerSecond = (_count - _lastRepCount) / elapsed;

      if (repsPerSecond > 1.0) {
        // Glute kickbacks are typically slower
        debugPrint("High rep rate detected: $repsPerSecond reps/sec");
      }

      _lastRepCount = _count;
      _lastRepRateCheck = now;
    }
  }

  // === ENHANCED PREDICTION METHODS ===

  void _updatePredictionHistory(double position, DateTime timestamp) {
    _positionHistory.add(position);
    _timestampHistory.add(timestamp);

    // Maintain history size
    if (_positionHistory.length > _historySize) {
      _positionHistory.removeAt(0);
      _timestampHistory.removeAt(0);
    }

    // Update movement pattern
    _updateMovementPattern();
  }

  void _updateMovementPattern() {
    if (_positionHistory.length >= 5) {
      // Simple pattern detection - look for consistent up-down pattern
      final recent = _positionHistory.sublist(_positionHistory.length - 5);
      final bool isOscillating = _isOscillatingPattern(recent);

      if (isOscillating) {
        _movementPattern = List.from(recent);
        _patternEstablished = true;
      }
    }
  }

  bool _isOscillatingPattern(List<double> positions) {
    // Check if positions show an up-down pattern
    int signChanges = 0;
    for (int i = 1; i < positions.length - 1; i++) {
      final prevDiff = positions[i] - positions[i - 1];
      final currDiff = positions[i + 1] - positions[i];
      if (prevDiff * currDiff < 0) {
        // Sign change indicates oscillation
        signChanges++;
      }
    }
    return signChanges >= 2; // At least 2 direction changes
  }

  double _predictNextPosition() {
    if (_positionHistory.length < 3) return 0;

    // Method 1: Linear extrapolation
    final linearPrediction = _linearPrediction();

    // Method 2: Pattern matching (if pattern established)
    final patternPrediction = _patternEstablished ? _patternPrediction() : 0;

    // Method 3: Velocity-based prediction
    final velocityPrediction = _velocityPrediction();

    // Weighted combination of methods
    return linearPrediction * _linearWeight +
        patternPrediction * _patternWeight +
        velocityPrediction * _velocityWeight;
  }

  double _linearPrediction() {
    final recent = _positionHistory.sublist(_positionHistory.length - 3);
    final slope = (recent.last - recent.first) / (recent.length - 1);
    return recent.last + slope;
  }

  double _patternPrediction() {
    if (!_patternEstablished || _movementPattern.length < 3) return 0;

    // Simple pattern prediction: assume pattern repeats
    // Find the most recent similar segment in the pattern
    final currentSegment = _positionHistory.sublist(
      _positionHistory.length - 3,
    );

    // Look for matching segment in pattern
    for (int i = 0; i <= _movementPattern.length - 3; i++) {
      final patternSegment = _movementPattern.sublist(i, i + 3);
      if (_segmentsMatch(currentSegment, patternSegment)) {
        // Predict next position based on pattern continuation
        if (i + 3 < _movementPattern.length) {
          return _movementPattern[i + 3];
        }
      }
    }

    return 0;
  }

  bool _segmentsMatch(List<double> seg1, List<double> seg2) {
    const double tolerance = 5.0; // 5 degrees tolerance for angle matching
    for (int i = 0; i < seg1.length; i++) {
      if ((seg1[i] - seg2[i]).abs() > tolerance) {
        return false;
      }
    }
    return true;
  }

  double _velocityPrediction() {
    if (_timestampHistory.length < 2) return 0;

    final recentPositions = _positionHistory.sublist(
      _positionHistory.length - 3,
    );
    final recentTimestamps = _timestampHistory.sublist(
      _timestampHistory.length - 3,
    );

    // Calculate instantaneous velocities
    List<double> velocities = [];
    for (int i = 1; i < recentPositions.length; i++) {
      final timeDelta =
          recentTimestamps[i]
              .difference(recentTimestamps[i - 1])
              .inMilliseconds /
          1000.0;
      final positionDelta = recentPositions[i] - recentPositions[i - 1];
      velocities.add(positionDelta / timeDelta);
    }

    // Use average velocity for prediction
    final avgVelocity = velocities.reduce((a, b) => a + b) / velocities.length;
    return _positionHistory.last + avgVelocity * 0.1; // Predict 100ms ahead
  }
}
