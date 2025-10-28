// lib/body_posture/exercises_logic/cobra_stretch_logic.dart

//NEED TESTING

import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show TimeExerciseLogic;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// Enum to define the states of a Cobra Stretch
enum PoseState { holding, notHolding, error }

// Enum for TTS feedback priority levels
enum TTSPriority {
  critical, // Immediate form corrections that could prevent injury
  important, // Form issues and timing feedback
  milestone, // Time milestones
  positive, // Encouragement
}

class TTSMessage {
  final String text;
  final TTSPriority priority;
  final DateTime timestamp;

  TTSMessage(this.text, this.priority) : timestamp = DateTime.now();
}

class CobraStretchLogic implements TimeExerciseLogic {
  int _elapsedSeconds = 0;
  Timer? _timer;
  PoseState _currentState = PoseState.notHolding;

  // Threshold values with tolerance ranges for accurate detection
  final double _elbowExtensionThresholdMin =
      140.0; // Min angle for straight arms
  final double _elbowExtensionThresholdMax =
      160.0; // Max angle for straight arms
  final double _shoulderLiftThresholdYMin =
      0.15; // Min Y difference hip→shoulder
  final double _shoulderLiftThresholdYMax =
      0.25; // Max Y difference hip→shoulder
  final double _backAlignmentTolerance = 15.0; // For back alignment checks
  final double _minLandmarkConfidence = 0.7; // Minimum confidence for landmarks

  // Enhanced TTS variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackSecond = 0;
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

  CobraStretchLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    _isTtsInitialized = true;
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
    if (_isSpeaking || !_isTtsInitialized) return;

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

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    final List<PoseLandmark> poseLandmarks = landmarks.cast<PoseLandmark>();

    // --- Landmark Retrieval for Cobra Stretch ---
    final leftElbow = _getLandmark(poseLandmarks, PoseLandmarkType.leftElbow);
    final rightElbow = _getLandmark(poseLandmarks, PoseLandmarkType.rightElbow);
    final leftShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.leftShoulder,
    );
    final rightShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.rightShoulder,
    );
    final leftWrist = _getLandmark(poseLandmarks, PoseLandmarkType.leftWrist);
    final rightWrist = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist);
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final nose = _getLandmark(poseLandmarks, PoseLandmarkType.nose);

    final bool allValid = _areLandmarksValid([
      leftElbow,
      rightElbow,
      leftShoulder,
      rightShoulder,
      leftWrist,
      rightWrist,
      leftHip,
      rightHip,
      nose,
    ]);

    if (!allValid) {
      _handleLandmarkError();
      return;
    }

    // Recovery from error state
    if (_currentState == PoseState.error) {
      if (DateTime.now().difference(_errorStartTime) > _errorRecoveryDuration) {
        _currentState = PoseState.notHolding;
        _consecutiveErrors = 0;
        _addTtsMessage("Resuming exercise", TTSPriority.important);
      }
      return;
    }

    // Process TTS queue
    _processTtsQueue();

    if (!_hasStarted) {
      _hasStarted = true;
      _addTtsMessage("Get into position", TTSPriority.important);
    }

    // --- Pose Detection Logic ---
    // Using null assertion operators since we've already validated the landmarks
    final double leftElbowAngle = _getAngle(
      leftShoulder!,
      leftElbow!,
      leftWrist!,
    );
    final double rightElbowAngle = _getAngle(
      rightShoulder!,
      rightElbow!,
      rightWrist!,
    );
    final double avgElbowAngle = (leftElbowAngle + rightElbowAngle) / 2.0;

    final double avgShoulderY = (leftShoulder.y + rightShoulder.y) / 2.0;
    final double avgHipY = (leftHip!.y + rightHip!.y) / 2.0;
    final double shoulderHipYDiff = (avgHipY - avgShoulderY);

    // Form analysis
    _checkForm(
      avgElbowAngle,
      shoulderHipYDiff,
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
    );

    bool inCobraPose =
        avgElbowAngle >= _elbowExtensionThresholdMin &&
        avgElbowAngle <= _elbowExtensionThresholdMax &&
        shoulderHipYDiff >= _shoulderLiftThresholdYMin &&
        shoulderHipYDiff <= _shoulderLiftThresholdYMax;

    if (inCobraPose && _currentState == PoseState.notHolding) {
      _currentState = PoseState.holding;
      _startTimer();
      _addTtsMessage("Good form! Hold the pose", TTSPriority.positive);
    } else if (!inCobraPose && _currentState == PoseState.holding) {
      _currentState = PoseState.notHolding;
      _stopTimer();
      _addTtsMessage("Hold the pose", TTSPriority.important);
    }

    if (_currentState == PoseState.holding &&
        _elapsedSeconds > 0 &&
        _elapsedSeconds != _lastFeedbackSecond) {
      _lastFeedbackSecond = _elapsedSeconds;

      if (_elapsedSeconds % 5 == 0) {
        _addTtsMessage(
          "Keep holding, $_elapsedSeconds seconds",
          TTSPriority.milestone,
        );
      } else if (_elapsedSeconds == 10) {
        _addTtsMessage("Great job! Halfway there", TTSPriority.milestone);
      } else if (_elapsedSeconds >= 15) {
        _addTtsMessage("Almost done! You can do it", TTSPriority.milestone);
      }
    }
  }

  void _handleLandmarkError() {
    _consecutiveErrors++;

    if (_currentState != PoseState.error) {
      _currentState = PoseState.error;
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
    double avgElbowAngle,
    double shoulderHipYDiff,
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
    PoseLandmark leftHip,
    PoseLandmark rightHip,
  ) {
    if (_lastFormFeedbackTime != null &&
        DateTime.now().difference(_lastFormFeedbackTime!) <
            _formFeedbackCooldown) {
      return;
    }

    String? feedback;
    TTSPriority priority = TTSPriority.positive;

    // Check for common form issues
    if (avgElbowAngle < _elbowExtensionThresholdMin) {
      feedback = "Straighten your arms more";
      priority = TTSPriority.important;
    } else if (avgElbowAngle > _elbowExtensionThresholdMax) {
      feedback = "Bend your elbows slightly";
      priority = TTSPriority.important;
    } else if (shoulderHipYDiff < _shoulderLiftThresholdYMin) {
      feedback = "Lift your chest higher";
      priority = TTSPriority.important;
    } else if (shoulderHipYDiff > _shoulderLiftThresholdYMax) {
      feedback = "Lower your chest slightly";
      priority = TTSPriority.important;
    }

    // Check back alignment (for injury prevention)
    final double shoulderHeight = (leftShoulder.y + rightShoulder.y) / 2.0;
    final double hipHeight = (leftHip.y + rightHip.y) / 2.0;
    final double backAlignmentDiff = (shoulderHeight - hipHeight).abs();

    if (backAlignmentDiff > _backAlignmentTolerance) {
      feedback = "Keep your back straight to prevent injury";
      priority = TTSPriority.critical;
    }

    // Positive feedback for good form
    if (feedback == null && _elapsedSeconds > 0 && _elapsedSeconds % 3 == 0) {
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
    _stopTimer();
    _elapsedSeconds = 0;
    _currentState = PoseState.notHolding;
    _hasStarted = false;
    _lastFeedbackSecond = 0;
    _lastFormFeedbackTime = null;
    _lastFormFeedback = null;
    _consecutiveErrors = 0;
    _ttsQueue.clear();
    _addTtsMessage("Exercise reset", TTSPriority.important);
  }

  @override
  String get progressLabel => 'Time: ${_formatTime(_elapsedSeconds)}';

  @override
  int get seconds => _elapsedSeconds;

  void _startTimer() {
    if (_timer != null && _timer!.isActive) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

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
    final double mag1 = sqrt(v1x * v1x + v1y * v1y);
    final double mag2 = sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0.0 || mag2 == 0.0) return 180.0;

    double cosine = dotProduct / (mag1 * mag2);
    cosine = max(-1.0, min(1.0, cosine));

    return acos(cosine) * 180.0 / pi;
  }

  String _formatTime(int totalSeconds) {
    final int minutes = (totalSeconds ~/ 60);
    final int seconds = (totalSeconds % 60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
