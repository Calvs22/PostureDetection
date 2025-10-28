// lib/body_posture/exercises/exercises_logic/lunges__logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show RepExerciseLogic;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// Enum to define the states of a Lunge
enum LungeState {
  up, // Starting position, both knees straight
  down, // Lunging position, knees are bent
  error, // Error state for tracking issues
}

class LungesLogic implements RepExerciseLogic {
  int _repCount = 0;
  LungeState _currentState = LungeState.up;

  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(
    milliseconds: 500,
  ); // Reduced cooldown to 500ms for faster rep counting
  bool _canCountRep = true;

  // Threshold values for accurate counting with tolerance ranges
  final double _kneeUpThresholdAngle = 160.0; // Base angle considered "up"
  final double _frontKneeDownThresholdAngle =
      120.0; // Base angle for the front knee when "down"
  final double _backKneeDownThresholdAngle =
      130.0; // Base angle for the back knee when "down"
  final double _angleTolerance = 10.0; // Tolerance range for angle thresholds
  final double _minLandmarkConfidence =
      0.7; // Minimum confidence for detected landmarks

  // Error handling variables
  DateTime _errorStartTime = DateTime.now();
  final Duration _errorRecoveryDuration = const Duration(seconds: 2);
  int _consecutiveErrors = 0;
  final int _maxConsecutiveErrors = 3;

  // TTS variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;

  // Form feedback variables
  DateTime _lastFormFeedbackTime = DateTime.now();
  final Duration _formFeedbackCooldown = const Duration(seconds: 3);
  String? _lastFormFeedback;

  // Performance optimization variables
  final double _smoothingFactor = 0.3; // 30% smoothing factor reduces jitter
  double _smoothedFrontKneeAngle = 160.0;
  double _smoothedBackKneeAngle = 160.0;
  bool _isMovingDown = false;
  bool _isMovingUp = false;
  double _frontKneeVelocity = 0.0;
  double _backKneeVelocity = 0.0;
  DateTime _lastUpdateTime = DateTime.now();

  // Enhanced prediction variables
  final List<double> _frontKneeHistory = [];
  final List<double> _backKneeHistory = [];
  final List<DateTime> _timeHistory = [];
  final int _historySize = 5;
  double _predictedFrontKneeAngle = 160.0;
  double _predictedBackKneeAngle = 160.0;
  final double _linearExtrapolationWeight = 0.4;
  final double _patternMatchingWeight = 0.3;
  final double _velocityBasedWeight = 0.3;

  // Form analysis variables
  final double _alignmentTolerance = 10.0; // Tolerance for body alignment
  final double _rhythmTolerance =
      0.5; // Tolerance for rhythm consistency (seconds)
  final List<Duration> _repDurations = [];
  DateTime _repStartTime = DateTime.now();

  LungesLogic() {
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
      // Store original rate and restore after speaking
      const originalRate = 0.5; // We set this in _initTts
      await _flutterTts.setSpeechRate(rate);
      await _flutterTts.speak(text);
      await _flutterTts.setSpeechRate(originalRate);
    }
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    // Cast landmarks to the correct type
    final List<PoseLandmark> poseLandmarks = landmarks.cast<PoseLandmark>();

    // --- Landmark Retrieval ---
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final leftKnee = _getLandmark(poseLandmarks, PoseLandmarkType.leftKnee);
    final leftAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.leftAnkle);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final rightKnee = _getLandmark(poseLandmarks, PoseLandmarkType.rightKnee);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);
    final leftShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.leftShoulder,
    );
    final rightShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.rightShoulder,
    );

    // Validate landmarks
    final bool allLandmarksValid = _areLandmarksValid([
      leftHip,
      leftKnee,
      leftAnkle,
      rightHip,
      rightKnee,
      rightAnkle,
      leftShoulder,
      rightShoulder,
    ]);

    // Error handling for invalid landmarks
    if (!allLandmarksValid) {
      _handleLandmarkError();
      return;
    }

    // Recovery from error state
    if (_currentState == LungeState.error) {
      if (DateTime.now().difference(_errorStartTime) > _errorRecoveryDuration) {
        _currentState = LungeState.up;
        _lastRepTime = DateTime.now().subtract(_cooldownDuration);
        _canCountRep = true;
        _consecutiveErrors = 0;
        _speak("Resuming exercise");
      }
      return;
    }

    // First time starting the exercise
    if (!_hasStarted) {
      _hasStarted = true;
      _repStartTime = DateTime.now();
      _speak("Get into Position");
    }

    // Calculate knee angles for both legs (Hip-Knee-Ankle angle)
    final double leftKneeAngle = _getAngle(leftHip!, leftKnee!, leftAnkle!);
    final double rightKneeAngle = _getAngle(rightHip!, rightKnee!, rightAnkle!);

    // Identify which leg is forward based on knee angles
    final bool isLeftLegForward = leftKneeAngle < rightKneeAngle;

    double frontKneeAngle;
    double backKneeAngle;

    if (isLeftLegForward) {
      frontKneeAngle = leftKneeAngle;
      backKneeAngle = rightKneeAngle;
    } else {
      frontKneeAngle = rightKneeAngle;
      backKneeAngle = leftKneeAngle;
    }

    // Update movement history for prediction
    _updateMovementHistory(frontKneeAngle, backKneeAngle);

    // Calculate velocities for direction tracking
    _calculateVelocities(frontKneeAngle, backKneeAngle);

    // Apply smoothing to reduce jitter
    _smoothedFrontKneeAngle =
        _smoothingFactor * frontKneeAngle +
        (1 - _smoothingFactor) * _smoothedFrontKneeAngle;
    _smoothedBackKneeAngle =
        _smoothingFactor * backKneeAngle +
        (1 - _smoothingFactor) * _smoothedBackKneeAngle;

    // Enhanced prediction algorithm
    _predictMovement();

    // Use predicted angles for earlier detection
    final double effectiveFrontKneeAngle = _predictedFrontKneeAngle;
    final double effectiveBackKneeAngle = _predictedBackKneeAngle;

    // Determine movement direction
    _determineMovementDirection(
      effectiveFrontKneeAngle,
      effectiveBackKneeAngle,
    );

    // Check for cooldown
    if (DateTime.now().difference(_lastRepTime) > _cooldownDuration) {
      if (!_canCountRep && _currentState == LungeState.up) {
        _canCountRep = true;
      }
    }

    // State machine logic with angle tolerance and movement direction
    switch (_currentState) {
      case LungeState.up:
        // User is moving from up to down (lunging) with tolerance
        if (effectiveFrontKneeAngle <
                (_frontKneeDownThresholdAngle + _angleTolerance) &&
            effectiveBackKneeAngle <
                (_backKneeDownThresholdAngle + _angleTolerance) &&
            _isMovingDown) {
          _currentState = LungeState.down;
        }
        break;

      case LungeState.down:
        // Provide form feedback in down position
        _provideFormFeedback(
          effectiveFrontKneeAngle,
          effectiveBackKneeAngle,
          leftShoulder!,
          rightShoulder!,
        );

        // User is moving from down to up (extending legs) with tolerance
        if (effectiveFrontKneeAngle >
                (_kneeUpThresholdAngle - _angleTolerance) &&
            effectiveBackKneeAngle >
                (_kneeUpThresholdAngle - _angleTolerance) &&
            _isMovingUp) {
          if (_canCountRep) {
            _repCount++;
            _currentState = LungeState.up;
            _lastRepTime = DateTime.now();
            _canCountRep = false;

            // Record rep duration for rhythm analysis
            final Duration repDuration = DateTime.now().difference(
              _repStartTime,
            );
            _repDurations.add(repDuration);
            _repStartTime = DateTime.now();

            // Provide feedback during exercise
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
          } else {
            _currentState = LungeState.up;
          }
        }
        break;

      case LungeState.error:
        // Already handled above
        break;
    }
  }

  void _updateMovementHistory(double frontKneeAngle, double backKneeAngle) {
    _frontKneeHistory.add(frontKneeAngle);
    _backKneeHistory.add(backKneeAngle);
    _timeHistory.add(DateTime.now());

    // Keep history at the specified size
    if (_frontKneeHistory.length > _historySize) {
      _frontKneeHistory.removeAt(0);
      _backKneeHistory.removeAt(0);
      _timeHistory.removeAt(0);
    }
  }

  void _calculateVelocities(double frontKneeAngle, double backKneeAngle) {
    final DateTime now = DateTime.now();
    final double timeDelta =
        now.difference(_lastUpdateTime).inMilliseconds / 1000.0;

    if (timeDelta > 0) {
      _frontKneeVelocity =
          (frontKneeAngle - _smoothedFrontKneeAngle) / timeDelta;
      _backKneeVelocity = (backKneeAngle - _smoothedBackKneeAngle) / timeDelta;
    }

    _lastUpdateTime = now;
  }

  void _predictMovement() {
    if (_frontKneeHistory.length < 2) {
      _predictedFrontKneeAngle = _smoothedFrontKneeAngle;
      _predictedBackKneeAngle = _smoothedBackKneeAngle;
      return;
    }

    // Linear extrapolation prediction
    double linearFrontPrediction = _smoothedFrontKneeAngle;
    double linearBackPrediction = _smoothedBackKneeAngle;

    if (_frontKneeHistory.length >= 2) {
      final double frontSlope =
          (_frontKneeHistory.last -
              _frontKneeHistory[_frontKneeHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;
      final double backSlope =
          (_backKneeHistory.last -
              _backKneeHistory[_backKneeHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;

      // Predict 100ms into the future
      linearFrontPrediction = _smoothedFrontKneeAngle + frontSlope * 0.1;
      linearBackPrediction = _smoothedBackKneeAngle + backSlope * 0.1;
    }

    // Pattern matching prediction for rhythmic exercises
    double patternFrontPrediction = _smoothedFrontKneeAngle;
    double patternBackPrediction = _smoothedBackKneeAngle;

    if (_repDurations.length >= 3) {
      // Using 3 as minimum for pattern validation
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
        // First half of rep (going down)
        patternFrontPrediction =
            _kneeUpThresholdAngle -
            (_kneeUpThresholdAngle - _frontKneeDownThresholdAngle) *
                (currentRepProgress * 2);
        patternBackPrediction =
            _kneeUpThresholdAngle -
            (_kneeUpThresholdAngle - _backKneeDownThresholdAngle) *
                (currentRepProgress * 2);
      } else {
        // Second half of rep (coming up)
        patternFrontPrediction =
            _frontKneeDownThresholdAngle +
            (_kneeUpThresholdAngle - _frontKneeDownThresholdAngle) *
                ((currentRepProgress - 0.5) * 2);
        patternBackPrediction =
            _backKneeDownThresholdAngle +
            (_kneeUpThresholdAngle - _backKneeDownThresholdAngle) *
                ((currentRepProgress - 0.5) * 2);
      }
    }

    // Velocity-based prediction
    final double velocityFrontPrediction =
        _smoothedFrontKneeAngle + _frontKneeVelocity * 0.1;
    final double velocityBackPrediction =
        _smoothedBackKneeAngle + _backKneeVelocity * 0.1;

    // Weighted combination of all prediction methods
    _predictedFrontKneeAngle =
        _linearExtrapolationWeight * linearFrontPrediction +
        _patternMatchingWeight * patternFrontPrediction +
        _velocityBasedWeight * velocityFrontPrediction;

    _predictedBackKneeAngle =
        _linearExtrapolationWeight * linearBackPrediction +
        _patternMatchingWeight * patternBackPrediction +
        _velocityBasedWeight * velocityBackPrediction;
  }

  void _determineMovementDirection(
    double frontKneeAngle,
    double backKneeAngle,
  ) {
    // Determine direction based on velocity and angle changes
    _isMovingDown =
        (_frontKneeVelocity < -2.0 && _backKneeVelocity < -2.0) ||
        (frontKneeAngle < _smoothedFrontKneeAngle &&
            backKneeAngle < _smoothedBackKneeAngle);

    _isMovingUp =
        (_frontKneeVelocity > 2.0 && _backKneeVelocity > 2.0) ||
        (frontKneeAngle > _smoothedFrontKneeAngle &&
            backKneeAngle > _smoothedBackKneeAngle);
  }

  void _handleLandmarkError() {
    _consecutiveErrors++;

    if (_currentState != LungeState.error) {
      _currentState = LungeState.error;
      _errorStartTime = DateTime.now();
      _speak("Please ensure your full body is visible");
    } else if (_consecutiveErrors >= _maxConsecutiveErrors) {
      _speak("Tracking paused. Please adjust your position");
    }
  }

  void _provideFormFeedback(
    double frontKneeAngle,
    double backKneeAngle,
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
  ) {
    if (DateTime.now().difference(_lastFormFeedbackTime) >
        _formFeedbackCooldown) {
      String? feedback;

      // Check for common form issues
      if (frontKneeAngle < 90) {
        feedback = "Bend your front knee less";
      } else if (backKneeAngle > 140) {
        feedback = "Bend your back knee more";
      } else if (frontKneeAngle > 130 && backKneeAngle > 130) {
        feedback = "Lower your body deeper";
      } else if (!_checkBodyAlignment(leftShoulder, rightShoulder)) {
        feedback = "Keep your upper body straight";
      } else if (!_checkRhythmConsistency()) {
        feedback = "Maintain a steady rhythm";
      } else if (_repCount > 0 && _repCount % 3 == 0) {
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
    // Calculate shoulder angle to check if upper body is leaning
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
        type: PoseLandmarkType.rightHip,
        x: (leftShoulder.x + rightShoulder.x) / 2,
        y: leftShoulder.y + 100,
        z: 0.0,
        likelihood: 1.0,
      ),
    );

    // Check if shoulder angle is within tolerance range
    return (shoulderAngle > (90 - _alignmentTolerance) &&
        shoulderAngle < (90 + _alignmentTolerance));
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
    _repCount = 0;
    _currentState = LungeState.up;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _consecutiveErrors = 0;
    _lastFormFeedbackTime = DateTime.now();
    _lastFormFeedback = null;
    _smoothedFrontKneeAngle = 160.0;
    _smoothedBackKneeAngle = 160.0;
    _frontKneeVelocity = 0.0;
    _backKneeVelocity = 0.0;
    _frontKneeHistory.clear();
    _backKneeHistory.clear();
    _timeHistory.clear();
    _predictedFrontKneeAngle = 160.0;
    _predictedBackKneeAngle = 160.0;
    _repDurations.clear();
    _speak("Exercise reset");
  }

  @override
  String get progressLabel => 'Lunges: $_repCount';

  @override
  int get reps => _repCount;

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

    if (magnitude1 == 0 || magnitude2 == 0) {
      return 180.0;
    }

    double cosineAngle = dotProduct / (magnitude1 * magnitude2);
    cosineAngle = max(-1.0, min(1.0, cosineAngle));

    double angleRad = acos(cosineAngle);
    return angleRad * 180 / pi;
  }
}
