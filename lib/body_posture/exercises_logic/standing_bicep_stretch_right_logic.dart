// lib/body_posture/exercises/exercises_logic/standing_bicep_stretch_right_logic.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class StandingBicepStretchRightLogic implements TimeExerciseLogic {
  // CHANGED: implements TimeExerciseLogic instead of ExerciseLogic
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _isHoldingPose = false;

  // Threshold values for accurate detection
  final double _armStraightThresholdAngle =
      160.0; // Angle of Shoulder-Elbow-Wrist to detect a straight arm
  final double _armBehindBodyThresholdX =
      0.1; // Relative horizontal difference to detect arm extended back
  final double _minLandmarkConfidence =
      0.7; // Minimum confidence for detected landmarks

  // Tolerance and hysteresis constants
  final double _armStraightTolerance = 10.0; // ±10 degrees tolerance
  final double _armBehindBodyTolerance = 0.05; // ±0.05 units tolerance
  final double _hysteresisBuffer = 5.0; // Prevents pose detection flickering

  // TTS variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackSecond = 0;

  // TTS feedback cooldown
  DateTime? _lastTtsFeedbackTime;
  final Duration _ttsFeedbackCooldown = Duration(seconds: 3);

  // Error handling variables
  DateTime? _lastInvalidLandmarksTime;
  final Duration _gracePeriod = Duration(seconds: 1);
  bool _isInGracePeriod = false;

  StandingBicepStretchRightLogic() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    _isTtsInitialized = true;
  }

  // Enhanced TTS method with cooldown
  Future<void> _speak(String text) async {
    final now = DateTime.now();
    if (_isTtsInitialized &&
        (_lastTtsFeedbackTime == null ||
            now.difference(_lastTtsFeedbackTime!) > _ttsFeedbackCooldown)) {
      await _flutterTts.speak(text);
      _lastTtsFeedbackTime = now;
    }
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    // Cast landmarks to the correct type
    final List<PoseLandmark> poseLandmarks = landmarks.cast<PoseLandmark>();

    // --- Landmark Retrieval for Standing Bicep Stretch (Right) ---
    final rightShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.rightShoulder,
    );
    final rightElbow = _getLandmark(poseLandmarks, PoseLandmarkType.rightElbow);
    final rightWrist = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist);
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);

    // Validate landmarks
    final bool allNecessaryLandmarksValid = _areLandmarksValid([
      rightShoulder,
      rightElbow,
      rightWrist,
      leftHip,
      rightHip,
    ]);

    // Error handling with grace period
    if (!allNecessaryLandmarksValid) {
      if (!_isInGracePeriod) {
        _lastInvalidLandmarksTime = DateTime.now();
        _isInGracePeriod = true;
        _speak("Adjust position - landmarks unclear");
      } else if (_lastInvalidLandmarksTime != null &&
          DateTime.now().difference(_lastInvalidLandmarksTime!) >
              _gracePeriod) {
        _stopTimer();
        _isHoldingPose = false;
        _isInGracePeriod = false;
        _speak("Position lost - please restart");
        return;
      }
    } else {
      _isInGracePeriod = false;
      _lastInvalidLandmarksTime = null;
    }

    // First time starting the exercise
    if (!_hasStarted) {
      _hasStarted = true;
      _speak("Get into Position");
    }

    // --- Pose Detection Logic ---
    // Check if the right arm is straight
    final double armAngle = _getAngle(rightShoulder!, rightElbow!, rightWrist!);

    // Arm straight check with tolerance and hysteresis
    final bool isArmStraight = _isHoldingPose
        ? armAngle >= (_armStraightThresholdAngle - _hysteresisBuffer)
        : armAngle >= (_armStraightThresholdAngle - _armStraightTolerance);

    // Check if the right arm is extended back (relative to the torso/shoulders)
    final double torsoMidpointX = (leftHip!.x + rightHip!.x) / 2;

    // Arm behind body check with tolerance and hysteresis
    final bool isArmBehindBody = _isHoldingPose
        ? rightWrist.x <
              (torsoMidpointX -
                  (_armBehindBodyThresholdX + _armBehindBodyTolerance))
        : rightWrist.x <
              (torsoMidpointX -
                  (_armBehindBodyThresholdX - _armBehindBodyTolerance));

    // Determine if in correct pose
    bool currentlyInPose = false;
    if (isArmStraight && isArmBehindBody) {
      currentlyInPose = true;
    }

    // Update pose state and timer
    if (currentlyInPose && !_isHoldingPose) {
      _isHoldingPose = true;
      _startTimer();
      _speak("Position good - start holding");
    } else if (!currentlyInPose && _isHoldingPose) {
      _isHoldingPose = false;
      _stopTimer();
      _speak("Adjust your position");
    }

    // Provide periodic feedback with enhanced TTS
    if (_isHoldingPose &&
        _elapsedSeconds > 0 &&
        _elapsedSeconds != _lastFeedbackSecond) {
      _lastFeedbackSecond = _elapsedSeconds;

      if (_elapsedSeconds % 5 == 0) {
        _speak(
          "Keep holding, $_elapsedSeconds seconds",
        ); // Fixed: Removed unnecessary braces
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
    _lastTtsFeedbackTime = null;
    _lastInvalidLandmarksTime = null;
    _isInGracePeriod = false;
    _speak("Exercise reset");
  }

  @override
  String get progressLabel => 'Time: ${_formatTime(_elapsedSeconds)}';

  @override
  int get seconds => _elapsedSeconds; // ADDED: Required getter for TimeExerciseLogic interface

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

  String _formatTime(int totalSeconds) {
    final int minutes = (totalSeconds ~/ 60);
    final int seconds = (totalSeconds % 60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
