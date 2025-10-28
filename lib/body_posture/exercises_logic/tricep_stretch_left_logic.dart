// lib/body_posture/exercises/exercises_logic/tricep_stretch_left_logic.dart
// NEED TESTING ASWELL
import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show TimeExerciseLogic; // Changed import
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class TricepStretchLeftLogic implements TimeExerciseLogic {
  // Changed from ExerciseLogic to TimeExerciseLogic
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _isHoldingPose = false;

  // Threshold values for accurate detection
  final double _minStretchAngle = 90.0; // Minimum angle (too deep of a bend)
  final double _maxStretchAngle = 130.0; // Maximum angle (not enough of a bend)
  final double _elbowHeightThresholdY =
      0.1; // Vertical difference to confirm elbow is raised above shoulder
  final double _handDistanceThreshold =
      0.05; // Relative distance between right hand and left elbow
  final double _minLandmarkConfidence =
      0.7; // Minimum confidence for detected landmarks

  // TTS variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackSecond = 0;

  TricepStretchLeftLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    _isTtsInitialized = true;
  }

  Future<void> _speak(String text) async {
    if (_isTtsInitialized) {
      await _flutterTts.speak(text);
    }
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    // Cast landmarks to the correct type
    final List<PoseLandmark> poseLandmarks = landmarks.cast<PoseLandmark>();

    // --- Landmark Retrieval for Tricep Stretch (Left) ---
    final leftShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.leftShoulder,
    );
    final leftElbow = _getLandmark(poseLandmarks, PoseLandmarkType.leftElbow);
    final leftWrist = _getLandmark(poseLandmarks, PoseLandmarkType.leftWrist);
    final rightWrist = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist);
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);

    // Validate landmarks
    final bool allNecessaryLandmarksValid = _areLandmarksValid([
      leftShoulder,
      leftElbow,
      leftWrist,
      rightWrist,
      leftHip,
    ]);

    if (!allNecessaryLandmarksValid) {
      _stopTimer();
      _isHoldingPose = false;
      return;
    }

    // First time starting the exercise
    if (!_hasStarted) {
      _hasStarted = true;
      _speak("Get into Position");
    }

    // --- Pose Detection Logic ---
    // Calculate arm angle
    final double armAngle = _getAngle(leftShoulder!, leftElbow!, leftWrist!);

    // Check if the left arm is properly bent (within the optimal range)
    final bool isArmBent =
        armAngle >= _minStretchAngle && armAngle <= _maxStretchAngle;

    // Check if the left elbow is raised above the shoulder
    final bool isElbowRaised =
        leftElbow.y < leftShoulder.y - _elbowHeightThresholdY;

    // Check if the right hand is near the left elbow to deepen the stretch
    final double handElbowDistance = _getDistance(rightWrist!, leftElbow);
    final double torsoHeight = _getDistance(leftShoulder, leftHip!);
    final bool isRightHandNearElbow =
        handElbowDistance < _handDistanceThreshold * torsoHeight;

    // Determine if in correct pose
    bool currentlyInPose = false;
    if (isArmBent && isElbowRaised && isRightHandNearElbow) {
      currentlyInPose = true;
    }

    // Provide specific angle feedback when needed
    if (!isArmBent && _isHoldingPose) {
      if (armAngle < _minStretchAngle) {
        _speak("Bend less - that's too deep");
      } else if (armAngle > _maxStretchAngle) {
        _speak("Bend more - reach further");
      }
    }

    // Update pose state and timer
    if (currentlyInPose && !_isHoldingPose) {
      _isHoldingPose = true;
      _startTimer();
    } else if (!currentlyInPose && _isHoldingPose) {
      _isHoldingPose = false;
      _stopTimer();
      _speak("Adjust your position");
    }

    // Provide periodic feedback
    if (_isHoldingPose &&
        _elapsedSeconds > 0 &&
        _elapsedSeconds != _lastFeedbackSecond) {
      _lastFeedbackSecond = _elapsedSeconds;

      if (_elapsedSeconds % 5 == 0) {
        _speak("Keep holding, $_elapsedSeconds seconds");
      } else if (_elapsedSeconds == 10) {
        _speak("Great job! Halfway there");
      } else if (_elapsedSeconds >= 15) {
        _speak("Almost done! You can do it");
      }
    }
  }

  @override
  void reset() {
    _stopTimer();
    _elapsedSeconds = 0;
    _isHoldingPose = false;
    _hasStarted = false;
    _lastFeedbackSecond = 0;
    _speak("Exercise reset");
  }

  @override
  String get progressLabel => 'Time: ${_formatTime(_elapsedSeconds)}';

  @override
  int get seconds => _elapsedSeconds; // Added getter for seconds

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
    final double magnitude1 = sqrt(v1x * v1x + v1y * v1y);
    final double magnitude2 = sqrt(v2x * v2x + v2y * v2y);

    if (magnitude1 == 0 || magnitude2 == 0) {
      return 180.0;
    }

    double cosineAngle = dotProduct / (magnitude1 * magnitude2);
    cosineAngle = max(-1.0, min(1.0, cosineAngle));

    double angleRad = acos(cosineAngle);
    return angleRad * 180 / pi;
  }

  double _getDistance(PoseLandmark p1, PoseLandmark p2) {
    final double dx = p1.x - p2.x;
    final double dy = p1.y - p2.y;
    return sqrt(dx * dx + dy * dy);
  }

  String _formatTime(int totalSeconds) {
    final int minutes = (totalSeconds ~/ 60);
    final int seconds = (totalSeconds % 60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
