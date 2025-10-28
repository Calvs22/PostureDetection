// lib/body_posture/exercises_logic/jumping_squat_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show RepExerciseLogic;

enum JumpingSquatState {
  standing, // Standing tall
  squatting, // In squat position
  jumping, // Jumping phase
  error, // Error state for tracking issues
}

class JumpingSquatLogic implements RepExerciseLogic {
  int _repCount = 0;
  JumpingSquatState _currentState = JumpingSquatState.standing;

  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(
    milliseconds: 300,
  ); // RESTORED - Base cooldown value
  bool _canCountRep = true;

  final double _squatDownThreshold = 100.0;
  final double _squatUpThreshold = 160.0;
  final double _minLandmarkConfidence = 0.7;
  final double _angleTolerance = 15.0;

  // Performance optimization variables
  final double _smoothingFactor = 0.2;
  double _smoothedKneeAngle = 180.0;
  bool _isMovingDown = false;
  bool _isMovingUp = false;
  double _kneeVelocity = 0.0;
  DateTime _lastUpdateTime = DateTime.now();

  // Enhanced prediction variables
  final List<double> _kneeAngleHistory = [];
  final List<DateTime> _timeHistory = [];
  final int _historySize = 3;
  double _predictedKneeAngle = 180.0;
  final double _linearExtrapolationWeight = 0.5;
  final double _patternMatchingWeight = 0.2;
  final double _velocityBasedWeight = 0.3;

  // Form analysis variables
  final double _hipAlignmentTolerance = 20.0;
  final double _rhythmTolerance = 0.7;
  final List<Duration> _repDurations = [];
  DateTime _repStartTime = DateTime.now();
  final double _jumpHeightThreshold = 0.1; // RESTORED - For jump detection

  // Performance monitoring variables
  double _repRate = 0.0;
  bool _isPatternValid = true; // RESTORED - For rhythm consistency feedback
  final int _minRepsForPatternValidation = 2;

  // TTS variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;
  DateTime _lastFormFeedbackTime = DateTime.now();
  final Duration _formFeedbackCooldown = const Duration(seconds: 2);
  String? _lastFormFeedback;

  // Error handling variables
  DateTime _errorStartTime = DateTime.now();
  final Duration _errorRecoveryDuration = const Duration(seconds: 1);
  int _consecutiveErrors = 0;
  final int _maxConsecutiveErrors = 2;

  // Fast user adaptation variables
  bool _isFastUser = false;
  final List<Duration> _recentRepTimes = [];
  final int _maxRecentReps = 5;
  double _adaptiveCooldown = 300.0; // Changed to double

  JumpingSquatLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.6);
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
      const originalRate = 0.6;
      await _flutterTts.setSpeechRate(rate);
      await _flutterTts.speak(text);
      await _flutterTts.setSpeechRate(originalRate);
    }
  }

  @override
  String get progressLabel => 'Jumping Squats: $_repCount';

  @override
  int get reps => _repCount;

  @override
  void update(List landmarks, bool isFrontCamera) {
    final leftHip = _getLandmark(landmarks, PoseLandmarkType.leftHip);
    final leftKnee = _getLandmark(landmarks, PoseLandmarkType.leftKnee);
    final leftAnkle = _getLandmark(landmarks, PoseLandmarkType.leftAnkle);
    final rightHip = _getLandmark(landmarks, PoseLandmarkType.rightHip);
    final rightKnee = _getLandmark(landmarks, PoseLandmarkType.rightKnee);
    final rightAnkle = _getLandmark(landmarks, PoseLandmarkType.rightAnkle);
    final leftShoulder = _getLandmark(landmarks, PoseLandmarkType.leftShoulder);
    final rightShoulder = _getLandmark(
      landmarks,
      PoseLandmarkType.rightShoulder,
    );

    final bool allValid =
        leftHip != null &&
        leftKnee != null &&
        leftAnkle != null &&
        rightHip != null &&
        rightKnee != null &&
        rightAnkle != null &&
        leftShoulder != null &&
        rightShoulder != null &&
        leftHip.likelihood >= _minLandmarkConfidence &&
        leftKnee.likelihood >= _minLandmarkConfidence &&
        leftAnkle.likelihood >= _minLandmarkConfidence &&
        rightHip.likelihood >= _minLandmarkConfidence &&
        rightKnee.likelihood >= _minLandmarkConfidence &&
        rightAnkle.likelihood >= _minLandmarkConfidence &&
        leftShoulder.likelihood >= _minLandmarkConfidence &&
        rightShoulder.likelihood >= _minLandmarkConfidence;

    if (!allValid) {
      _handleLandmarkError();
      return;
    }

    // Recovery from error state
    if (_currentState == JumpingSquatState.error) {
      if (DateTime.now().difference(_errorStartTime) > _errorRecoveryDuration) {
        _currentState = JumpingSquatState.standing;
        _lastRepTime = DateTime.now().subtract(
          Duration(milliseconds: _adaptiveCooldown.toInt()),
        );
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

    final leftKneeAngle = _getAngle(leftHip, leftKnee, leftAnkle);
    final rightKneeAngle = _getAngle(rightHip, rightKnee, rightAnkle);
    final avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2;

    // Update movement history for prediction
    _updateMovementHistory(avgKneeAngle);

    // Calculate velocity for direction tracking
    _calculateVelocity(avgKneeAngle);

    // Apply smoothing to reduce jitter
    _smoothedKneeAngle =
        _smoothingFactor * avgKneeAngle +
        (1 - _smoothingFactor) * _smoothedKneeAngle;

    // Enhanced prediction algorithm
    _predictMovement();

    // Use predicted angle for earlier detection
    final double effectiveKneeAngle = _predictedKneeAngle;

    // Determine movement direction with increased sensitivity
    _determineMovementDirection(effectiveKneeAngle);

    // Check for jump phase - RESTORED FUNCTIONALITY
    final bool isJumping = _checkJumpPhase(
      leftHip,
      rightHip,
      leftKnee,
      rightKnee,
    );

    // Adaptive cooldown based on user speed
    _updateAdaptiveCooldown();

    // Use adaptive cooldown for checking
    if (DateTime.now().difference(_lastRepTime).inMilliseconds >
        _adaptiveCooldown) {
      if (!_canCountRep && _currentState == JumpingSquatState.standing) {
        _canCountRep = true;
      }
    }

    switch (_currentState) {
      case JumpingSquatState.standing:
        if (effectiveKneeAngle < (_squatDownThreshold + _angleTolerance) &&
            _isMovingDown) {
          _currentState = JumpingSquatState.squatting;
        }
        break;

      case JumpingSquatState.squatting:
        // Provide form feedback in squat position
        _provideFormFeedback(
          effectiveKneeAngle,
          leftHip,
          rightHip,
          leftShoulder,
          rightShoulder,
          leftKnee,
          rightKnee,
        );

        if (effectiveKneeAngle > (_squatUpThreshold - _angleTolerance) &&
            _isMovingUp) {
          if (_canCountRep) {
            _repCount++;
            _currentState = JumpingSquatState.standing;
            _lastRepTime = DateTime.now();
            _canCountRep = false;

            // Record rep duration for rhythm analysis
            final Duration repDuration = DateTime.now().difference(
              _repStartTime,
            );
            _repDurations.add(repDuration);
            _repStartTime = DateTime.now();

            // Track recent rep times for speed detection
            _trackRecentRepTime(repDuration);

            // Update performance metrics
            _updatePerformanceMetrics();

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
            _currentState = JumpingSquatState.standing;
          }
        }
        break;

      case JumpingSquatState.jumping:
        // Handle jumping state - RESTORED FUNCTIONALITY
        if (!isJumping &&
            effectiveKneeAngle > (_squatUpThreshold - _angleTolerance)) {
          _currentState = JumpingSquatState.standing;
        }
        break;

      case JumpingSquatState.error:
        // Already handled above
        break;
    }
  }

  void _trackRecentRepTime(Duration repDuration) {
    _recentRepTimes.add(repDuration);

    // Keep only the most recent rep times
    if (_recentRepTimes.length > _maxRecentReps) {
      _recentRepTimes.removeAt(0);
    }

    // Detect if user is fast (average rep time < 1 second)
    if (_recentRepTimes.length >= 3) {
      final double avgRepTimeMs =
          _recentRepTimes.fold(
            0,
            (sum, duration) => sum + duration.inMilliseconds,
          ) /
          _recentRepTimes.length;
      _isFastUser = avgRepTimeMs < 1000; // Less than 1 second per rep
    }
  }

  void _updateAdaptiveCooldown() {
    if (_isFastUser) {
      _adaptiveCooldown = 200.0; // Changed to double
    } else {
      _adaptiveCooldown = _cooldownDuration.inMilliseconds
          .toDouble(); // Changed to double
    }
  }

  void _updateMovementHistory(double kneeAngle) {
    _kneeAngleHistory.add(kneeAngle);
    _timeHistory.add(DateTime.now());

    // Keep history at the specified size
    if (_kneeAngleHistory.length > _historySize) {
      _kneeAngleHistory.removeAt(0);
      _timeHistory.removeAt(0);
    }
  }

  void _calculateVelocity(double kneeAngle) {
    final DateTime now = DateTime.now();
    final double timeDelta =
        now.difference(_lastUpdateTime).inMilliseconds / 1000.0;

    if (timeDelta > 0) {
      _kneeVelocity = (kneeAngle - _smoothedKneeAngle) / timeDelta;
    }

    _lastUpdateTime = now;
  }

  void _predictMovement() {
    if (_kneeAngleHistory.length < 2) {
      _predictedKneeAngle = _smoothedKneeAngle;
      return;
    }

    // Linear extrapolation prediction
    double linearPrediction = _smoothedKneeAngle;

    if (_kneeAngleHistory.length >= 2) {
      final double slope =
          (_kneeAngleHistory.last -
              _kneeAngleHistory[_kneeAngleHistory.length - 2]) /
          _timeHistory.last
              .difference(_timeHistory[_timeHistory.length - 2])
              .inMilliseconds *
          1000;

      // Predict 150ms into the future
      linearPrediction = _smoothedKneeAngle + slope * 0.15;
    }

    // Pattern matching prediction for rhythmic exercises
    double patternPrediction = _smoothedKneeAngle;

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
        // First half of rep (squatting down)
        patternPrediction =
            _squatUpThreshold -
            (_squatUpThreshold - _squatDownThreshold) *
                (currentRepProgress * 2);
      } else {
        // Second half of rep (standing up)
        patternPrediction =
            _squatDownThreshold +
            (_squatUpThreshold - _squatDownThreshold) *
                ((currentRepProgress - 0.5) * 2);
      }
    }

    // Velocity-based prediction
    final double velocityPrediction = _smoothedKneeAngle + _kneeVelocity * 0.15;

    // Weighted combination of all prediction methods
    _predictedKneeAngle =
        _linearExtrapolationWeight * linearPrediction +
        _patternMatchingWeight * patternPrediction +
        _velocityBasedWeight * velocityPrediction;
  }

  void _determineMovementDirection(double kneeAngle) {
    // More sensitive direction detection for fast users
    final double velocityThreshold = _isFastUser ? 1.5 : 2.0;

    // Determine direction based on velocity and angle changes
    _isMovingDown =
        _kneeVelocity < -velocityThreshold || kneeAngle < _smoothedKneeAngle;
    _isMovingUp =
        _kneeVelocity > velocityThreshold || kneeAngle > _smoothedKneeAngle;
  }

  // RESTORED JUMP DETECTION FUNCTIONALITY
  bool _checkJumpPhase(
    PoseLandmark leftHip,
    PoseLandmark rightHip,
    PoseLandmark leftKnee,
    PoseLandmark rightKnee,
  ) {
    // Calculate average hip position
    final double avgHipY = (leftHip.y + rightHip.y) / 2;

    // Calculate average knee position
    final double avgKneeY = (leftKnee.y + rightKnee.y) / 2;

    // Check if knees are significantly higher than hips (indicating a jump)
    final double hipKneeDifference = avgKneeY - avgHipY;

    // If knees are much higher than hips, user is likely jumping
    return hipKneeDifference < -_jumpHeightThreshold;
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

    // Validate pattern consistency - RESTORED FUNCTIONALITY
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

    if (_currentState != JumpingSquatState.error) {
      _currentState = JumpingSquatState.error;
      _errorStartTime = DateTime.now();
      _speak("Please ensure your full body is visible");
    } else if (_consecutiveErrors >= _maxConsecutiveErrors) {
      _speak("Tracking paused. Please adjust your position");
    }
  }

  void _provideFormFeedback(
    double kneeAngle,
    PoseLandmark leftHip,
    PoseLandmark rightHip,
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
    PoseLandmark leftKnee, // Added parameter
    PoseLandmark rightKnee, // Added parameter
  ) {
    if (DateTime.now().difference(_lastFormFeedbackTime) >
        _formFeedbackCooldown) {
      String? feedback;

      // Check for common form issues
      if (kneeAngle > (_squatDownThreshold + _angleTolerance)) {
        feedback = "Squat deeper";
      } else if (!_checkHipAlignment(leftHip, rightHip)) {
        feedback = "Keep your hips level";
      } else if (!_checkBackPosition(leftShoulder, leftHip)) {
        feedback = "Keep your back straight";
      } else if (!_checkKneeAlignment(leftHip, leftKnee, rightHip, rightKnee)) {
        feedback = "Keep your knees aligned with your feet";
      } else if (_repRate > 0.8 && _repCount > 3) {
        // Pacing feedback for very fast users
        feedback = "Great speed! Maintain control";
      } else if (_repRate > 0.5 && _repCount > 3) {
        // Pacing feedback based on rep rate
        feedback = "Good pace, keep it up";
      } else if (!_isPatternValid && _repCount > _minRepsForPatternValidation) {
        // RESTORED FUNCTIONALITY - Rhythm feedback
        feedback = "Try to maintain a steady rhythm";
      } else if (_repCount > 0 && _repCount % 3 == 0) {
        // Positive feedback for good form
        feedback = "Excellent form!";
      }

      // Provide feedback if new issue detected
      if (feedback != null && feedback != _lastFormFeedback) {
        _speakWithRate(feedback, 0.5);
        _lastFormFeedbackTime = DateTime.now();
        _lastFormFeedback = feedback;
      }
    }
  }

  bool _checkHipAlignment(PoseLandmark leftHip, PoseLandmark rightHip) {
    // Check if hips are level (similar Y-coordinates)
    final double hipYDifference = (leftHip.y - rightHip.y).abs();
    final double hipDistance = _getDistance(leftHip, rightHip);
    final double hipAlignmentRatio = hipYDifference / hipDistance;

    // Check if hip alignment is within tolerance
    return hipAlignmentRatio < 0.05; // 5% of hip distance
  }

  bool _checkBackPosition(PoseLandmark shoulder, PoseLandmark hip) {
    // Calculate back angle to check if it's straight
    final double backAngle = _getAngle(
      PoseLandmark(
        type: PoseLandmarkType.leftShoulder,
        x: shoulder.x,
        y: shoulder.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: hip.x,
        y: hip.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.leftKnee,
        x: hip.x,
        y: hip.y + 100,
        z: 0.0,
        likelihood: 1.0,
      ),
    );

    // Check if back angle is within tolerance range (close to 180 degrees for straight back)
    return (backAngle > (180 - _hipAlignmentTolerance) &&
        backAngle < (180 + _hipAlignmentTolerance));
  }

  bool _checkKneeAlignment(
    PoseLandmark leftHip,
    PoseLandmark leftKnee,
    PoseLandmark rightHip,
    PoseLandmark rightKnee,
  ) {
    // Calculate knee-to-hip alignment to check if knees are tracking over feet
    final double leftKneeAlignment = _getAngle(
      PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: leftHip.x,
        y: leftHip.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.leftKnee,
        x: leftKnee.x,
        y: leftKnee.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.leftAnkle,
        x: leftKnee.x,
        y: leftKnee.y + 50,
        z: 0.0,
        likelihood: 1.0,
      ),
    );

    final double rightKneeAlignment = _getAngle(
      PoseLandmark(
        type: PoseLandmarkType.rightHip,
        x: rightHip.x,
        y: rightHip.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.rightKnee,
        x: rightKnee.x,
        y: rightKnee.y,
        z: 0.0,
        likelihood: 1.0,
      ),
      PoseLandmark(
        type: PoseLandmarkType.rightAnkle,
        x: rightKnee.x,
        y: rightKnee.y + 50,
        z: 0.0,
        likelihood: 1.0,
      ),
    );

    // Check if knee alignment is within tolerance range (close to 180 degrees)
    return (leftKneeAlignment > (180 - _hipAlignmentTolerance) &&
        leftKneeAlignment < (180 + _hipAlignmentTolerance) &&
        rightKneeAlignment > (180 - _hipAlignmentTolerance) &&
        rightKneeAlignment < (180 + _hipAlignmentTolerance));
  }

  @override
  void reset() {
    _repCount = 0;
    _currentState = JumpingSquatState.standing;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _smoothedKneeAngle = 180.0;
    _kneeVelocity = 0.0;
    _kneeAngleHistory.clear();
    _timeHistory.clear();
    _predictedKneeAngle = 180.0;
    _repDurations.clear();
    _repRate = 0.0;
    _isPatternValid = true; // RESTORED
    _lastFormFeedbackTime = DateTime.now();
    _lastFormFeedback = null;
    _consecutiveErrors = 0;
    _isFastUser = false;
    _recentRepTimes.clear();
    _adaptiveCooldown = _cooldownDuration.inMilliseconds
        .toDouble(); // Changed to double
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

  double _getDistance(PoseLandmark p1, PoseLandmark p2) {
    final double dx = p1.x - p2.x;
    final double dy = p1.y - p2.y;
    return sqrt(dx * dx + dy * dy);
  }
}
