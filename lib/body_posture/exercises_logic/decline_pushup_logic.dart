// lib/body_posture/exercises/exercises_logic/decline_pushup_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart' show RepExerciseLogic;

enum DeclinePushupState {
  up, // Arms extended
  down, // Arms bent
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

class DeclinePushUpLogic implements RepExerciseLogic {
  int _repCount = 0;
  DeclinePushupState _currentState = DeclinePushupState.up;

  DateTime _lastRepTime = DateTime.now();
  Duration _cooldownDuration = const Duration(milliseconds: 500);
  bool _canCountRep = true;

  // Angle thresholds with tolerance ranges and hysteresis
  final double _declinePushUpUpAngleMin = 150.0;
  final double _declinePushUpUpAngleMax = 170.0;
  final double _declinePushUpDownAngleMin = 80.0;
  final double _declinePushUpDownAngleMax = 100.0;
  final double _angleHysteresis = 8.0; // Hysteresis band to prevent flickering

  final double _minLandmarkConfidence = 0.7;

  // Enhanced TTS variables
  final FlutterTts _flutterTts = FlutterTts();
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
  final double _hipAlignmentTolerance = 15.0;
  final double _backAlignmentTolerance = 20.0;
  final double _elbowAlignmentTolerance = 10.0; // For injury prevention

  DeclinePushUpLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
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
    if (landmarks.isEmpty) return;

    if (!_hasStarted) {
      _addTtsMessage("Get into Position", TTSPriority.important);
      _hasStarted = true;
      _currentRepStartTime = DateTime.now(); // Initialize first rep start time
    }

    final leftShoulder = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftShoulder,
    );
    final leftElbow = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftElbow,
    );
    final leftWrist = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftWrist,
    );
    final leftHip = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftHip,
    );
    final leftAnkle = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftAnkle,
    );

    final rightShoulder = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightShoulder,
    );
    final rightElbow = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightElbow,
    );
    final rightWrist = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightWrist,
    );
    final rightHip = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightHip,
    );
    final rightAnkle = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightAnkle,
    );

    // Ensure landmarks are reliable
    final bool allValid =
        leftShoulder != null &&
        leftElbow != null &&
        leftWrist != null &&
        rightShoulder != null &&
        rightElbow != null &&
        rightWrist != null &&
        leftHip != null &&
        leftAnkle != null &&
        rightHip != null &&
        rightAnkle != null &&
        leftShoulder.likelihood >= _minLandmarkConfidence &&
        leftElbow.likelihood >= _minLandmarkConfidence &&
        leftWrist.likelihood >= _minLandmarkConfidence &&
        rightShoulder.likelihood >= _minLandmarkConfidence &&
        rightElbow.likelihood >= _minLandmarkConfidence &&
        rightWrist.likelihood >= _minLandmarkConfidence &&
        leftHip.likelihood >= _minLandmarkConfidence &&
        leftAnkle.likelihood >= _minLandmarkConfidence &&
        rightHip.likelihood >= _minLandmarkConfidence &&
        rightAnkle.likelihood >= _minLandmarkConfidence;

    if (!allValid) {
      _handleLandmarkError();
      return;
    }

    // Recovery from error state
    if (_currentState == DeclinePushupState.error) {
      if (DateTime.now().difference(_errorStartTime) > _errorRecoveryDuration) {
        _currentState = DeclinePushupState.up;
        _consecutiveErrors = 0;
        _addTtsMessage("Resuming exercise", TTSPriority.important);
      }
      return;
    }

    final double leftElbowAngle = _getAngle(leftShoulder, leftElbow, leftWrist);
    final double rightElbowAngle = _getAngle(
      rightShoulder,
      rightElbow,
      rightWrist,
    );
    final double avgElbowAngle = (leftElbowAngle + rightElbowAngle) / 2;

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

    // Form analysis
    _checkForm(
      avgElbowAngle,
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
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
      if (!_canCountRep && _currentState == DeclinePushupState.up) {
        _canCountRep = true;
      }
    }

    switch (_currentState) {
      case DeclinePushupState.up:
        if (avgElbowAngle <= (_declinePushUpDownAngleMax + _angleHysteresis) &&
            avgElbowAngle >= (_declinePushUpDownAngleMin - _angleHysteresis)) {
          _currentState = DeclinePushupState.down;
          _addTtsMessage("Down", TTSPriority.important);
        }
        break;

      case DeclinePushupState.down:
        if (avgElbowAngle >= (_declinePushUpUpAngleMin - _angleHysteresis) &&
            avgElbowAngle <= (_declinePushUpUpAngleMax + _angleHysteresis)) {
          if (_canCountRep) {
            _repCount++;
            _currentState = DeclinePushupState.up;
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
            if (_repCount != _lastFeedbackRep) {
              _lastFeedbackRep = _repCount;

              if (_repCount % 5 == 0) {
                _addTtsMessage(
                  "$_repCount reps, keep going!",
                  TTSPriority.milestone,
                );
              } else if (_repCount == 10) {
                _addTtsMessage(
                  "Great job! Halfway there!",
                  TTSPriority.milestone,
                );
              } else if (_repCount >= 15) {
                _addTtsMessage(
                  "Almost done! You can do it!",
                  TTSPriority.milestone,
                );
              } else {
                _addTtsMessage("Good job!", TTSPriority.positive);
              }
            }
          } else {
            _currentState = DeclinePushupState.up;
          }
        }
        break;

      case DeclinePushupState.error:
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

      // Detect if user is fast (less than 1.5 seconds per rep)
      _isFastUser = _avgRepTime < 1500;

      // Adjust cooldown based on user speed
      if (_isFastUser) {
        _cooldownDuration = Duration(milliseconds: 350);
      } else {
        _cooldownDuration = Duration(milliseconds: 500);
      }
    }
  }

  void _handleLandmarkError() {
    _consecutiveErrors++;

    if (_currentState != DeclinePushupState.error) {
      _currentState = DeclinePushupState.error;
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
    if (_lastFormFeedbackTime != null &&
        now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
      return;
    }

    // For decline push-ups, elbows should be tucked in closer to the body
    // Check if elbows are too wide (flared out) - this puts stress on shoulders
    if (elbowAlignment > 45.0 + _elbowAlignmentTolerance) {
      _addTtsMessage(
        "Keep your elbows closer to your body to protect your shoulders",
        TTSPriority.critical,
      );
    }
    // Provide positive feedback when form improves
    else if (_lastFormFeedbackTime != null && elbowAlignment <= 45.0) {
      _addTtsMessage(
        "Perfect elbow position! This protects your shoulders",
        TTSPriority.positive,
      );
    }
  }

  void _checkForm(
    double elbowAngle,
    PoseLandmark? leftShoulder,
    PoseLandmark? rightShoulder,
    PoseLandmark? leftHip,
    PoseLandmark? rightHip,
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

    // Check for common form issues
    if (elbowAngle > (_declinePushUpDownAngleMax + 10.0)) {
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

      // Check back alignment (for injury prevention)
      final double shoulderHeight = (leftShoulder.y + rightShoulder.y) / 2;
      final double hipHeight = (leftHip.y + rightHip.y) / 2;
      final double backAlignmentDiff = (shoulderHeight - hipHeight).abs();

      if (backAlignmentDiff > _backAlignmentTolerance) {
        feedback = "Keep your body in a straight line";
        priority = TTSPriority.critical;
      }
    }

    // Positive feedback for good form
    if (feedback == null && _repCount > 0 && _repCount % 3 == 0) {
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
    _repCount = 0;
    _currentState = DeclinePushupState.up;
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
    _cooldownDuration = Duration(milliseconds: 500);
    _ttsQueue.clear();
    _currentRepStartTime = null;
    _addTtsMessage("Exercise reset", TTSPriority.important);
  }

  @override
  String get progressLabel => "Decline Push-ups: $_repCount";

  @override
  int get reps => _repCount;

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final double v1x = p1.x - p2.x;
    final double v1y = p1.y - p2.y;
    final double v2x = p3.x - p2.x;
    final double v2y = p3.y - p2.y;

    final double dot = v1x * v2x + v1y * v2y;
    final double mag1 = sqrt(v1x * v1x + v1y * v1y);
    final double mag2 = sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0 || mag2 == 0) return 180.0;

    double cosTheta = dot / (mag1 * mag2);
    cosTheta = cosTheta.clamp(-1.0, 1.0);

    return acos(cosTheta) * 180 / pi;
  }

  Future<void> _speak(String text) async {
    if (_isSpeaking) return;

    _isSpeaking = true;
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.speak(text);
    } catch (e) {
      // Silently handle TTS errors
    } finally {
      _isSpeaking = false;
    }
  }
}

// Extension to safely find landmarks
extension FirstWhereOrNullExtension<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
