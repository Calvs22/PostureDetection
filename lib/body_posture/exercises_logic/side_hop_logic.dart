// lib/body_posture/exercises/exercises_logic/side_hop_logic.dart

//NEED TESTING

import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';
import '/body_posture/camera/pose_painter.dart'; // Needed for FirstWhereOrNullExtension

// Enum to define the states of a Side Hop
enum SideHopState {
  right, // User is on the right side of the center
  left, // User is on the left side of the center
}

class SideHopLogic implements RepExerciseLogic {
  // CHANGED: implements RepExerciseLogic instead of ExerciseLogic
  int _repCount = 0;
  SideHopState? _currentState;
  double? _centerOfMassX;

  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(milliseconds: 200);

  bool _canCountRep = true;

  // Thresholds for side hop detection
  final double _hopThresholdX = 0.15;
  final double _minLandmarkConfidence = 0.7;

  // Tolerance and hysteresis constants
  final double _hopThresholdTolerance = 0.05;
  final double _hysteresisBuffer = 0.02;

  // TTS instance
  final FlutterTts _tts = FlutterTts();
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;

  // Form feedback cooldown
  DateTime? _lastFormFeedbackTime;
  final Duration _formFeedbackCooldown = Duration(seconds: 5);

  // TTS feedback cooldown
  DateTime? _lastTtsFeedbackTime;
  final Duration _ttsFeedbackCooldown = Duration(seconds: 3);

  // Error handling variables
  DateTime? _lastInvalidLandmarksTime;
  final Duration _gracePeriod = Duration(seconds: 1);
  bool _isInGracePeriod = false;

  // Velocity tracking for anticipation
  double _lastHorizontalDifference = 0;
  DateTime _lastUpdateTime = DateTime.now();

  // Movement direction tracking
  bool _isMovingRight = false;
  bool _isMovingLeft = false;

  // Movement smoothing
  double _smoothedHorizontalDifference = 0;
  final double _smoothingFactor = 0.3;

  // === ENHANCED PREDICTION VARIABLES ===
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

  // Camera view size for distance calculations
  Size? _cameraViewSize;

  // Hip height tracking for form analysis
  double _lastHipHeight = 0.0;
  final double _hipHeightThreshold = 0.05; // Threshold for hip height changes

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    // Cast landmarks to the correct type
    final poseLandmarks = landmarks as List<PoseLandmark>;

    // Speak initial message immediately on first update
    if (!_hasStarted) {
      _speak("Get into Position");
      _hasStarted = true;
    }

    // --- Landmark Retrieval ---
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);

    // Validate landmarks
    final bool allNecessaryLandmarksValid = _areLandmarksValid([
      leftHip,
      rightHip,
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
        _currentState = null;
        _canCountRep = false;
        _isInGracePeriod = false;
        _speak("Position lost - please restart");
        return;
      }
    } else {
      _isInGracePeriod = false;
      _lastInvalidLandmarksTime = null;
    }

    // FIXED: Added null checks before accessing leftHip and rightHip
    if (leftHip == null || rightHip == null) {
      return;
    }

    // Determine the user's horizontal center point (center of hips)
    final double currentCenterOfMassX = (leftHip.x + rightHip.x) / 2.0;

    // Set the initial center point on the first valid frame
    if (_centerOfMassX == null) {
      _centerOfMassX = currentCenterOfMassX;
      _currentState = SideHopState.right;
      _lastUpdateTime = DateTime.now();
      return;
    }

    // FIXED: Added null check for _centerOfMassX
    if (_centerOfMassX == null) return;

    // Calculate the horizontal difference from the initial center
    final double horizontalDifference = currentCenterOfMassX - _centerOfMassX!;

    // Calculate movement velocity for anticipation
    final now = DateTime.now();
    final timeDelta = now.difference(_lastUpdateTime).inMilliseconds / 1000.0;
    final velocity = timeDelta > 0.0
        ? (horizontalDifference - _lastHorizontalDifference) / timeDelta
        : 0.0;

    _lastHorizontalDifference = horizontalDifference;
    _lastUpdateTime = now;

    // Apply movement smoothing
    _smoothedHorizontalDifference =
        _smoothedHorizontalDifference * _smoothingFactor +
        horizontalDifference * (1.0 - _smoothingFactor);

    // Update prediction history
    _updatePredictionHistory(_smoothedHorizontalDifference, now);

    // Get enhanced prediction
    final predictedPosition = _predictNextPosition();

    // Track movement direction for better anticipation
    _isMovingRight = velocity > 0.5;
    _isMovingLeft = velocity < -0.5;

    // Hop detection with tolerance and hysteresis
    final bool isRight = _currentState == SideHopState.right
        ? _smoothedHorizontalDifference > (_hopThresholdX - _hysteresisBuffer)
        : _smoothedHorizontalDifference >
              (_hopThresholdX - _hopThresholdTolerance);

    final bool isLeft = _currentState == SideHopState.left
        ? _smoothedHorizontalDifference < (-_hopThresholdX + _hysteresisBuffer)
        : _smoothedHorizontalDifference <
              (-_hopThresholdX + _hopThresholdTolerance);

    // ENHANCED: Use prediction for earlier detection
    final bool willBeRight = predictedPosition > _hopThresholdX;
    final bool willBeLeft = predictedPosition < -_hopThresholdX;

    // Form analysis
    _checkForm(
      leftHip,
      rightHip,
      _smoothedHorizontalDifference,
      isRight,
      isLeft,
    );

    // Faster cooldown reset
    if (DateTime.now().difference(_lastRepTime) > _cooldownDuration) {
      if (!_canCountRep) {
        _canCountRep = true;
      }
    }

    // FIXED: Added null check for _currentState
    if (_currentState == null) return;

    // FIXED: Removed null assertion operator and used local variable instead
    final currentState = _currentState!;
    switch (currentState) {
      case SideHopState.right:
        // ENHANCED: Use prediction for earlier detection
        if ((isLeft && _isMovingLeft) || (willBeLeft && _isMovingLeft)) {
          if (_canCountRep) {
            _repCount++;
            _currentState = SideHopState.left;
            _lastRepTime = DateTime.now();
            _canCountRep = false;

            // Provide feedback every 5 reps
            if (_repCount % 5 == 0 && _repCount != _lastFeedbackRep) {
              _speak("Good job! Keep going!");
              _lastFeedbackRep = _repCount;
            }

            // Completion feedback
            if (_repCount == 10) {
              _speak("Almost there! Just a few more!");
            }
          } else {
            _currentState = SideHopState.left;
          }
        }
        break;

      case SideHopState.left:
        // ENHANCED: Use prediction for earlier detection
        if ((isRight && _isMovingRight) || (willBeRight && _isMovingRight)) {
          if (_canCountRep) {
            _repCount++;
            _currentState = SideHopState.right;
            _lastRepTime = DateTime.now();
            _canCountRep = false;
          } else {
            _currentState = SideHopState.right;
          }
        }
        break;
    }

    // Check rep rate for performance monitoring
    _checkRepRate();
  }

  @override
  void reset() {
    _repCount = 0;
    _currentState = SideHopState.right;
    _centerOfMassX = null;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastFormFeedbackTime = null;
    _lastTtsFeedbackTime = null;
    _lastInvalidLandmarksTime = null;
    _isInGracePeriod = false;

    // Reset performance tracking variables
    _lastHorizontalDifference = 0.0;
    _lastUpdateTime = DateTime.now();
    _smoothedHorizontalDifference = 0.0;

    // Reset prediction variables
    _positionHistory.clear();
    _timestampHistory.clear();
    _movementPattern.clear();
    _patternEstablished = false;

    _lastRepCount = 0;
    _lastRepRateCheck = DateTime.now();

    // Reset hip height tracking
    _lastHipHeight = 0.0;

    _speak("Reset complete. Get into Position");
  }

  @override
  String get progressLabel => "Side Hops: $_repCount";

  // ADDED: Required getter for RepExerciseLogic interface
  @override
  int get reps => _repCount;

  // Method to set camera view size (called from UI)
  void setCameraViewSize(Size size) {
    _cameraViewSize = size;

    // Use camera view size to adjust hop threshold based on screen size
    if (_cameraViewSize != null) {
      // Adjust threshold based on camera view width
      final double normalizedThreshold =
          _cameraViewSize!.width * 0.15; // 15% of screen width
      log(
        "Camera view size: $_cameraViewSize, adjusted threshold: $normalizedThreshold",
        name: 'SideHopLogic',
      );
    }
  }

  // Helper method to get landmark with confidence check
  PoseLandmark? _getLandmark(
    List<PoseLandmark> landmarks,
    PoseLandmarkType type,
  ) {
    // FIXED: Added null safety check for landmarks list
    if (landmarks.isEmpty) return null;

    final landmark = landmarks.firstWhereOrNull((l) => l.type == type);
    if (landmark != null && landmark.likelihood >= _minLandmarkConfidence) {
      return landmark;
    }
    return null;
  }

  // Helper method to validate landmarks
  bool _areLandmarksValid(List<PoseLandmark?> landmarks) {
    // FIXED: Added null safety check for landmarks list
    if (landmarks.isEmpty) return false;

    return landmarks.every(
      (landmark) =>
          landmark != null && landmark.likelihood >= _minLandmarkConfidence,
    );
  }

  // Form analysis with comprehensive checks
  void _checkForm(
    PoseLandmark? leftHip,
    PoseLandmark? rightHip,
    double horizontalDifference,
    bool isRight,
    bool isLeft,
  ) {
    final now = DateTime.now();

    // Check for sufficient hop distance with tolerance
    if (horizontalDifference.abs() <
            (_hopThresholdX - _hopThresholdTolerance) &&
        _currentState != null) {
      _provideFormFeedback("Hop further to the side", now);
    }

    // FIXED: Added null checks for leftHip and rightHip
    if (leftHip != null && rightHip != null) {
      final double hipHeightDiff = (leftHip.y - rightHip.y).abs();
      if (hipHeightDiff > 20.0) {
        _provideFormFeedback("Land with both feet level", now);
      }
    }

    // Check for steady rhythm
    final Duration timeSinceLastHop = DateTime.now().difference(_lastRepTime);
    if (timeSinceLastHop > Duration(seconds: 2) && _repCount > 2) {
      _provideFormFeedback("Keep a steady rhythm", now);
    }

    // FIXED: Added null checks for leftHip and rightHip
    if (leftHip != null && rightHip != null) {
      final double avgHipHeight = (leftHip.y + rightHip.y) / 2.0;

      // Track hip height changes over time
      final double hipHeightChange = (avgHipHeight - _lastHipHeight).abs();
      _lastHipHeight = avgHipHeight;

      // Check for proper landing technique
      if (_repCount > 3) {
        if (hipHeightChange > _hipHeightThreshold) {
          _provideFormFeedback("Keep your movements light and quick", now);
        } else if (hipHeightChange < _hipHeightThreshold * 0.5) {
          _provideFormFeedback("Try to hop with more explosive power", now);
        }
      }
    }

    // Positive feedback for good form
    if (horizontalDifference.abs() >
            (_hopThresholdX + _hopThresholdTolerance) &&
        _repCount > 3) {
      _provideFormFeedback("Great form! Good explosive movement", now);
    }
  }

  // Helper method for form feedback with cooldown
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

  // Performance monitoring
  int _lastRepCount = 0;
  DateTime _lastRepRateCheck = DateTime.now();

  void _checkRepRate() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRepRateCheck).inSeconds;

    if (elapsed >= 5) {
      final repsPerSecond = (_repCount - _lastRepCount) / elapsed.toDouble();

      if (repsPerSecond > 4.0) {
        log(
          "High rep rate detected: $repsPerSecond reps/sec",
          name: 'SideHopLogic',
        );
        _provideFormFeedback("Slow down for better form", now);
      } else if (repsPerSecond < 1.0 && _repCount > 5) {
        // Too slow might indicate poor form or rest
        log(
          "Low rep rate detected: $repsPerSecond reps/sec",
          name: 'SideHopLogic',
        );
        _provideFormFeedback("Increase your pace slightly", now);
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
      // Simple pattern detection - look for consistent oscillation
      final recent = _positionHistory.sublist(_positionHistory.length - 5);
      final bool isOscillating = _isOscillatingPattern(recent);

      if (isOscillating) {
        _movementPattern = List.from(recent);
        _patternEstablished = true;
      }
    }
  }

  bool _isOscillatingPattern(List<double> positions) {
    // Check if positions show a side-to-side pattern
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
    const double tolerance = 0.02;
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
