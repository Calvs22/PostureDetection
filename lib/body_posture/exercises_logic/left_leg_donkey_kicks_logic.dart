// lib/body_posture/exercises/exercises_logic/left_leg_donkey_kicks_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show RepExerciseLogic;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// Enum to define the state of the donkey kick
enum DonkeyKickState {
  down, // Knee is on the ground or tucked (start position)
  up, // Leg is kicked up (top position)
  error, // Error state for tracking issues
}

class LeftLegDonkeyKicksLogic implements RepExerciseLogic {
  int _leftDonkeyKickCount = 0;
  DonkeyKickState _leftLegState = DonkeyKickState.down;

  DateTime _lastLeftKickTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(
    milliseconds: 500,
  ); // Reduced to 500ms for faster rep counting

  // Angle thresholds for donkey kick detection
  final double _activeKneeBendAngleMin = 70.0; // Min angle for active bent knee
  final double _activeKneeBendAngleMax =
      110.0; // Max angle for active bent knee
  final double _stationaryKneeBendAngleMin =
      70.0; // Min angle for stationary bent knee
  final double _stationaryKneeBendAngleMax =
      110.0; // Max angle for stationary bent knee
  final double _bodyAlignmentAngleMin = 160.0; // Min angle for a straight back
  final double _kickUpMinYDifferenceRatio = 0.10; // Min vertical lift ratio
  final double _maxHipRotationYDifferenceRatio =
      0.05; // Max vertical difference between hips
  final double _minLandmarkConfidence = 0.7; // Minimum confidence for landmarks
  final double _angleTolerance = 10.0; // Tolerance range for angle thresholds

  // Performance optimization variables
  final double _smoothingFactor = 0.3; // 30% smoothing factor reduces jitter
  double _smoothedLeftKneeAngle = 90.0;
  double _smoothedLegLiftRatio = 0.0;
  bool _isMovingUp = false;
  bool _isMovingDown = false;
  double _kneeVelocity = 0.0;
  double _liftVelocity = 0.0;
  DateTime _lastUpdateTime = DateTime.now();

  // Enhanced prediction variables
  final List<double> _kneeAngleHistory = [];
  final List<double> _liftRatioHistory = [];
  final List<DateTime> _timeHistory = [];
  final int _historySize = 5;
  double _predictedKneeAngle = 90.0;
  double _predictedLiftRatio = 0.0;
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

  // Error handling variables
  DateTime _errorStartTime = DateTime.now();
  final Duration _errorRecoveryDuration = const Duration(seconds: 2);
  int _consecutiveErrors = 0;
  final int _maxConsecutiveErrors = 3;

  LeftLegDonkeyKicksLogic() {
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
    // Cast landmarks to the correct type
    final List<PoseLandmark> poseLandmarks = landmarks.cast<PoseLandmark>();

    // --- Landmark Retrieval ---
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final leftKnee = _getLandmark(poseLandmarks, PoseLandmarkType.leftKnee);
    final leftAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.leftAnkle);
    final leftShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.leftShoulder,
    );
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final rightKnee = _getLandmark(poseLandmarks, PoseLandmarkType.rightKnee);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);
    final rightShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.rightShoulder,
    );

    // --- Confidence Check ---
    bool areAllLandmarksConfident = _areLandmarksValid([
      leftHip,
      leftKnee,
      leftAnkle,
      leftShoulder,
      rightHip,
      rightKnee,
      rightAnkle,
      rightShoulder,
    ]);

    // Error handling for invalid landmarks
    if (!areAllLandmarksConfident) {
      _handleLandmarkError();
      return;
    }

    // Recovery from error state
    if (_leftLegState == DonkeyKickState.error) {
      if (DateTime.now().difference(_errorStartTime) > _errorRecoveryDuration) {
        _leftLegState = DonkeyKickState.down;
        _lastLeftKickTime = DateTime.now().subtract(_cooldownDuration);
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

    // --- Calculate Common Conditions ---
    final double avgBodyAlignmentAngle =
        (_getAngle(leftShoulder!, leftHip!, leftKnee!) +
            _getAngle(rightShoulder!, rightHip!, rightKnee!)) /
        2;

    // Calculate body reference measurements
    final double shoulderDistance = _getDistance(leftShoulder, rightShoulder);

    final bool isBodyStable =
        avgBodyAlignmentAngle > (_bodyAlignmentAngleMin - _angleTolerance) &&
        (leftHip.y - rightHip.y).abs() <
            (shoulderDistance * _maxHipRotationYDifferenceRatio);

    // --- Left Leg Kick Specific Checks ---
    final double leftKneeAngle = _getAngle(leftHip, leftKnee, leftAnkle!);
    final double rightKneeAngle = _getAngle(rightHip, rightKnee, rightAnkle!);
    final double leftLegLength = _getDistance(leftHip, leftKnee);

    // Calculate leg lift ratio
    final double currentLegLiftRatio = (leftHip.y - leftKnee.y) / leftLegLength;

    // Update movement history for prediction
    _updateMovementHistory(leftKneeAngle, currentLegLiftRatio);

    // Calculate velocities for direction tracking
    _calculateVelocities(leftKneeAngle, currentLegLiftRatio);

    // Apply smoothing to reduce jitter
    _smoothedLeftKneeAngle =
        _smoothingFactor * leftKneeAngle +
        (1 - _smoothingFactor) * _smoothedLeftKneeAngle;
    _smoothedLegLiftRatio =
        _smoothingFactor * currentLegLiftRatio +
        (1 - _smoothingFactor) * _smoothedLegLiftRatio;

    // Enhanced prediction algorithm
    _predictMovement();

    // Use predicted values for earlier detection
    final double effectiveKneeAngle = _predictedKneeAngle;
    final double effectiveLiftRatio = _predictedLiftRatio;

    // Determine movement direction
    _determineMovementDirection(effectiveKneeAngle, effectiveLiftRatio);

    // Check vertical lift for the left leg
    final bool isLeftKneeBent =
        effectiveKneeAngle > (_activeKneeBendAngleMin - _angleTolerance) &&
        effectiveKneeAngle < (_activeKneeBendAngleMax + _angleTolerance);
    final bool isLeftLegLifted =
        effectiveLiftRatio > _kickUpMinYDifferenceRatio;

    // Check stationary leg (RIGHT) stability
    final bool isRightLegStable =
        rightKneeAngle > (_stationaryKneeBendAngleMin - _angleTolerance) &&
        rightKneeAngle < (_stationaryKneeBendAngleMax + _angleTolerance);

    // --- Left Leg Donkey Kick Detection Logic ---
    if (isBodyStable && isLeftKneeBent && isRightLegStable) {
      switch (_leftLegState) {
        case DonkeyKickState.down:
          // Transition to UP: Left leg lifts
          if (isLeftLegLifted && _isMovingUp) {
            _leftLegState = DonkeyKickState.up;
          }
          break;
        case DonkeyKickState.up:
          // Transition to DOWN: Left leg returns to down position, then count
          if (!isLeftLegLifted && _isMovingDown) {
            // Leg has returned to the down position
            // Check cooldown before counting
            if (DateTime.now().difference(_lastLeftKickTime) >
                _cooldownDuration) {
              _leftDonkeyKickCount++;
              _lastLeftKickTime = DateTime.now();
              _leftLegState = DonkeyKickState.down;

              // Record rep duration for rhythm analysis
              final Duration repDuration = DateTime.now().difference(
                _repStartTime,
              );
              _repDurations.add(repDuration);
              _repStartTime = DateTime.now();

              // Provide feedback during exercise
              if (_leftDonkeyKickCount != _lastFeedbackRep) {
                _lastFeedbackRep = _leftDonkeyKickCount;

                if (_leftDonkeyKickCount % 5 == 0) {
                  _speak("$_leftDonkeyKickCount kicks, keep going!");
                } else if (_leftDonkeyKickCount == 10) {
                  _speak("Great job! Halfway there!");
                } else if (_leftDonkeyKickCount >= 15) {
                  _speak("Almost done! You can do it!");
                } else {
                  _speak("Good job!");
                }
              }
            } else {
              _leftLegState = DonkeyKickState.down;
            }
          }
          break;
        case DonkeyKickState.error:
          // Already handled above
          break;
      }
    } else {
      // If general conditions for a donkey kick are not met, reset left leg state
      _leftLegState = DonkeyKickState.down;
    }

    // Provide form feedback
    _provideFormFeedback(
      effectiveKneeAngle,
      effectiveLiftRatio,
      leftHip,
      rightHip,
      leftShoulder,
      rightShoulder,
    );
  }

  void _updateMovementHistory(double kneeAngle, double liftRatio) {
    _kneeAngleHistory.add(kneeAngle);
    _liftRatioHistory.add(liftRatio);
    _timeHistory.add(DateTime.now());

    // Keep history at the specified size
    if (_kneeAngleHistory.length > _historySize) {
      _kneeAngleHistory.removeAt(0);
      _liftRatioHistory.removeAt(0);
      _timeHistory.removeAt(0);
    }
  }

  void _calculateVelocities(double kneeAngle, double liftRatio) {
    final DateTime now = DateTime.now();
    final double timeDelta =
        now.difference(_lastUpdateTime).inMilliseconds / 1000.0;

    if (timeDelta > 0) {
      _kneeVelocity = (kneeAngle - _smoothedLeftKneeAngle) / timeDelta;
      _liftVelocity = (liftRatio - _smoothedLegLiftRatio) / timeDelta;
    }

    _lastUpdateTime = now;
  }

  void _predictMovement() {
    if (_kneeAngleHistory.length < 2) {
      _predictedKneeAngle = _smoothedLeftKneeAngle;
      _predictedLiftRatio = _smoothedLegLiftRatio;
      return;
    }

    // Linear extrapolation prediction
    double linearKneePrediction = _smoothedLeftKneeAngle;
    double linearLiftPrediction = _smoothedLegLiftRatio;

    if (_kneeAngleHistory.length >= 2) {
      final double kneeSlope =
          (_kneeAngleHistory.last -
              _kneeAngleHistory[_kneeAngleHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;
      final double liftSlope =
          (_liftRatioHistory.last -
              _liftRatioHistory[_liftRatioHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;

      // Predict 100ms into the future
      linearKneePrediction = _smoothedLeftKneeAngle + kneeSlope * 0.1;
      linearLiftPrediction = _smoothedLegLiftRatio + liftSlope * 0.1;
    }

    // Pattern matching prediction for rhythmic exercises
    double patternKneePrediction = _smoothedLeftKneeAngle;
    double patternLiftPrediction = _smoothedLegLiftRatio;

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
        // First half of rep (kicking up)
        patternKneePrediction =
            _activeKneeBendAngleMax -
            (_activeKneeBendAngleMax - _activeKneeBendAngleMin) *
                (currentRepProgress * 2);
        patternLiftPrediction =
            _kickUpMinYDifferenceRatio * currentRepProgress * 2;
      } else {
        // Second half of rep (returning down)
        patternKneePrediction =
            _activeKneeBendAngleMin +
            (_activeKneeBendAngleMax - _activeKneeBendAngleMin) *
                ((currentRepProgress - 0.5) * 2);
        patternLiftPrediction =
            _kickUpMinYDifferenceRatio * (2 - currentRepProgress * 2);
      }
    }

    // Velocity-based prediction
    final double velocityKneePrediction =
        _smoothedLeftKneeAngle + _kneeVelocity * 0.1;
    final double velocityLiftPrediction =
        _smoothedLegLiftRatio + _liftVelocity * 0.1;

    // Weighted combination of all prediction methods
    _predictedKneeAngle =
        _linearExtrapolationWeight * linearKneePrediction +
        _patternMatchingWeight * patternKneePrediction +
        _velocityBasedWeight * velocityKneePrediction;

    _predictedLiftRatio =
        _linearExtrapolationWeight * linearLiftPrediction +
        _patternMatchingWeight * patternLiftPrediction +
        _velocityBasedWeight * velocityLiftPrediction;
  }

  void _determineMovementDirection(double kneeAngle, double liftRatio) {
    // Determine direction based on velocity and angle changes
    _isMovingUp =
        (_liftVelocity > 0.1 && _kneeVelocity < -1.0) ||
        (liftRatio > _smoothedLegLiftRatio &&
            kneeAngle < _smoothedLeftKneeAngle);

    _isMovingDown =
        (_liftVelocity < -0.1 && _kneeVelocity > 1.0) ||
        (liftRatio < _smoothedLegLiftRatio &&
            kneeAngle > _smoothedLeftKneeAngle);
  }

  void _handleLandmarkError() {
    _consecutiveErrors++;

    if (_leftLegState != DonkeyKickState.error) {
      _leftLegState = DonkeyKickState.error;
      _errorStartTime = DateTime.now();
      _speak("Please ensure your full body is visible");
    } else if (_consecutiveErrors >= _maxConsecutiveErrors) {
      _speak("Tracking paused. Please adjust your position");
    }
  }

  void _provideFormFeedback(
    double kneeAngle,
    double liftRatio,
    PoseLandmark leftHip,
    PoseLandmark rightHip,
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
  ) {
    if (DateTime.now().difference(_lastFormFeedbackTime) >
        _formFeedbackCooldown) {
      String? feedback;

      // Check for common form issues
      if (kneeAngle < _activeKneeBendAngleMin) {
        feedback = "Bend your knee more";
      } else if (kneeAngle > _activeKneeBendAngleMax) {
        feedback = "Straighten your knee less";
      } else if (liftRatio < _kickUpMinYDifferenceRatio) {
        feedback = "Lift your leg higher";
      } else if (!_checkHipStability(leftHip, rightHip)) {
        feedback = "Keep your hips stable";
      } else if (!_checkBodyAlignment(leftShoulder, leftHip)) {
        feedback = "Keep your back straight";
      } else if (!_checkRhythmConsistency()) {
        feedback = "Maintain a steady rhythm";
      } else if (_leftDonkeyKickCount > 0 && _leftDonkeyKickCount % 3 == 0) {
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

  bool _checkBodyAlignment(PoseLandmark leftShoulder, PoseLandmark leftHip) {
    // Calculate body alignment angle to check if back is straight
    final double bodyAlignmentAngle = _getAngle(
      PoseLandmark(
        type: PoseLandmarkType.leftShoulder,
        x: leftShoulder.x,
        y: leftShoulder.y,
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
        type: PoseLandmarkType.leftKnee,
        x: leftHip.x,
        y: leftHip.y + 100,
        z: 0.0,
        likelihood: 1.0,
      ),
    );

    // Check if body alignment angle is within tolerance range (close to 180 degrees for straight back)
    return (bodyAlignmentAngle > (180 - _hipStabilityTolerance) &&
        bodyAlignmentAngle < (180 + _hipStabilityTolerance));
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
    _leftDonkeyKickCount = 0;
    _leftLegState = DonkeyKickState.down;
    _lastLeftKickTime = DateTime.now();
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _smoothedLeftKneeAngle = 90.0;
    _smoothedLegLiftRatio = 0.0;
    _kneeVelocity = 0.0;
    _liftVelocity = 0.0;
    _kneeAngleHistory.clear();
    _liftRatioHistory.clear();
    _timeHistory.clear();
    _predictedKneeAngle = 90.0;
    _predictedLiftRatio = 0.0;
    _repDurations.clear();
    _lastFormFeedbackTime = DateTime.now();
    _lastFormFeedback = null;
    _consecutiveErrors = 0;
    _speak("Exercise reset");
  }

  @override
  String get progressLabel => 'Left Leg Kicks: $_leftDonkeyKickCount';

  @override
  int get reps => _leftDonkeyKickCount;

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

  double _getDistance(PoseLandmark p1, PoseLandmark p2) {
    final double dx = p1.x - p2.x;
    final double dy = p1.y - p2.y;
    return sqrt(dx * dx + dy * dy);
  }
}
