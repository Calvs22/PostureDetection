//lib/body_posture/exercises_logic/alternating_hooks_logic.dart

//NEED TESTING

import 'dart:async';
import 'dart:math';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart';

// Enum to define the state of each arm for hook detection
enum HookState {
  retracted, // Arm is close to the body, ready to punch
  punching, // Arm is extended outwards for the hook
}

class AlternatingHooksLogic implements RepExerciseLogic, TimeExerciseLogic {
  // Counters for left and right hooks
  int _leftHookCount = 0;
  int _rightHookCount = 0;

  // State for each arm's hook detection cycle
  HookState _leftHookState = HookState.retracted;
  HookState _rightHookState = HookState.retracted;

  // Flags to indicate which arm is currently in the punching phase
  bool _isLeftPunchingActive = false;
  bool _isRightPunchingActive = false;

  // Cooldown timestamps for each arm to prevent rapid counting
  DateTime _lastLeftHookTime = DateTime.now();
  DateTime _lastRightHookTime = DateTime.now();

  // Time tracking fields
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _timerStarted = false;

  // Configuration constants with tolerance ranges
  final Duration _cooldownDuration = const Duration(milliseconds: 700);
  final double _hookElbowAngleMin = 65.0; // Lower bound for elbow bend
  final double _hookElbowAngleMax = 115.0; // Upper bound for elbow bend
  final double _armTuckedInAngleMax = 45.0; // Maximum angle for tucked arm
  final double _armExtendedOutAngleMin = 55.0; // Minimum angle for extended arm
  final double _minLandmarkConfidence = 0.7;

  // Hysteresis margin to prevent rapid state changes
  final double _hysteresisMargin = 5.0;

  // Form feedback properties
  String _formFeedback = "Get in position to start";
  double _formScore = 100.0;
  String _lastSpokenFeedback = "";
  DateTime _lastFeedbackTime = DateTime.now().subtract(
    const Duration(seconds: 5),
  );
  final Duration _feedbackCooldown = const Duration(seconds: 3);

  // Error handling related fields
  bool _isSensorStable = true; // Used for sensor state tracking
  int _consecutivePoorFrames = 0;
  static const int _maxPoorFramesBeforeReset = 10;
  bool _isRecoveringFromSensorIssue = false;

  @override
  String get progressLabel =>
      "Left: $_leftHookCount, Right: $_rightHookCount, Time: ${_formatTime(_elapsedSeconds)}";

  /// ✅ Numeric reps (total hooks)
  @override
  int get reps => _leftHookCount + _rightHookCount;

  @override
  int get seconds => _elapsedSeconds;

  // Extra feedback (not part of ExerciseLogic, but useful for UI/voice)
  String get formFeedback => _formFeedback;
  double get formScore => _formScore;

  String get ttsFeedback {
    // Only return feedback that hasn't been spoken recently
    if (_formFeedback != _lastSpokenFeedback &&
        DateTime.now().difference(_lastFeedbackTime) > _feedbackCooldown) {
      _lastSpokenFeedback = _formFeedback;
      _lastFeedbackTime = DateTime.now();
      return _formFeedback;
    }
    return "";
  }

  @override
  void update(List landmarks, bool isFrontCamera) {
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
        _formFeedback = "Tracking resumed. Continue your exercise.";
      }
    }

    // Extract landmarks based on camera orientation
    final landmarksMap = _extractLandmarks(landmarks, isFrontCamera);

    // Process left arm if landmarks are confident
    if (_areLandmarksConfident(landmarksMap['left']!)) {
      _processLeftArm(landmarksMap['left']!);
    } else {
      _resetLeftArm();
    }

    // Process right arm if landmarks are confident
    if (_areLandmarksConfident(landmarksMap['right']!)) {
      _processRightArm(landmarksMap['right']!);
    } else {
      _resetRightArm();
    }

    // Update form feedback based on current state
    _updateFormFeedback(landmarksMap);

    // Start timer when exercise begins
    if (!_timerStarted && (_leftHookCount > 0 || _rightHookCount > 0)) {
      _startTimer();
      _timerStarted = true;
    }
  }

  @override
  void reset() {
    _leftHookCount = 0;
    _rightHookCount = 0;
    _leftHookState = HookState.retracted;
    _rightHookState = HookState.retracted;
    _isLeftPunchingActive = false;
    _isRightPunchingActive = false;
    _lastLeftHookTime = DateTime.now();
    _lastRightHookTime = DateTime.now();
    _formFeedback = "Get in position to start";
    _formScore = 100.0;
    _lastSpokenFeedback = "";
    _lastFeedbackTime = DateTime.now().subtract(const Duration(seconds: 5));
    _stopTimer();
    _elapsedSeconds = 0;
    _timerStarted = false;
    _isSensorStable = true;
    _consecutivePoorFrames = 0;
    _isRecoveringFromSensorIssue = false;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  Map<String, Map<PoseLandmarkType, PoseLandmark>> _extractLandmarks(
    List landmarks,
    bool isFrontCamera,
  ) {
    final leftShoulder = _getLandmark(
      landmarks,
      isFrontCamera
          ? PoseLandmarkType.rightShoulder
          : PoseLandmarkType.leftShoulder,
    );
    final leftElbow = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.rightElbow : PoseLandmarkType.leftElbow,
    );
    final leftWrist = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.rightWrist : PoseLandmarkType.leftWrist,
    );
    final leftHip = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.rightHip : PoseLandmarkType.leftHip,
    );

    final rightShoulder = _getLandmark(
      landmarks,
      isFrontCamera
          ? PoseLandmarkType.leftShoulder
          : PoseLandmarkType.rightShoulder,
    );
    final rightElbow = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow,
    );
    final rightWrist = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.leftWrist : PoseLandmarkType.rightWrist,
    );
    final rightHip = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip,
    );

    return {
      'left': {
        PoseLandmarkType.leftShoulder: leftShoulder!,
        PoseLandmarkType.leftElbow: leftElbow!,
        PoseLandmarkType.leftWrist: leftWrist!,
        PoseLandmarkType.leftHip: leftHip!,
      },
      'right': {
        PoseLandmarkType.rightShoulder: rightShoulder!,
        PoseLandmarkType.rightElbow: rightElbow!,
        PoseLandmarkType.rightWrist: rightWrist!,
        PoseLandmarkType.rightHip: rightHip!,
      },
    };
  }

  PoseLandmark? _getLandmark(List landmarks, PoseLandmarkType type) {
    try {
      return landmarks.firstWhere((l) => l.type == type);
    } catch (e) {
      return null;
    }
  }

  bool _areLandmarksConfident(Map<PoseLandmarkType, PoseLandmark> landmarks) {
    return landmarks.values.every(
      (landmark) => landmark.likelihood >= _minLandmarkConfidence,
    );
  }

  void _processLeftArm(Map<PoseLandmarkType, PoseLandmark> landmarks) {
    final elbowAngle = _getAngle(
      landmarks[PoseLandmarkType.leftShoulder]!,
      landmarks[PoseLandmarkType.leftElbow]!,
      landmarks[PoseLandmarkType.leftWrist]!,
    );

    final armTorsoAngle = _getAngle(
      landmarks[PoseLandmarkType.leftHip]!,
      landmarks[PoseLandmarkType.leftShoulder]!,
      landmarks[PoseLandmarkType.leftElbow]!,
    );

    switch (_leftHookState) {
      case HookState.retracted:
        if (!_isRightPunchingActive &&
            elbowAngle >= _hookElbowAngleMin &&
            elbowAngle <= _hookElbowAngleMax &&
            armTorsoAngle >= _armExtendedOutAngleMin + _hysteresisMargin) {
          _leftHookState = HookState.punching;
          _isLeftPunchingActive = true;
          _isRightPunchingActive = false;
          _rightHookState = HookState.retracted;
        }
        break;
      case HookState.punching:
        if (armTorsoAngle < _armTuckedInAngleMax - _hysteresisMargin) {
          if (DateTime.now().difference(_lastLeftHookTime) >
              _cooldownDuration) {
            _leftHookCount++;
            _lastLeftHookTime = DateTime.now();
          }
          _leftHookState = HookState.retracted;
          _isLeftPunchingActive = false;
        }
        break;
    }
  }

  void _processRightArm(Map<PoseLandmarkType, PoseLandmark> landmarks) {
    final elbowAngle = _getAngle(
      landmarks[PoseLandmarkType.rightShoulder]!,
      landmarks[PoseLandmarkType.rightElbow]!,
      landmarks[PoseLandmarkType.rightWrist]!,
    );

    final armTorsoAngle = _getAngle(
      landmarks[PoseLandmarkType.rightHip]!,
      landmarks[PoseLandmarkType.rightShoulder]!,
      landmarks[PoseLandmarkType.rightElbow]!,
    );

    switch (_rightHookState) {
      case HookState.retracted:
        if (!_isLeftPunchingActive &&
            elbowAngle >= _hookElbowAngleMin &&
            elbowAngle <= _hookElbowAngleMax &&
            armTorsoAngle >= _armExtendedOutAngleMin + _hysteresisMargin) {
          _rightHookState = HookState.punching;
          _isRightPunchingActive = true;
          _isLeftPunchingActive = false;
          _leftHookState = HookState.retracted;
        }
        break;
      case HookState.punching:
        if (armTorsoAngle < _armTuckedInAngleMax - _hysteresisMargin) {
          if (DateTime.now().difference(_lastRightHookTime) >
              _cooldownDuration) {
            _rightHookCount++;
            _lastRightHookTime = DateTime.now();
          }
          _rightHookState = HookState.retracted;
          _isRightPunchingActive = false;
        }
        break;
    }
  }

  void _resetLeftArm() {
    if (_leftHookState != HookState.retracted || _isLeftPunchingActive) {
      _leftHookState = HookState.retracted;
      _isLeftPunchingActive = false;
    }
  }

  void _resetRightArm() {
    if (_rightHookState != HookState.retracted || _isRightPunchingActive) {
      _rightHookState = HookState.retracted;
      _isRightPunchingActive = false;
    }
  }

  void _updateFormFeedback(
    Map<String, Map<PoseLandmarkType, PoseLandmark>> landmarksMap,
  ) {
    _formFeedback = "Good form!";
    _formScore = 100.0;

    if (_areLandmarksConfident(landmarksMap['left']!)) {
      final leftElbowAngle = _getAngle(
        landmarksMap['left']![PoseLandmarkType.leftShoulder]!,
        landmarksMap['left']![PoseLandmarkType.leftElbow]!,
        landmarksMap['left']![PoseLandmarkType.leftWrist]!,
      );

      if (leftElbowAngle < _hookElbowAngleMin) {
        _formFeedback = "Bend your left elbow more";
        _formScore = 70.0;
      } else if (leftElbowAngle > _hookElbowAngleMax) {
        _formFeedback = "Your left elbow is too bent";
        _formScore = 70.0;
      }
    }

    if (_areLandmarksConfident(landmarksMap['right']!)) {
      final rightElbowAngle = _getAngle(
        landmarksMap['right']![PoseLandmarkType.rightShoulder]!,
        landmarksMap['right']![PoseLandmarkType.rightElbow]!,
        landmarksMap['right']![PoseLandmarkType.rightWrist]!,
      );

      if (rightElbowAngle < _hookElbowAngleMin) {
        _formFeedback = "Bend your right elbow more";
        _formScore = 70.0;
      } else if (rightElbowAngle > _hookElbowAngleMax) {
        _formFeedback = "Your right elbow is too bent";
        _formScore = 70.0;
      }
    }

    if (_leftHookState == HookState.punching) {
      _formFeedback = "Extend your left arm fully";
      _formScore = 80.0;
    } else if (_rightHookState == HookState.punching) {
      _formFeedback = "Extend your right arm fully";
      _formScore = 80.0;
    }
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

    if (angleDeg > 180) {
      angleDeg = 360 - angleDeg;
    }
    return angleDeg;
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
      _formFeedback =
          "Camera tracking issue detected. Please ensure you're visible in the frame.";
    }

    // Reset arm states but preserve counts and time
    _resetLeftArm();
    _resetRightArm();

    // Reset poor frame counter to allow recovery
    _consecutivePoorFrames = 0;
  }
}
