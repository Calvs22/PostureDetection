// lib/body_posture/exercises/exercises_logic/left_leg_glute_kickback_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';

// Logic class for Left Leg Glute Kickback
enum LegState { down, middle, up }

class LeftLegGluteKickbackLogic implements RepExerciseLogic {
  // CHANGED: implements RepExerciseLogic instead of ExerciseLogic
  int _count = 0;
  bool _isRepInProgress = false;
  LegState _currentState = LegState.down;

  final double _kickbackUpAngleThreshold = 160.0;
  final double _kickbackDownAngleThreshold = 100.0;
  final double _minLandmarkConfidence = 0.7;
  final double _angleTolerance = 10.0; // Tolerance range for angle thresholds

  // Angle tolerance improvements
  final double _hysteresisFactor = 0.8; // For smoother state transitions
  final double _middleRangeFactor = 0.3; // Defines the size of the middle range

  // Performance optimization variables
  final double _smoothingFactor = 0.3; // 30% smoothing factor reduces jitter
  double _smoothedLegAngle = 160.0;
  bool _isMovingUp = false;
  bool _isMovingDown = false;
  double _legVelocity = 0.0;
  DateTime _lastUpdateTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(
    milliseconds: 500,
  ); // Cooldown between reps

  // Enhanced prediction variables
  final List<double> _legAngleHistory = [];
  final List<DateTime> _timeHistory = [];
  final int _historySize = 5;
  double _predictedLegAngle = 160.0;
  final double _linearExtrapolationWeight = 0.4;
  final double _patternMatchingWeight = 0.3;
  final double _velocityBasedWeight = 0.3;

  // Form analysis variables
  final double _hipStabilityTolerance = 15.0; // Tolerance for hip stability
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

  // TTS feedback enhancements
  DateTime _lastFeedbackTime = DateTime.now();
  final Duration _feedbackCooldown = Duration(
    seconds: 2,
  ); // Minimum time between feedback
  LegState _lastFeedbackState = LegState.down; // Track last state for feedback

  // Error handling improvements
  bool _sensorConnected = true;
  int _consecutiveLowConfidenceFrames = 0;
  final int _maxLowConfidenceFrames = 10; // Before warning user
  LegState _lastStableState = LegState.down;

  LeftLegGluteKickbackLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    _isTtsInitialized = true;
  }

  Future<void> _speak(String text) async {
    // Check cooldown period
    final now = DateTime.now();
    if (now.difference(_lastFeedbackTime) < _feedbackCooldown) {
      return; // Skip this feedback to prevent spamming
    }

    if (_isTtsInitialized) {
      await _flutterTts.speak(text);
      _lastFeedbackTime = now;
    }
  }

  Future<void> _speakWithRate(String text, double rate) async {
    // Check cooldown period
    final now = DateTime.now();
    if (now.difference(_lastFeedbackTime) < _feedbackCooldown) {
      return; // Skip this feedback to prevent spamming
    }

    if (_isTtsInitialized) {
      const originalRate = 0.5; // We set this in _initTts
      await _flutterTts.setSpeechRate(rate);
      await _flutterTts.speak(text);
      await _flutterTts.setSpeechRate(originalRate);
      _lastFeedbackTime = now;
    }
  }

  @override
  String get progressLabel => 'Left Leg Glute Kickbacks: $_count';

  @override
  int get reps => _count; // ADDED: Required getter for RepExerciseLogic interface

  @override
  void update(List landmarks, bool isFrontCamera) {
    // Monitor sensor state
    if (landmarks.isEmpty) {
      _consecutiveLowConfidenceFrames++;
      if (_consecutiveLowConfidenceFrames >= _maxLowConfidenceFrames &&
          _sensorConnected) {
        _sensorConnected = false;
        _speak("Camera connection issue. Please check your camera.");
      }
      // If sensor is disconnected, maintain last stable state
      if (!_sensorConnected && _lastStableState != LegState.down) {
        _currentState = _lastStableState;
      }
      return;
    } else {
      if (!_sensorConnected) {
        _sensorConnected = true;
        _speak("Camera reconnected. Continuing exercise.");
      }
      _consecutiveLowConfidenceFrames = 0;
    }

    final leftHip = _getLandmark(landmarks, PoseLandmarkType.leftHip);
    final leftKnee = _getLandmark(landmarks, PoseLandmarkType.leftKnee);
    final leftAnkle = _getLandmark(landmarks, PoseLandmarkType.leftAnkle);
    final rightHip = _getLandmark(landmarks, PoseLandmarkType.rightHip);
    final rightKnee = _getLandmark(landmarks, PoseLandmarkType.rightKnee);
    final rightAnkle = _getLandmark(landmarks, PoseLandmarkType.rightAnkle);

    if (leftHip == null ||
        leftKnee == null ||
        leftAnkle == null ||
        rightHip == null ||
        rightKnee == null ||
        rightAnkle == null ||
        leftHip.likelihood < _minLandmarkConfidence ||
        leftKnee.likelihood < _minLandmarkConfidence ||
        leftAnkle.likelihood < _minLandmarkConfidence ||
        rightHip.likelihood < _minLandmarkConfidence ||
        rightKnee.likelihood < _minLandmarkConfidence ||
        rightAnkle.likelihood < _minLandmarkConfidence) {
      _consecutiveLowConfidenceFrames++;

      // Only provide feedback occasionally to avoid spamming
      if (_consecutiveLowConfidenceFrames == _maxLowConfidenceFrames) {
        _speak("Please ensure your body is fully visible.");
      }

      // Maintain last stable state if we lose tracking temporarily
      if (_lastStableState != LegState.down) {
        _currentState = _lastStableState;
      }
      _isRepInProgress = false; // Reset rep progress if tracking lost
      return;
    } else {
      _consecutiveLowConfidenceFrames = 0;
    }

    // First time starting the exercise
    if (!_hasStarted) {
      _hasStarted = true;
      _repStartTime = DateTime.now();
      _speak("Get into Position");
    }

    final double leftLegAngle = _getAngle(leftHip, leftKnee, leftAnkle);

    // Update movement history for prediction
    _updateMovementHistory(leftLegAngle);

    // Calculate velocity for direction tracking
    _calculateVelocity(leftLegAngle);

    // Apply smoothing to reduce jitter
    _smoothedLegAngle =
        _smoothingFactor * leftLegAngle +
        (1 - _smoothingFactor) * _smoothedLegAngle;

    // Enhanced prediction algorithm
    _predictMovement();

    // Use predicted angle for earlier detection
    final double effectiveLegAngle = _predictedLegAngle;

    // Determine movement direction
    _determineMovementDirection(effectiveLegAngle);

    // Define tolerance ranges with hysteresis
    final double upThreshold = _kickbackUpAngleThreshold - _angleTolerance;
    final double downThreshold = _kickbackDownAngleThreshold + _angleTolerance;

    // Define middle range with hysteresis
    final double middleRangeUp =
        upThreshold -
        (upThreshold - downThreshold) * _middleRangeFactor * _hysteresisFactor;
    final double middleRangeDown =
        downThreshold +
        (upThreshold - downThreshold) * _middleRangeFactor * _hysteresisFactor;

    // State machine with enhanced detection and hysteresis
    LegState newState = _currentState;

    if (_currentState == LegState.down) {
      if (effectiveLegAngle > upThreshold && _isMovingUp) {
        newState = LegState.up;
        _isRepInProgress = true; // Mark rep as in progress
      } else if (effectiveLegAngle > middleRangeUp) {
        newState = LegState.middle;
      }
    } else if (_currentState == LegState.up) {
      if (effectiveLegAngle < downThreshold && _isMovingDown) {
        newState = LegState.down;
        // Check cooldown before counting rep
        if (_isRepInProgress &&
            DateTime.now().difference(_lastUpdateTime) > _cooldownDuration) {
          _count++;
          _isRepInProgress = false; // Mark rep as completed

          // Record rep duration for rhythm analysis
          final Duration repDuration = DateTime.now().difference(_repStartTime);
          _repDurations.add(repDuration);
          _repStartTime = DateTime.now();

          // Provide feedback during exercise
          if (_count != _lastFeedbackRep) {
            _lastFeedbackRep = _count;

            if (_count % 5 == 0) {
              _speak("$_count reps, keep going!");
            } else if (_count == 10) {
              _speak("Great job! Halfway there!");
            } else if (_count >= 15) {
              _speak("Almost done! You can do it!");
            } else {
              _speak("Good job!");
            }
          }
        }
      } else if (effectiveLegAngle < middleRangeDown) {
        newState = LegState.middle;
      }
    } else if (_currentState == LegState.middle) {
      if (effectiveLegAngle > upThreshold && _isMovingUp) {
        newState = LegState.up;
        _isRepInProgress = true; // Mark rep as in progress
      } else if (effectiveLegAngle < downThreshold && _isMovingDown) {
        newState = LegState.down;
        // Check cooldown before counting rep
        if (_isRepInProgress &&
            DateTime.now().difference(_lastUpdateTime) > _cooldownDuration) {
          _count++;
          _isRepInProgress = false; // Mark rep as completed

          // Record rep duration for rhythm analysis
          final Duration repDuration = DateTime.now().difference(_repStartTime);
          _repDurations.add(repDuration);
          _repStartTime = DateTime.now();

          // Provide feedback during exercise
          if (_count != _lastFeedbackRep) {
            _lastFeedbackRep = _count;

            if (_count % 5 == 0) {
              _speak("$_count reps, keep going!");
            } else if (_count == 10) {
              _speak("Great job! Halfway there!");
            } else if (_count >= 15) {
              _speak("Almost done! You can do it!");
            } else {
              _speak("Good job!");
            }
          }
        }
      }
    }

    // Update state and track last stable state
    if (newState != _currentState) {
      _lastStableState = newState;
      _currentState = newState;

      // Use _lastFeedbackState to provide state-specific guidance
      _provideStateGuidance(newState);
    }

    // Provide form feedback
    _provideFormFeedback(effectiveLegAngle, leftHip, rightHip);
  }

  // New method to provide state-specific guidance using _lastFeedbackState
  void _provideStateGuidance(LegState currentState) {
    // Only provide guidance if we've entered a new state different from the last feedback state
    if (currentState != _lastFeedbackState) {
      switch (currentState) {
        case LegState.up:
          // Only provide up guidance if we haven't recently
          _speak("Good extension");
          break;
        case LegState.down:
          // Only provide down guidance if we haven't recently
          _speak("Return to start");
          break;
        case LegState.middle:
          // Middle state guidance
          _speak("Control movement");
          break;
      }

      // Update the last feedback state
      _lastFeedbackState = currentState;
    }
  }

  void _updateMovementHistory(double legAngle) {
    _legAngleHistory.add(legAngle);
    _timeHistory.add(DateTime.now());

    // Keep history at the specified size
    if (_legAngleHistory.length > _historySize) {
      _legAngleHistory.removeAt(0);
      _timeHistory.removeAt(0);
    }
  }

  void _calculateVelocity(double legAngle) {
    final DateTime now = DateTime.now();
    final double timeDelta =
        now.difference(_lastUpdateTime).inMilliseconds / 1000.0;

    if (timeDelta > 0) {
      _legVelocity = (legAngle - _smoothedLegAngle) / timeDelta;
    }

    _lastUpdateTime = now;
  }

  void _predictMovement() {
    if (_legAngleHistory.length < 2) {
      _predictedLegAngle = _smoothedLegAngle;
      return;
    }

    // Linear extrapolation prediction
    double linearPrediction = _smoothedLegAngle;

    if (_legAngleHistory.length >= 2) {
      final double slope =
          (_legAngleHistory.last -
              _legAngleHistory[_legAngleHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;

      // Predict 100ms into the future
      linearPrediction = _smoothedLegAngle + slope * 0.1;
    }

    // Pattern matching prediction for rhythmic exercises
    double patternPrediction = _smoothedLegAngle;

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
        // First half of rep (kicking back)
        patternPrediction =
            _kickbackUpAngleThreshold -
            (_kickbackUpAngleThreshold - _kickbackDownAngleThreshold) *
                (currentRepProgress * 2);
      } else {
        // Second half of rep (returning)
        patternPrediction =
            _kickbackDownAngleThreshold +
            (_kickbackUpAngleThreshold - _kickbackDownAngleThreshold) *
                ((currentRepProgress - 0.5) * 2);
      }
    }

    // Velocity-based prediction
    final double velocityPrediction = _smoothedLegAngle + _legVelocity * 0.1;

    // Weighted combination of all prediction methods
    _predictedLegAngle =
        _linearExtrapolationWeight * linearPrediction +
        _patternMatchingWeight * patternPrediction +
        _velocityBasedWeight * velocityPrediction;
  }

  void _determineMovementDirection(double legAngle) {
    // Determine direction based on velocity and angle changes
    _isMovingUp = _legVelocity > 2.0 || legAngle > _smoothedLegAngle;
    _isMovingDown = _legVelocity < -2.0 || legAngle < _smoothedLegAngle;
  }

  void _provideFormFeedback(
    double legAngle,
    PoseLandmark leftHip,
    PoseLandmark rightHip,
  ) {
    if (DateTime.now().difference(_lastFormFeedbackTime) >
        _formFeedbackCooldown) {
      String? feedback;

      // Check for common form issues
      if (legAngle > (_kickbackUpAngleThreshold - _angleTolerance)) {
        feedback = "Kick your leg back further";
      } else if (legAngle < (_kickbackDownAngleThreshold + _angleTolerance)) {
        feedback = "Return your leg more slowly";
      } else if (!_checkHipStability(leftHip, rightHip)) {
        feedback = "Keep your hips stable";
      } else if (!_checkRhythmConsistency()) {
        feedback = "Maintain a steady rhythm";
      } else if (_count > 0 && _count % 3 == 0) {
        // Positive feedback for good form
        feedback = "Excellent form!";
      }

      // Provide feedback if new issue detected and we haven't given feedback for this state yet
      if (feedback != null &&
          feedback != _lastFormFeedback &&
          _currentState != _lastFeedbackState) {
        _speakWithRate(feedback, 0.4);
        _lastFormFeedbackTime = DateTime.now();
        _lastFormFeedback = feedback;
      }
    }
  }

  bool _checkHipStability(PoseLandmark leftHip, PoseLandmark rightHip) {
    // Calculate hip angle to check if hips are stable
    final double hipAngle = _getAngle(
      PoseLandmark(
        type: PoseLandmarkType.leftShoulder,
        x: leftHip.x,
        y: leftHip.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: leftHip.x,
        y: leftHip.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.rightHip,
        x: rightHip.x,
        y: rightHip.y,
        z: 0.0,
        likelihood: 1.0,
      ),
    );

    // Check if hip angle is within tolerance range (close to 180 degrees for stable hips)
    return (hipAngle > (180 - _hipStabilityTolerance) &&
        hipAngle < (180 + _hipStabilityTolerance));
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
    _count = 0;
    _isRepInProgress = false;
    _hasStarted = false;
    _currentState = LegState.down;
    _lastStableState = LegState.down;
    _lastFeedbackState = LegState.down;
    _lastFeedbackRep = 0;
    _smoothedLegAngle = 160.0;
    _legVelocity = 0.0;
    _legAngleHistory.clear();
    _timeHistory.clear();
    _predictedLegAngle = 160.0;
    _repDurations.clear();
    _lastFormFeedbackTime = DateTime.now();
    _lastFormFeedback = null;
    _consecutiveLowConfidenceFrames = 0;
    _sensorConnected = true;
    _speak("Exercise reset");
  }

  PoseLandmark? _getLandmark(List landmarks, PoseLandmarkType type) {
    try {
      return landmarks.firstWhere((l) => l.type == type);
    } catch (_) {
      return null;
    }
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
}
