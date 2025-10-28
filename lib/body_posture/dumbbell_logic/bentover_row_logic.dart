// lib/body_posture/dumbbells/dumbbell_logic/bent_over_row_logic.dart (Complete and Fixed)

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
// NOTE: Assuming this path is correct for your RepExerciseLogic definition
import '../camera/exercises_logic.dart'; 


enum BentOverRowState {
  down, // Arms extended, weights hanging (Ready to pull up)
  up, // Arms bent, weights near torso (Peak Contraction - **Count happens here**)
  inDownCooldown, // Briefly after counting 'up' to ensure a full descent
}

class BentOverRowLogic extends RepExerciseLogic {
  int _repCount = 0;
  BentOverRowState _currentState = BentOverRowState.down; 

  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(milliseconds: 500); 
  final Duration _formFeedbackCooldown = const Duration(seconds: 4);
  DateTime _lastFormFeedbackTime = DateTime.now();

  // --- ANGLE THRESHOLDS ---
  final double _maxTorsoAngleThreshold = 135.0; // Torso angle (Shoulder-Hip-Knee)
  final double _upThreshold = 95.0; // Elbow angle for UP position
  final double _downThreshold = 155.0; // Elbow angle for DOWN position
  // ------------------------

  final double _minLandmarkConfidence = 0.7;
  final List<double> _armAngleBuffer = [];
  final List<double> _torsoAngleBuffer = [];
  final int _bufferSize = 5; 

  final FlutterTts _flutterTts = FlutterTts();

  BentOverRowLogic() {
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setVolume(1.0);
    _flutterTts.setPitch(1.0);
  }

  @override
  int get reps => _repCount;

  @override
  String get progressLabel => "Reps: $_repCount";


  // ###########################################
  // ### HELPER METHODS (Needed by the core logic)
  // ###########################################

  Future<void> _speak(String message) async {
    if (DateTime.now().difference(_lastRepTime).inMilliseconds < 1000) {
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    _lastRepTime = DateTime.now();
  }

  Future<void> _speakFormFeedback(String message) async {
    if (DateTime.now().difference(_lastFormFeedbackTime) < _formFeedbackCooldown) {
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    _lastFormFeedbackTime = DateTime.now();
  }

  PoseLandmark _getLandmarkSafe(List<dynamic> landmarks, PoseLandmarkType type) {
    try {
      final landmark = landmarks.firstWhere((l) => l.type == type); 
      if (landmark.likelihood < _minLandmarkConfidence) {
        throw StateError("Low confidence");
      }
      return landmark;
    } catch (e) {
      return PoseLandmark(type: type, x: 0.0, y: 0.0, z: 0.0, likelihood: 0.0);
    }
  }

  double _smoothAngle(List<double> buffer, double newAngle) {
    buffer.add(newAngle);
    if (buffer.length > _bufferSize) {
      buffer.removeAt(0);
    }
    return buffer.reduce((a, b) => a + b) / buffer.length;
  }

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final double v1x = p1.x - p2.x;
    final double v1y = p1.y - p2.y;
    final double v2x = p3.x - p2.x;
    final double v2y = p3.y - p2.y;

    final double dotProduct = v1x * v2x + v1y * v2y;
    final double magnitude1 = math.sqrt(v1x * v1x + v1y * v1y);
    final double magnitude2 = math.sqrt(v2x * v2x + v2y * v2y);

    if (magnitude1 == 0 || magnitude2 == 0) return 180.0;

    double cosineAngle = dotProduct / (magnitude1 * magnitude2);
    cosineAngle = math.max(-1.0, math.min(1.0, cosineAngle));

    return math.acos(cosineAngle) * 180 / math.pi;
  }

  // ###########################################
  // ### CORE LOGIC (Updated to use new state and count on UP)
  // ###########################################

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    if (landmarks.isEmpty) {
      _speakFormFeedback("No body detected. Ensure you are visible in the camera.");
      return;
    }

    // Retrieve and check landmarks for sufficient visibility
    final leftShoulder = _getLandmarkSafe(landmarks, PoseLandmarkType.leftShoulder);
    final rightShoulder = _getLandmarkSafe(landmarks, PoseLandmarkType.rightShoulder);
    final leftElbow = _getLandmarkSafe(landmarks, PoseLandmarkType.leftElbow);
    final rightElbow = _getLandmarkSafe(landmarks, PoseLandmarkType.rightElbow);
    final leftWrist = _getLandmarkSafe(landmarks, PoseLandmarkType.leftWrist);
    final rightWrist = _getLandmarkSafe(landmarks, PoseLandmarkType.rightWrist);
    final leftHip = _getLandmarkSafe(landmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmarkSafe(landmarks, PoseLandmarkType.rightHip);
    final leftKnee = _getLandmarkSafe(landmarks, PoseLandmarkType.leftKnee);
    final rightKnee = _getLandmarkSafe(landmarks, PoseLandmarkType.rightKnee);

    if (leftShoulder.likelihood == 0 || rightShoulder.likelihood == 0 ||
        leftElbow.likelihood == 0 || rightElbow.likelihood == 0 ||
        leftHip.likelihood == 0 || rightHip.likelihood == 0) {
      _speakFormFeedback("Ensure your back and arms are clearly visible. Position the camera side-on.");
      return;
    }

    // Calculate angles
    final double leftArmAngle = _getAngle(leftShoulder, leftElbow, leftWrist);
    final double rightArmAngle = _getAngle(rightShoulder, rightElbow, rightWrist);
    final double averageArmAngle = _smoothAngle(_armAngleBuffer, (leftArmAngle + rightArmAngle) / 2);

    final double leftTorsoAngle = _getAngle(leftShoulder, leftHip, leftKnee);
    final double rightTorsoAngle = _getAngle(rightShoulder, rightHip, rightKnee);
    final double averageTorsoAngle = _smoothAngle(_torsoAngleBuffer, (leftTorsoAngle + rightTorsoAngle) / 2);

    debugPrint(
        "State: $_currentState, ArmAngle: $averageArmAngle, "
        "TorsoAngle: $averageTorsoAngle, Reps: $_repCount");

    // Form validation: Check bent-over posture
    final bool isBentOver = averageTorsoAngle <= _maxTorsoAngleThreshold;
    if (!isBentOver) {
      _speakFormFeedback("Bend forward more at the hips. Keep your back flat.");
      return; 
    }

    // Check arm positions
    final bool inUpPosition = averageArmAngle <= _upThreshold;
    final bool inDownPosition = averageArmAngle >= _downThreshold;

    // Rep counting logic
    switch (_currentState) {
      case BentOverRowState.down:
        // Form feedback for arm extension
        if (!inDownPosition && averageArmAngle < _downThreshold - 10) {
           _speakFormFeedback("Fully extend your arms downward.");
        }
        
        // Transition from DOWN (arms extended) to UP (arms bent)
        if (inUpPosition) {
          if (DateTime.now().difference(_lastRepTime) >= _cooldownDuration) {
            // Rep counted here (at peak contraction)
            _repCount++;
            _currentState = BentOverRowState.up;
            _lastRepTime = DateTime.now();
            _speak("Rep $_repCount.");
          } else {
            // Too fast, remain in DOWN state, don't count, and advise
            _speakFormFeedback("Slow down the pull.");
          }
        }
        break;

      case BentOverRowState.up:
        // We've counted the rep. Now look for the full descent.
        // Form feedback for peak contraction
        if (!inUpPosition && averageArmAngle > _upThreshold + 10) {
          _speakFormFeedback("Squeeze your back at the top.");
        }
        
        // Transition from UP (arms bent) to Cooldown after reaching full extension
        if (inDownPosition) {
          _currentState = BentOverRowState.inDownCooldown;
        }
        break;

      case BentOverRowState.inDownCooldown:
        // This state ensures the user stays at or near the bottom for a moment, 
        // preventing a bounce count before restarting the pull up.
        
        // As soon as the arms start bending again (angle drops below the down threshold)
        // or the user lifts the torso slightly, transition back to DOWN state, ready to pull up.
        if (averageArmAngle < _downThreshold - 5) {
          _currentState = BentOverRowState.down;
        }
        break;
    }
  }

  @override
  void reset() {
    _repCount = 0;
    _currentState = BentOverRowState.down;
    _lastRepTime = DateTime.now();
    _lastFormFeedbackTime = DateTime.now();
    _armAngleBuffer.clear();
    _torsoAngleBuffer.clear();
    _speak("Exercise reset. Start your rows.");
  }
}