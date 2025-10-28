// lib/body_posture/exercises/exercises_logic/inchworm_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';
import '/body_posture/camera/pose_painter.dart'; // Needed for FirstWhereOrNullExtension

// Enum to define the states of an Inchworm Repetition
enum InchwormState {
  retracted, // Starting position, hands and feet close together
  plank, // Hands are walked out, body is in a plank position
  error, // Error state for tracking issues
}

// Enum for TTS feedback priority levels
enum TTSPriority {
  critical, // Immediate form corrections that could prevent injury
  important, // Form issues and rhythm feedback
  milestone, // Rep count milestones
  positive, // Encouragement
}

class TTSMessage {
  final String text;
  final TTSPriority priority;
  final DateTime timestamp;

  TTSMessage(this.text, this.priority) : timestamp = DateTime.now();
}

class InchwormLogic implements RepExerciseLogic {
  // CHANGED: implements RepExerciseLogic instead of ExerciseLogic
  int _repCount = 0;
  InchwormState _currentState = InchwormState.retracted;

  DateTime _lastRepTime = DateTime.now();
  Duration _cooldownDuration = const Duration(milliseconds: 1500);
  bool _canCountRep = true;

  // Angle thresholds with tolerance ranges and hysteresis
  final double _plankThresholdAngleMin = 165.0;
  final double _plankThresholdAngleMax = 175.0;
  final double _bentOverThresholdAngleMin = 110.0;
  final double _bentOverThresholdAngleMax = 130.0;
  final double _angleHysteresis = 8.0; // Hysteresis band to prevent flickering

  final double _minLandmarkConfidence = 0.7;

  // Enhanced TTS variables
  final FlutterTts _tts = FlutterTts();
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;
  final List<TTSMessage> _ttsQueue = [];
  bool _isSpeaking = false;
  DateTime _lastTtsTime = DateTime.now();
  final Duration _ttsMinInterval = Duration(milliseconds: 500);
  DateTime? _lastFormFeedbackTime;
  final Duration _formFeedbackCooldown = Duration(seconds: 3);
  String? _lastFormFeedback;

  // Enhanced error handling variables
  DateTime _errorStartTime = DateTime.now();
  final Duration _errorRecoveryDuration = Duration(seconds: 1);
  int _consecutiveErrors = 0;
  final int _maxConsecutiveErrors = 3;

  // Fast user adaptation variables
  bool _isFastUser = false;
  final List<Duration> _repDurations = [];
  final int _maxRepHistory = 5;
  double _avgRepTime = 0.0;

  // Rep timing variables
  DateTime? _currentRepStartTime;

  // Form analysis variables
  final double _hipAlignmentTolerance =
      15.0; // Added back - for hip alignment checks
  final double _backAlignmentTolerance = 20.0;
  final double _ankleDistanceThreshold = 50.0;

  InchwormLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setPitch(1.0);
  }

  void _addTtsMessage(String text, TTSPriority priority) {
    // Skip if same as last message within cooldown
    if (_lastFormFeedbackTime != null &&
        text == _lastFormFeedback &&
        DateTime.now().difference(_lastTtsTime) < _formFeedbackCooldown) {
      return;
    }

    _ttsQueue.add(TTSMessage(text, priority));
    _lastFormFeedbackTime = DateTime.now();
    _lastFormFeedback = text;
  }

  void _processTtsQueue() {
    if (_ttsQueue.isEmpty || _isSpeaking) return;

    // Sort queue by priority (critical first)
    _ttsQueue.sort((a, b) => a.priority.index.compareTo(b.priority.index));

    // Get highest priority message
    final message = _ttsQueue.removeAt(0);

    // Check minimum interval between messages
    if (DateTime.now().difference(_lastTtsTime) < _ttsMinInterval) {
      // Re-add to queue for later
      _ttsQueue.add(message);
      return;
    }

    _speak(message.text);
    _lastTtsTime = DateTime.now();
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    final poseLandmarks = landmarks as List<PoseLandmark>;

    if (!_hasStarted) {
      _addTtsMessage("Get into Position", TTSPriority.important);
      _hasStarted = true;
      _currentRepStartTime = DateTime.now(); // Initialize first rep start time
    }

    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final leftShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.leftShoulder,
    );
    final leftElbow = _getLandmark(poseLandmarks, PoseLandmarkType.leftElbow);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final rightShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.rightShoulder,
    );
    final rightElbow = _getLandmark(poseLandmarks, PoseLandmarkType.rightElbow);
    final leftAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.leftAnkle);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);
    final leftWrist = _getLandmark(poseLandmarks, PoseLandmarkType.leftWrist);
    final rightWrist = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist);

    final bool allValid =
        leftHip != null &&
        leftShoulder != null &&
        leftElbow != null &&
        rightHip != null &&
        rightShoulder != null &&
        rightElbow != null &&
        leftAnkle != null &&
        rightAnkle != null &&
        leftWrist != null &&
        rightWrist != null;

    if (!allValid) {
      _handleLandmarkError();
      return;
    }

    // Recovery from error state
    if (_currentState == InchwormState.error) {
      if (DateTime.now().difference(_errorStartTime) > _errorRecoveryDuration) {
        _currentState = InchwormState.retracted;
        _consecutiveErrors = 0;
        _addTtsMessage("Resuming exercise", TTSPriority.important);
      }
      return;
    }

    final double leftTorsoArmAngle = _getAngle(
      leftHip,
      leftShoulder,
      leftElbow,
    );
    final double rightTorsoArmAngle = _getAngle(
      rightHip,
      rightShoulder,
      rightElbow,
    );
    final double averageTorsoArmAngle =
        (leftTorsoArmAngle + rightTorsoArmAngle) / 2;

    _checkForm(
      leftTorsoArmAngle,
      rightTorsoArmAngle,
      averageTorsoArmAngle,
      leftHip,
      rightHip,
      leftShoulder,
      rightShoulder,
      leftAnkle,
      rightAnkle,
    );

    // Process TTS queue
    _processTtsQueue();

    // Adaptive cooldown based on user speed
    final Duration effectiveCooldown = _isFastUser
        ? Duration(
            milliseconds: (_cooldownDuration.inMilliseconds * 0.7).round(),
          )
        : _cooldownDuration;

    if (DateTime.now().difference(_lastRepTime) > effectiveCooldown) {
      if (!_canCountRep && _currentState == InchwormState.retracted) {
        _canCountRep = true;
      }
    }

    switch (_currentState) {
      case InchwormState.retracted:
        if (averageTorsoArmAngle >=
                (_plankThresholdAngleMin - _angleHysteresis) &&
            averageTorsoArmAngle <=
                (_plankThresholdAngleMax + _angleHysteresis)) {
          _currentState = InchwormState.plank;
          _addTtsMessage("Plank position", TTSPriority.important);
        }
        break;

      case InchwormState.plank:
        if (averageTorsoArmAngle <=
                (_bentOverThresholdAngleMax + _angleHysteresis) &&
            averageTorsoArmAngle >=
                (_bentOverThresholdAngleMin - _angleHysteresis)) {
          if (_canCountRep) {
            _repCount++;
            _currentState = InchwormState.retracted;
            _lastRepTime = DateTime.now();
            _canCountRep = false;

            // Calculate and track rep duration
            if (_currentRepStartTime != null) {
              final Duration repDuration = DateTime.now().difference(
                _currentRepStartTime!,
              );
              _updateRepHistory(repDuration);
            }
            _currentRepStartTime =
                DateTime.now(); // Set start time for next rep

            if (_repCount % 3 == 0 && _repCount != _lastFeedbackRep) {
              _addTtsMessage("Good job! Keep going!", TTSPriority.milestone);
              _lastFeedbackRep = _repCount;
            }

            if (_repCount == 6) {
              _addTtsMessage(
                "Almost there! Just a few more!",
                TTSPriority.milestone,
              );
            }
          } else {
            _currentState = InchwormState.retracted;
          }
        }
        break;

      case InchwormState.error:
        // Already handled above
        break;
    }
  }

  void _updateRepHistory(Duration repDuration) {
    _repDurations.add(repDuration);
    if (_repDurations.length > _maxRepHistory) {
      _repDurations.removeAt(0);
    }

    if (_repDurations.length >= 3) {
      final double totalMs = _repDurations.fold(
        0,
        (sum, duration) => sum + duration.inMilliseconds,
      );
      _avgRepTime = totalMs / _repDurations.length;

      // Detect if user is fast (less than 2 seconds per rep for inchworms)
      _isFastUser = _avgRepTime < 2000;

      // Adjust cooldown based on user speed
      if (_isFastUser) {
        _cooldownDuration = Duration(milliseconds: 1000);
      } else {
        _cooldownDuration = Duration(milliseconds: 1500);
      }
    }
  }

  void _handleLandmarkError() {
    _consecutiveErrors++;

    if (_currentState != InchwormState.error) {
      _currentState = InchwormState.error;
      _errorStartTime = DateTime.now();
      _addTtsMessage(
        "Please ensure your full body is visible",
        TTSPriority.critical,
      );
    } else if (_consecutiveErrors >= _maxConsecutiveErrors) {
      _addTtsMessage(
        "Tracking paused. Please adjust your position",
        TTSPriority.critical,
      );
    }
  }

  void _checkForm(
    double leftTorsoArmAngle,
    double rightTorsoArmAngle,
    double averageTorsoArmAngle,
    PoseLandmark? leftHip,
    PoseLandmark? rightHip,
    PoseLandmark? leftShoulder,
    PoseLandmark? rightShoulder,
    PoseLandmark? leftAnkle,
    PoseLandmark? rightAnkle,
  ) {
    if (_lastFormFeedbackTime != null &&
        DateTime.now().difference(_lastFormFeedbackTime!) <
            _formFeedbackCooldown) {
      return;
    }

    String? feedback;
    TTSPriority priority = TTSPriority.positive;

    if (_currentState == InchwormState.plank) {
      final double angleDifference = (leftTorsoArmAngle - rightTorsoArmAngle)
          .abs();
      if (angleDifference > 20.0) {
        feedback = "Keep your body straight";
        priority = TTSPriority.important;
      }

      if (averageTorsoArmAngle < 160.0) {
        feedback = "Lower your hips more";
        priority = TTSPriority.critical;
      }

      // Check back alignment (for injury prevention)
      if (leftHip != null &&
          rightHip != null &&
          leftShoulder != null &&
          rightShoulder != null) {
        final double shoulderHeight = (leftShoulder.y + rightShoulder.y) / 2;
        final double hipHeight = (leftHip.y + rightHip.y) / 2;
        final double backAlignmentDiff = (shoulderHeight - hipHeight).abs();

        if (backAlignmentDiff > _backAlignmentTolerance) {
          feedback = "Keep your back straight to prevent injury";
          priority = TTSPriority.critical;
        }
      }

      // Check hip alignment (added back feature)
      if (leftHip != null && rightHip != null) {
        final double hipHeightDiff = (leftHip.y - rightHip.y).abs();
        if (hipHeightDiff > _hipAlignmentTolerance) {
          feedback = "Keep your hips level";
          priority = TTSPriority.important;
        }
      }
    }

    if (_currentState == InchwormState.retracted) {
      if (averageTorsoArmAngle > 140.0) {
        feedback = "Bend over more";
        priority = TTSPriority.important;
      }

      if (leftAnkle != null && rightAnkle != null) {
        final double ankleDistance = (leftAnkle.x - rightAnkle.x).abs();
        if (ankleDistance > _ankleDistanceThreshold) {
          feedback = "Keep your feet together";
          priority = TTSPriority.important;
        }
      }

      // Check hip alignment in retracted position as well
      if (leftHip != null && rightHip != null) {
        final double hipHeightDiff = (leftHip.y - rightHip.y).abs();
        if (hipHeightDiff > _hipAlignmentTolerance) {
          feedback = "Keep your hips level";
          priority = TTSPriority.important;
        }
      }
    }

    // Rhythm feedback
    final Duration timeSinceLastRep = DateTime.now().difference(_lastRepTime);
    if (timeSinceLastRep > Duration(seconds: 4) && _repCount > 1) {
      feedback = "Keep a steady pace";
      priority = TTSPriority.important;
    }

    // Positive feedback
    if (_currentState == InchwormState.plank &&
        averageTorsoArmAngle >= 165.0 &&
        _repCount > 2) {
      feedback = "Great plank position!";
      priority = TTSPriority.positive;
    }

    // Provide feedback if new issue detected
    if (feedback != null && feedback != _lastFormFeedback) {
      _addTtsMessage(feedback, priority);
    }
  }

  @override
  void reset() {
    _repCount = 0;
    _currentState = InchwormState.retracted;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastFormFeedbackTime = null;
    _lastFormFeedback = null;
    _consecutiveErrors = 0;
    _isFastUser = false;
    _repDurations.clear();
    _avgRepTime = 0.0;
    _cooldownDuration = Duration(milliseconds: 1500);
    _ttsQueue.clear();
    _currentRepStartTime = null;
    _addTtsMessage("Reset complete. Get into Position", TTSPriority.important);
  }

  @override
  String get progressLabel => "Inchworms: $_repCount";

  @override
  int get reps => _repCount; // ADDED: @override annotation

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

  Future<void> _speak(String text) async {
    if (_isSpeaking) return;

    _isSpeaking = true;
    try {
      await _tts.setLanguage("en-US");
      await _tts.setPitch(1.0);
      await _tts.speak(text);
    } catch (e) {
      // Silently handle TTS errors
    } finally {
      _isSpeaking = false;
    }
  }
}
