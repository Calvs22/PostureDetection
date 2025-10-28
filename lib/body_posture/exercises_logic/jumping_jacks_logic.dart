// lib/body_posture/exercises/exercises_logic/jumping_jacks_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter/material.dart'; // Added import for Size class
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show RepExerciseLogic;
import '/body_posture/camera/pose_painter.dart'; // Needed for FirstWhereOrNullExtension

// Enum to define the states of a Jumping Jack rep
enum JumpingJackState {
  initial, // Arms and legs together (starting position)
  armsUpLegsOut, // Arms up and legs spread
  error, // Error state for tracking issues
}

// Enum for TTS feedback priority levels
enum TTSPriority {
  critical, // Immediate form corrections
  important, // Rhythm and timing issues
  milestone, // Rep count milestones
  positive, // Encouragement
}

class TTSMessage {
  final String text;
  final TTSPriority priority;
  final DateTime timestamp;

  TTSMessage(this.text, this.priority) : timestamp = DateTime.now();
}

class JumpingJacksLogic implements RepExerciseLogic {
  int _jumpingJackCount = 0;
  JumpingJackState _currentState = JumpingJackState.initial;

  // Cooldown to prevent rapid, false counts
  DateTime _lastCountTime = DateTime.now();
  Duration _cooldownDuration = const Duration(milliseconds: 200);

  // Angle thresholds for arm detection with tolerance ranges
  final double _armsUpShoulderAngleMin = 80.0;
  final double _armsUpShoulderAngleMax = 100.0;
  final double _armsDownShoulderAngleMin = 130.0;
  final double _armsDownShoulderAngleMax = 150.0;
  final double _angleHysteresis = 5.0; // Hysteresis band to prevent flickering

  // Leg movement thresholds with tolerance ranges
  final double _legsTogetherHorizontalDistanceRatio = 0.05;
  final double _legsSpreadHorizontalDistanceRatio = 0.10;
  final double _legHysteresis = 0.01;

  final double _minLandmarkConfidence = 0.7;

  // TTS instance and queue
  final FlutterTts _tts = FlutterTts();
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;
  final List<TTSMessage> _ttsQueue = [];
  bool _isSpeaking = false;
  DateTime _lastTtsTime = DateTime.now();
  final Duration _ttsMinInterval = Duration(milliseconds: 500);

  // Form feedback cooldown
  DateTime? _lastFormFeedbackTime;
  final Duration _formFeedbackCooldown = Duration(seconds: 3);
  String? _lastFormFeedback; // Added to track last feedback text

  // Camera view size for distance calculations
  Size? _cameraViewSize;

  // Error handling variables
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

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    final poseLandmarks = landmarks as List<PoseLandmark>;

    // Speak initial message immediately on first update
    if (!_hasStarted) {
      _speak("Get into Position");
      _hasStarted = true;
      _currentRepStartTime = DateTime.now(); // Initialize first rep start time
    }

    // --- Landmark Retrieval ---
    final leftShoulder = _getLandmark(
      poseLandmarks,
      isFrontCamera
          ? PoseLandmarkType.rightShoulder
          : PoseLandmarkType.leftShoulder,
    );
    final leftElbow = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.rightElbow : PoseLandmarkType.leftElbow,
    );
    final leftWrist = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.rightWrist : PoseLandmarkType.leftWrist,
    );
    final leftHip = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.rightHip : PoseLandmarkType.leftHip,
    );
    final leftAnkle = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.rightAnkle : PoseLandmarkType.leftAnkle,
    );

    final rightShoulder = _getLandmark(
      poseLandmarks,
      isFrontCamera
          ? PoseLandmarkType.leftShoulder
          : PoseLandmarkType.rightShoulder,
    );
    final rightElbow = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow,
    );
    final rightWrist = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.leftWrist : PoseLandmarkType.rightWrist,
    );
    final rightHip = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip,
    );
    final rightAnkle = _getLandmark(
      poseLandmarks,
      isFrontCamera ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle,
    );

    // Validate if all necessary landmarks are detected
    final bool allValid =
        leftShoulder != null &&
        leftElbow != null &&
        leftWrist != null &&
        leftHip != null &&
        leftAnkle != null &&
        rightShoulder != null &&
        rightElbow != null &&
        rightWrist != null &&
        rightHip != null &&
        rightAnkle != null;

    // Error handling
    if (!allValid) {
      _handleLandmarkError();
      return;
    }

    // Recovery from error state
    if (_currentState == JumpingJackState.error) {
      if (DateTime.now().difference(_errorStartTime) > _errorRecoveryDuration) {
        _currentState = JumpingJackState.initial;
        _consecutiveErrors = 0;
        _speak("Resuming exercise");
      }
      return;
    }

    // Calculate average shoulder angle
    final double avgShoulderAngle =
        (_getAngle(leftHip, leftShoulder, leftElbow) +
            _getAngle(rightHip, rightShoulder, rightElbow)) /
        2;

    // Calculate horizontal distance between ankles
    final double ankleHorizontalDistance = (leftAnkle.x - rightAnkle.x).abs();
    double ankleDistanceRatio = 0.0;
    if (_cameraViewSize != null) {
      ankleDistanceRatio = ankleHorizontalDistance / _cameraViewSize!.width;
    }

    // New condition: wrists above shoulders
    final bool armsAreOverhead =
        (leftWrist.y < leftShoulder.y && rightWrist.y < rightShoulder.y);

    // Form analysis
    _checkForm(
      avgShoulderAngle,
      ankleDistanceRatio,
      armsAreOverhead,
      leftShoulder,
      rightShoulder,
      leftWrist,
      rightWrist,
      leftHip,
      rightHip,
    );

    // Process TTS queue
    _processTtsQueue();

    // --- Jumping Jack State Machine ---
    final Duration effectiveCooldown = _isFastUser
        ? Duration(
            milliseconds: (_cooldownDuration.inMilliseconds * 0.7).round(),
          )
        : _cooldownDuration;

    if (DateTime.now().difference(_lastCountTime) > effectiveCooldown) {
      switch (_currentState) {
        case JumpingJackState.initial:
          if (avgShoulderAngle <=
                  (_armsUpShoulderAngleMax + _angleHysteresis) &&
              avgShoulderAngle >=
                  (_armsUpShoulderAngleMin - _angleHysteresis) &&
              ankleDistanceRatio >=
                  (_legsSpreadHorizontalDistanceRatio - _legHysteresis) &&
              armsAreOverhead) {
            _currentState = JumpingJackState.armsUpLegsOut;
            _addTtsMessage("Up", TTSPriority.important);
          }
          break;

        case JumpingJackState.armsUpLegsOut:
          if (avgShoulderAngle >=
                  (_armsDownShoulderAngleMin - _angleHysteresis) &&
              avgShoulderAngle <=
                  (_armsDownShoulderAngleMax + _angleHysteresis) &&
              ankleDistanceRatio <=
                  (_legsTogetherHorizontalDistanceRatio + _legHysteresis)) {
            _jumpingJackCount++;
            _lastCountTime = DateTime.now();
            _currentState = JumpingJackState.initial;

            // Calculate and track rep duration
            if (_currentRepStartTime != null) {
              final Duration repDuration = DateTime.now().difference(
                _currentRepStartTime!,
              );
              _updateRepHistory(repDuration);
            }
            _currentRepStartTime =
                DateTime.now(); // Set start time for next rep

            if (_jumpingJackCount % 10 == 0 &&
                _jumpingJackCount != _lastFeedbackRep) {
              _addTtsMessage("Good job! Keep going!", TTSPriority.milestone);
              _lastFeedbackRep = _jumpingJackCount;
            }

            if (_jumpingJackCount == 20) {
              _addTtsMessage(
                "Almost there! Just a few more!",
                TTSPriority.milestone,
              );
            }
          }
          break;

        case JumpingJackState.error:
          // Already handled above
          break;
      }
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

      // Detect if user is fast (less than 1 second per rep)
      _isFastUser = _avgRepTime < 1000;

      // Adjust cooldown based on user speed
      if (_isFastUser) {
        _cooldownDuration = Duration(milliseconds: 150);
      } else {
        _cooldownDuration = Duration(milliseconds: 200);
      }
    }
  }

  void _handleLandmarkError() {
    _consecutiveErrors++;

    if (_currentState != JumpingJackState.error) {
      _currentState = JumpingJackState.error;
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
  void reset() {
    _jumpingJackCount = 0;
    _currentState = JumpingJackState.initial;
    _lastCountTime = DateTime.now();
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastFormFeedbackTime = null;
    _lastFormFeedback = null;
    _consecutiveErrors = 0;
    _isFastUser = false;
    _repDurations.clear();
    _avgRepTime = 0.0;
    _cooldownDuration = Duration(milliseconds: 200);
    _ttsQueue.clear();
    _currentRepStartTime = null;
    _speak("Reset complete. Get into Position");
  }

  @override
  String get progressLabel => "Jumping Jacks: $_jumpingJackCount";

  @override
  int get reps => _jumpingJackCount;

  // Method to set camera view size (called from UI)
  void setCameraViewSize(Size size) {
    _cameraViewSize = size;
  }

  // Helper method to get landmark with confidence check
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

  // Helper function to calculate angle
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
    return angleRad * 180 / pi;
  }

  // Form analysis
  void _checkForm(
    double avgShoulderAngle,
    double ankleDistanceRatio,
    bool armsAreOverhead,
    PoseLandmark? leftShoulder,
    PoseLandmark? rightShoulder,
    PoseLandmark? leftWrist,
    PoseLandmark? rightWrist,
    PoseLandmark? leftHip,
    PoseLandmark? rightHip,
  ) {
    final now = DateTime.now();

    // Check for form issues only if not in error state
    if (_currentState == JumpingJackState.error) return;

    // Critical form issues
    if (!armsAreOverhead && _currentState == JumpingJackState.armsUpLegsOut) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _addTtsMessage("Raise your arms higher", TTSPriority.critical);
      }
    }

    if (ankleDistanceRatio < _legsSpreadHorizontalDistanceRatio &&
        _currentState == JumpingJackState.armsUpLegsOut) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _addTtsMessage("Spread your legs wider", TTSPriority.critical);
      }
    }

    // Important form issues
    if (leftShoulder != null && rightShoulder != null) {
      final double shoulderHeightDiff = (leftShoulder.y - rightShoulder.y)
          .abs();
      if (shoulderHeightDiff > 20.0) {
        if (_lastFormFeedbackTime == null ||
            now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
          _addTtsMessage("Keep your shoulders level", TTSPriority.important);
        }
      }
    }

    // Rhythm feedback
    final Duration timeSinceLastRep = DateTime.now().difference(_lastCountTime);
    if (timeSinceLastRep > Duration(seconds: 2) && _jumpingJackCount > 3) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _addTtsMessage("Keep a steady rhythm", TTSPriority.important);
      }
    }

    // Positive feedback
    if (armsAreOverhead &&
        ankleDistanceRatio > _legsSpreadHorizontalDistanceRatio &&
        _jumpingJackCount > 5) {
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _addTtsMessage("Great form! Keep it up", TTSPriority.positive);
      }
    }
  }

  // TTS helper
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
