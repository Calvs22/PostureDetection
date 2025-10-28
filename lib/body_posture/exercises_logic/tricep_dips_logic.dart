// lib/body_posture/exercises/exercises_logic/tricep_dips_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart' show RepExerciseLogic; // Changed import
import '/body_posture/camera/pose_painter.dart'; // Needed for FirstWhereOrNullExtension

// Enum to define the states of a Tricep Dip
enum TricepDipState {
  up, // Top of the movement, arms straight
  down, // Bottom of the movement, elbows bent
}

class TricepDipsLogic implements RepExerciseLogic {
  // Changed from ExerciseLogic to RepExerciseLogic
  int _repCount = 0;
  TricepDipState _currentState = TricepDipState.up;

  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(
    milliseconds: 500,
  ); // 0.5 second cooldown

  bool _canCountRep = true;

  // Thresholds for tricep dips
  final double _downThresholdAngle = 110.0; // Angle for the 'down' state
  final double _upThresholdAngle = 160.0; // Angle for the 'up' state
  final double _minLandmarkConfidence = 0.7;

  // NEW: Tolerance constants
  final double _angleTolerance = 10.0; // ±10 degrees tolerance
  final double _hysteresisBuffer = 5.0; // Prevents state flickering

  // TTS instance
  final FlutterTts _tts = FlutterTts();
  bool _hasStarted = false;
  int _lastFeedbackRep = 0;

  // Form feedback cooldown
  DateTime? _lastFormFeedbackTime;
  final Duration _formFeedbackCooldown = Duration(seconds: 5);

  // Range of motion tracking
  double _minElbowAngle = 180.0;
  double _maxElbowAngle = 0.0;
  bool _hasReachedFullExtension = false;

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    // Cast landmarks to the correct type
    final poseLandmarks = landmarks as List<PoseLandmark>;

    // Speak initial message immediately on first update
    if (!_hasStarted) {
      _speak("Get into Position");
      _hasStarted = true;
    }

    // Retrieve essential landmarks for tricep dip detection
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

    // Additional landmarks for form analysis
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final leftAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.leftAnkle);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);

    // Validate landmarks
    if (leftShoulder == null ||
        leftElbow == null ||
        leftWrist == null ||
        rightShoulder == null ||
        rightElbow == null ||
        rightWrist == null ||
        leftHip == null ||
        rightHip == null ||
        leftAnkle == null ||
        rightAnkle == null) {
      if (_currentState != TricepDipState.up) {
        _currentState = TricepDipState.up;
        _canCountRep = false;
      }
      return;
    }

    // Calculate the elbow angles for both arms
    final double leftArmAngle = _getAngle(leftShoulder, leftElbow, leftWrist);
    final double rightArmAngle = _getAngle(
      rightShoulder,
      rightElbow,
      rightWrist,
    );
    final double averageArmAngle = (leftArmAngle + rightArmAngle) / 2;

    // Update range of motion tracking
    _minElbowAngle = min(_minElbowAngle, averageArmAngle);
    _maxElbowAngle = max(_maxElbowAngle, averageArmAngle);

    // NEW: Define position checks with tolerance
    final bool isDownPosition =
        averageArmAngle <= (_downThresholdAngle + _angleTolerance);
    final bool isUpPosition =
        averageArmAngle >= (_upThresholdAngle - _angleTolerance);

    // Enhanced form analysis
    _checkForm(
      leftArmAngle,
      rightArmAngle,
      leftShoulder,
      rightShoulder,
      leftElbow,
      rightElbow,
      leftHip,
      rightHip,
      leftAnkle,
      rightAnkle,
    );

    // State Machine Logic with hysteresis
    if (DateTime.now().difference(_lastRepTime) > _cooldownDuration) {
      if (!_canCountRep) {
        _canCountRep = true;
      }
    }

    switch (_currentState) {
      case TricepDipState.up:
        // User is lowering into the 'down' position with hysteresis
        if (isDownPosition &&
            averageArmAngle <= (_downThresholdAngle + _hysteresisBuffer)) {
          _currentState = TricepDipState.down;
          _speak("Down");
        }
        break;

      case TricepDipState.down:
        // User is pushing back up into the 'up' position with hysteresis
        if (isUpPosition &&
            averageArmAngle >= (_upThresholdAngle - _hysteresisBuffer)) {
          if (_canCountRep) {
            _repCount++;
            _currentState = TricepDipState.up;
            _lastRepTime = DateTime.now();
            _canCountRep = false;

            // Check if user achieved full extension with tolerance
            if (_maxElbowAngle >= (170.0 - _angleTolerance)) {
              _hasReachedFullExtension = true;
            }

            // Provide feedback every 5 reps
            if (_repCount % 5 == 0 && _repCount != _lastFeedbackRep) {
              _speak("Good job! Keep going!");
              _lastFeedbackRep = _repCount;
            }

            // Completion feedback
            if (_repCount == 10) {
              _speak("Almost there! Just a few more!");
            }
          } else {
            _currentState = TricepDipState.up;
          }
        }
        break;
    }
  }

  @override
  void reset() {
    _repCount = 0;
    _currentState = TricepDipState.up;
    _lastRepTime = DateTime.now();
    _canCountRep = true;
    _hasStarted = false;
    _lastFeedbackRep = 0;
    _lastFormFeedbackTime = null;
    _minElbowAngle = 180.0;
    _maxElbowAngle = 0.0;
    _hasReachedFullExtension = false;
    _speak("Reset complete. Get into Position");
  }

  @override
  String get progressLabel => "Dips: $_repCount";

  @override
  int get reps => _repCount; // Added getter for reps

  // Helper method to get landmark with confidence check
  PoseLandmark? _getLandmark(
    List<PoseLandmark> landmarks,
    PoseLandmarkType type,
  ) {
    final landmark = landmarks.firstWhereOrNull((l) => l.type == type);
    // Check if landmark exists and has sufficient confidence
    if (landmark != null && landmark.likelihood >= _minLandmarkConfidence) {
      return landmark;
    }
    return null;
  }

  // Helper function to calculate the angle between three landmarks
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

    return angleDeg;
  }

  // Enhanced form analysis with tolerance
  void _checkForm(
    double leftArmAngle,
    double rightArmAngle,
    PoseLandmark? leftShoulder,
    PoseLandmark? rightShoulder,
    PoseLandmark? leftElbow,
    PoseLandmark? rightElbow,
    PoseLandmark? leftHip,
    PoseLandmark? rightHip,
    PoseLandmark? leftAnkle,
    PoseLandmark? rightAnkle,
  ) {
    final now = DateTime.now();

    // 1. Check if arms are moving symmetrically with tolerance
    final double angleDifference = (leftArmAngle - rightArmAngle).abs();
    if (angleDifference > (20.0 + _angleTolerance)) {
      _provideFormFeedback("Keep your arms even", now);
    }

    // 2. Check if elbows are flaring out too much with tolerance
    if (leftArmAngle < (90.0 - _angleTolerance) ||
        rightArmAngle < (90.0 - _angleTolerance)) {
      _provideFormFeedback("Don't bend your elbows too much", now);
    }

    // 3. Body alignment check with tolerance
    if (leftShoulder != null && leftHip != null && leftAnkle != null) {
      final double bodyAlignmentAngle = _getAngle(
        leftShoulder,
        leftHip,
        leftAnkle,
      );
      // If body alignment angle is too small, body is swinging
      if (bodyAlignmentAngle < (150.0 - _angleTolerance)) {
        _provideFormFeedback("Keep your body straight, avoid swinging", now);
      }
    }

    // 4. Shoulder position check with tolerance
    if (leftShoulder != null && leftElbow != null && leftHip != null) {
      final double shoulderAngle = _getAngle(leftElbow, leftShoulder, leftHip);
      // If shoulder angle is too small, shoulders are hunched
      if (shoulderAngle < (60.0 - _angleTolerance)) {
        _provideFormFeedback("Keep your shoulders back and down", now);
      }
    }

    // 5. Range of motion check with tolerance
    if (_maxElbowAngle < (160.0 - _angleTolerance) && _repCount > 2) {
      _provideFormFeedback("Extend your arms fully at the top", now);
    }

    // Positive feedback for good form with tolerance
    if (_hasReachedFullExtension &&
        _minElbowAngle <= (100.0 + _angleTolerance) &&
        _repCount > 3) {
      _provideFormFeedback("Great form! Full range of motion", now);
    }
  }

  // NEW: Helper method for form feedback with cooldown
  void _provideFormFeedback(String message, DateTime now) {
    if (_lastFormFeedbackTime == null ||
        now.difference(_lastFormFeedbackTime!) > _formFeedbackCooldown) {
      _speak(message);
      _lastFormFeedbackTime = now;
    }
  }

  // TTS helper method
  Future<void> _speak(String text) async {
    await _tts.setLanguage("en-US");
    await _tts.setPitch(1.0);
    await _tts.speak(text);
  }
}
