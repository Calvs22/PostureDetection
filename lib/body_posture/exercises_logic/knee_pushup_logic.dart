// lib/body_posture/exercises/exercises_logic/knee_push_up_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show RepExerciseLogic;
import '/body_posture/camera/pose_painter.dart'; // Needed for FirstWhereOrNullExtension

// Define states for a knee push-up repetition
enum KneePushUpState {
  initial, // User is at the top position, ready to go down
  downPosition, // User has lowered themselves to the bottom position
  error, // Error state for tracking issues
}

class KneePushUpLogic implements RepExerciseLogic {
  int _pushUpCount = 0;
  KneePushUpState _currentState = KneePushUpState.initial;

  // Cooldown to prevent rapid, false counts
  DateTime _lastCountTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(milliseconds: 500);

  // Angle thresholds for push-up detection
  final double _elbowBentThreshold = 90.0;
  final double _elbowStraightThreshold = 160.0;

  // Body straightness and knee bend
  final double _bodyStraightnessMinThreshold = 160.0;
  final double _kneeBentMaxThreshold = 110.0;

  final double _minLandmarkConfidence = 0.7;
  final double _angleTolerance = 10.0; // Tolerance range for angle thresholds

  // TTS instance
  final FlutterTts _tts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;

  // Form feedback cooldown
  DateTime? _lastFormFeedbackTime;
  final Duration _formFeedbackCooldown = Duration(seconds: 3);

  // Range of motion tracking
  double _minElbowAngle = 180.0;
  double _maxElbowAngle = 0.0;
  bool _hasReachedFullExtension = false;

  // Performance optimization variables
  final double _smoothingFactor = 0.3; // 30% smoothing factor reduces jitter
  double _smoothedElbowAngle = 180.0;
  double _smoothedBodyAngle = 180.0;
  double _smoothedKneeAngle = 90.0;
  bool _isMovingDown = false;
  bool _isMovingUp = false;
  double _elbowVelocity = 0.0;
  DateTime _lastUpdateTime = DateTime.now();

  // Enhanced prediction variables
  final List<double> _elbowAngleHistory = [];
  final List<DateTime> _timeHistory = [];
  final int _historySize = 5;
  double _predictedElbowAngle = 180.0;
  final double _linearExtrapolationWeight = 0.4;
  final double _patternMatchingWeight = 0.3;
  final double _velocityBasedWeight = 0.3;

  // Form analysis variables
  final double _shoulderAlignmentTolerance =
      15.0; // Tolerance for shoulder alignment
  final double _rhythmTolerance =
      0.5; // Tolerance for rhythm consistency (seconds)
  final List<Duration> _repDurations = [];
  DateTime _repStartTime = DateTime.now();

  // Performance monitoring variables
  double _repRate = 0.0; // reps per second - RESTORED AND UTILIZED
  bool _isPatternValid = true;
  final int _minRepsForPatternValidation = 3;

  // Error handling variables
  DateTime _errorStartTime = DateTime.now();
  final Duration _errorRecoveryDuration = const Duration(seconds: 2);
  int _consecutiveErrors = 0;
  final int _maxConsecutiveErrors = 3;

  KneePushUpLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _isTtsInitialized = true;
  }

  @override
  String get progressLabel => "Knee Push-ups: $_pushUpCount";

  @override
  int get reps => _pushUpCount;

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    final poseLandmarks = landmarks as List<PoseLandmark>;

    if (!_hasStarted) {
      _speak("Get into Position");
      _hasStarted = true;
      _repStartTime = DateTime.now();
    }

    // --- Landmark Retrieval ---
    final actualLeftShoulder = _getLandmark(
      poseLandmarks,
      isFrontCamera
          ? PoseLandmarkType.rightShoulder
          : PoseLandmarkType.leftShoulder,
    );
    final actualLeftElbow = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.rightElbow : PoseLandmarkType.leftElbow,
    );
    final actualLeftWrist = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.rightWrist : PoseLandmarkType.leftWrist,
    );
    final actualLeftHip = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.rightHip : PoseLandmarkType.leftHip,
    );
    final actualLeftKnee = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.rightKnee : PoseLandmarkType.leftKnee,
    );
    final actualLeftAnkle = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.rightAnkle : PoseLandmarkType.leftAnkle,
    );

    final actualRightShoulder = _getLandmark(
      poseLandmarks,
      isFrontCamera
          ? PoseLandmarkType.leftShoulder
          : PoseLandmarkType.rightShoulder,
    );
    final actualRightElbow = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow,
    );
    final actualRightWrist = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.leftWrist : PoseLandmarkType.rightWrist,
    );
    final actualRightHip = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip,
    );
    final actualRightKnee = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee,
    );
    final actualRightAnkle = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle,
    );

    // Validate if all necessary landmarks are detected
    if (actualLeftShoulder == null ||
        actualLeftElbow == null ||
        actualLeftWrist == null ||
        actualLeftHip == null ||
        actualLeftKnee == null ||
        actualLeftAnkle == null ||
        actualRightShoulder == null ||
        actualRightElbow == null ||
        actualRightWrist == null ||
        actualRightHip == null ||
        actualRightKnee == null ||
        actualRightAnkle == null) {
      _handleLandmarkError();
      return;
    }

    // Recovery from error state
    if (_currentState == KneePushUpState.error) {
      if (DateTime.now().difference(_errorStartTime) > _errorRecoveryDuration) {
        _currentState = KneePushUpState.initial;
        _lastCountTime = DateTime.now().subtract(_cooldownDuration);
        _consecutiveErrors = 0;
        _speak("Resuming exercise");
      }
      return;
    }

    // Calculate elbow angles
    final double leftElbowAngle = _getAngle(
      actualLeftShoulder,
      actualLeftElbow,
      actualLeftWrist,
    );
    final double rightElbowAngle = _getAngle(
      actualRightShoulder,
      actualRightElbow,
      actualRightWrist,
    );
    final double averageElbowAngle = (leftElbowAngle + rightElbowAngle) / 2;

    // Update movement history for prediction
    _updateMovementHistory(averageElbowAngle);

    // Calculate velocity for direction tracking
    _calculateVelocity(averageElbowAngle);

    // Apply smoothing to reduce jitter
    _smoothedElbowAngle =
        _smoothingFactor * averageElbowAngle +
        (1 - _smoothingFactor) * _smoothedElbowAngle;

    // Enhanced prediction algorithm
    _predictMovement();

    // Use predicted angle for earlier detection
    final double effectiveElbowAngle = _predictedElbowAngle;

    // Determine movement direction
    _determineMovementDirection(effectiveElbowAngle);

    // Track range of motion
    _minElbowAngle = min(_minElbowAngle, effectiveElbowAngle);
    _maxElbowAngle = max(_maxElbowAngle, effectiveElbowAngle);

    // Calculate body straightness (Shoulder-Hip-Knee)
    final double leftBodyAngle = _getAngle(
      actualLeftShoulder,
      actualLeftHip,
      actualLeftKnee,
    );
    final double rightBodyAngle = _getAngle(
      actualRightShoulder,
      actualRightHip,
      actualRightKnee,
    );
    final double averageBodyAngle = (leftBodyAngle + rightBodyAngle) / 2;

    // Apply smoothing to body angle
    _smoothedBodyAngle =
        _smoothingFactor * averageBodyAngle +
        (1 - _smoothingFactor) * _smoothedBodyAngle;

    // Calculate knee bend (Hip-Knee-Ankle)
    final double leftKneeBendAngle = _getAngle(
      actualLeftHip,
      actualLeftKnee,
      actualLeftAnkle,
    );
    final double rightKneeBendAngle = _getAngle(
      actualRightHip,
      actualRightKnee,
      actualRightAnkle,
    );
    final double averageKneeBendAngle =
        (leftKneeBendAngle + rightKneeBendAngle) / 2;

    // Apply smoothing to knee angle
    _smoothedKneeAngle =
        _smoothingFactor * averageKneeBendAngle +
        (1 - _smoothingFactor) * _smoothedKneeAngle;

    // Check form
    final bool isCorrectForm =
        _smoothedBodyAngle >
            (_bodyStraightnessMinThreshold - _angleTolerance) &&
        _smoothedKneeAngle < (_kneeBentMaxThreshold + _angleTolerance);

    _checkForm(
      effectiveElbowAngle,
      _smoothedBodyAngle,
      _smoothedKneeAngle,
      actualLeftShoulder,
      actualRightShoulder,
      actualLeftHip,
      actualRightHip,
      actualLeftKnee,
      actualRightKnee,
    );

    // --- Push-up State Machine ---
    if (DateTime.now().difference(_lastCountTime) > _cooldownDuration) {
      switch (_currentState) {
        case KneePushUpState.initial:
          if (isCorrectForm &&
              effectiveElbowAngle < (_elbowBentThreshold + _angleTolerance) &&
              _isMovingDown) {
            _currentState = KneePushUpState.downPosition;
            _speak("Down");
          }
          break;

        case KneePushUpState.downPosition:
          if (isCorrectForm &&
              effectiveElbowAngle >
                  (_elbowStraightThreshold - _angleTolerance) &&
              _isMovingUp) {
            _pushUpCount++;
            _lastCountTime = DateTime.now();
            _currentState = KneePushUpState.initial;

            // Record rep duration for rhythm analysis
            final Duration repDuration = DateTime.now().difference(
              _repStartTime,
            );
            _repDurations.add(repDuration);
            _repStartTime = DateTime.now();

            // Update performance metrics
            _updatePerformanceMetrics();

            if (_maxElbowAngle >= 170.0) {
              _hasReachedFullExtension = true;
            }

            if (_pushUpCount % 5 == 0 && _pushUpCount != _lastFeedbackRep) {
              _speakWithRate("Good job! Keep going!", 0.5);
              _lastFeedbackRep = _pushUpCount;
            }

            if (_pushUpCount == 10) {
              _speak("Almost there! Just a few more!");
            }
          }
          break;

        case KneePushUpState.error:
          // Already handled above
          break;
      }
    }
  }

  void _updateMovementHistory(double elbowAngle) {
    _elbowAngleHistory.add(elbowAngle);
    _timeHistory.add(DateTime.now());

    // Keep history at the specified size
    if (_elbowAngleHistory.length > _historySize) {
      _elbowAngleHistory.removeAt(0);
      _timeHistory.removeAt(0);
    }
  }

  void _calculateVelocity(double elbowAngle) {
    final DateTime now = DateTime.now();
    final double timeDelta =
        now.difference(_lastUpdateTime).inMilliseconds / 1000.0;

    if (timeDelta > 0) {
      _elbowVelocity = (elbowAngle - _smoothedElbowAngle) / timeDelta;
    }

    _lastUpdateTime = now;
  }

  void _predictMovement() {
    if (_elbowAngleHistory.length < 2) {
      _predictedElbowAngle = _smoothedElbowAngle;
      return;
    }

    // Linear extrapolation prediction
    double linearPrediction = _smoothedElbowAngle;

    if (_elbowAngleHistory.length >= 2) {
      final double slope =
          (_elbowAngleHistory.last -
              _elbowAngleHistory[_elbowAngleHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;

      // Predict 100ms into the future
      linearPrediction = _smoothedElbowAngle + slope * 0.1;
    }

    // Pattern matching prediction for rhythmic exercises
    double patternPrediction = _smoothedElbowAngle;

    if (_repDurations.length >= _minRepsForPatternValidation) {
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
        patternPrediction =
            _elbowStraightThreshold -
            (_elbowStraightThreshold - _elbowBentThreshold) *
                (currentRepProgress * 2);
      } else {
        // Second half of rep (coming up)
        patternPrediction =
            _elbowBentThreshold +
            (_elbowStraightThreshold - _elbowBentThreshold) *
                ((currentRepProgress - 0.5) * 2);
      }
    }

    // Velocity-based prediction
    final double velocityPrediction =
        _smoothedElbowAngle + _elbowVelocity * 0.1;

    // Weighted combination of all prediction methods
    _predictedElbowAngle =
        _linearExtrapolationWeight * linearPrediction +
        _patternMatchingWeight * patternPrediction +
        _velocityBasedWeight * velocityPrediction;
  }

  void _determineMovementDirection(double elbowAngle) {
    // Determine direction based on velocity and angle changes
    _isMovingDown = _elbowVelocity < -2.0 || elbowAngle < _smoothedElbowAngle;
    _isMovingUp = _elbowVelocity > 2.0 || elbowAngle > _smoothedElbowAngle;
  }

  void _updatePerformanceMetrics() {
    // Calculate rep rate (reps per second)
    if (_repDurations.isNotEmpty) {
      final double avgDuration =
          _repDurations.fold(
            0,
            (sum, duration) => sum + duration.inMilliseconds,
          ) /
          _repDurations.length /
          1000.0;
      _repRate = 1.0 / avgDuration;
    }

    // Validate pattern consistency
    if (_repDurations.length >= _minRepsForPatternValidation) {
      _isPatternValid = _checkRhythmConsistency();
    }
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

  void _handleLandmarkError() {
    _consecutiveErrors++;

    if (_currentState != KneePushUpState.error) {
      _currentState = KneePushUpState.error;
      _errorStartTime = DateTime.now();
      _speak("Please ensure your full body is visible");
    } else if (_consecutiveErrors >= _maxConsecutiveErrors) {
      _speak("Tracking paused. Please adjust your position");
    }
  }

  @override
  void reset() {
    _pushUpCount = 0;
    _currentState = KneePushUpState.initial;
    _lastCountTime = DateTime.now();
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastFormFeedbackTime = null;
    _minElbowAngle = 180.0;
    _maxElbowAngle = 0.0;
    _hasReachedFullExtension = false;
    _smoothedElbowAngle = 180.0;
    _smoothedBodyAngle = 180.0;
    _smoothedKneeAngle = 90.0;
    _elbowVelocity = 0.0;
    _elbowAngleHistory.clear();
    _timeHistory.clear();
    _predictedElbowAngle = 180.0;
    _repDurations.clear();
    _repRate = 0.0; // Reset rep rate
    _isPatternValid = true;
    _consecutiveErrors = 0;
    _speak("Reset complete. Get into Position");
  }

  PoseLandmark? _getLandmark(
    List<PoseLandmark> landmarks,
    PoseLandmarkType type,
  ) {
    final landmark = landmarks.firstWhereOrNull((l) => l.type == type);
    if (landmark != null && landmark.likelihood >= _minLandmarkConfidence) {
      return landmark;
    }
    return null;
  }

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

    return acos(cosineAngle) * 180 / pi;
  }

  void _checkForm(
    double averageElbowAngle,
    double averageBodyAngle,
    double averageKneeBendAngle,
    PoseLandmark? leftShoulder,
    PoseLandmark? rightShoulder,
    PoseLandmark? leftHip,
    PoseLandmark? rightHip,
    PoseLandmark? leftKnee,
    PoseLandmark? rightKnee,
  ) {
    final now = DateTime.now();

    // Pacing feedback based on rep rate
    if (_repRate > 0.5 && _pushUpCount > 3) {
      // Faster than 1 rep every 2 seconds
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _speakWithRate("Slow down for better form", 0.4);
        _lastFormFeedbackTime = now;
      }
    }

    // Good pace encouragement
    if (_repRate > 0.2 &&
        _repRate <= 0.4 &&
        _pushUpCount > 5 &&
        _pushUpCount % 7 == 0) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _speakWithRate("Good steady pace", 0.4);
        _lastFormFeedbackTime = now;
      }
    }

    if (averageBodyAngle < (_bodyStraightnessMinThreshold - _angleTolerance)) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _speakWithRate("Keep your body straight", 0.4);
        _lastFormFeedbackTime = now;
      }
    }

    if (averageKneeBendAngle > (_kneeBentMaxThreshold + _angleTolerance)) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _speakWithRate("Bend your knees more", 0.4);
        _lastFormFeedbackTime = now;
      }
    }

    if (leftShoulder != null &&
        rightShoulder != null &&
        leftHip != null &&
        rightHip != null) {
      final double shoulderHeightDiff = (leftShoulder.y - rightShoulder.y)
          .abs();
      if (shoulderHeightDiff > _shoulderAlignmentTolerance) {
        if (_lastFormFeedbackTime == null ||
            now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
          _speakWithRate("Keep your shoulders level", 0.4);
          _lastFormFeedbackTime = now;
        }
      }
    }

    if (_maxElbowAngle < (_elbowStraightThreshold - _angleTolerance) &&
        _pushUpCount > 2) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _speakWithRate("Extend your arms fully at the top", 0.4);
        _lastFormFeedbackTime = now;
      }
    }

    if (_minElbowAngle > (_elbowBentThreshold + _angleTolerance) &&
        _pushUpCount > 2) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _speakWithRate("Lower your chest closer to the ground", 0.4);
        _lastFormFeedbackTime = now;
      }
    }

    if (_hasReachedFullExtension &&
        _minElbowAngle <= (_elbowBentThreshold + _angleTolerance) &&
        averageBodyAngle >= (_bodyStraightnessMinThreshold - _angleTolerance) &&
        _pushUpCount > 3) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _speakWithRate("Great form! Full range of motion", 0.4);
        _lastFormFeedbackTime = now;
      }
    }

    // Check rhythm consistency
    if (!_isPatternValid && _pushUpCount > _minRepsForPatternValidation) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _speakWithRate("Try to maintain a steady rhythm", 0.4);
        _lastFormFeedbackTime = now;
      }
    }
  }

  Future<void> _speak(String text) async {
    if (_isTtsInitialized) {
      await _tts.speak(text);
    }
  }

  Future<void> _speakWithRate(String text, double rate) async {
    if (_isTtsInitialized) {
      const originalRate = 0.5; // We set this in _initTts
      await _tts.setSpeechRate(rate);
      await _tts.speak(text);
      await _tts.setSpeechRate(originalRate);
    }
  }
}
