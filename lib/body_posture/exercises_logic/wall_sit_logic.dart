// lib/body_posture/exercises/exercises_logic/wall_sit_logic.dart

import 'dart:math';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../camera/exercises_logic.dart'
    show TimeExerciseLogic; // Changed import

enum WallSitState { notSitting, sitting }

class WallSitLogic implements TimeExerciseLogic {
  // Changed from ExerciseLogic to TimeExerciseLogic
  int _holdTime = 0;
  WallSitState _currentState = WallSitState.notSitting;
  DateTime? _startSitTime;
  final FlutterTts _tts = FlutterTts();

  // Confidence threshold for landmarks
  final double _minLandmarkConfidence = 0.7;

  WallSitLogic() {
    _tts.setLanguage("en-US");
    _tts.setSpeechRate(0.5);
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    if (landmarks.isEmpty) return;

    final leftHip = landmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.leftHip,
      orElse: () => null,
    );
    final rightHip = landmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.rightHip,
      orElse: () => null,
    );
    final leftKnee = landmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.leftKnee,
      orElse: () => null,
    );
    final rightKnee = landmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.rightKnee,
      orElse: () => null,
    );
    final leftAnkle = landmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.leftAnkle,
      orElse: () => null,
    );
    final rightAnkle = landmarks.firstWhere(
      (l) => l.type == PoseLandmarkType.rightAnkle,
      orElse: () => null,
    );

    // ✅ Confidence validation
    final bool allValid = [
      leftHip,
      rightHip,
      leftKnee,
      rightKnee,
      leftAnkle,
      rightAnkle,
    ].every((lm) => lm != null && lm.likelihood >= _minLandmarkConfidence);

    if (!allValid) {
      _speak("Make sure your lower body is visible.");
      _currentState = WallSitState.notSitting;
      _startSitTime = null;
      return;
    }

    // Calculate knee angle
    final leftKneeAngle = _getAngle(leftHip!, leftKnee!, leftAnkle!);
    final rightKneeAngle = _getAngle(rightHip!, rightKnee!, rightAnkle!);
    final avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2;

    if (avgKneeAngle >= 80 && avgKneeAngle <= 100) {
      // Sitting position
      if (_currentState == WallSitState.notSitting) {
        _speak("Good! Hold that wall sit.");
        _startSitTime = DateTime.now();
      }
      _currentState = WallSitState.sitting;

      if (_startSitTime != null) {
        _holdTime = DateTime.now().difference(_startSitTime!).inSeconds;
      }
    } else {
      // Not sitting
      if (_currentState == WallSitState.sitting) {
        _speak("You stood up. Resetting timer.");
      }
      _currentState = WallSitState.notSitting;
      _startSitTime = null;
      _holdTime = 0;
    }
  }

  @override
  void reset() {
    _holdTime = 0;
    _currentState = WallSitState.notSitting;
    _startSitTime = null;
  }

  @override
  String get progressLabel => "Time: $_holdTime s";

  @override
  int get seconds => _holdTime; // Added getter for seconds

  void _speak(String message) async {
    await _tts.stop();
    await _tts.speak(message);
  }

  // Helper to calculate angle
  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final v1x = p1.x - p2.x;
    final v1y = p1.y - p2.y;
    final v2x = p3.x - p2.x;
    final v2y = p3.y - p2.y;

    final dot = v1x * v2x + v1y * v2y;
    final mag1 = sqrt(v1x * v1x + v1y * v1y);
    final mag2 = sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0 || mag2 == 0) return 180;

    double cosAngle = dot / (mag1 * mag2);
    cosAngle = cosAngle.clamp(-1.0, 1.0);
    return acos(cosAngle) * 180 / pi;
  }
}
