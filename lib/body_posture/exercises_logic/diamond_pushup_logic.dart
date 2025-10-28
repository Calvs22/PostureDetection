// lib/body_posture/exercises/exercises_logic/diamond_pushup_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';
import '/body_posture/camera/pose_painter.dart'; // Needed for firstWhereOrNull extension

enum DiamondPushupState {
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

class DiamondPushUpLogic extends RepExerciseLogic {
  int _diamondPushUpCount = 0;
  DiamondPushupState _currentState = DiamondPushupState.up;

  DateTime _lastRepTime = DateTime.now();
  Duration _cooldownDuration = const Duration(milliseconds: 1000);
  bool _canCountRep = true;

  // Angle thresholds with tolerance ranges and hysteresis
  final double _diamondPushUpUpAngleMin = 140.0;
  final double _diamondPushUpUpAngleMax = 160.0;
  final double _diamondPushUpDownAngleMin = 60.0;
  final double _diamondPushUpDownAngleMax = 80.0;
  final double _angleHysteresis = 8.0; // Hysteresis band to prevent flickering

  final double _minLandmarkConfidence = 0.7;

  // Form analysis thresholds
  final double _backAlignmentThreshold = 160.0; // Min angle for straight back
  final double _minGripWidthRatio =
      0.3; // Min ratio of wrist distance to shoulder width

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
  final double _hipAlignmentTolerance = 15.0;
  final double _backAlignmentTolerance = 20.0; // For back alignment checks
  final double _elbowAlignmentTolerance = 10.0; // For injury prevention

  // Form feedback cooldown
  DateTime? _lastBackFeedbackTime;
  DateTime? _lastGripFeedbackTime;
  DateTime? _lastElbowFeedbackTime;
  final Duration _feedbackCooldown = const Duration(seconds: 5);

  DiamondPushUpLogic() {
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
    if (!_hasStarted) {
      _addTtsMessage("Get into Position", TTSPriority.important);
      _hasStarted = true;
      _currentRepStartTime = DateTime.now(); // Initialize first rep start time
    }

    final poseLandmarks = landmarks as List<PoseLandmark>;

    final leftShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.leftShoulder,
    );
    final leftElbow = _getLandmark(poseLandmarks, PoseLandmarkType.leftElbow);
    final leftWrist = _getLandmark(poseLandmarks, PoseLandmarkType.leftWrist);
    final rightShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.rightShoulder,
    );
    final rightElbow = _getLandmark(poseLandmarks, PoseLandmarkType.rightElbow);
    final rightWrist = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist);

    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final leftAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.leftAnkle);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);

    final bool allValid =
        leftShoulder != null &&
        leftElbow != null &&
        leftWrist != null &&
        rightShoulder != null &&
        rightElbow != null &&
        rightWrist != null &&
        leftHip != null &&
        rightHip != null &&
        leftAnkle != null &&
        rightAnkle != null;

    if (!allValid) {
      _handleLandmarkError();
      return;
    }

    // Recovery from error state
    if (_currentState == DiamondPushupState.error) {
      if (DateTime.now().difference(_errorStartTime) > _errorRecoveryDuration) {
        _currentState = DiamondPushupState.up;
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
    final double averageElbowAngle = (leftElbowAngle + rightElbowAngle) / 2;

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

    _checkBackAlignment(leftShoulder, leftHip, leftAnkle);
    _checkGripWidth(leftShoulder, rightShoulder, leftWrist, rightWrist);
    _checkHipAlignment(leftHip, rightHip);

    // Process TTS queue
    _processTtsQueue();

    // Adaptive cooldown based on user speed
    final Duration effectiveCooldown = _isFastUser
        ? Duration(
            milliseconds: (_cooldownDuration.inMilliseconds * 0.7).round(),
          )
        : _cooldownDuration;

    if (DateTime.now().difference(_lastRepTime) > effectiveCooldown) {
      if (!_canCountRep && _currentState == DiamondPushupState.up) {
        _canCountRep = true;
      }
    }

    switch (_currentState) {
      case DiamondPushupState.up:
        if (averageElbowAngle <=
                (_diamondPushUpDownAngleMax + _angleHysteresis) &&
            averageElbowAngle >=
                (_diamondPushUpDownAngleMin - _angleHysteresis)) {
          _currentState = DiamondPushupState.down;
          _addTtsMessage("Down", TTSPriority.important);
        }
        break;

      case DiamondPushupState.down:
        if (averageElbowAngle >=
                (_diamondPushUpUpAngleMin - _angleHysteresis) &&
            averageElbowAngle <=
                (_diamondPushUpUpAngleMax + _angleHysteresis)) {
          if (_canCountRep) {
            _diamondPushUpCount++;
            _currentState = DiamondPushupState.up;
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

            if (_diamondPushUpCount % 5 == 0 &&
                _diamondPushUpCount != _lastFeedbackRep) {
              _addTtsMessage("Good job! Keep going!", TTSPriority.milestone);
              _lastFeedbackRep = _diamondPushUpCount;
            }

            if (_diamondPushUpCount == 10) {
              _addTtsMessage(
                "Almost there! Just a few more!",
                TTSPriority.milestone,
              );
            }
          } else {
            _currentState = DiamondPushupState.up;
          }
        }
        break;

      case DiamondPushupState.error:
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
        _cooldownDuration = Duration(milliseconds: 700);
      } else {
        _cooldownDuration = Duration(milliseconds: 1000);
      }
    }
  }

  void _handleLandmarkError() {
    _consecutiveErrors++;

    if (_currentState != DiamondPushupState.error) {
      _currentState = DiamondPushupState.error;
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
    if (_lastElbowFeedbackTime != null &&
        now.difference(_lastElbowFeedbackTime!) > _feedbackCooldown) {
      return;
    }

    // For diamond push-ups, elbows should be tucked in closer to the body
    // Check if elbows are too wide (flared out) - this puts stress on shoulders
    if (elbowAlignment > 45.0 + _elbowAlignmentTolerance) {
      _addTtsMessage(
        "Keep your elbows closer to your body to protect your shoulders",
        TTSPriority.critical,
      );
      _lastElbowFeedbackTime = now;
    }
    // Provide positive feedback when form improves
    else if (_lastElbowFeedbackTime != null && elbowAlignment <= 45.0) {
      _addTtsMessage(
        "Perfect elbow position! This protects your shoulders",
        TTSPriority.positive,
      );
      _lastElbowFeedbackTime = now;
    }
  }

  void _checkBackAlignment(
    PoseLandmark? shoulder,
    PoseLandmark? hip,
    PoseLandmark? ankle,
  ) {
    if (shoulder == null || hip == null || ankle == null) return;

    final double backAngle = _getAngle(shoulder, hip, ankle);

    // Use different thresholds based on exercise state
    if (_currentState == DiamondPushupState.down) {
      // In down position, use fixed threshold for strict form
      if (backAngle < _backAlignmentThreshold) {
        final now = DateTime.now();
        if (_lastBackFeedbackTime == null ||
            now.difference(_lastBackFeedbackTime!) > _feedbackCooldown) {
          _addTtsMessage("Keep your back straight", TTSPriority.critical);
          _lastBackFeedbackTime = now;
        }
      }
    } else {
      // In up position, use tolerance-based approach
      if (backAngle < (180.0 - _backAlignmentTolerance)) {
        final now = DateTime.now();
        if (_lastBackFeedbackTime == null ||
            now.difference(_lastBackFeedbackTime!) > _feedbackCooldown) {
          _addTtsMessage("Keep your back straight", TTSPriority.critical);
          _lastBackFeedbackTime = now;
        }
      }
    }
  }

  void _checkGripWidth(
    PoseLandmark? leftShoulder,
    PoseLandmark? rightShoulder,
    PoseLandmark? leftWrist,
    PoseLandmark? rightWrist,
  ) {
    if (leftShoulder == null ||
        rightShoulder == null ||
        leftWrist == null ||
        rightWrist == null) {
      return;
    }

    final double shoulderWidth = sqrt(
      pow(rightShoulder.x - leftShoulder.x, 2) +
          pow(rightShoulder.y - leftShoulder.y, 2),
    );

    final double wristDistance = sqrt(
      pow(rightWrist.x - leftWrist.x, 2) + pow(rightWrist.y - leftWrist.y, 2),
    );

    final double gripRatio = wristDistance / shoulderWidth;

    if (gripRatio < _minGripWidthRatio) {
      final now = DateTime.now();
      if (_lastGripFeedbackTime == null ||
          now.difference(_lastGripFeedbackTime!) > _feedbackCooldown) {
        _addTtsMessage("Widen your grip slightly", TTSPriority.important);
        _lastGripFeedbackTime = now;
      }
    }
  }

  void _checkHipAlignment(PoseLandmark? leftHip, PoseLandmark? rightHip) {
    if (leftHip == null || rightHip == null) {
      return;
    }

    final double hipHeightDiff = (leftHip.y - rightHip.y).abs();
    if (hipHeightDiff > _hipAlignmentTolerance) {
      final now = DateTime.now();
      if (_lastFormFeedbackTime == null ||
          now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
        _addTtsMessage("Keep your hips level", TTSPriority.important);
      }
    }
  }

  @override
  void reset() {
    _diamondPushUpCount = 0;
    _currentState = DiamondPushupState.up;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastFormFeedbackTime = null;
    _lastFormFeedback = null;
    _lastBackFeedbackTime = null;
    _lastGripFeedbackTime = null;
    _lastElbowFeedbackTime = null;
    _consecutiveErrors = 0;
    _isFastUser = false;
    _repDurations.clear();
    _avgRepTime = 0.0;
    _cooldownDuration = Duration(milliseconds: 1000);
    _ttsQueue.clear();
    _currentRepStartTime = null;
    _addTtsMessage("Reset complete. Get into Position", TTSPriority.important);
  }

  @override
  String get progressLabel => "Diamond Push-ups: $_diamondPushUpCount";

  @override
  int get reps => _diamondPushUpCount;

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
    double angleDeg = angleRad * 180 / pi;

    if (angleDeg > 180) {
      angleDeg = 360 - angleDeg;
    }
    return angleDeg;
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
