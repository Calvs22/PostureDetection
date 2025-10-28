// lib/body_posture/exercises/exercises_logic/right_leg_donkey_kicks_logic.dart

//NOT ENHANCED

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// Enum to define the state of the donkey kick
enum DonkeyKickState {
  down, // Knee is on the ground or tucked (start position)
  up, // Leg is kicked up (top position)
}

class RightLegDonkeyKicksLogic implements RepExerciseLogic {
  // CHANGED: implements RepExerciseLogic instead of ExerciseLogic
  int _rightDonkeyKickCount = 0;
  DonkeyKickState _rightLegState = DonkeyKickState.down;

  DateTime _lastRightKickTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(
    milliseconds: 700,
  ); // 0.7 seconds cooldown

  // Angle thresholds for donkey kick detection
  final double _activeKneeBendAngleMin = 70.0; // Min angle for active bent knee
  final double _activeKneeBendAngleMax =
      110.0; // Max angle for active bent knee
  final double _stationaryKneeBendAngleMin =
      70.0; // Min angle for stationary bent knee
  final double _stationaryKneeBendAngleMax =
      110.0; // Max angle for stationary bent knee
  final double _bodyAlignmentAngleMin = 160.0; // Min angle for a straight back
  final double _kickUpMinYDifferenceRatio = 0.10; // Min vertical lift ratio
  final double _maxHipRotationYDifferenceRatio =
      0.05; // Max vertical difference between hips
  final double _minLandmarkConfidence = 0.7; // Minimum confidence for landmarks

  // TTS variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isTtsInitialized = false;
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;

  RightLegDonkeyKicksLogic() {
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

    // --- Landmark Retrieval ---
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final leftKnee = _getLandmark(poseLandmarks, PoseLandmarkType.leftKnee);
    final leftAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.leftAnkle);
    final leftShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.leftShoulder,
    );
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final rightKnee = _getLandmark(poseLandmarks, PoseLandmarkType.rightKnee);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);
    final rightShoulder = _getLandmark(
      poseLandmarks,
      PoseLandmarkType.rightShoulder,
    );

    // --- Confidence Check ---
    bool areAllLandmarksConfident = _areLandmarksValid([
      leftHip,
      leftKnee,
      leftAnkle,
      leftShoulder,
      rightHip,
      rightKnee,
      rightAnkle,
      rightShoulder,
    ]);

    if (!areAllLandmarksConfident) {
      _rightLegState = DonkeyKickState.down;
      return;
    }

    // First time starting the exercise
    if (!_hasStarted) {
      _hasStarted = true;
      _speak("Get into Position");
    }

    // --- Calculate Common Conditions ---
    final double avgBodyAlignmentAngle =
        (_getAngle(leftShoulder!, leftHip!, leftKnee!) +
            _getAngle(rightShoulder!, rightHip!, rightKnee!)) /
        2;

    // Calculate body reference measurements
    final double shoulderDistance = _getDistance(leftShoulder, rightShoulder);
    _getDistance(leftHip, rightHip);

    final bool isBodyStable =
        avgBodyAlignmentAngle > _bodyAlignmentAngleMin &&
        (leftHip.y - rightHip.y).abs() <
            (shoulderDistance * _maxHipRotationYDifferenceRatio);

    // --- Right Leg Kick Specific Checks ---
    final double rightKneeAngle = _getAngle(rightHip, rightKnee, rightAnkle!);
    final double leftKneeAngle = _getAngle(leftHip, leftKnee, leftAnkle!);
    final double rightLegLength = _getDistance(rightHip, rightKnee);

    // Check vertical lift for the right leg
    final bool isRightKneeBent =
        rightKneeAngle > _activeKneeBendAngleMin &&
        rightKneeAngle < _activeKneeBendAngleMax;
    final bool isRightLegLifted =
        (rightHip.y - rightKnee.y) >
        (rightLegLength * _kickUpMinYDifferenceRatio);

    // Check stationary leg (LEFT) stability
    final bool isLeftLegStable =
        leftKneeAngle > _stationaryKneeBendAngleMin &&
        leftKneeAngle < _stationaryKneeBendAngleMax;

    // --- Right Leg Donkey Kick Detection Logic ---
    if (isBodyStable && isRightKneeBent && isLeftLegStable) {
      switch (_rightLegState) {
        case DonkeyKickState.down:
          // Transition to UP: Right leg lifts
          if (isRightLegLifted) {
            _rightLegState = DonkeyKickState.up;
          }
          break;
        case DonkeyKickState.up:
          // Transition to DOWN: Right leg returns to down position, then count
          if (!isRightLegLifted) {
            // Leg has returned to the down position
            // Check cooldown before counting
            if (DateTime.now().difference(_lastRightKickTime) >
                _cooldownDuration) {
              _rightDonkeyKickCount++;
              _lastRightKickTime = DateTime.now();
              _rightLegState = DonkeyKickState.down;

              // Provide feedback during exercise
              if (_rightDonkeyKickCount != _lastFeedbackRep) {
                _lastFeedbackRep = _rightDonkeyKickCount;

                if (_rightDonkeyKickCount % 5 == 0) {
                  _speak("$_rightDonkeyKickCount kicks, keep going!");
                } else if (_rightDonkeyKickCount == 10) {
                  _speak("Great job! Halfway there!");
                } else if (_rightDonkeyKickCount >= 15) {
                  _speak("Almost done! You can do it!");
                } else {
                  _speak("Good job!");
                }
              }
            } else {
              _rightLegState = DonkeyKickState.down;
            }
          }
          break;
      }
    } else {
      // If general conditions for a donkey kick are not met, reset right leg state
      _rightLegState = DonkeyKickState.down;
    }
  }

  @override
  void reset() {
    _rightDonkeyKickCount = 0;
    _rightLegState = DonkeyKickState.down;
    _lastRightKickTime = DateTime.now();
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _speak("Exercise reset");
  }

  @override
  String get progressLabel => 'Right Leg Kicks: $_rightDonkeyKickCount';

  @override
  int get reps => _rightDonkeyKickCount; // ADDED: Required getter for RepExerciseLogic interface

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
}
