import 'dart:math' as math;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart'; // Assuming this points to your ExerciseLogic interface

enum DumbbellSquatState { up, down }

class DumbbellSquatLogic implements RepExerciseLogic {
  int _repCount = 0;
  DumbbellSquatState _currentState = DumbbellSquatState.up;
  final FlutterTts _flutterTts = FlutterTts();
// Still used internally to manage TTS cooldown

  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(milliseconds: 500);
  DateTime? _lastFeedbackTime;
  final Duration _feedbackCooldown = Duration(seconds: 4);

  bool _hasStarted = false;

  // Thresholds
  final double _kneeUpAngle = 170.0; // Standing position (close to straight)
  final double _kneeDownAngle = 145.0; // CRITICAL: Adjusted for front-view visibility
  final double _torsoAngleMin = 140.0; // For chest-up feedback
  final double _minLandmarkConfidence = 0.7;

  // Smoothing
  final List<double> _kneeAngleBuffer = [];
  final List<double> _torsoAngleBuffer = [];
  final int _bufferSize = 5; // Smooth over 5 frames

  // Error handling
  DateTime? _lastInvalidLandmarksTime;
  final Duration _gracePeriod = Duration(seconds: 1);
  bool _isInGracePeriod = false;

  DumbbellSquatLogic() {
    _initializeTts();
  }

  void _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _speak(String message) async {
    final now = DateTime.now();
    if (_lastFeedbackTime != null &&
        now.difference(_lastFeedbackTime!) < _feedbackCooldown) {
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    _lastFeedbackTime = now;
// Store last spoken feedback
  }

  PoseLandmark? _getLandmark(List<PoseLandmark> landmarks, PoseLandmarkType type) {
    for (final landmark in landmarks) {
      if (landmark.type == type && landmark.likelihood >= _minLandmarkConfidence) {
        return landmark;
      }
    }
    return null;
  }

  bool _areLandmarksValid(List<PoseLandmark?> landmarks) {
    return landmarks.every((landmark) => landmark != null);
  }

  double _smoothAngle(List<double> buffer, double newAngle) {
    buffer.add(newAngle);
    if (buffer.length > _bufferSize) {
      buffer.removeAt(0);
    }
    return buffer.isEmpty ? newAngle : buffer.reduce((a, b) => a + b) / buffer.length;
  }

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final v1x = p1.x - p2.x;
    final v1y = p1.y - p2.y;
    final v2x = p3.x - p2.x;
    final v2y = p3.y - p2.y;
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return 180.0;
    double cosine = dot / (mag1 * mag2);
    cosine = math.max(-1.0, math.min(1.0, cosine));
    return math.acos(cosine) * 180 / math.pi;
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    if (!_hasStarted) {
      _speak("Get into squat position. Feet shoulder-width apart, dumbbells in hand.");
      _hasStarted = true;
    }

    final poseLandmarks = landmarks.cast<PoseLandmark>();

    // Retrieve necessary landmarks
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final leftKnee = _getLandmark(poseLandmarks, PoseLandmarkType.leftKnee);
    final rightKnee = _getLandmark(poseLandmarks, PoseLandmarkType.rightKnee);
    final leftAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.leftAnkle);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);
    final leftShoulder = _getLandmark(poseLandmarks, PoseLandmarkType.leftShoulder);
    final rightShoulder = _getLandmark(poseLandmarks, PoseLandmarkType.rightShoulder);

    // Validate landmarks (only hip, knee, ankle are critical for rep count)
    final bool allNecessaryLandmarksValid = _areLandmarksValid([
      leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle,
    ]);

    if (!allNecessaryLandmarksValid) {
      _handleInvalidLandmarks();
      return;
    }
    _isInGracePeriod = false;
    _lastInvalidLandmarksTime = null;

    // Calculate and smooth angles
    final double leftKneeAngle = _getAngle(leftHip!, leftKnee!, leftAnkle!);
    final double rightKneeAngle = _getAngle(rightHip!, rightKnee!, rightAnkle!);
    final double avgKneeAngle = _smoothAngle(_kneeAngleBuffer, (leftKneeAngle + rightKneeAngle) / 2);
    
    // Torso angle (used only for feedback, not rep counting)
    if (leftShoulder != null && rightShoulder != null) {
      final double leftTorsoAngle = _getAngle(leftShoulder, leftHip, leftKnee);
      final double rightTorsoAngle = _getAngle(rightShoulder, rightHip, rightKnee);
      final double avgTorsoAngle = _smoothAngle(_torsoAngleBuffer, (leftTorsoAngle + rightTorsoAngle) / 2);
      
      // Form check: Torso (Keep your chest up)
      if (avgTorsoAngle < _torsoAngleMin) {
        _speak("Keep your chest up and back straight.");
      }
    }

    // Simplified Rep counting logic (based on state and position only)
    if (_currentState == DumbbellSquatState.up) {
      if (avgKneeAngle <= _kneeDownAngle) {
        // Transition to Down state once the squat depth is reached
        _currentState = DumbbellSquatState.down;
        _speak("Go lower!");
      } else if (avgKneeAngle < _kneeUpAngle - 10) {
        // Encourage full stand-up
        _speak("Fully stand up.");
      }
    } else if (_currentState == DumbbellSquatState.down) {
      if (avgKneeAngle >= _kneeUpAngle) {
        // Transition to Up state and count rep once the standing position is reached
        if (DateTime.now().difference(_lastRepTime) >= _cooldownDuration) {
          _repCount++;
          _currentState = DumbbellSquatState.up;
          _lastRepTime = DateTime.now();
          _speak(_repCount % 5 == 0 ? "You're strong! Reps: $_repCount" : "Rep $_repCount");
        } else {
          _speak("Slow down the movement.");
        }
      } else if (avgKneeAngle > _kneeDownAngle + 10) {
        // Encourage deeper squat
        _speak("Lower deeper into the squat.");
      }
    }
  }

  void _handleInvalidLandmarks() {
    if (!_isInGracePeriod) {
      _lastInvalidLandmarksTime = DateTime.now();
      _isInGracePeriod = true;
      _speak("Ensure your full body is visible.");
    } else if (_lastInvalidLandmarksTime != null &&
        DateTime.now().difference(_lastInvalidLandmarksTime!) > _gracePeriod) {
      _currentState = DumbbellSquatState.up;
      _isInGracePeriod = false;
      _speak("Position lost. Try to center yourself again.");
    }
  }

  @override
  void reset() {
    _repCount = 0;
    _currentState = DumbbellSquatState.up;
    _lastRepTime = DateTime.now();
    _hasStarted = false;
    _lastFeedbackTime = null;
    _lastInvalidLandmarksTime = null;
    _isInGracePeriod = false;
    _kneeAngleBuffer.clear();
    _torsoAngleBuffer.clear();
    _speak("Exercise reset.");
  }

  @override
  // MODIFIED: Removed the voice feedback message from the progress label
  String get progressLabel => "Reps: $_repCount";

  @override
  int get reps => _repCount;
}