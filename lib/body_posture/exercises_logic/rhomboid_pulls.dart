// lib/exercises/rhomboid_pulls.dart

//NEED TESTING

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// Enum to define the states of a Rhomboid Pull
enum RhomboidPullState {
  extended, // Arms are extended forward
  retracted, // Arms are pulled back, squeezing shoulder blades
}

class RhomboidPullsLogic implements RepExerciseLogic {
  // CHANGED: implements RepExerciseLogic instead of ExerciseLogic
  int _repCount = 0;
  RhomboidPullState _currentState = RhomboidPullState.extended;

  DateTime _lastRepTime = DateTime.now();
  // OPTIMIZED: Reduced cooldown for faster counting
  final Duration _cooldownDuration = const Duration(
    milliseconds: 500, // Reduced from 1000ms
  );
  bool _canCountRep = true;

  // Threshold values for accurate counting
  final double _elbowExtendedThresholdAngle = 160.0;
  final double _elbowRetractedThresholdAngle = 90.0;
  final double _minLandmarkConfidence = 0.7;

  // NEW: Tolerance and hysteresis constants
  final double _elbowAngleTolerance = 10.0; // ±10 degrees tolerance
  final double _hysteresisBuffer = 5.0; // Prevents state flickering

  // TTS variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;

  // NEW: TTS feedback cooldown
  DateTime? _lastTtsFeedbackTime;
  final Duration _ttsFeedbackCooldown = Duration(seconds: 3);

  // NEW: Error handling variables
  DateTime? _lastInvalidLandmarksTime;
  final Duration _gracePeriod = Duration(seconds: 1);
  bool _isInGracePeriod = false;

  // NEW: Velocity tracking for anticipation
  double _lastElbowAngle = 0;
  DateTime _lastUpdateTime = DateTime.now();

  // NEW: Movement direction tracking
  bool _isMovingBack = false;
  bool _isMovingForward = false;

  // NEW: Movement smoothing
  double _smoothedElbowAngle = 0;
  final double _smoothingFactor = 0.3;

  // NEW: Enhanced prediction variables
  final List<double> _positionHistory = [];
  final List<DateTime> _timestampHistory = [];
  final int _historySize = 10;

  // NEW: Movement pattern recognition
  List<double> _movementPattern = [];
  bool _patternEstablished = false;

  // NEW: Prediction weights
  final double _linearWeight = 0.5;
  final double _patternWeight = 0.3;
  final double _velocityWeight = 0.2;

  RhomboidPullsLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    _isTtsInitialized = true;
  }

  // NEW: Enhanced TTS method with cooldown
  Future<void> _speak(String text) async {
    final now = DateTime.now();
    if (_isTtsInitialized &&
        (_lastTtsFeedbackTime == null ||
            now.difference(_lastTtsFeedbackTime!) > _ttsFeedbackCooldown)) {
      await _flutterTts.speak(text);
      _lastTtsFeedbackTime = now;
    }
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    // Cast landmarks to the correct type
    final List<PoseLandmark> poseLandmarks = landmarks.cast<PoseLandmark>();

    // Retrieve necessary landmarks
    final leftShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.leftShoulder,
    );
    final leftElbow = _getLandmark(poseLandmarks, PoseLandmarkType.leftElbow);
    final leftWrist = _getLandmark(poseLandmarks, PoseLandmarkType.leftWrist);
    final rightShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.rightShoulder,
    );
    final rightElbow = _getLandmark(poseLandmarks, PoseLandmarkType.rightElbow);
    final rightWrist = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist);

    // Validate landmarks
    final bool areAllLandmarksValid = _areLandmarksValid([
      leftShoulder,
      leftElbow,
      leftWrist,
      rightShoulder,
      rightElbow,
      rightWrist,
    ]);

    // NEW: Error handling with grace period
    if (!areAllLandmarksValid) {
      if (!_isInGracePeriod) {
        _lastInvalidLandmarksTime = DateTime.now();
        _isInGracePeriod = true;
        _speak("Adjust position - landmarks unclear");
      } else if (_lastInvalidLandmarksTime != null &&
          DateTime.now().difference(_lastInvalidLandmarksTime!) >
              _gracePeriod) {
        _currentState = RhomboidPullState.extended;
        _canCountRep = false;
        _isInGracePeriod = false;
        _speak("Position lost - please restart");
        return;
      }
    } else {
      _isInGracePeriod = false;
      _lastInvalidLandmarksTime = null;
    }

    // First time starting the exercise
    if (!_hasStarted) {
      _hasStarted = true;
      _speak("Get into Position");
    }

    // Calculate angles
    final double leftElbowAngle = _getAngle(
      leftShoulder!,
      leftElbow!,
      leftWrist!,
    );
    final double rightElbowAngle = _getAngle(
      rightShoulder!,
      rightElbow!,
      rightWrist!,
    );
    final double averageElbowAngle = (leftElbowAngle + rightElbowAngle) / 2.0;

    // NEW: Calculate movement velocity for anticipation
    final now = DateTime.now();
    final timeDelta = now.difference(_lastUpdateTime).inMilliseconds / 1000.0;
    final velocity = timeDelta > 0.0
        ? (averageElbowAngle - _lastElbowAngle) / timeDelta
        : 0.0;

    _lastElbowAngle = averageElbowAngle;
    _lastUpdateTime = now;

    // NEW: Apply movement smoothing
    _smoothedElbowAngle =
        _smoothedElbowAngle * _smoothingFactor +
        averageElbowAngle * (1.0 - _smoothingFactor);

    // NEW: Update prediction history
    _updatePredictionHistory(_smoothedElbowAngle, now);

    // NEW: Get enhanced prediction
    final predictedAngle = _predictNextPosition();

    // NEW: Track movement direction for better anticipation
    _isMovingBack = velocity < -20.0; // Moving back (retracting) threshold
    _isMovingForward = velocity > 20.0; // Moving forward (extending) threshold

    // NEW: Elbow angle detection with tolerance and hysteresis
    final bool isElbowRetracted = _currentState == RhomboidPullState.retracted
        ? _smoothedElbowAngle <
              (_elbowRetractedThresholdAngle + _hysteresisBuffer)
        : _smoothedElbowAngle <
              (_elbowRetractedThresholdAngle + _elbowAngleTolerance);

    final bool isElbowExtended = _currentState == RhomboidPullState.extended
        ? _smoothedElbowAngle >
              (_elbowExtendedThresholdAngle - _hysteresisBuffer)
        : _smoothedElbowAngle >
              (_elbowExtendedThresholdAngle - _elbowAngleTolerance);

    // NEW: Use prediction for earlier detection
    final bool willBeElbowRetracted =
        predictedAngle < _elbowRetractedThresholdAngle;
    final bool willBeElbowExtended =
        predictedAngle > _elbowExtendedThresholdAngle;

    // Check cooldown
    if (DateTime.now().difference(_lastRepTime) > _cooldownDuration) {
      if (!_canCountRep && _currentState == RhomboidPullState.extended) {
        _canCountRep = true;
      }
    }

    // Form analysis
    _checkForm(
      leftElbowAngle,
      rightElbowAngle,
      _smoothedElbowAngle,
      isElbowRetracted,
      isElbowExtended,
    );

    // NEW: Check rep rate for performance monitoring
    _checkRepRate();

    // Enhanced state machine logic with prediction and direction
    switch (_currentState) {
      case RhomboidPullState.extended:
        // NEW: Enhanced detection with prediction and direction
        if ((isElbowRetracted && _isMovingBack) ||
            (willBeElbowRetracted && _isMovingBack)) {
          _currentState = RhomboidPullState.retracted;
        }
        break;

      case RhomboidPullState.retracted:
        // NEW: Enhanced detection with prediction and direction
        if ((isElbowExtended && _isMovingForward) ||
            (willBeElbowExtended && _isMovingForward)) {
          if (_canCountRep) {
            _repCount++;
            _currentState = RhomboidPullState.extended;
            _lastRepTime = DateTime.now();
            _canCountRep = false;

            // Provide feedback during exercise
            _provideExerciseFeedback();
          } else {
            _currentState = RhomboidPullState.extended;
          }
        }
        break;
    }
  }

  @override
  void reset() {
    _repCount = 0;
    _currentState = RhomboidPullState.extended;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastTtsFeedbackTime = null;
    _lastInvalidLandmarksTime = null;
    _isInGracePeriod = false;

    // NEW: Reset performance tracking variables
    _lastElbowAngle = 0.0;
    _lastUpdateTime = DateTime.now();
    _smoothedElbowAngle = 0.0;

    // NEW: Reset prediction variables
    _positionHistory.clear();
    _timestampHistory.clear();
    _movementPattern.clear();
    _patternEstablished = false;

    // Reset direction tracking
    _isMovingBack = false;
    _isMovingForward = false;

    // Reset rep rate tracking
    _lastRepCount = 0;
    _lastRepRateCheck = DateTime.now();

    _speak("Exercise reset");
  }

  @override
  String get progressLabel => 'Rhomboid Pulls: $_repCount';

  @override
  int get reps => _repCount; // ADDED: Required getter for RepExerciseLogic interface

  // Helper methods
  PoseLandmark? _getLandmark(
    List<PoseLandmark> landmarks,
    PoseLandmarkType type,
  ) {
    try {
      return landmarks.firstWhere((l) => l.type == type);
    } catch (e) {
      return null;
    }
  }

  bool _areLandmarksValid(List<PoseLandmark?> landmarks) {
    return landmarks.every(
      (landmark) =>
          landmark != null && landmark.likelihood >= _minLandmarkConfidence,
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

    if (magnitude1 == 0.0 || magnitude2 == 0.0) {
      return 180.0;
    }

    double cosineAngle = dotProduct / (magnitude1 * magnitude2);
    cosineAngle = max(-1.0, min(1.0, cosineAngle));

    double angleRad = acos(cosineAngle);
    return angleRad * 180.0 / pi;
  }

  // NEW: Form analysis with comprehensive checks
  void _checkForm(
    double leftElbowAngle,
    double rightElbowAngle,
    double averageElbowAngle,
    bool isElbowRetracted,
    bool isElbowExtended,
  ) {
    final now = DateTime.now();

    // 1. Check for symmetric movement between arms
    final double elbowAngleDifference = (leftElbowAngle - rightElbowAngle)
        .abs();
    if (elbowAngleDifference > 15.0) {
      _provideFormFeedback("Keep your arms even", now);
    }

    // 2. Check for full retraction
    if (averageElbowAngle >
            (_elbowRetractedThresholdAngle + _elbowAngleTolerance) &&
        isElbowRetracted) {
      _provideFormFeedback("Squeeze your shoulder blades together", now);
    }

    // 3. Check for full extension
    if (averageElbowAngle <
            (_elbowExtendedThresholdAngle - _elbowAngleTolerance) &&
        !isElbowExtended) {
      _provideFormFeedback("Extend your arms fully", now);
    }

    // 4. Check for steady rhythm
    final Duration timeSinceLastRep = DateTime.now().difference(_lastRepTime);
    if (timeSinceLastRep > Duration(seconds: 2) && _repCount > 2) {
      _provideFormFeedback("Keep a steady rhythm", now);
    }

    // Positive feedback for good form with tolerance
    if (averageElbowAngle <
            (_elbowRetractedThresholdAngle - _elbowAngleTolerance) &&
        _repCount > 3) {
      _provideFormFeedback("Great form! Full retraction", now);
    }
  }

  // NEW: Helper method for exercise feedback with cooldown
  void _provideFormFeedback(String message, DateTime now) {
    if (_lastTtsFeedbackTime == null ||
        now.difference(_lastTtsFeedbackTime!) > _ttsFeedbackCooldown) {
      _speak(message);
      _lastTtsFeedbackTime = now;
    }
  }

  // NEW: Helper method for exercise feedback with cooldown
  void _provideExerciseFeedback() {
    if (_repCount != _lastFeedbackRep) {
      _lastFeedbackRep = _repCount;

      if (_repCount % 5 == 0) {
        _speak("$_repCount reps, keep going!");
      } else if (_repCount == 10) {
        _speak("Great job! Halfway there!");
      } else if (_repCount >= 15) {
        _speak("Almost done! You can do it!");
      } else {
        _speak("Good job!");
      }
    }
  }

  // NEW: Performance monitoring
  int _lastRepCount = 0;
  DateTime _lastRepRateCheck = DateTime.now();

  void _checkRepRate() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRepRateCheck).inSeconds;

    if (elapsed >= 5) {
      final repsPerSecond = (_repCount - _lastRepCount) / elapsed.toDouble();

      if (repsPerSecond > 0.7) {
        // Rhomboid pulls are typically slower
        debugPrint("High rep rate detected: $repsPerSecond reps/sec");
        _provideFormFeedback("Slow down for better form", now);
      } else if (repsPerSecond < 0.3 && _repCount > 5) {
        // Too slow might indicate poor form or rest
        _provideFormFeedback("Maintain a steady pace", now);
      }

      _lastRepCount = _repCount;
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
      // Simple pattern detection - look for consistent back-forth pattern
      final recent = _positionHistory.sublist(_positionHistory.length - 5);
      final bool isOscillating = _isOscillatingPattern(recent);

      if (isOscillating) {
        _movementPattern = List.from(recent);
        _patternEstablished = true;
      }
    }
  }

  bool _isOscillatingPattern(List<double> positions) {
    // Check if positions show a back-forth pattern
    int signChanges = 0;
    for (int i = 1; i < positions.length - 1; i++) {
      final prevDiff = positions[i] - positions[i - 1];
      final currDiff = positions[i + 1] - positions[i];
      if (prevDiff * currDiff < 0.0) {
        // Sign change indicates oscillation
        signChanges++;
      }
    }
    return signChanges >= 2; // At least 2 direction changes
  }

  double _predictNextPosition() {
    if (_positionHistory.length < 3) return 0.0;

    // Method 1: Linear extrapolation
    final linearPrediction = _linearPrediction();

    // Method 2: Pattern matching (if pattern established)
    final patternPrediction = _patternEstablished ? _patternPrediction() : 0.0;

    // Method 3: Velocity-based prediction
    final velocityPrediction = _velocityPrediction();

    // Weighted combination of methods
    return linearPrediction * _linearWeight +
        patternPrediction * _patternWeight +
        velocityPrediction * _velocityWeight;
  }

  double _linearPrediction() {
    final recent = _positionHistory.sublist(_positionHistory.length - 3);
    final slope = (recent.last - recent.first) / (recent.length - 1).toDouble();
    return recent.last + slope;
  }

  double _patternPrediction() {
    if (!_patternEstablished || _movementPattern.length < 3) return 0.0;

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

    return 0.0;
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
    if (_timestampHistory.length < 2) return 0.0;

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
    final avgVelocity =
        velocities.reduce((a, b) => a + b) / velocities.length.toDouble();
    return _positionHistory.last + avgVelocity * 0.1; // Predict 100ms ahead
  }
}
