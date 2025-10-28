// lib/body_posture/exercises/exercises_logic/russian_twist_logic.dart

import 'dart:developer';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
// NOTE: Assuming this file contains the definition for RepExerciseLogic
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'; 

// The 'firstWhereOrNull' extension is missing here, but we will ignore it 
// and assume it's correctly handled via the imported 'pose_painter.dart' or an implicit extension. 

// Enum to define the states of a Russian Twist
enum RussianTwistState {
  center, // Torso facing forward
  twistedRight, // Torso twisted to the right
  twistedLeft, // Torso twisted to the left
}

// FIX: Ensure 'implements RepExerciseLogic' is used as the primary declaration
class RussianTwistLogic implements RepExerciseLogic { 
  int _repCount = 0;
  RussianTwistState _currentState = RussianTwistState.center;

  // 🎯 THE REQUIRED FIX: The getter from RepExerciseLogic must be implemented.
  @override
  int get reps => _repCount; 
  
  // ... (Other class fields and methods) ...
  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(milliseconds: 200); 

  bool _canCountRep = true;
  bool _hasSwungToSide = false;

  // Thresholds for Russian twist detection
  final double _twistThresholdX = 0.15; 
  final double _minLandmarkConfidence = 0.7; 

  // NEW: Tolerance and hysteresis constants
  final double _twistThresholdTolerance = 0.05; 
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
  double _lastTwistDifference = 0;
  DateTime _lastUpdateTime = DateTime.now();

  // Movement direction tracking
  bool _isMovingRight = false;
  bool _isMovingLeft = false;

  // Movement smoothing
  double _smoothedTwistDifference = 0;
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

  // Hip stability tracking
  double _lastHipPosition = 0.0;
  final double _hipMovementThreshold = 0.05; 

  // Performance monitoring
  int _lastRepCount = 0;
  DateTime _lastRepRateCheck = DateTime.now();


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
    // NOTE: The _getLandmark helper will return null if confidence is low, 
    // so null safety is critical here.
    final leftShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.leftShoulder,
    );
    final rightShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.rightShoulder,
    );
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);

    // Validate landmarks
    final bool allNecessaryLandmarksValid = _areLandmarksValid([
      leftShoulder,
      rightShoulder,
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
        _currentState = RussianTwistState.center;
        _canCountRep = false;
        _hasSwungToSide = false;
        _isInGracePeriod = false;
        _speak("Position lost - please restart");
        return;
      }
      return; // Skip logic if landmarks are invalid
    } else {
      _isInGracePeriod = false;
      _lastInvalidLandmarksTime = null;
    }

    // Since landmarks are valid, we can safely use the non-null assertion operator (!)
    final double leftShoulderHipDiffX = leftShoulder!.x - leftHip!.x;
    final double rightShoulderHipDiffX = rightShoulder!.x - rightHip!.x;

    // Calculate the twist range (difference between left and right sides)
    final double twistDifference = leftShoulderHipDiffX - rightShoulderHipDiffX;

    // Calculate movement velocity for anticipation
    final now = DateTime.now();
    final timeDelta = now.difference(_lastUpdateTime).inMilliseconds / 1000.0;
    final velocity = timeDelta > 0.0
        ? (twistDifference - _lastTwistDifference) / timeDelta
        : 0.0;

    _lastTwistDifference = twistDifference;
    _lastUpdateTime = now;

    // Apply movement smoothing
    _smoothedTwistDifference =
        _smoothedTwistDifference * _smoothingFactor +
        twistDifference * (1.0 - _smoothingFactor);

    // Update prediction history
    _updatePredictionHistory(_smoothedTwistDifference, now);

    // Get enhanced prediction
    final predictedPosition = _predictNextPosition();

    // Track movement direction for better anticipation
    _isMovingRight = velocity > 0.5; // Moving right threshold
    _isMovingLeft = velocity < -0.5; // Moving left threshold

    // Twist detection with tolerance and hysteresis
    // Hysteresis: Stay in current state unless crossing a tighter threshold back towards center.
    final bool isTwistedRight = _currentState == RussianTwistState.twistedRight
        ? _smoothedTwistDifference > (_twistThresholdX - _hysteresisBuffer)
        : _smoothedTwistDifference > (_twistThresholdX - _twistThresholdTolerance);

    final bool isTwistedLeft = _currentState == RussianTwistState.twistedLeft
        ? _smoothedTwistDifference < (-_twistThresholdX + _hysteresisBuffer)
        : _smoothedTwistDifference < (-_twistThresholdX + _twistThresholdTolerance);

    // Use prediction for earlier detection
    final bool willBeTwistedRight = predictedPosition > _twistThresholdX;
    final bool willBeTwistedLeft = predictedPosition < -_twistThresholdX;

    // Form analysis
    _checkForm(
      leftShoulderHipDiffX,
      rightShoulderHipDiffX,
      _smoothedTwistDifference, // Use smoothed value
      isTwistedRight,
      isTwistedLeft,
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
    );

    // Cooldown reset
    if (DateTime.now().difference(_lastRepTime) > _cooldownDuration) {
      if (!_canCountRep) {
        _canCountRep = true;
      }
    }

    switch (_currentState) {
      case RussianTwistState.center:
        // Use prediction for earlier detection and direction
        if ((isTwistedRight && _isMovingRight) || (willBeTwistedRight && _isMovingRight)) {
          _currentState = RussianTwistState.twistedRight;
          _hasSwungToSide = true;
          _speak("Right");
        } else if ((isTwistedLeft && _isMovingLeft) || (willBeTwistedLeft && _isMovingLeft)) {
          _currentState = RussianTwistState.twistedLeft;
          _hasSwungToSide = true;
          _speak("Left");
        }
        break;

      case RussianTwistState.twistedRight:
        // Transition from Right to Left counts a rep.
        if ((isTwistedLeft && _isMovingLeft) || (willBeTwistedLeft && _isMovingLeft)) {
          if (_canCountRep && _hasSwungToSide) {
            _repCount++; // Rep is counted here (Right to Left)
            _currentState = RussianTwistState.twistedLeft;
            _lastRepTime = DateTime.now();
            _canCountRep = false;
            _hasSwungToSide = true;
            
            if (_repCount % 5 == 0 && _repCount != _lastFeedbackRep) {
              _speak("Good job! Reps: $_repCount");
              _lastFeedbackRep = _repCount;
            } else {
              _speak("Left");
            }
          } else {
            _currentState = RussianTwistState.twistedLeft;
            _speak("Left");
          }
        }
        break;

      case RussianTwistState.twistedLeft:
        // Transition from Left to Right counts a rep.
        if ((isTwistedRight && _isMovingRight) || (willBeTwistedRight && _isMovingRight)) {
          if (_canCountRep && _hasSwungToSide) {
            _repCount++; // Rep is counted here (Left to Right)
            _currentState = RussianTwistState.twistedRight;
            _lastRepTime = DateTime.now();
            _canCountRep = false;
            _hasSwungToSide = true;

            // Provide feedback every 5 reps
            if (_repCount % 5 == 0 && _repCount != _lastFeedbackRep) {
              _speak("Halfway there! Reps: $_repCount");
              _lastFeedbackRep = _repCount;
            } else {
              _speak("Right");
            }

          } else {
            _currentState = RussianTwistState.twistedRight;
            _speak("Right");
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
    _currentState = RussianTwistState.center;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasSwungToSide = false;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastFormFeedbackTime = null;
    _lastTtsFeedbackTime = null;
    _lastInvalidLandmarksTime = null;
    _isInGracePeriod = false;

    // Reset performance tracking variables
    _lastTwistDifference = 0.0;
    _lastUpdateTime = DateTime.now();
    _smoothedTwistDifference = 0.0;

    // Reset prediction variables
    _positionHistory.clear();
    _timestampHistory.clear();
    _movementPattern.clear();
    _patternEstablished = false;

    _lastRepCount = 0;
    _lastRepRateCheck = DateTime.now();

    // Reset hip tracking
    _lastHipPosition = 0.0;

    _speak("Reset complete. Get into Position");
  }

  @override
  String get progressLabel => "Reps: $_repCount"; // CHANGED: More concise label for UI

  // Helper method to get landmark with confidence check
  // NOTE: This helper should be located in a shared utility or extension file, 
  // but is kept here for completeness.
  PoseLandmark? _getLandmark(
    List<PoseLandmark> landmarks,
    PoseLandmarkType type,
  ) {
    // Custom logic for 'firstWhereOrNull' equivalent if not using a library extension
    for (final landmark in landmarks) {
      if (landmark.type == type && landmark.likelihood >= _minLandmarkConfidence) {
        return landmark;
      }
    }
    return null;
  }

  // Helper method to validate landmarks
  bool _areLandmarksValid(List<PoseLandmark?> landmarks) {
    return landmarks.every((landmark) => landmark != null);
  }

  // Form analysis with comprehensive checks
  void _checkForm(
    double leftShoulderHipDiffX,
    double rightShoulderHipDiffX,
    double twistDifference, 
    bool isTwistedRight,
    bool isTwistedLeft,
    PoseLandmark? leftShoulder,
    PoseLandmark? rightShoulder,
    PoseLandmark? leftHip,
    PoseLandmark? rightHip,
  ) {
    final now = DateTime.now();

    // 1. Check for sufficient twist range with tolerance
    if (twistDifference.abs() < (_twistThresholdX - _twistThresholdTolerance) &&
        _currentState != RussianTwistState.center) {
      _provideFormFeedback("Twist further to the side", now);
    }

    // 2. Check for hip stability (hips shouldn't move much during twists)
    if (leftHip != null && rightHip != null) {
      // Average hip height (Y-coordinate)
      final double hipPosition = (leftHip.y + rightHip.y) / 2.0; 

      final double hipMovementChange = (_lastHipPosition == 0.0) 
        ? 0.0 
        : (hipPosition - _lastHipPosition).abs();
        
      _lastHipPosition = hipPosition;

      if (hipMovementChange > _hipMovementThreshold && _repCount > 3) {
        _provideFormFeedback("Keep your hips stable", now);
      }
    }

    // 3. Check for upper body alignment (shoulders should be relatively level)
    if (leftShoulder != null && rightShoulder != null) {
      final double shoulderHeightDiff = (leftShoulder.y - rightShoulder.y).abs();
      if (shoulderHeightDiff > 15.0) { // 15.0 is an arbitrary pixel difference threshold
        _provideFormFeedback("Keep your shoulders level", now);
      }
    }

    // 4. Check for steady rhythm (If stationary for too long)
    final Duration timeSinceLastRep = DateTime.now().difference(_lastRepTime);
    if (timeSinceLastRep > Duration(seconds: 2) && _repCount > 2) {
      _provideFormFeedback("Keep a steady rhythm", now);
    }

    // Positive feedback for good form with tolerance (Only if a full, deep twist is achieved)
    if (twistDifference.abs() > (_twistThresholdX + _twistThresholdTolerance) &&
        _repCount > 3 && _currentState != RussianTwistState.center) {
      _provideFormFeedback("Great form! Full range of motion", now);
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
  void _checkRepRate() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRepRateCheck).inSeconds;

    if (elapsed >= 5 && _repCount > _lastRepCount) {
      final repsPerSecond = (_repCount - _lastRepCount) / elapsed.toDouble();

      // Rep rate logic for Russian Twists
      if (repsPerSecond > 1.5) { // A high rate suggests rushing
        log("High rep rate detected: $repsPerSecond reps/sec", name: 'RussianTwistLogic');
        _provideFormFeedback("Slow down for better form", now);
      } else if (repsPerSecond < 0.2 && _repCount > 5) { // Too slow suggests resting
        log("Low rep rate detected: $repsPerSecond reps/sec", name: 'RussianTwistLogic');
        _provideFormFeedback("Maintain a steady pace", now);
      }

      _lastRepCount = _repCount;
      _lastRepRateCheck = now;
    }
  }

  // === ENHANCED PREDICTION METHODS ===
  // NOTE: Prediction logic is generally functional but overly complex for a typical simple fitness tracker.
  // Keeping it for now as requested.

  void _updatePredictionHistory(double position, DateTime timestamp) {
    _positionHistory.add(position);
    _timestampHistory.add(timestamp);

    if (_positionHistory.length > _historySize) {
      _positionHistory.removeAt(0);
      _timestampHistory.removeAt(0);
    }

    _updateMovementPattern();
  }

  void _updateMovementPattern() {
    if (_positionHistory.length >= 5) {
      final recent = _positionHistory.sublist(_positionHistory.length - 5);
      final bool isOscillating = _isOscillatingPattern(recent);

      if (isOscillating) {
        _movementPattern = List.from(recent);
        _patternEstablished = true;
      }
    }
  }

  bool _isOscillatingPattern(List<double> positions) {
    int signChanges = 0;
    for (int i = 1; i < positions.length - 1; i++) {
      final prevDiff = positions[i] - positions[i - 1];
      final currDiff = positions[i + 1] - positions[i];
      if (prevDiff * currDiff < 0.0) {
        signChanges++;
      }
    }
    return signChanges >= 2; 
  }

  double _predictNextPosition() {
    if (_positionHistory.length < 3) return 0.0;

    final linearPrediction = _linearPrediction();
    final patternPrediction = _patternEstablished ? _patternPrediction() : 0.0;
    final velocityPrediction = _velocityPrediction();

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

    final currentSegment = _positionHistory.sublist(_positionHistory.length - 3);

    for (int i = 0; i <= _movementPattern.length - 3; i++) {
      final patternSegment = _movementPattern.sublist(i, i + 3);
      if (_segmentsMatch(currentSegment, patternSegment)) {
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

    final recentPositions = _positionHistory.sublist(_positionHistory.length - 3);
    final recentTimestamps = _timestampHistory.sublist(_timestampHistory.length - 3);

    List<double> velocities = [];
    for (int i = 1; i < recentPositions.length; i++) {
      final timeDelta = recentTimestamps[i].difference(recentTimestamps[i - 1]).inMilliseconds / 1000.0;
      final positionDelta = recentPositions[i] - recentPositions[i - 1];
      velocities.add(positionDelta / timeDelta);
    }

    final avgVelocity = velocities.reduce((a, b) => a + b) / velocities.length.toDouble();
    return _positionHistory.last + avgVelocity * 0.1; 
  }
}