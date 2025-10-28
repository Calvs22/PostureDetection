//lib/body_posture/exercises_logic/arm_circles_clockwise_logic.dart

//NEED TESTING

import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';
import 'package:collection/collection.dart';
import 'dart:collection';

// Enum to define the state of the arm circle repetition for clockwise circles
enum CircleState { initial, downBack, upForward }

class ArmCirclesClockwiseLogic implements TimeExerciseLogic {
  CircleState _currentCircleState = CircleState.initial;

  DateTime _lastCircleTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(milliseconds: 300);

  // Time tracking fields
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _timerStarted = false;

  // Angle thresholds with tolerance ranges
  final double _armStraightnessMinAngle =
      155.0; // Lower bound for straight arms
  final double _armStraightnessMaxAngle =
      180.0; // Upper bound for straight arms
  final double _clockwiseUpForwardMinAngle = 45.0;
  final double _clockwiseUpForwardMaxAngle = 135.0;
  final double _clockwiseDownBackMinAngle = 225.0;
  final double _clockwiseDownBackMaxAngle = 315.0;
  final double _minLandmarkConfidence = 0.7;

  // TTS instance and queue
  final FlutterTts _tts = FlutterTts();
  final Queue<String> _ttsQueue = Queue();
  bool _isProcessingTtsQueue = false;
  bool _hasStarted = false;
  int _lastFeedbackTime = 0;

  DateTime? _lastFormFeedbackTime;
  final Duration _formFeedbackCooldown = const Duration(seconds: 5);

  // Error handling related fields
  bool _isSensorStable = true; // Used for sensor state tracking
  int _consecutivePoorFrames = 0;
  static const int _maxPoorFramesBeforeReset = 10;
  bool _isRecoveringFromSensorIssue = false;

  ArmCirclesClockwiseLogic() {
    _initTts();
  }

  void _initTts() {
    _tts.setCompletionHandler(() {
      _isProcessingTtsQueue = false;
      _processTtsQueue();
    });
  }

  void _addToTtsQueue(String text) {
    _ttsQueue.add(text);
    if (!_isProcessingTtsQueue) {
      _processTtsQueue();
    }
  }

  Future<void> _processTtsQueue() async {
    if (_isProcessingTtsQueue || _ttsQueue.isEmpty) {
      return;
    }
    _isProcessingTtsQueue = true;
    final text = _ttsQueue.removeFirst();
    await _tts.setLanguage("en-US");
    await _tts.setPitch(1.0);
    await _tts.speak(text);
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    // Check sensor stability before processing
    _isSensorStable = _checkSensorStability(landmarks);
    if (!_isSensorStable) {
      _consecutivePoorFrames++;

      if (_consecutivePoorFrames >= _maxPoorFramesBeforeReset) {
        _handleSensorFailure();
      }
      return;
    }

    // Reset poor frame counter on good frame
    if (_consecutivePoorFrames > 0) {
      _consecutivePoorFrames = 0;

      // If recovering from sensor issue, provide feedback
      if (_isRecoveringFromSensorIssue) {
        _isRecoveringFromSensorIssue = false;
        _addToTtsQueue("Tracking resumed. Continue your exercise.");
      }
    }

    final poseLandmarks = landmarks as List<PoseLandmark>;

    if (!_hasStarted) {
      _addToTtsQueue("Get into Position");
      _hasStarted = true;
    }

    PoseLandmark? leftShoulder, leftElbow, leftWrist;
    PoseLandmark? rightShoulder, rightElbow, rightWrist;

    if (isFrontCamera) {
      leftShoulder = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.rightShoulder,
      );
      leftElbow = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.rightElbow,
      );
      leftWrist = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.rightWrist,
      );
      rightShoulder = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.leftShoulder,
      );
      rightElbow = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.leftElbow,
      );
      rightWrist = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.leftWrist,
      );
    } else {
      leftShoulder = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.leftShoulder,
      );
      leftElbow = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.leftElbow,
      );
      leftWrist = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.leftWrist,
      );
      rightShoulder = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.rightShoulder,
      );
      rightElbow = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.rightElbow,
      );
      rightWrist = poseLandmarks.firstWhereOrNull(
        (l) => l.type == PoseLandmarkType.rightWrist,
      );
    }

    if (!_areAllLandmarksAvailable([
      leftShoulder,
      leftElbow,
      leftWrist,
      rightShoulder,
      rightElbow,
      rightWrist,
    ])) {
      if (_currentCircleState != CircleState.initial) {
        _currentCircleState = CircleState.initial;
      }
      _stopTimer();
      return;
    }

    final double leftArmStraightnessAngle = _getAngle(
      leftShoulder!,
      leftElbow!,
      leftWrist!,
    );
    final double rightArmStraightnessAngle = _getAngle(
      rightShoulder!,
      rightElbow!,
      rightWrist!,
    );

    // Check arm straightness with tolerance range
    final bool areArmsStraight =
        leftArmStraightnessAngle >= _armStraightnessMinAngle &&
        leftArmStraightnessAngle <= _armStraightnessMaxAngle &&
        rightArmStraightnessAngle >= _armStraightnessMinAngle &&
        rightArmStraightnessAngle <= _armStraightnessMaxAngle;

    if (!areArmsStraight) {
      if (_currentCircleState != CircleState.initial) {
        _currentCircleState = CircleState.initial;
      }
      _stopTimer();
      return;
    }

    final double leftWristAngle = _getArmAngleAroundShoulder(
      leftShoulder,
      leftWrist,
      isFrontCamera,
      true,
    );
    final double rightWristAngle = _getArmAngleAroundShoulder(
      rightShoulder,
      rightWrist,
      isFrontCamera,
      false,
    );

    bool areArmsUpForward =
        (leftWristAngle >= _clockwiseUpForwardMinAngle &&
            leftWristAngle <= _clockwiseUpForwardMaxAngle) &&
        (rightWristAngle >= _clockwiseUpForwardMinAngle &&
            rightWristAngle <= _clockwiseUpForwardMaxAngle);

    bool areArmsDownBack =
        (leftWristAngle >= _clockwiseDownBackMinAngle &&
            leftWristAngle <= _clockwiseDownBackMaxAngle) &&
        (rightWristAngle >= _clockwiseDownBackMinAngle &&
            rightWristAngle <= _clockwiseDownBackMaxAngle);

    _checkForm(
      leftArmStraightnessAngle,
      rightArmStraightnessAngle,
      leftWristAngle,
      rightWristAngle,
      areArmsStraight,
    );

    if (DateTime.now().difference(_lastCircleTime) > _cooldownDuration) {
      switch (_currentCircleState) {
        case CircleState.initial:
          if (areArmsDownBack) {
            _currentCircleState = CircleState.downBack;
            _addToTtsQueue("Start position");
            // Start timer when exercise begins
            if (!_timerStarted) {
              _startTimer();
              _timerStarted = true;
            }
          }
          break;

        case CircleState.downBack:
          if (areArmsUpForward) {
            _currentCircleState = CircleState.upForward;
            _addToTtsQueue("Up");
          }
          break;

        case CircleState.upForward:
          if (areArmsDownBack) {
            _lastCircleTime = DateTime.now();
            _currentCircleState = CircleState.downBack;

            // Provide time-based feedback
            if (_elapsedSeconds > 0 &&
                _elapsedSeconds % 15 == 0 &&
                _elapsedSeconds != _lastFeedbackTime) {
              _addToTtsQueue("Good job! Keep going!");
              _lastFeedbackTime = _elapsedSeconds;
            }
          }
          break;
      }
    }
  }

  @override
  void reset() {
    _currentCircleState = CircleState.initial;
    _lastCircleTime = DateTime.now();
    _hasStarted = false;
    _lastFeedbackTime = 0;
    _lastFormFeedbackTime = null;
    _stopTimer();
    _elapsedSeconds = 0;
    _timerStarted = false;
    _isSensorStable = true;
    _consecutivePoorFrames = 0;
    _isRecoveringFromSensorIssue = false;
    _addToTtsQueue("Reset complete. Get into Position");
  }

  @override
  String get progressLabel => "Time: ${_formatTime(_elapsedSeconds)}";

  @override
  int get seconds => _elapsedSeconds;

  bool _areAllLandmarksAvailable(List<PoseLandmark?> landmarks) {
    return landmarks.every(
      (landmark) =>
          landmark != null && landmark.likelihood >= _minLandmarkConfidence,
    );
  }

  double _getArmAngleAroundShoulder(
    PoseLandmark shoulder,
    PoseLandmark wrist,
    bool isFrontCamera,
    bool isLeftArm,
  ) {
    double deltaX = wrist.x - shoulder.x;
    double actualDeltaY = shoulder.y - wrist.y;
    double angleRad = atan2(actualDeltaY, deltaX);
    double angleDeg = angleRad * 180 / pi;
    if (angleDeg < 0) {
      angleDeg += 360;
    }
    return angleDeg;
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
    double angleDeg = angleRad * 180 / pi;
    return angleDeg;
  }

  void _checkForm(
    double leftArmStraightnessAngle,
    double rightArmStraightnessAngle,
    double leftWristAngle,
    double rightWristAngle,
    bool areArmsStraight,
  ) {
    final now = DateTime.now();
    if (_lastFormFeedbackTime == null ||
        now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
      String? feedback;
      if (!areArmsStraight) {
        feedback = "Keep your arms straight";
      } else {
        final double angleDifference = (leftWristAngle - rightWristAngle).abs();
        if (angleDifference > 30.0 &&
            _currentCircleState != CircleState.initial) {
          feedback = "Move both arms together";
        }
      }

      if (feedback != null) {
        _addToTtsQueue(feedback);
        _lastFormFeedbackTime = now;
      }
    }

    if (areArmsStraight) {
      final double angleDifference = (leftWristAngle - rightWristAngle).abs();
      if (angleDifference < 15.0 &&
          (DateTime.now().difference(_lastFormFeedbackTime ?? DateTime.now()) >
              Duration(seconds: 10))) {
        _addToTtsQueue("Great form! Keep it up");
        _lastFormFeedbackTime = now;
      }
    }
  }

  // Timer management methods
  void _startTimer() {
    if (_timer != null && _timer!.isActive) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // New method for checking sensor stability
  bool _checkSensorStability(List landmarks) {
    // Check if we have enough landmarks
    if (landmarks.length < 10) {
      return false;
    }

    // Check if landmarks have reasonable confidence
    double avgConfidence =
        landmarks.fold(0.0, (sum, landmark) => sum + landmark.likelihood) /
        landmarks.length;

    // Consider sensor unstable if average confidence is too low
    if (avgConfidence < _minLandmarkConfidence * 0.8) {
      // 80% of the min confidence threshold
      return false;
    }

    return true;
  }

  // New method for handling sensor failure
  void _handleSensorFailure() {
    if (!_isRecoveringFromSensorIssue) {
      _isRecoveringFromSensorIssue = true;
      _addToTtsQueue(
        "Camera tracking issue detected. Please ensure you're visible in the frame.",
      );
    }

    // Stop timer but preserve elapsed time
    _stopTimer();
    _currentCircleState = CircleState.initial;

    // Reset poor frame counter to allow recovery
    _consecutivePoorFrames = 0;
  }
}
