// lib/body_posture/exercises/exercises_logic/push_up_logic.dart

//NEED TESTING

import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';
import '/body_posture/camera/pose_painter.dart'; // Needed for FirstWhereOrNullExtension

// Enum to define the states of a Push-Up
enum PushUpState {
  up, // Top of the movement, arms straight
  down, // Bottom of the movement, elbows bent
}

class PushUpLogic implements RepExerciseLogic {
  // CHANGED: implements RepExerciseLogic instead of ExerciseLogic
  int _pushUpCount = 0;
  PushUpState _currentState = PushUpState.up;

  DateTime _lastRepTime = DateTime.now();
  // OPTIMIZED: Reduced cooldown for faster counting
  final Duration _cooldownDuration = const Duration(
    milliseconds: 300, // Reduced from 500ms
  );

  bool _canCountRep = true;

  // Thresholds for push-ups
  final double _pushUpDownAngleThreshold = 90.0; // Angle for the 'down' state
  final double _pushUpUpAngleThreshold = 160.0; // Angle for the 'up' state
  final double _minLandmarkConfidence = 0.7;

  // NEW: Tolerance and hysteresis constants
  final double _elbowAngleTolerance = 10.0; // ±10 degrees tolerance
  final double _hysteresisBuffer = 5.0; // Prevents state flickering

  // TTS instance
  final FlutterTts _tts = FlutterTts();
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;

  // Form feedback cooldown
  DateTime? _lastFormFeedbackTime;
  final Duration _formFeedbackCooldown = Duration(seconds: 5);

  // NEW: TTS feedback cooldown
  DateTime? _lastTtsFeedbackTime;
  final Duration _ttsFeedbackCooldown = Duration(seconds: 3);

  // NEW: Error handling variables
  DateTime? _lastInvalidLandmarksTime;
  final Duration _gracePeriod = Duration(seconds: 1);
  bool _isInGracePeriod = false;

  // Range of motion tracking
  double _minElbowAngle = 180.0;
  double _maxElbowAngle = 0.0;
  bool _hasReachedFullExtension = false;

  // NEW: Velocity tracking for anticipation
  double _lastElbowAngle = 0;
  DateTime _lastUpdateTime = DateTime.now();

  // NEW: Movement direction tracking
  bool _isMovingDown = false;
  bool _isMovingUp = false;

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

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    // Cast landmarks to the correct type
    final poseLandmarks = landmarks as List<PoseLandmark>;

    // Speak initial message immediately on first update
    if (!_hasStarted) {
      _speak("Get into Position");
      _hasStarted = true;
    }

    // Retrieve essential landmarks for push-up detection
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

    // Additional landmarks for form analysis
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final leftAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.leftAnkle);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);

    // Validate landmarks
    final bool allNecessaryLandmarksValid = _areLandmarksValid([
      leftShoulder,
      leftElbow,
      leftWrist,
      rightShoulder,
      rightElbow,
      rightWrist,
      leftHip,
      rightHip,
      leftAnkle,
      rightAnkle,
    ]);

    // NEW: Error handling with grace period
    if (!allNecessaryLandmarksValid) {
      if (!_isInGracePeriod) {
        _lastInvalidLandmarksTime = DateTime.now();
        _isInGracePeriod = true;
        _speak("Adjust position - landmarks unclear");
      } else if (_lastInvalidLandmarksTime != null &&
          DateTime.now().difference(_lastInvalidLandmarksTime!) >
              _gracePeriod) {
        _currentState = PushUpState.up;
        _canCountRep = false;
        _isInGracePeriod = false;
        _speak("Position lost - please restart");
        return;
      }
    } else {
      _isInGracePeriod = false;
      _lastInvalidLandmarksTime = null;
    }

    // Calculate the elbow angles for both arms
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
    final double averageElbowAngle = (leftElbowAngle + rightElbowAngle) / 2;

    // Update range of motion tracking
    _minElbowAngle = min(_minElbowAngle, averageElbowAngle);
    _maxElbowAngle = max(_maxElbowAngle, averageElbowAngle);

    // NEW: Calculate movement velocity for anticipation
    final now = DateTime.now();
    final timeDelta = now.difference(_lastUpdateTime).inMilliseconds / 1000.0;
    final velocity = timeDelta > 0
        ? (averageElbowAngle - _lastElbowAngle) / timeDelta
        : 0;

    _lastElbowAngle = averageElbowAngle;
    _lastUpdateTime = now;

    // NEW: Apply movement smoothing
    _smoothedElbowAngle =
        _smoothedElbowAngle * _smoothingFactor +
        averageElbowAngle * (1 - _smoothingFactor);

    // NEW: Update prediction history
    _updatePredictionHistory(_smoothedElbowAngle, now);

    // NEW: Get enhanced prediction
    final predictedAngle = _predictNextPosition();

    // NEW: Track movement direction for better anticipation
    _isMovingDown = velocity < -20.0; // Moving down threshold (degrees/sec)
    _isMovingUp = velocity > 20.0; // Moving up threshold (degrees/sec)

    // NEW: Elbow angle detection with tolerance and hysteresis
    final bool isDown = _currentState == PushUpState.down
        ? _smoothedElbowAngle < (_pushUpDownAngleThreshold + _hysteresisBuffer)
        : _smoothedElbowAngle <
              (_pushUpDownAngleThreshold + _elbowAngleTolerance);

    final bool isUp = _currentState == PushUpState.up
        ? _smoothedElbowAngle > (_pushUpUpAngleThreshold - _hysteresisBuffer)
        : _smoothedElbowAngle >
              (_pushUpUpAngleThreshold - _elbowAngleTolerance);

    // NEW: Use prediction for earlier detection
    final bool willBeDown = predictedAngle < _pushUpDownAngleThreshold;
    final bool willBeUp = predictedAngle > _pushUpUpAngleThreshold;

    // Form analysis
    _checkForm(
      leftElbowAngle,
      rightElbowAngle,
      leftShoulder,
      rightShoulder,
      leftElbow,
      rightElbow,
      leftHip,
      rightHip,
      leftAnkle,
      rightAnkle,
    );

    // State Machine Logic with enhanced detection
    if (DateTime.now().difference(_lastRepTime) > _cooldownDuration) {
      if (!_canCountRep) {
        _canCountRep = true;
      }
    }

    switch (_currentState) {
      case PushUpState.up:
        // User is lowering into the 'down' position
        // NEW: Enhanced detection with prediction and direction
        if ((isDown && _isMovingDown) || (willBeDown && _isMovingDown)) {
          _currentState = PushUpState.down;
          _speak("Down");
        }
        break;

      case PushUpState.down:
        // User is pushing back up into the 'up' position
        // NEW: Enhanced detection with prediction and direction
        if ((isUp && _isMovingUp) || (willBeUp && _isMovingUp)) {
          if (_canCountRep) {
            _pushUpCount++;
            _currentState = PushUpState.up;
            _lastRepTime = DateTime.now();
            _canCountRep = false;

            // Check if user achieved full extension with tolerance
            if (_maxElbowAngle >= (170.0 - _elbowAngleTolerance)) {
              _hasReachedFullExtension = true;
            }

            // Provide feedback every 5 reps
            if (_pushUpCount % 5 == 0 && _pushUpCount != _lastFeedbackRep) {
              _speak("Good job! Keep going!");
              _lastFeedbackRep = _pushUpCount;
            }

            // Completion feedback
            if (_pushUpCount == 10) {
              _speak("Almost there! Just a few more!");
            }
          } else {
            _currentState = PushUpState.up;
          }
        }
        break;
    }
  }

  @override
  void reset() {
    _pushUpCount = 0;
    _currentState = PushUpState.up;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastFormFeedbackTime = null;
    _lastTtsFeedbackTime = null;
    _lastInvalidLandmarksTime = null;
    _isInGracePeriod = false;
    _minElbowAngle = 180.0;
    _maxElbowAngle = 0.0;
    _hasReachedFullExtension = false;

    // NEW: Reset performance tracking variables
    _lastElbowAngle = 0;
    _lastUpdateTime = DateTime.now();
    _smoothedElbowAngle = 0;

    // NEW: Reset prediction variables
    _positionHistory.clear();
    _timestampHistory.clear();
    _movementPattern.clear();
    _patternEstablished = false;

    // Reset direction tracking
    _isMovingDown = false;
    _isMovingUp = false;

    _speak("Reset complete. Get into Position");
  }

  @override
  String get progressLabel => "Push-ups: $_pushUpCount";

  @override
  int get reps => _pushUpCount; // ADDED: Required getter for RepExerciseLogic interface

  // Helper method to get landmark with confidence check
  PoseLandmark? _getLandmark(
    List<PoseLandmark> landmarks,
    PoseLandmarkType type,
  ) {
    final landmark = landmarks.firstWhereOrNull((l) => l.type == type);
    // Check if landmark exists and has sufficient confidence
    if (landmark != null && landmark.likelihood >= _minLandmarkConfidence) {
      return landmark;
    }
    return null;
  }

  // NEW: Helper method to validate landmarks
  bool _areLandmarksValid(List<PoseLandmark?> landmarks) {
    return landmarks.every(
      (landmark) =>
          landmark != null && landmark.likelihood >= _minLandmarkConfidence,
    );
  }

  // Helper function to calculate the angle between three landmarks
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

    return angleDeg;
  }

  // Form analysis with comprehensive checks
  void _checkForm(
    double leftElbowAngle,
    double rightElbowAngle,
    PoseLandmark? leftShoulder,
    PoseLandmark? rightShoulder,
    PoseLandmark? leftElbow,
    PoseLandmark? rightElbow,
    PoseLandmark? leftHip,
    PoseLandmark? rightHip,
    PoseLandmark? leftAnkle,
    PoseLandmark? rightAnkle,
  ) {
    final now = DateTime.now();

    // 1. Check if arms are moving symmetrically with tolerance
    final double angleDifference = (leftElbowAngle - rightElbowAngle).abs();
    if (angleDifference > (20.0 + _elbowAngleTolerance)) {
      _provideFormFeedback("Keep your arms even", now);
    }

    // 2. Check if elbows are flaring out too much with tolerance
    if (leftElbowAngle < (70.0 - _elbowAngleTolerance) ||
        rightElbowAngle < (70.0 - _elbowAngleTolerance)) {
      _provideFormFeedback("Keep your elbows close to your body", now);
    }

    // 3. Body alignment check (to prevent sagging) with tolerance
    if (leftShoulder != null && leftHip != null && leftAnkle != null) {
      final double bodyAlignmentAngle = _getAngle(
        leftShoulder,
        leftHip,
        leftAnkle,
      );
      // If body alignment angle is too small, body is sagging
      if (bodyAlignmentAngle < (160.0 - _elbowAngleTolerance)) {
        _provideFormFeedback("Keep your body straight, don't sag", now);
      }
    }

    // 4. Hip position check (to prevent piking)
    if (leftShoulder != null && leftHip != null && leftAnkle != null) {
      // Calculate hip position relative to shoulder-ankle line
      final double shoulderToAnkleX = leftAnkle.x - leftShoulder.x;
      final double shoulderToAnkleY = leftAnkle.y - leftShoulder.y;
      final double shoulderToHipX = leftHip.x - leftShoulder.x;
      final double shoulderToHipY = leftHip.y - leftShoulder.y;

      // Calculate cross product to determine which side of the line the hip is on
      final double crossProduct =
          shoulderToAnkleX * shoulderToHipY - shoulderToAnkleY * shoulderToHipX;

      // If cross product is positive, hip is above the line (piking)
      if (crossProduct > 20.0) {
        _provideFormFeedback(
          "Don't raise your hips, keep your body straight",
          now,
        );
      }
      // If cross product is negative, hip is below the line (sagging)
      else if (crossProduct < -20.0) {
        _provideFormFeedback("Don't let your hips sag", now);
      }
    }

    // 5. Range of motion check (to ensure full extension) with tolerance
    if (_maxElbowAngle < (160.0 - _elbowAngleTolerance) && _pushUpCount > 2) {
      _provideFormFeedback("Extend your arms fully at the top", now);
    }

    // 6. Depth check (to ensure going low enough) with tolerance
    if (_minElbowAngle > (100.0 + _elbowAngleTolerance) && _pushUpCount > 2) {
      _provideFormFeedback("Lower your chest closer to the ground", now);
    }

    // Positive feedback for good form with tolerance
    if (_hasReachedFullExtension &&
        _minElbowAngle <= (90.0 + _elbowAngleTolerance) &&
        _pushUpCount > 3) {
      _provideFormFeedback("Great form! Full range of motion", now);
    }
  }

  // NEW: Helper method for form feedback with cooldown
  void _provideFormFeedback(String message, DateTime now) {
    if (_lastFormFeedbackTime == null ||
        now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
      _speak(message);
      _lastFormFeedbackTime = now;
    }
  }

  // Enhanced TTS helper method with cooldown
  Future<void> _speak(String text) async {
    final now = DateTime.now();
    if (_lastTtsFeedbackTime == null ||
        now.difference(_lastTtsFeedbackTime!) > _ttsFeedbackCooldown) {
      await _tts.setLanguage("en-US");
      await _tts.setPitch(1.0);
      await _tts.speak(text);
      _lastTtsFeedbackTime = now;
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
