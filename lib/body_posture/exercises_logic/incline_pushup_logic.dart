// lib/body_posture/exercises/exercises_logic/incline_pushup_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show RepExerciseLogic;

enum PushupState {
  up, // Arms extended
  down, // Arms bent
  error, // Error state for tracking issues
}

// Enum for TTS feedback priority levels
enum TTSPriority {
  critical, // Immediate form corrections that could prevent injury
  important, // Form issues
  milestone, // Rep count milestones
  positive, // Encouragement
}

class TTSMessage {
  final String text;
  final TTSPriority priority;
  final DateTime timestamp;

  TTSMessage(this.text, this.priority) : timestamp = DateTime.now();
}

class InclinePushupLogic implements RepExerciseLogic {
  int _count = 0;
  PushupState _currentState = PushupState.up;

  DateTime _lastRepTime = DateTime.now();
  Duration _cooldownDuration = const Duration(milliseconds: 1000);
  bool _canCountRep = true;

  // Angle thresholds with tolerance ranges and hysteresis
  final double _pushupUpThresholdMin = 150.0;
  final double _pushupUpThresholdMax = 170.0;
  final double _pushupDownThresholdMin = 90.0;
  final double _pushupDownThresholdMax = 110.0;
  final double _angleHysteresis = 8.0; // Hysteresis band to prevent flickering

  // Elbow alignment thresholds (for injury prevention)
  final double _elbowAlignmentMin = 25.0; // Minimum angle from vertical
  final double _elbowAlignmentMax = 65.0; // Maximum angle from vertical
  final double _elbowAlignmentTolerance = 10.0; // Tolerance for feedback

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
  final Duration _formFeedbackCooldown = const Duration(seconds: 3);
  String? _lastFormFeedback;

  // Enhanced error handling variables
  DateTime _errorStartTime = DateTime.now();
  final Duration _errorRecoveryDuration = const Duration(seconds: 1);
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
  final double _hipAlignmentTolerance = 15.0;
  final double _backAlignmentTolerance = 20.0;

  // Injury prevention variables
  DateTime? _lastElbowFeedbackTime;
  final Duration _elbowFeedbackCooldown = const Duration(seconds: 5);
  bool _hasElbowIssue = false;

  InclinePushupLogic() {
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

  @override
  String get progressLabel => 'Incline Push-ups: $_count';

  @override
  int get reps => _count;

  @override
  void update(List landmarks, bool isFrontCamera) {
    final leftShoulder = _getLandmark(landmarks, PoseLandmarkType.leftShoulder);
    final leftElbow = _getLandmark(landmarks, PoseLandmarkType.leftElbow);
    final leftWrist = _getLandmark(landmarks, PoseLandmarkType.leftWrist);
    final rightShoulder = _getLandmark(
      landmarks,
      PoseLandmarkType.rightShoulder,
    );
    final rightElbow = _getLandmark(landmarks, PoseLandmarkType.rightElbow);
    final rightWrist = _getLandmark(landmarks, PoseLandmarkType.rightWrist);
    final leftHip = _getLandmark(landmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(landmarks, PoseLandmarkType.rightHip);

    final bool allValid =
        leftShoulder != null &&
        leftElbow != null &&
        leftWrist != null &&
        rightShoulder != null &&
        rightElbow != null &&
        rightWrist != null &&
        leftHip != null &&
        rightHip != null &&
        leftShoulder.likelihood >= _minLandmarkConfidence &&
        leftElbow.likelihood >= _minLandmarkConfidence &&
        leftWrist.likelihood >= _minLandmarkConfidence &&
        rightShoulder.likelihood >= _minLandmarkConfidence &&
        rightElbow.likelihood >= _minLandmarkConfidence &&
        rightWrist.likelihood >= _minLandmarkConfidence &&
        leftHip.likelihood >= _minLandmarkConfidence &&
        rightHip.likelihood >= _minLandmarkConfidence;

    if (!allValid) {
      _handleLandmarkError();
      return;
    }

    // Recovery from error state
    if (_currentState == PushupState.error) {
      if (DateTime.now().difference(_errorStartTime) > _errorRecoveryDuration) {
        _currentState = PushupState.up;
        _consecutiveErrors = 0;
        _addTtsMessage("Resuming exercise", TTSPriority.important);
      }
      return;
    }

    // First time starting the exercise
    if (!_hasStarted) {
      _hasStarted = true;
      _currentRepStartTime = DateTime.now(); // Initialize first rep start time
      _addTtsMessage("Get into position", TTSPriority.important);
    }

    final leftElbowAngle = _getAngle(leftShoulder, leftElbow, leftWrist);
    final rightElbowAngle = _getAngle(rightShoulder, rightElbow, rightWrist);
    final averageElbowAngle = (leftElbowAngle + rightElbowAngle) / 2;

    // Calculate elbow alignment angles (for injury prevention)
    final leftElbowAlignment = _calculateElbowAlignment(
      leftShoulder,
      leftElbow,
      leftHip,
    );
    final rightElbowAlignment = _calculateElbowAlignment(
      rightShoulder,
      rightElbow,
      rightHip,
    );
    final avgElbowAlignment = (leftElbowAlignment + rightElbowAlignment) / 2;

    // Check for elbow alignment issues (critical for injury prevention)
    _checkElbowAlignment(avgElbowAlignment);

    // Process TTS queue
    _processTtsQueue();

    // Adaptive cooldown based on user speed
    final Duration effectiveCooldown = _isFastUser
        ? Duration(
            milliseconds: (_cooldownDuration.inMilliseconds * 0.7).round(),
          )
        : _cooldownDuration;

    if (DateTime.now().difference(_lastRepTime) > effectiveCooldown) {
      if (!_canCountRep && _currentState == PushupState.up) {
        _canCountRep = true;
      }
    }

    switch (_currentState) {
      case PushupState.up:
        if (averageElbowAngle <= (_pushupDownThresholdMax + _angleHysteresis) &&
            averageElbowAngle >= (_pushupDownThresholdMin - _angleHysteresis)) {
          _currentState = PushupState.down;
        }
        break;

      case PushupState.down:
        // Provide form feedback in down position
        _checkForm(
          averageElbowAngle,
          leftShoulder,
          rightShoulder,
          leftHip,
          rightHip,
          leftElbow,
          rightElbow,
        );

        if (averageElbowAngle >= (_pushupUpThresholdMin - _angleHysteresis) &&
            averageElbowAngle <= (_pushupUpThresholdMax + _angleHysteresis)) {
          if (_canCountRep) {
            _count++;
            _currentState = PushupState.up;
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

            // Provide feedback during exercise
            if (_count != _lastFeedbackRep) {
              _lastFeedbackRep = _count;

              if (_count % 5 == 0) {
                _addTtsMessage(
                  "$_count push-ups, keep going!",
                  TTSPriority.milestone,
                );
              } else if (_count == 10) {
                _addTtsMessage(
                  "Great job! Halfway there!",
                  TTSPriority.milestone,
                );
              } else if (_count >= 15) {
                _addTtsMessage(
                  "Almost done! You can do it!",
                  TTSPriority.milestone,
                );
              } else {
                _addTtsMessage("Good job!", TTSPriority.positive);
              }
            }
          } else {
            _currentState = PushupState.up;
          }
        }
        break;

      case PushupState.error:
        // Already handled above
        break;
    }
  }

  // Calculate elbow alignment angle (angle between upper arm and vertical)
  double _calculateElbowAlignment(
    PoseLandmark? shoulder,
    PoseLandmark? elbow,
    PoseLandmark? hip,
  ) {
    if (shoulder == null || elbow == null || hip == null) {
      return 45.0; // Default safe angle
    }

    // Create a virtual point directly below the shoulder to represent vertical
    final virtualPoint = PoseLandmark(
      type: PoseLandmarkType
          .leftShoulder, // Type doesn't matter for this calculation
      x: shoulder.x,
      y: shoulder.y + 100, // 100 units below shoulder
      z: shoulder.z,
      likelihood: 1.0,
    );

    // Calculate angle between vertical line (shoulder to virtual point) and upper arm (shoulder to elbow)
    return _getAngle(virtualPoint, shoulder, elbow);
  }

  // Check elbow alignment for injury prevention
  void _checkElbowAlignment(double elbowAlignment) {
    final now = DateTime.now();

    // Skip if we recently gave elbow feedback
    if (_lastElbowFeedbackTime != null &&
        now.difference(_lastElbowFeedbackTime!) < _elbowFeedbackCooldown) {
      return;
    }

    // Check if elbows are too wide (flared out) - this puts stress on shoulders
    if (elbowAlignment > (_elbowAlignmentMax + _elbowAlignmentTolerance)) {
      _addTtsMessage(
        "Keep your elbows closer to your body to protect your shoulders",
        TTSPriority.critical,
      );
      _lastElbowFeedbackTime = now;
      _hasElbowIssue = true;
    }
    // Check if elbows are too narrow (tucked in) - this can also cause strain
    else if (elbowAlignment < (_elbowAlignmentMin - _elbowAlignmentTolerance)) {
      _addTtsMessage(
        "Keep your elbows slightly wider for better shoulder alignment",
        TTSPriority.critical,
      );
      _lastElbowFeedbackTime = now;
      _hasElbowIssue = true;
    }
    // Provide positive feedback when form improves
    else if (_hasElbowIssue &&
        elbowAlignment >= _elbowAlignmentMin &&
        elbowAlignment <= _elbowAlignmentMax) {
      _addTtsMessage(
        "Perfect elbow position! This protects your shoulders",
        TTSPriority.positive,
      );
      _lastElbowFeedbackTime = now;
      _hasElbowIssue = false;
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

      // Detect if user is fast (less than 1.5 seconds per rep)
      _isFastUser = _avgRepTime < 1500;

      // Adjust cooldown based on user speed
      if (_isFastUser) {
        _cooldownDuration = Duration(milliseconds: 700);
      } else {
        _cooldownDuration = Duration(milliseconds: 1000);
      }
    }
  }

  void _handleLandmarkError() {
    _consecutiveErrors++;

    if (_currentState != PushupState.error) {
      _currentState = PushupState.error;
      _errorStartTime = DateTime.now();
      _addTtsMessage(
        "Please ensure your upper body is visible",
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
    double elbowAngle,
    PoseLandmark? leftShoulder,
    PoseLandmark? rightShoulder,
    PoseLandmark? leftHip,
    PoseLandmark? rightHip,
    PoseLandmark? leftElbow,
    PoseLandmark? rightElbow,
  ) {
    if (_lastFormFeedbackTime != null &&
        DateTime.now().difference(_lastFormFeedbackTime!) <
            _formFeedbackCooldown) {
      return;
    }

    String? feedback;
    TTSPriority priority = TTSPriority.positive;

    // Check for common form issues
    if (elbowAngle > (_pushupDownThresholdMax + 10.0)) {
      feedback = "Lower your chest more";
      priority = TTSPriority.important;
    } else if (leftShoulder != null &&
        rightShoulder != null &&
        leftHip != null &&
        rightHip != null) {
      // Check hip alignment
      final double hipHeightDiff = (leftHip.y - rightHip.y).abs();
      if (hipHeightDiff > _hipAlignmentTolerance) {
        feedback = "Keep your hips level";
        priority = TTSPriority.important;
      }

      // Check back alignment (shoulders and hips should be in line)
      final double shoulderHeight = (leftShoulder.y + rightShoulder.y) / 2;
      final double hipHeight = (leftHip.y + rightHip.y) / 2;
      final double backAlignmentDiff = (shoulderHeight - hipHeight).abs();

      if (backAlignmentDiff > _backAlignmentTolerance) {
        feedback = "Keep your body in a straight line";
        priority = TTSPriority.critical;
      }

      // Check hand position (should be slightly wider than shoulders)
      if (leftElbow != null && rightElbow != null) {
        final double shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
        final double handWidth = (leftElbow.x - rightElbow.x).abs();

        // If hands are too close together, it can strain shoulders
        if (handWidth < shoulderWidth * 0.9) {
          feedback = "Place your hands slightly wider than your shoulders";
          priority = TTSPriority.critical;
        }
        // If hands are too wide, it can reduce exercise effectiveness
        else if (handWidth > shoulderWidth * 1.8) {
          feedback = "Bring your hands closer to shoulder width";
          priority = TTSPriority.important;
        }
      }
    }

    // Positive feedback for good form
    if (feedback == null && _count > 0 && _count % 3 == 0) {
      feedback = "Excellent form!";
      priority = TTSPriority.positive;
    }

    // Provide feedback if new issue detected
    if (feedback != null && feedback != _lastFormFeedback) {
      _addTtsMessage(feedback, priority);
    }
  }

  @override
  void reset() {
    _count = 0;
    _currentState = PushupState.up;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastFormFeedbackTime = null;
    _lastFormFeedback = null;
    _lastElbowFeedbackTime = null;
    _hasElbowIssue = false;
    _consecutiveErrors = 0;
    _isFastUser = false;
    _repDurations.clear();
    _avgRepTime = 0.0;
    _cooldownDuration = Duration(milliseconds: 1000);
    _ttsQueue.clear();
    _currentRepStartTime = null;
    _addTtsMessage("Exercise reset", TTSPriority.important);
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
