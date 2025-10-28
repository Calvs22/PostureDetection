// lib/body_posture/exercises/exercises_logic/pike_pushup_logic.dart

//NEED TESTING

import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show RepExerciseLogic;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// Enum to define the states of a Pike Push-up
enum PikePushupState {
  up, // Arms are extended, hips are high
  down, // Head is lowered, elbows are bent
}

class PikePushupLogic implements RepExerciseLogic {
  int _pushupCount = 0;
  PikePushupState _currentState = PikePushupState.up;

  DateTime _lastRepTime = DateTime.now();
  // OPTIMIZED: Reduced cooldown for faster counting
  final Duration _cooldownDuration = const Duration(
    milliseconds: 500, // Reduced from 1000ms
  );
  bool _canCountRep = true;

  // Threshold values for accurate counting
  final double _elbowUpThresholdAngle =
      160.0; // Angle considered "up" (arms extended)
  final double _elbowDownThresholdAngle =
      100.0; // Angle considered "down" (elbows bent)
  final double _pikeHipAngleThreshold =
      120.0; // Hip-Shoulder-Elbow angle should be acute for a pike
  final double _minLandmarkConfidence =
      0.7; // Minimum confidence for detected landmarks

  // NEW: Tolerance and hysteresis constants
  final double _elbowAngleTolerance = 10.0; // ±10 degrees tolerance
  final double _hipAngleTolerance = 10.0; // ±10 degrees tolerance
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
  double _lastHipAngle = 0;
  DateTime _lastUpdateTime = DateTime.now();

  // NEW: Movement direction tracking
  bool _isMovingDown = false;
  bool _isMovingUp = false;

  // NEW: Movement smoothing
  double _smoothedElbowAngle = 0;
  double _smoothedHipAngle = 0;
  final double _smoothingFactor = 0.3;

  // NEW: Enhanced prediction variables
  final List<double> _elbowAngleHistory = [];
  final List<double> _hipAngleHistory = [];
  final List<DateTime> _timestampHistory = [];
  final int _historySize = 10;

  // NEW: Movement pattern recognition
  List<double> _movementPattern = [];
  bool _patternEstablished = false;

  // NEW: Prediction weights
  final double _linearWeight = 0.5;
  final double _patternWeight = 0.3;
  final double _velocityWeight = 0.2;

  PikePushupLogic() {
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

    // --- Landmark Retrieval ---
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
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);

    // Validate if all necessary landmarks are detected and have sufficient confidence
    final bool allLandmarksValid = _areLandmarksValid([
      leftShoulder,
      leftElbow,
      leftWrist,
      rightShoulder,
      rightElbow,
      rightWrist,
      leftHip,
      rightHip,
    ]);

    // NEW: Error handling with grace period
    if (!allLandmarksValid) {
      if (!_isInGracePeriod) {
        _lastInvalidLandmarksTime = DateTime.now();
        _isInGracePeriod = true;
        _speak("Adjust position - landmarks unclear");
      } else if (_lastInvalidLandmarksTime != null &&
          DateTime.now().difference(_lastInvalidLandmarksTime!) >
              _gracePeriod) {
        _currentState = PikePushupState.up;
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

    // Calculate elbow angles for both sides (Shoulder-Elbow-Wrist angle)
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

    // Calculate hip angle (Hip-Shoulder-Elbow) to verify pike position
    final double leftHipAngle = _getAngle(leftElbow, leftShoulder, leftHip!);
    final double rightHipAngle = _getAngle(
      rightElbow,
      rightShoulder,
      rightHip!,
    );
    final double averageHipAngle = (leftHipAngle + rightHipAngle) / 2.0;

    // NEW: Calculate movement velocity for anticipation
    final now = DateTime.now();
    final timeDelta = now.difference(_lastUpdateTime).inMilliseconds / 1000.0;
    final elbowAngleVelocity = timeDelta > 0.0
        ? (averageElbowAngle - _lastElbowAngle) / timeDelta
        : 0.0;
    final hipAngleVelocity = timeDelta > 0.0
        ? (averageHipAngle - _lastHipAngle) / timeDelta
        : 0.0;

    _lastElbowAngle = averageElbowAngle;
    _lastHipAngle = averageHipAngle;
    _lastUpdateTime = now;

    // NEW: Apply movement smoothing
    _smoothedElbowAngle =
        _smoothedElbowAngle * _smoothingFactor +
        averageElbowAngle * (1.0 - _smoothingFactor);
    _smoothedHipAngle =
        _smoothedHipAngle * _smoothingFactor +
        averageHipAngle * (1.0 - _smoothingFactor);

    // NEW: Update prediction history
    _updatePredictionHistory(_smoothedElbowAngle, _smoothedHipAngle, now);

    // NEW: Get enhanced prediction
    final predictionResult = _predictNextPosition();
    final double predictedElbowAngle = predictionResult['elbowAngle'] ?? 0.0;
    final double predictedHipAngle = predictionResult['hipAngle'] ?? 0.0;

    // NEW: Track movement direction for better anticipation
    _isMovingDown =
        elbowAngleVelocity < -20.0; // Moving down threshold (degrees/sec)
    _isMovingUp =
        elbowAngleVelocity > 20.0; // Moving up threshold (degrees/sec)

    // Check for cooldown
    if (DateTime.now().difference(_lastRepTime) > _cooldownDuration) {
      if (!_canCountRep && _currentState == PikePushupState.up) {
        _canCountRep = true;
      }
    }

    // NEW: Pike position check with tolerance
    final bool isInPikePosition =
        averageHipAngle < (_pikeHipAngleThreshold + _hipAngleTolerance);

    // NEW: Elbow angle detection with tolerance and hysteresis
    final bool isElbowDown = _currentState == PikePushupState.down
        ? _smoothedElbowAngle < (_elbowDownThresholdAngle + _hysteresisBuffer)
        : _smoothedElbowAngle <
              (_elbowDownThresholdAngle + _elbowAngleTolerance);

    final bool isElbowUp = _currentState == PikePushupState.up
        ? _smoothedElbowAngle > (_elbowUpThresholdAngle - _hysteresisBuffer)
        : _smoothedElbowAngle > (_elbowUpThresholdAngle - _elbowAngleTolerance);

    // NEW: Use prediction for earlier detection
    final bool willBeElbowDown = predictedElbowAngle < _elbowDownThresholdAngle;
    final bool willBeElbowUp = predictedElbowAngle > _elbowUpThresholdAngle;

    // NEW: Use hip angle velocity for enhanced movement detection
    final bool isHipMovingDown = hipAngleVelocity < -15.0;
    final bool isHipMovingUp = hipAngleVelocity > 15.0;

    // NEW: Use predicted hip angle for enhanced position detection
    final bool willBeInPikePosition =
        predictedHipAngle < _pikeHipAngleThreshold;

    // Form analysis
    _checkForm(
      leftElbowAngle,
      rightElbowAngle,
      averageElbowAngle,
      leftHipAngle,
      rightHipAngle,
      averageHipAngle,
      isInPikePosition,
      isElbowDown,
      isElbowUp,
      hipAngleVelocity,
      predictedHipAngle,
    );

    // Enhanced state machine logic with prediction and direction
    switch (_currentState) {
      case PikePushupState.up:
        // User is moving from up to down (lowering head)
        // NEW: Enhanced detection with prediction and direction
        if ((isInPikePosition && isElbowDown && _isMovingDown) ||
            (isInPikePosition && willBeElbowDown && _isMovingDown) ||
            (willBeInPikePosition && isElbowDown && isHipMovingDown) ||
            (willBeInPikePosition && willBeElbowDown && isHipMovingDown)) {
          _currentState = PikePushupState.down;
        }
        break;

      case PikePushupState.down:
        // User is moving from down to up (extending arms)
        // NEW: Enhanced detection with prediction and direction
        if ((isInPikePosition && isElbowUp && _isMovingUp) ||
            (isInPikePosition && willBeElbowUp && _isMovingUp) ||
            (willBeInPikePosition && isElbowUp && isHipMovingUp) ||
            (willBeInPikePosition && willBeElbowUp && isHipMovingUp)) {
          if (_canCountRep) {
            _pushupCount++;
            _currentState = PikePushupState.up;
            _lastRepTime = DateTime.now();
            _canCountRep = false;

            // Provide feedback during exercise
            _provideExerciseFeedback();
          } else {
            _currentState = PikePushupState.up;
          }
        }
        break;
    }
  }

  @override
  void reset() {
    _pushupCount = 0;
    _currentState = PikePushupState.up;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastTtsFeedbackTime = null;
    _lastInvalidLandmarksTime = null;
    _isInGracePeriod = false;

    // NEW: Reset performance tracking variables
    _lastElbowAngle = 0.0;
    _lastHipAngle = 0.0;
    _lastUpdateTime = DateTime.now();
    _smoothedElbowAngle = 0.0;
    _smoothedHipAngle = 0.0;

    // NEW: Reset prediction variables
    _elbowAngleHistory.clear();
    _hipAngleHistory.clear();
    _timestampHistory.clear();
    _movementPattern.clear();
    _patternEstablished = false;

    // Reset direction tracking
    _isMovingDown = false;
    _isMovingUp = false;

    _speak("Exercise reset");
  }

  @override
  String get progressLabel => 'Pike Push-ups: $_pushupCount';

  @override
  int get reps => _pushupCount;

  @override
  // ignore: override_on_non_overriding_member
  int get seconds => 0;

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
    double leftHipAngle,
    double rightHipAngle,
    double averageHipAngle,
    bool isInPikePosition,
    bool isElbowDown,
    bool isElbowUp,
    double hipAngleVelocity,
    double predictedHipAngle,
  ) {
    final now = DateTime.now();

    // 1. Check if arms are moving symmetrically with tolerance
    final double elbowAngleDifference = (leftElbowAngle - rightElbowAngle)
        .abs();
    if (elbowAngleDifference > (20.0 + _elbowAngleTolerance)) {
      _provideFormFeedback("Keep your arms even", now);
    }

    // 2. Check for proper pike position with tolerance
    if (!isInPikePosition) {
      _provideFormFeedback("Maintain pike position with hips high", now);
    }

    // NEW: Use predicted hip angle to anticipate form issues
    if (predictedHipAngle > _pikeHipAngleThreshold + _hipAngleTolerance) {
      _provideFormFeedback("Prepare to raise your hips higher", now);
    }

    // 3. Check for full range of motion with tolerance
    if (averageElbowAngle > (_elbowUpThresholdAngle - _elbowAngleTolerance) &&
        !isElbowUp) {
      _provideFormFeedback("Extend your arms fully", now);
    }

    // 4. Check for sufficient depth with tolerance
    if (averageElbowAngle < (_elbowDownThresholdAngle + _elbowAngleTolerance) &&
        !isElbowDown) {
      _provideFormFeedback("Lower your head closer to the ground", now);
    }

    // NEW: Use hip velocity to check for controlled movement
    if (hipAngleVelocity.abs() > 30.0) {
      _provideFormFeedback("Control your movement speed", now);
    }

    // 5. Check for steady rhythm
    final Duration timeSinceLastRep = DateTime.now().difference(_lastRepTime);
    if (timeSinceLastRep > Duration(seconds: 2) && _pushupCount > 2) {
      _provideFormFeedback("Keep a steady rhythm", now);
    }

    // Positive feedback for good form with tolerance
    if (isInPikePosition &&
        averageElbowAngle < (_elbowDownThresholdAngle + _elbowAngleTolerance) &&
        _pushupCount > 3) {
      _provideFormFeedback("Great form! Good pike position", now);
    }
  }

  // NEW: Helper method for form feedback with cooldown
  void _provideFormFeedback(String message, DateTime now) {
    if (_lastTtsFeedbackTime == null ||
        now.difference(_lastTtsFeedbackTime!) > _ttsFeedbackCooldown) {
      _speak(message);
      _lastTtsFeedbackTime = now;
    }
  }

  // NEW: Helper method for exercise feedback with cooldown
  void _provideExerciseFeedback() {
    if (_pushupCount != _lastFeedbackRep) {
      _lastFeedbackRep = _pushupCount;

      if (_pushupCount % 5 == 0) {
        _speak("$_pushupCount reps, keep going!");
      } else if (_pushupCount == 10) {
        _speak("Great job! Halfway there!");
      } else if (_pushupCount >= 15) {
        _speak("Almost done! You can do it!");
      } else {
        _speak("Good job!");
      }
    }
  }

  // === ENHANCED PREDICTION METHODS ===

  void _updatePredictionHistory(
    double elbowAngle,
    double hipAngle,
    DateTime timestamp,
  ) {
    _elbowAngleHistory.add(elbowAngle);
    _hipAngleHistory.add(hipAngle);
    _timestampHistory.add(timestamp);

    // Maintain history size
    if (_elbowAngleHistory.length > _historySize) {
      _elbowAngleHistory.removeAt(0);
      _hipAngleHistory.removeAt(0);
      _timestampHistory.removeAt(0);
    }

    // Update movement pattern
    _updateMovementPattern();
  }

  void _updateMovementPattern() {
    if (_elbowAngleHistory.length >= 5) {
      // Simple pattern detection - look for consistent up-down pattern
      final recentElbowAngles = _elbowAngleHistory.sublist(
        _elbowAngleHistory.length - 5,
      );
      final bool isOscillating = _isOscillatingPattern(recentElbowAngles);

      if (isOscillating) {
        _movementPattern = List.from(recentElbowAngles);
        _patternEstablished = true;
      }
    }
  }

  bool _isOscillatingPattern(List<double> values) {
    // Check if values show an up-down pattern
    int signChanges = 0;
    for (int i = 1; i < values.length - 1; i++) {
      final prevDiff = values[i] - values[i - 1];
      final currDiff = values[i + 1] - values[i];
      if (prevDiff * currDiff < 0.0) {
        // Sign change indicates oscillation
        signChanges++;
      }
    }
    return signChanges >= 2; // At least 2 direction changes
  }

  Map<String, double> _predictNextPosition() {
    if (_elbowAngleHistory.length < 3) return {};

    // Method 1: Linear extrapolation
    final elbowLinearPrediction = _linearPrediction(_elbowAngleHistory);
    final hipLinearPrediction = _linearPrediction(_hipAngleHistory);

    // Method 2: Pattern matching (if pattern established)
    final elbowPatternPrediction = _patternEstablished
        ? _patternPrediction(_elbowAngleHistory)
        : 0.0;
    final hipPatternPrediction = _patternEstablished
        ? _patternPrediction(_hipAngleHistory)
        : 0.0;

    // Method 3: Velocity-based prediction
    final elbowVelocityPrediction = _velocityPrediction(
      _elbowAngleHistory,
      _timestampHistory,
    );
    final hipVelocityPrediction = _velocityPrediction(
      _hipAngleHistory,
      _timestampHistory,
    );

    // Weighted combination of methods
    return {
      'elbowAngle':
          elbowLinearPrediction * _linearWeight +
          elbowPatternPrediction * _patternWeight +
          elbowVelocityPrediction * _velocityWeight,
      'hipAngle':
          hipLinearPrediction * _linearWeight +
          hipPatternPrediction * _patternWeight +
          hipVelocityPrediction * _velocityWeight,
    };
  }

  double _linearPrediction(List<double> values) {
    if (values.length < 3) return 0.0;
    final recent = values.sublist(values.length - 3);
    final slope = (recent.last - recent.first) / (recent.length - 1).toDouble();
    return recent.last + slope;
  }

  double _patternPrediction(List<double> values) {
    if (!_patternEstablished || _movementPattern.length < 3) return 0.0;

    // Simple pattern prediction: assume pattern repeats
    final currentSegment = values.sublist(values.length - 3);

    // Look for matching segment in pattern
    for (int i = 0; i <= _movementPattern.length - 3; i++) {
      final patternSegment = _movementPattern.sublist(i, i + 3);
      if (_segmentsMatch(currentSegment, patternSegment)) {
        // Predict next value based on pattern continuation
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

  double _velocityPrediction(List<double> values, List<DateTime> timestamps) {
    if (timestamps.length < 2) return 0.0;

    final recentValues = values.sublist(values.length - 3);
    final recentTimestamps = timestamps.sublist(timestamps.length - 3);

    // Calculate instantaneous velocities
    List<double> velocities = [];
    for (int i = 1; i < recentValues.length; i++) {
      final timeDelta =
          recentTimestamps[i]
              .difference(recentTimestamps[i - 1])
              .inMilliseconds /
          1000.0;
      final valueDelta = recentValues[i] - recentValues[i - 1];
      velocities.add(valueDelta / timeDelta);
    }

    // Use average velocity for prediction
    final avgVelocity =
        velocities.reduce((a, b) => a + b) / velocities.length.toDouble();
    return values.last + avgVelocity * 0.1; // Predict 100ms ahead
  }
}
